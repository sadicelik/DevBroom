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
}
