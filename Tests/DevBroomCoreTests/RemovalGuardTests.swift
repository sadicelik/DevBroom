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
}
