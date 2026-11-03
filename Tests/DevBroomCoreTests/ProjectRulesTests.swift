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

    private func git(_ dir: URL, _ args: String...) throws {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/git")
        p.arguments = ["-C", dir.path, "-c", "user.name=t", "-c", "user.email=t@t"] + args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
    }
    private var gitAvailable: Bool {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/xcode-select"); p.arguments = ["-p"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        return (try? p.run()) != nil && { p.waitUntilExit(); return p.terminationStatus == 0 }()
    }

    @Test func gitTracking() throws {
        guard gitAvailable else { return }
        let tracked = try h.dir("tracked")
        try git(tracked, "init"); try h.make("tracked/build/script.sh")
        try git(tracked, "add", "."); try git(tracked, "commit", "-m", "x")
        #expect(gitTracksFiles(in: tracked.appending(path: "build")))
        let untracked = try h.dir("untracked")
        try git(untracked, "init"); try h.make("untracked/build/out.o")
        #expect(!gitTracksFiles(in: untracked.appending(path: "build")))
        #expect(!gitTracksFiles(in: try h.dir("norepo/build")))
    }

    @Test func projectFolderRules() throws {
        let root = try h.dir("root")
        try h.dir("root/p/.git"); try h.make("root/p/entry/hvigorfile.ts")
        #expect(projectFolder(forMarkerFolder: h.url.appending(path: "root/p/entry"), scanRoot: root).lastPathComponent == "p")
        try h.make("root/q/entry/hvigorfile.ts")
        #expect(projectFolder(forMarkerFolder: h.url.appending(path: "root/q/entry"), scanRoot: root).lastPathComponent == "entry")
        try h.dir(".git")  // above the scan root: ignored
        #expect(projectFolder(forMarkerFolder: h.url.appending(path: "root/q/entry"), scanRoot: root).lastPathComponent == "entry")
    }

    @Test func modelNames() {
        #expect(modelDisplayName("models--a--b") == "a/b")
        #expect(modelDisplayName("datasets--a--b") == "a/b (dataset)")
        #expect(modelDisplayName("models--b") == "b")
        #expect(modelDisplayName("other") == nil)
    }
}
