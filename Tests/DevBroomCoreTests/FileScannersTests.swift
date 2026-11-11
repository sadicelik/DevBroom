import XCTest
@testable import DevBroomCore

final class FileScannersTests: XCTestCase {
    private func scanners(_ h: TempHome, running: Set<String> = []) -> FileScanners {
        FileScanners(locations: Locations(home: h.url), scanRoots: [h.url], now: now, cutoffDays: 14, runningBundleIDs: running)
    }
    private func repo(_ h: TempHome, _ rel: String) throws {
        if TempHome.gitAvailable { try h.git(try h.dir(rel), "init") } else { try h.dir(rel + "/.git") }
    }
    private func result(_ r: [CategoryResult], _ id: CategoryID) -> CategoryResult { r.first { $0.id == id }! }
    private func hmosProject(_ h: TempHome) throws {
        try repo(h, "p")
        try h.make("p/package.json", modified: ago(100))
        try h.make("p/node_modules/x", modified: ago(100))
        try h.make("p/entry/hvigorfile.ts", modified: ago(100))
        try h.make("p/entry/build/x", modified: ago(100))
        try h.make("p/src/a.ets", modified: ago(100))
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
        try h.make("code/a/package.json")
        try h.make("code/a/node_modules/x/package.json")
        try h.make("code/a/node_modules/x/node_modules/y")
        try h.make(".vscode/ext/package.json")
        try h.make(".vscode/ext/node_modules/z")
        try h.make("Library/p/package.json")
        try h.make("Library/p/node_modules/z")
        try h.make("code/b/src/f")
        let r = try scanners(h).projects().first { $0.id == .nodeModules }!
        XCTAssertEqual(r.items.count, 1)
        XCTAssertTrue(r.items[0].id.hasSuffix("code/a/node_modules"))
        XCTAssertEqual(r.items[0].name, "a")
    }

    func testNodeModulesLastUsedFromProject() throws {
        let h = try TempHome()
        try h.make("code/a/package.json", modified: ago(2))
        try h.make("code/a/node_modules/x", modified: ago(100))
        let r = try scanners(h).projects().first { $0.id == .nodeModules }!
        XCTAssertTrue(r.items[0].tags.contains(.recentlyUsed))
    }

    func testNodeModulesSkipsAppBundlesAndNonProjects() throws {
        let h = try TempHome()
        try h.make("code/Foo.app/Contents/Resources/app/package.json")
        try h.make("code/Foo.app/Contents/Resources/app/node_modules/x")
        try h.make("n/lib/node_modules/npm/f")
        try h.make("code/a/package.json")
        try h.make("code/a/node_modules/x")
        let r = try scanners(h).projects().first { $0.id == .nodeModules }!
        XCTAssertEqual(r.items.map(\.name), ["a"])
    }

    func testNodeModulesOverlappingRootsNoDuplicates() throws {
        let h = try TempHome()
        try h.make("code/a/package.json")
        try h.make("code/a/node_modules/x")
        let s = FileScanners(locations: Locations(home: h.url), scanRoots: [h.url, h.url.appending(path: "code")],
                             now: now, cutoffDays: 14, runningBundleIDs: [])
        XCTAssertEqual(try s.projects().first { $0.id == .nodeModules }!.items.count, 1)
    }

    func testNodeModulesUnderHiddenRootNotListed() throws {
        let h = try TempHome()
        try h.make(".hidden/code/a/package.json")
        try h.make(".hidden/code/a/node_modules/x")
        let s = FileScanners(locations: Locations(home: h.url), scanRoots: [h.url.appending(path: ".hidden/code")],
                             now: now, cutoffDays: 14, runningBundleIDs: [])
        XCTAssertTrue(try s.projects().first { $0.id == .nodeModules }!.items.isEmpty)
    }

