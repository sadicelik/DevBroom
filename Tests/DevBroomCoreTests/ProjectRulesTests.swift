import Testing
import Foundation
@testable import DevBroomCore

struct ProjectRulesTests {
    let h: TempHome
    init() throws { h = try TempHome() }

    @Test func markerTable() throws {
        for (marker, eco) in [("hvigorfile.ts", Ecosystem.harmonyOS), ("build.gradle", .gradle), ("build.gradle.kts", .gradle),
                              ("pubspec.yaml", .flutter), ("App.xcodeproj/project.pbxproj", .xcode)] {
            let d = "m-\(UUID().uuidString)"
            try h.make("\(d)/\(marker)")
            let b = try h.dir("\(d)/build")
            #expect(buildEcosystem(of: b) == eco, "\(marker)")
        }
        try h.make("r/Cargo.toml"); try h.dir("r/target")
        #expect(buildEcosystem(of: h.url.appending(path: "r/target")) == .rust)
        try h.make("o/oh-package.json5"); try h.dir("o/oh_modules")
        #expect(buildEcosystem(of: h.url.appending(path: "o/oh_modules")) == .harmonyOS)
        try h.make("o/hvigorfile.ts"); try h.dir("o/.hvigor")
        #expect(buildEcosystem(of: h.url.appending(path: "o/.hvigor")) == .harmonyOS)
        try h.make("v/.venv/pyvenv.cfg")
        #expect(buildEcosystem(of: h.url.appending(path: "v/.venv")) == .python)
    }

