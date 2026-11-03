import XCTest
@testable import DevBroomCore

final class FileScannersTests: XCTestCase {
    private func scanners(_ h: TempHome, running: Set<String> = []) -> FileScanners {
        FileScanners(locations: Locations(home: h.url), scanRoots: [h.url], now: now, cutoffDays: 14, runningBundleIDs: running)
    }
    private func ago(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

    func testStatsSumsAndNewest() throws {
        let h = try TempHome()
        let d1 = Date(timeIntervalSince1970: 1_700_000_000), d2 = d1.addingTimeInterval(1000)
        try h.make("s/a", bytes: 1_000_000, modified: d1)
        try h.make("s/b", bytes: 2_000_000, modified: d2)
        let s = try folderStats(h.url.appending(path: "s"))
        XCTAssertGreaterThanOrEqual(s.allocatedBytes, 3_000_000)
        XCTAssertEqual(s.newestModification, d2)
    }

    func testStatsSkipsUnreadable() throws {
        let h = try TempHome()
        try h.make("s/a", bytes: 1_000_000)
        let locked = try h.dir("s/locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertGreaterThanOrEqual(try folderStats(h.url.appending(path: "s")).allocatedBytes, 1_000_000)
    }

    func testDerivedDataStripsHash() throws {
        let h = try TempHome()
        try h.make("Library/Developer/Xcode/DerivedData/MyApp-bxyzabcdefghij/x")
        let r = try scanners(h).derivedData()
        XCTAssertEqual(r.items.map(\.name), ["MyApp"])
    }

    func testAppCachesSkipsAppleAndPackageCaches() throws {
        let h = try TempHome()
        for n in ["com.apple.Safari", "Homebrew", "com.google.Chrome"] { try h.make("Library/Caches/\(n)/f") }
        let r = try scanners(h, running: ["com.google.Chrome"]).appCaches()
        XCTAssertEqual(r.items.map(\.detail), ["com.google.Chrome"])
        XCTAssertTrue(r.items[0].tags.contains(.appRunning))
    }

    func testNodeModulesRules() throws {
        let h = try TempHome()
        try h.make("code/a/node_modules/x/node_modules/y")
        try h.make(".vscode/ext/node_modules/z")
        try h.make("Library/p/node_modules/z")
        try h.make("code/b/src/f")
        let r = try scanners(h).nodeModules()
        XCTAssertEqual(r.items.count, 1)
        XCTAssertTrue(r.items[0].id.hasSuffix("code/a/node_modules"))
        XCTAssertEqual(r.items[0].name, "a")
    }

    func testNodeModulesLastUsedFromProject() throws {
        let h = try TempHome()
        try h.make("code/a/package.json", modified: ago(2))
        try h.make("code/a/node_modules/x", modified: ago(100))
        let r = try scanners(h).nodeModules()
        XCTAssertTrue(r.items[0].tags.contains(.recentlyUsed))
    }

    func testDeviceSupportHandlesSpaces() throws {
        let h = try TempHome()
        try h.make("Library/Developer/Xcode/iOS DeviceSupport/18.1 (22B83)/f")
        let r = try scanners(h).deviceSupport()
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.items[0].detail, "iOS DeviceSupport")
    }

    func testMissingFoldersGiveEmptyResult() throws {
        let s = scanners(try TempHome())
        for r in [try s.derivedData(), try s.packageCaches(), try s.appCaches(),
                  try s.deviceSupport(), try s.wallpaper(), try s.nodeModules()] {
            XCTAssertTrue(r.items.isEmpty)
        }
    }

    func testNodeModulesFreshInstallOldProjectNotRecent() throws {
        let h = try TempHome()
        try h.make("code/a/package.json", modified: ago(100))
        try h.make("code/a/node_modules/x", modified: ago(1))
        let r = try scanners(h).nodeModules()
        XCTAssertEqual(r.items.count, 1)
        XCTAssertFalse(r.items[0].tags.contains(.recentlyUsed))
    }

    func testSymlinkRootsNeverFollowed() throws {
        let h = try TempHome()
        let target = try h.dir("target")
        try h.make("target/big", bytes: 1_000_000)
        try h.dir("Library/Caches")
        let link = h.url.appending(path: "Library/Caches/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try h.make("Library/Caches/real/f")
        XCTAssertEqual(try folderStats(link).allocatedBytes, 0)
        XCTAssertEqual(try scanners(h).appCaches().items.map(\.detail), ["real"])
    }
}