    func testDeviceSupportHandlesSpaces() throws {
        let h = try TempHome()
        try h.make("Library/Developer/Xcode/iOS DeviceSupport/18.1 (22B83)/f")
        let r = try scanners(h).deviceSupport()
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.items[0].detail, "iOS DeviceSupport")
    }

    func testPackageCachesNewToolsAndKinds() throws {
        let h = try TempHome()
        for d in [".m2/repository/x", ".cargo/registry/x", ".pub-cache/x"] { try h.make(d) }
        let r = try scanners(h).packageCaches()
        XCTAssertEqual(r.items.map(\.name), ["Cargo", "Maven", "Dart/Flutter"])
        XCTAssertEqual(r.items.map(\.kind), [.rebuilds, .redownload, .redownload])
    }

    func testMissingFoldersGiveEmptyResult() throws {
        let s = scanners(try TempHome())
        for r in [try s.derivedData(), try s.packageCaches(), try s.appCaches(),
                  try s.deviceSupport(), try s.wallpaper(), try s.projects().first { $0.id == .nodeModules }!] {
            XCTAssertTrue(r.items.isEmpty)
        }
    }

    func testNodeModulesFreshInstallOldProjectNotRecent() throws {
        let h = try TempHome()
        try h.make("code/a/package.json", modified: ago(100))
        try h.make("code/a/node_modules/x", modified: ago(1))
        let r = try scanners(h).projects().first { $0.id == .nodeModules }!
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

    func testV032Scanners() throws {
        let h = try TempHome()
        try h.make("Library/Developer/XCPGDevices/ABC/data")
        try h.make("Library/Developer/Xcode/DocumentationCache/v1/f")
        try h.make(".android/avd/Pixel_8.avd/config.ini"); try h.make(".android/avd/Pixel_8.ini")
        try h.make("Library/Android/sdk/system-images/android-34/x")
        try h.make(".lmstudio/models/pub/model-x/w.gguf")
        try h.make(".ollama/models/blobs/b")
        try h.make("s/Package.swift"); try h.make("s/.build/debug/x", modified: ago(60)); try h.make("s/Sources/a.swift", modified: ago(60))
        let sc = scanners(h)
        XCTAssertEqual(Set(try sc.xcodeExtras().items.map(\.name)), ["SwiftUI previews: ABC", "Documentation cache: v1"])
        XCTAssertEqual(Set(try sc.androidEmulators().items.map(\.name)), ["Pixel_8", "System image android-34"])
        let projects = try sc.projects()
        XCTAssertEqual(Set(projects[2].items.map(\.name)), ["pub/model-x", "All Ollama models"])
        XCTAssertTrue(projects[2].items.allSatisfy { $0.kind == .redownload })
        XCTAssertEqual(projects[1].items.map(\.name), ["s · SwiftPM .build"])
    }

    func testProjectWalkFindsBuildsAndKeepsNodeModules() throws {
        let h = try TempHome()
        try hmosProject(h)
        let r = try scanners(h).projects()
        XCTAssertEqual(r.map(\.id), [.nodeModules, .projectBuilds, .aiModels])
        XCTAssertEqual(result(r, .nodeModules).items.count, 1)
        let b = result(r, .projectBuilds).items
        XCTAssertEqual(b.map(\.name), ["p · HarmonyOS build"])
        XCTAssertEqual(b.first?.detail, "~/p/entry")
        XCTAssertFalse(b[0].tags.contains(.recentlyUsed))
    }

    func testSiblingEditMarksBuildRecent() throws {
        let h = try TempHome()
        try hmosProject(h)
        try h.make("p/feature/x.ets", modified: ago(0))
        let b = result(try scanners(h).projects(), .projectBuilds).items
        XCTAssertEqual(b.count, 1)
        XCTAssertTrue(b[0].tags.contains(.recentlyUsed))
    }

    func testUnmarkedBuildIsWalkedInto() throws {
        let h = try TempHome()
        try h.make("a/build/inner/Cargo.toml")
        try h.make("a/build/inner/target/x")
        let b = result(try scanners(h).projects(), .projectBuilds).items
        XCTAssertEqual(b.count, 1)
        XCTAssertTrue(b[0].id.hasSuffix("a/build/inner/target"))
    }

    func testGitTrackedBuildSkipped() throws {
        try XCTSkipUnless(TempHome.gitAvailable)
        let h = try TempHome()
        try h.make("p/build.gradle")
        try h.make("p/build/script.sh")
        try h.git(try h.dir("p"), "init")
        try h.git(h.url.appending(path: "p"), "add", "-A")
        try h.git(h.url.appending(path: "p"), "commit", "-m", "x")
        XCTAssertTrue(result(try scanners(h).projects(), .projectBuilds).items.isEmpty)
    }

    func testHubModels() throws {
        let h = try TempHome()
        try h.make("z/hf/hub/models--facebook--nllb/x")
        try h.make(".cache/huggingface/hub/models--a--b/x")
        try h.make("y/hub/notes.txt")
        let m = result(try scanners(h).projects(), .aiModels).items
        XCTAssertEqual(Set(m.map(\.name)), ["facebook/nllb", "a/b"])
        XCTAssertEqual(m.count, 2)
        XCTAssertTrue(m.allSatisfy { $0.kind == .redownload })
    }

    func testDotBuildFolders() throws {
        let h = try TempHome()
        try h.make("p/.venv/pyvenv.cfg")
        try h.make(".hidden/q/build.gradle")
        try h.make(".hidden/q/build/x")
        let b = result(try scanners(h).projects(), .projectBuilds).items
        XCTAssertEqual(b.map(\.name), ["p · Python .venv"])
    }

    func testGitTrackedBuildIsWalkedInto() throws {
        try XCTSkipUnless(TempHome.gitAvailable)
        let h = try TempHome()
        try h.make("p/build.gradle")
        try h.make("p/build/q/Cargo.toml")
        let p = try h.dir("p")
        try h.git(p, "init"); try h.git(p, "add", "build.gradle", "build/q/Cargo.toml"); try h.git(p, "commit", "-m", "x")
        try h.make("p/build/q/target/x")  // untracked, added after the commit
        let b = result(try scanners(h).projects(), .projectBuilds).items
        XCTAssertEqual(b.count, 1)
        XCTAssertTrue(b[0].id.hasSuffix("p/build/q/target"))
    }

    func testBuildFreshOutputOldProjectNotRecent() throws {
        let h = try TempHome()
        try repo(h, "p")
        try h.make("p/entry/hvigorfile.ts", modified: ago(100))
        try h.make("p/src/a.ets", modified: ago(100))
        try h.make("p/entry/build/x", modified: ago(0))
        let b = result(try scanners(h).projects(), .projectBuilds).items
        XCTAssertEqual(b.count, 1)
        XCTAssertFalse(b[0].tags.contains(.recentlyUsed))
    }

    func testTwoBuildFoldersShareProjectRecency() throws {
        let h = try TempHome()
        try repo(h, "p")
        try h.make("p/a/hvigorfile.ts", modified: ago(100))
        try h.make("p/a/build/x", modified: ago(100))
        try h.make("p/b/build.gradle", modified: ago(100))
        try h.make("p/b/build/x", modified: ago(100))
        try h.make("p/src/new.ets", modified: ago(1))
        let b = result(try scanners(h).projects(), .projectBuilds).items
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[0].lastUsed, b[1].lastUsed)
        XCTAssertTrue(b.allSatisfy { $0.tags.contains(.recentlyUsed) })
    }

    func testPackageCacheWalkSkipped() throws {
        let h = try TempHome()
        try h.make("go/pkg/mod/x/build.gradle")
        try h.make("go/pkg/mod/x/build/f")
        XCTAssertTrue(result(try scanners(h).projects(), .projectBuilds).items.isEmpty)
    }

    func testOldExtensionsListsOldVersionsAndTagsRunningEditor() throws {
        let h = try TempHome()
        for f in ["a.b-1.0.0", "a.b-1.2.0"] { try h.make(".vscode/extensions/\(f)/package.json") }
        try Data("[{\"relativeLocation\":\"a.b-1.2.0\"}]".utf8).write(to: h.url.appending(path: ".vscode/extensions/extensions.json"))
        let r = try scanners(h, running: ["com.microsoft.VSCode"]).oldExtensions()
        XCTAssertEqual(r.id, .oldExtensions)
        XCTAssertEqual(r.items.map(\.name), ["a.b 1.0.0 · VS Code"])
        XCTAssertEqual(r.items[0].detail, "a.b")
        XCTAssertTrue(r.items[0].tags.contains(.appRunning))
        XCTAssertFalse(defaultTicked(r.items[0], now: now, cutoffDays: 14))
    }

    func testOldExtensionsEmptyWithoutExtensionsJson() throws {
        let h = try TempHome()
        for f in ["a.b-1.0.0", "a.b-1.2.0"] { try h.make(".cursor/extensions/\(f)/package.json") }
        XCTAssertTrue(try scanners(h).oldExtensions().items.isEmpty)
    }
}
