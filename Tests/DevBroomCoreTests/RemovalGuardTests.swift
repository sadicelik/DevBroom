import Testing
import Foundation
@testable import DevBroomCore

struct RemovalGuardTests {
    let h: TempHome
    let g: RemovalGuard
    init() throws {
        h = try TempHome()
        g = RemovalGuard(locations: Locations(home: h.url), scanRoots: [h.url])
    }
    func u(_ p: String) -> URL { h.url.appending(path: p) }

    @Test func allowedPaths() {
        for p in ["Library/Caches/com.google.Chrome", "Library/Developer/Xcode/DerivedData/App-abc123",
                  "Library/Developer/Xcode/iOS DeviceSupport/18.1 (22B83)",
                  "Library/Application Support/com.apple.wallpaper/aerials/videos/A.mov",
                  ".npm", ".gradle/caches", "code/site/node_modules"] {
            #expect(g.allows(u(p)), "\(p)")
        }
    }

    @Test func refusedPaths() {
        #expect(!g.allows(h.url))
        for p in ["Library", "Library/Caches", "Library/Developer/Xcode/DerivedData", "Library/Caches/a/b",
                  ".npm/_cacache", ".vscode/extensions/x/node_modules", "Library/foo/node_modules", "LIBRARY/foo/node_modules",
                  "code/site", "Library/Caches/../Documents",
                  "Library/Application Support/com.apple.wallpaper/aerials/manifest"] {
            #expect(!g.allows(u(p)), "\(p)")
        }
        #expect(!g.allows(URL(filePath: "/etc/hosts")))
    }

    @Test func nodeModulesOutsideScanRootsRefused() {
        let g2 = RemovalGuard(locations: Locations(home: h.url), scanRoots: [u("code")])
        #expect(!g2.allows(u("other/node_modules")))
        #expect(g2.allows(u("code/x/node_modules")))
    }

    @Test func appBundleComponentRefused() {
        #expect(!g.allows(u("code/Foo.app/Contents/Resources/app/node_modules")))
        #expect(!g.allows(u("code/Bar.APP/x/node_modules")))
    }