    @Test func newBuildFolderMarkers() throws {
        try h.make("s/Package.swift"); try h.dir("s/.build")
        #expect(buildEcosystem(of: h.url.appending(path: "s/.build")) == .swiftPM)
        for name in [".next", ".turbo", ".parcel-cache"] {
            try h.make("w/package.json"); try h.dir("w/\(name)")
            #expect(buildEcosystem(of: h.url.appending(path: "w/\(name)")) == .web, "\(name)")
        }
        for marker in ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"] {
            let d = "g-\(UUID().uuidString)"
            try h.make("\(d)/\(marker)"); try h.dir("\(d)/.gradle")
            #expect(buildEcosystem(of: h.url.appending(path: "\(d)/.gradle")) == .gradle, "\(marker)")
        }
        // Without markers: nothing.
        for p in ["n/.build", "n/.next", "n/.turbo", "n/.parcel-cache", "n/.gradle"] {
            #expect(buildEcosystem(of: try h.dir(p)) == nil, "\(p)")
        }
        // Gradle's own ~/.gradle is never a project build folder, even with a Gradle file in home.
        let home = try TempHome()
        try home.make("settings.gradle"); try home.dir(".gradle/caches")
        #expect(buildEcosystem(of: home.url.appending(path: ".gradle"), home: home.url) == nil)
        #expect(buildEcosystem(of: home.url.appending(path: ".gradle")) == .gradle)  // without the home it would count
        let g = RemovalGuard(locations: Locations(home: home.url), scanRoots: [home.url])
        #expect(!g.allows(home.url.appending(path: ".gradle")))
    }

    @Test func missingMarkerIsNil() throws {
        #expect(buildEcosystem(of: try h.dir("a/build")) == nil)
        #expect(buildEcosystem(of: try h.dir("a/oh_modules")) == nil)
        #expect(buildEcosystem(of: try h.dir("a/.venv")) == nil)
        #expect(buildEcosystem(of: try h.dir("a/other")) == nil)
    }

    @Test func gitTracking() throws {
        guard TempHome.gitAvailable else { return }
        let tracked = try h.dir("tracked")
        try h.git(tracked, "init"); try h.make("tracked/build/script.sh")
        try h.git(tracked, "add", "-f", "."); try h.git(tracked, "commit", "-m", "x")
        #expect(gitTracksFiles(in: tracked.appending(path: "build")))
        let untracked = try h.dir("untracked")
        try h.git(untracked, "init"); try h.make("untracked/build/out.o")
        #expect(!gitTracksFiles(in: untracked.appending(path: "build")))
        #expect(!gitTracksFiles(in: try h.dir("norepo/build")))
    }

    @Test func unreadableRepoFailsClosed() throws {
        guard TempHome.gitAvailable else { return }
        try h.make("bad/.git", bytes: 0)  // .git is an empty file: git cannot read the repo
        try h.make("bad/build/out.o")
        #expect(gitTracksFiles(in: h.url.appending(path: "bad/build")))
    }

    @Test func projectFolderRules() throws {
        let root = try h.dir("root")
        try h.dir("root/p/.git"); try h.make("root/p/entry/hvigorfile.ts")
        #expect(projectFolder(forMarkerFolder: h.url.appending(path: "root/p/entry"), scanRoot: root).lastPathComponent == "p")
        try h.make("root/q/entry/hvigorfile.ts")
        #expect(projectFolder(forMarkerFolder: h.url.appending(path: "root/q/entry"), scanRoot: root).lastPathComponent == "entry")
        try h.dir(".git")  // above the scan root: ignored
        #expect(projectFolder(forMarkerFolder: h.url.appending(path: "root/q/entry"), scanRoot: root).lastPathComponent == "entry")
        try h.dir("root/.git")  // exactly at the scan root: ignored
        let m = h.url.appending(path: "root/q/entry")
        #expect(projectFolder(forMarkerFolder: m, scanRoot: root) == m)
        #expect(projectFolder(forMarkerFolder: m, scanRoot: URL(filePath: "/")).path != "/")  // terminates; h/.git is the nearest repo
    }

    @Test func modelNames() {
        #expect(modelDisplayName("models--a--b") == "a/b")
        #expect(modelDisplayName("datasets--a--b") == "a/b (dataset)")
        #expect(modelDisplayName("models--b") == "b")
        #expect(modelDisplayName("other") == nil)
    }

    private func item(_ c: CategoryID, _ u: URL) -> CleanItem {
        CleanItem(id: u.path, category: c, name: "n", detail: "", sizeBytes: 1, lastUsed: nil, method: .trash(u), tags: [])
    }

    @Test func usageFolderRules() throws {
        let nm = try h.dir("u/node_modules")
        let a = usageFolder(for: item(.nodeModules, nm), scanRoots: [h.url])
        #expect(a?.folder == nm.deletingLastPathComponent() && a?.skipping == ["node_modules"])
        try h.dir("p/.git")
        let b = try h.dir("p/entry/build")
        let r = usageFolder(for: item(.projectBuilds, b), scanRoots: [h.url])
        #expect(r?.folder.standardizedFileURL == h.url.appending(path: "p").standardizedFileURL)
        #expect(r?.skipping == projectBuildFolderNames.union(["node_modules"]))
        let outside = usageFolder(for: item(.projectBuilds, b), scanRoots: [])
        #expect(outside?.folder == b.deletingLastPathComponent())
        let plain = usageFolder(for: item(.appCaches, b), scanRoots: [h.url])
        #expect(plain?.folder == b && plain?.skipping == [])
        var cmd = item(.docker, b); cmd.method = .dockerPrune
        #expect(usageFolder(for: cmd, scanRoots: [h.url]) == nil)
    }

    private func extDir(_ listed: [String], folders: [String], json: String? = nil, at base: String = "x") throws -> URL {
        for f in folders { try h.make("\(base)/\(f)/package.json") }
        let entries = listed.map { "{\"identifier\":{\"id\":\"i\"},\"version\":\"1\",\"relativeLocation\":\"\($0)\"}" }
        let body = json ?? "[" + entries.joined(separator: ",") + "]"
        try Data(body.utf8).write(to: h.url.appending(path: "\(base)/extensions.json"))
        return h.url.appending(path: base)
    }
    private let four = ["a.b-1.0.0", "a.b-1.2.0", "ms-python.python-2026.4.0-darwin-arm64", "ms-python.python-2026.10.0-darwin-arm64"]

    @Test func removableExtensionFoldersOlderVersions() throws {
        let d = try extDir(["a.b-1.2.0", "ms-python.python-2026.10.0-darwin-arm64"], folders: four)
        #expect(removableExtensionFolders(in: d) == ["a.b-1.0.0", "ms-python.python-2026.4.0-darwin-arm64"])
    }

    @Test func listedOldVersionIsKept() throws {
        let d = try extDir(["a.b-1.2.0", "a.b-1.0.0", "ms-python.python-2026.10.0-darwin-arm64"], folders: four)
        #expect(removableExtensionFolders(in: d) == ["ms-python.python-2026.4.0-darwin-arm64"])
    }

    @Test func missingOrCorruptExtensionsJsonRemovesNothing() throws {
        for f in four { try h.make("n/\(f)/package.json") }
        #expect(removableExtensionFolders(in: h.url.appending(path: "n")).isEmpty)
        for body in ["{", "{}", "\"x\""] {
            let d = try extDir([], folders: four, json: body, at: "c")
            #expect(removableExtensionFolders(in: d).isEmpty, "\(body)")
        }
    }

    @Test func equalVersionsAndUnparseableNeverRemovable() throws {
        let d = try extDir(["z.z-1.0.0"], folders: ["a.b-1.0", "a.b-1.0.0", "weird", "q.r-2.0.0", "Q.R-10"])
        // a.b-1.0 and a.b-1.0.0 compare equal; Q.R lowercased groups with q.r, 10 > 2
        #expect(removableExtensionFolders(in: d) == ["q.r-2.0.0"])
    }

    @Test func nonDirectoriesAndDotEntriesSkipped() throws {
        let d = try extDir(["a.b-1.2.0"], folders: ["a.b-1.2.0", ".hidden-1.0.0", ".hidden-2.0.0"])
        try Data().write(to: d.appending(path: "a.b-1.0.0"))
        #expect(removableExtensionFolders(in: d).isEmpty)
    }

    @Test func entryWithOnlyLocationPathProtectsItsFolder() throws {
        let d = try extDir([], folders: four, json: "[{\"identifier\":{\"id\":\"i\"},\"location\":{\"path\":\"/Users/u/.vscode/extensions/a.b-1.0.0\"}},{\"location\":{\"fsPath\":\"/x/ms-python.python-2026.4.0-darwin-arm64\"}}]")
        #expect(removableExtensionFolders(in: d) == [])
        let d2 = try extDir([], folders: four, json: "[{\"location\":{\"path\":\"/Users/u/.vscode/extensions/a.b-1.0.0\"}}]", at: "y")
        #expect(removableExtensionFolders(in: d2) == ["ms-python.python-2026.4.0-darwin-arm64"])
    }

    @Test func entryWithNoLocationFailsClosed() throws {
        let d = try extDir([], folders: four, json: "[{\"relativeLocation\":\"a.b-1.2.0\"},{\"identifier\":{\"id\":\"i\"}}]")
        #expect(removableExtensionFolders(in: d).isEmpty)
    }
}
