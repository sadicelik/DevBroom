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
    func trash(_ u: URL) throws {
        let n = lock.withLock { count += 1; return count }
        if failFirst && n == 1 { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: u, to: bin.appending(path: UUID().uuidString))
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
