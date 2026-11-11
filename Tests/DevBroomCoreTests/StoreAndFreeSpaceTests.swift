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

    @Test func decodesV010Item() throws {
        let json = #"""
        {"id":"a","category":"nodeModules","name":"n","detail":"d","sizeBytes":5,
         "method":{"trash":{"_0":"file:///tmp/a"}},"tags":[]}
        """#
        let it = try JSONDecoder().decode(CleanItem.self, from: Data(json.utf8))
        #expect(it.kindOverride == nil)
        #expect(it.kind == .rebuilds)
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

    @MainActor @Test func hiddenItemsPersist() {
        let suite = UUID().uuidString
        let s = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        #expect(s.hiddenItems.isEmpty)
        s.hiddenItems["/Users/you/code/keep/node_modules"] = "keep"
        let again = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        #expect(again.hiddenItems == ["/Users/you/code/keep/node_modules": "keep"])
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @MainActor @Test func guideSeenPersists() {
        let suite = UUID().uuidString
        let s = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        #expect(s.guideSeen == false)
        s.guideSeen = true
        #expect(AppSettings(defaults: UserDefaults(suiteName: suite)!).guideSeen)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func freeBytesForHome() {
        let b = freeBytes(at: FileManager.default.homeDirectoryForCurrentUser)
        #expect(b != nil && b! > 0)
    }

    private final class Calls { var log: [Bool] = [] }
    private struct Boom: Error {}

    private func make(fail: Bool, _ c: Calls) -> (AppSettings, UserDefaults) {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        let s = AppSettings(defaults: d, registrar: { on in c.log.append(on); if fail { throw Boom() } })
        return (s, d)
    }

    @Test func launchAtLoginSuccess() {
        let c = Calls(); let (s, d) = make(fail: false, c)
        s.launchAtLogin = true
        #expect(s.launchAtLogin && d.bool(forKey: "launchAtLogin") && c.log == [true] && s.launchAtLoginError == nil)
    }

    @Test func launchAtLoginFailureReverts() {
        let c = Calls(); let (s, d) = make(fail: true, c)
        s.launchAtLogin = true
        #expect(!s.launchAtLogin && !d.bool(forKey: "launchAtLogin") && c.log == [true] && s.launchAtLoginError != nil)
    }

    @Test func launchAtLoginSameValueNoCall() {
        let c = Calls(); let (s, _) = make(fail: false, c)
        s.launchAtLogin = false
        #expect(c.log.isEmpty)
    }
}
