import Testing
import Foundation
@testable import DevBroomCore

fileprivate final class RecordingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var status: Int32 = 0
    var calls: [[String]] { lock.withLock { _calls } }
    func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: String) {
        lock.withLock { _calls.append([executable.path] + args) }
        return (status, "")
    }
}

fileprivate final class TrashSpy: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0
    var failFirst = false
    let bin: URL
    init(bin: URL) { self.bin = bin }
    func trash(_ u: URL) throws -> URL? {
        let n = lock.withLock { count += 1; return count }
        if failFirst && n == 1 { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let to = bin.appending(path: UUID().uuidString)
        try FileManager.default.moveItem(at: u, to: to)
        return to
    }
}

private func cleanItem(_ id: String, _ method: RemovalMethod, bytes: Int64 = 100) -> CleanItem {
    CleanItem(id: id, category: .appCaches, name: id, detail: "", sizeBytes: bytes, lastUsed: nil, method: method, tags: [])
}

@Suite fileprivate struct CleanerTests {
    let h: TempHome
    let runner = RecordingRunner()
    let spy: TrashSpy
    let cleaner: Cleaner

    init() throws {
        h = try TempHome()
        spy = TrashSpy(bin: h.url.appending(path: ".Trash"))
        let g = RemovalGuard(locations: Locations(home: h.url), scanRoots: [h.url])
        let spy = spy
        cleaner = Cleaner(removalGuard: g, runner: runner, home: h.url, trash: { try spy.trash($0) })
    }

    @Test func trashesAllowedItem() async throws {
        let d = try h.make("Library/Caches/com.x.y/f.bin").deletingLastPathComponent()
        let r = await cleaner.clean([cleanItem("a", .trash(d))]) { _, _ in }
        #expect(r.outcomes["a"] == .trashed(bytes: 100))
        #expect(!FileManager.default.fileExists(atPath: d.path))
    }

    /// Uses the real FileManager.trashItem: moves one tiny temp folder to the owner's Trash.
    @Test func defaultTrashClosureTrashes() async throws {
        let d = try h.make("Library/Caches/DevBroomTest-\(UUID().uuidString)/f").deletingLastPathComponent()
        let real = Cleaner(removalGuard: RemovalGuard(locations: Locations(home: h.url), scanRoots: [h.url]),
                           runner: runner, home: h.url)
        let r = await real.clean([cleanItem("a", .trash(d))]) { _, _ in }
        #expect(r.outcomes["a"] == .trashed(bytes: 100))
        #expect(!FileManager.default.fileExists(atPath: d.path))
    }

    private var isBin: (URL, URL) -> Bool { { [bin = spy.bin] folder, _ in folder.standardizedFileURL.path == bin.standardizedFileURL.path } }

    @Test func deleteFromTrashRemovesOnlyWhatWasTrashed() async throws {
        let a = try h.make("Library/Caches/com.a/f").deletingLastPathComponent()
        let other = try h.make(".Trash/keep-me")  // something the owner trashed earlier
        let r = await cleaner.clean([cleanItem("a", .trash(a), bytes: 50)]) { _, _ in }
        #expect(r.trashedItems.count == 1)
        let purge = deleteFromTrash(r.trashedItems, isTrash: isBin)
        #expect(purge.bytes == 50 && purge.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: r.trashedItems[0].url.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(deleteFromTrash(r.trashedItems, isTrash: isBin).bytes == 0)  // already gone: nothing counted, no failure
    }

    /// Put back, then another item lands at the same Trash path: the new item must survive.
    @Test func deleteFromTrashSkipsReplacedItem() async throws {
        let a = try h.make("Library/Caches/com.a/f").deletingLastPathComponent()
        let r = await cleaner.clean([cleanItem("a", .trash(a), bytes: 50)]) { _, _ in }
        let landed = r.trashedItems[0].url
        try FileManager.default.moveItem(at: landed, to: a)                      // "Put Back"
        try FileManager.default.createDirectory(at: landed, withIntermediateDirectories: true)  // owner's own item
        let purge = deleteFromTrash(r.trashedItems, isTrash: isBin)
        #expect(purge.bytes == 0 && purge.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: landed.path))
    }

    /// Real ~/.Trash and the default Trash check: one tiny temp folder is trashed, deleted, then reported as already gone.
    @Test func deleteFromTrashWithRealTrash() throws {
        let d = try h.make("DevBroomPurgeTest-\(UUID().uuidString)/f").deletingLastPathComponent()
        var out: NSURL?
        try FileManager.default.trashItem(at: d, resultingItemURL: &out)
        let item = TrashedItem(url: try #require(out as URL?), bytes: 7)
        let first = deleteFromTrash([item])
        #expect(first.bytes == 7 && first.failures.isEmpty)
        let again = deleteFromTrash([item])
        #expect(again.bytes == 0 && again.failures.isEmpty)
    }

    @Test func deleteFromTrashRefusesPathsOutsideTheTrash() throws {
        let f = try h.make("Library/Caches/com.b/f")
        let fake = try h.make("proj/.Trash/src")  // a folder merely named .Trash
        let purge = deleteFromTrash([TrashedItem(url: f, bytes: 10), TrashedItem(url: fake, bytes: 10)])
        #expect(purge.bytes == 0 && purge.failures.count == 2)
        #expect(FileManager.default.fileExists(atPath: f.path) && FileManager.default.fileExists(atPath: fake.path))
    }

    @Test func androidEmulatorIniGoesWithIt() async throws {
        let avd = try h.make(".android/avd/Pixel_8.avd/config.ini").deletingLastPathComponent()
        let ini = try h.make(".android/avd/Pixel_8.ini")
        let r = await cleaner.clean([cleanItem("a", .trash(avd))]) { _, _ in }
        #expect(r.outcomes["a"] == .trashed(bytes: 100))
        #expect(!FileManager.default.fileExists(atPath: avd.path) && !FileManager.default.fileExists(atPath: ini.path))
    }

    @Test func iniOutsideTheAvdFolderIsLeftAlone() async throws {
        let cache = try h.make("Library/Caches/x.avd/f").deletingLastPathComponent()
        let ini = try h.make("Library/Caches/x.ini")
        let r = await cleaner.clean([cleanItem("c", .trash(cache))]) { _, _ in }
        #expect(r.outcomes["c"] == .trashed(bytes: 100))
        #expect(FileManager.default.fileExists(atPath: ini.path))
    }

    @Test func trashesPathWithSpaces() async throws {
        let d = try h.make("Library/Developer/Xcode/iOS DeviceSupport/18.1 (22B83)/f").deletingLastPathComponent()
        let r = await cleaner.clean([cleanItem("a", .trash(d))]) { _, _ in }
        #expect(r.outcomes["a"] == .trashed(bytes: 100))
    }

    @Test func refusesUnsafePathWithoutCallingTrash() async throws {
        let d = try h.dir("Library/Caches")
        let r = await cleaner.clean([cleanItem("a", .trash(d))]) { _, _ in }
        #expect(r.outcomes["a"] == .failed("Refused by safety guard"))
        #expect(spy.count == 0)
        #expect(r.failures.count == 1)
    }

    @Test func missingItemIsAlreadyGone() async throws {
        let u = h.url.appending(path: "Library/Caches/nope")
        let r = await cleaner.clean([cleanItem("a", .trash(u))]) { _, _ in }
        #expect(r.outcomes["a"] == .alreadyGone)
        #expect(r.trashedBytes == 0)
        #expect(r.failures.isEmpty)
    }

    @Test func failureDoesNotStopOthers() async throws {
        spy.failFirst = true
        let a = try h.make("Library/Caches/a/f").deletingLastPathComponent()
        let b = try h.make("Library/Caches/b/f").deletingLastPathComponent()
        var progress: [Int] = []
        let r = await cleaner.clean([cleanItem("a", .trash(a)), cleanItem("b", .trash(b))]) { d, t in
            #expect(t == 2); progress.append(d)
        }
        if case .failed = r.outcomes["a"] {} else { Issue.record("first should fail") }
        #expect(r.outcomes["b"] == .trashed(bytes: 100))
        #expect(r.failures.map(\.name) == ["a"])
        #expect(progress == [1, 2])
    }

    @Test func permanentCommandsAreExact() async throws {
        let dock = try h.make(".docker/bin/docker")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dock.path)
        let r = await cleaner.clean([cleanItem("d", .simctlDevice(udid: "U1"), bytes: 5),
                                     cleanItem("r", .simctlRuntime(identifier: "R1"), bytes: 7),
                                     cleanItem("k", .dockerPrune, bytes: 11)]) { _, _ in }
        #expect(runner.calls == [["/usr/bin/xcrun", "simctl", "delete", "U1"],
                                 ["/usr/bin/xcrun", "simctl", "runtime", "delete", "R1"],
                                 [dock.path, "system", "prune", "-a", "-f"]])
        #expect(!runner.calls.joined().contains("--volumes"))
        #expect(r.deletedBytes == 23)
    }

    @Test func nonZeroExitFails() async throws {
        runner.status = 3
        let r = await cleaner.clean([cleanItem("d", .simctlDevice(udid: "U1"))]) { _, _ in }
        #expect(r.outcomes["d"] == .failed("xcrun exited with 3"))
    }

    @Test func dockerMissingFails() async throws {
        // Skip when a real docker exists in a system location.
        guard ToolLocator.docker(home: h.url) == nil else { return }
        let r = await cleaner.clean([cleanItem("k", .dockerPrune)]) { _, _ in }
        #expect(r.outcomes["k"] == .failed("Docker not found"))
        #expect(runner.calls.isEmpty)
    }

    @Test func reportTotals() async throws {
        let a = try h.make("Library/Caches/a/f").deletingLastPathComponent()
        let b = try h.make("Library/Caches/b/f").deletingLastPathComponent()
        let r = await cleaner.clean([cleanItem("a", .trash(a), bytes: 10), cleanItem("b", .trash(b), bytes: 20),
                                     cleanItem("d", .simctlDevice(udid: "U"), bytes: 5)]) { _, _ in }
        #expect(r.trashedBytes == 30)
        #expect(r.deletedBytes == 5)
    }
}
