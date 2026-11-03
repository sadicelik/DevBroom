import Testing
import Foundation
@testable import DevBroomCore

@MainActor
struct StoreAndFreeSpaceTests {
    @Test func storeRoundTrip() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("sub/last-scan.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        let it = CleanItem(id: "a", category: .derivedData, name: "n", detail: "d", sizeBytes: 5,
                           lastUsed: nil, method: .trash(URL(fileURLWithPath: "/tmp/a")), tags: [.inUse])
        let input = [CategoryResult(id: .derivedData, items: [it], status: .notUpdated),
                     CategoryResult(id: .docker, items: [], status: .unavailable("x"))]
        let store = ScanStore(file: file)
        try store.save(input)
        let out = store.load()
        #expect(out.map(\.id) == input.map(\.id))
        #expect(out.map(\.status) == input.map(\.status))
        #expect(out.map { $0.items.map(\.id) } == input.map { $0.items.map(\.id) })
    }

    @Test func storeCorruptReturnsEmpty() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try "nope".write(to: file, atomically: true, encoding: .utf8)
        #expect(ScanStore(file: file).load().isEmpty)
    }

    @Test func notifierFiresOncePerCrossing() {
        var n = LowSpaceNotifier(limitBytes: 15_000_000_000)
        let r = [20, 14, 13, 16, 12].map { n.update(freeBytes: Int64($0) * 1_000_000_000) }
        #expect(r == [false, true, false, false, true])
    }

    @Test func settingsDefaults() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let s = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!, home: home)
        #expect(s.cutoffDays == 14)
        #expect(s.lowSpaceLimitGB == 15)
        #expect(s.launchAtLogin == false)
        #expect(s.scanRoots == [home])
    }

    @Test func freeBytesForHome() {
        let b = freeBytes(at: FileManager.default.homeDirectoryForCurrentUser)
        #expect(b != nil && b! > 0)
    }
}