    @Test func symlinkRefused() throws {
        try h.dir("Documents")
        try h.dir("Library/Caches")
        let link = u("Library/Caches/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: u("Documents"))
        #expect(!g.allows(link))
    }

    @Test func symlinkedParentRefused() throws {
        try h.dir("Library/Application Support/x/node_modules")
        try h.dir("code")
        try FileManager.default.createSymbolicLink(at: u("code/link"), withDestinationURL: u("Library/Application Support"))
        #expect(!g.allows(u("code/link/x/node_modules")))
    }

    @Test func dotAboveScanRootOutsideHomeRefused() throws {
        let other = try TempHome()
        let root = other.url.appending(path: ".hidden/code")
        let g2 = RemovalGuard(locations: Locations(home: h.url), scanRoots: [root])
        #expect(!g2.allows(root.appending(path: "x/node_modules")))
    }

    @Test func v032Locations() throws {
        // Allowed.
        try h.make("s/Package.swift"); try h.make("w/package.json"); try h.make("gr/settings.gradle")
        for p in ["s/.build", "w/.next", "w/.turbo", "w/.parcel-cache", "gr/.gradle",
                  ".lmstudio/models/pub/model-x", ".cache/lm-studio/models/pub/model-y",
                  ".android/avd/Pixel_8.avd", "Library/Android/sdk/system-images/android-34",
                  "Library/Developer/XCPGDevices/ABC", "Library/Developer/Xcode/UserData/Previews/Simulator Devices/DEF",
                  "Library/Developer/Xcode/DocumentationCache/v1", "Library/Developer/CoreSimulator/Caches/dyld"] {
            try h.dir(p)
            #expect(g.allows(u(p)), "\(p)")
        }
        try h.make(".android/avd/Pixel_8.ini")
        #expect(g.allows(u(".android/avd/Pixel_8.ini")))
        // Hidden entries and anything that isn't an emulator folder or .ini file are refused.
        try h.make(".android/avd/notes.txt"); try h.make(".android/avd/fake.avd"); try h.dir(".android/avd/odd.ini")
        try h.make("Library/Developer/XCPGDevices/.DS_Store"); try h.make(".lmstudio/models/pub/.DS_Store")
        try h.dir(".lmstudio/models/.hidden/m")
        for p in [".android/avd/notes.txt", ".android/avd/fake.avd", ".android/avd/odd.ini",
                  "Library/Developer/XCPGDevices/.DS_Store", ".lmstudio/models/pub/.DS_Store", ".lmstudio/models/.hidden/m"] {
            #expect(!g.allows(u(p)), "\(p)")
        }
        try h.dir(".ollama/models/blobs")
        #expect(g.allows(u(".ollama/models")))
        // Refused: the folders themselves, wrong depths, unmarked dot folders, Ollama's insides.
        for p in [".lmstudio/models", ".lmstudio/models/pub", ".lmstudio/models/pub/model-x/file.gguf",
                  ".ollama", ".ollama/models/blobs", ".android/avd", ".android", "Library/Android/sdk/system-images",
                  "Library/Developer/XCPGDevices", "Library/Developer/CoreSimulator/Caches",
                  "n/.build", "n/.next", "n/.gradle", ".build"] {
            try h.dir(p)
            #expect(!g.allows(u(p)), "\(p)")
        }
    }

    @Test func projectAndModelFolders() throws {
        try h.make("p/entry/hvigorfile.ts"); try h.dir("p/entry/build")
        try h.make("p/Cargo.toml"); try h.dir("p/target")
        try h.make("p/.venv/pyvenv.cfg")
        for p in ["p/entry/build", "p/target", "p/.venv", ".cache/huggingface/hub/models--a--b", "z/hf/hub/models--a--b"] {
            try h.dir(p)
            #expect(g.allows(u(p)), "\(p)")
        }
        try h.dir("p2/build"); try h.dir(".cache/huggingface/hub")
        try h.make("m/build.gradle"); try h.make("m/build/run.sh")
        try h.make("X.app/Contents/Cargo.toml"); try h.dir("X.app/Contents/target")
        try h.make(".secret/p/Cargo.toml"); try h.dir(".secret/p/target")
        try h.make("Library/p/build.gradle"); try h.dir("Library/p/build")
        try h.make("p/.hvigor/build.gradle"); try h.dir("p/.hvigor/build")
        try h.dir("z/hf/models--a--b")
        if TempHome.gitAvailable {
            try h.git(u("m"), "init"); try h.git(u("m"), "add", "-f", "."); try h.git(u("m"), "commit", "-m", "x")
            #expect(!g.allows(u("m/build")), "git-tracked")
        }
        for p in ["p2/build", ".cache/huggingface", ".cache/huggingface/hub", "z/hf/models--a--b", "X.app/Contents/target",
                  ".secret/p/target", "Library/p/build", "p/.hvigor/build"] {
            #expect(!g.allows(u(p)), "\(p)")
        }
    }

    @Test func oldEditorExtensionsOnlyWhenRemovable() throws {
        for f in ["a.b-1.0.0", "a.b-1.2.0"] { try h.make(".vscode/extensions/\(f)/package.json") }
        try Data("[{\"relativeLocation\":\"a.b-1.2.0\"}]".utf8).write(to: u(".vscode/extensions/extensions.json"))
        #expect(g.allows(u(".vscode/extensions/a.b-1.0.0")))
        #expect(!g.allows(u(".vscode/extensions")))
        #expect(!g.allows(u(".vscode/extensions/a.b-1.2.0")))
        #expect(!g.allows(u(".vscode/extensions/a.b-1.0.0/package.json")))
        #expect(!g.allows(u(".vscode/extensions/extensions.json")))
        try FileManager.default.removeItem(at: u(".vscode/extensions/extensions.json"))
        #expect(!g.allows(u(".vscode/extensions/a.b-1.0.0")))
    }
}
