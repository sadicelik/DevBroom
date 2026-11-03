import Foundation

public struct Locations: Sendable {
    public let home: URL
    public init(home: URL) { self.home = home }

    private func h(_ path: String) -> URL { home.appendingPathComponent(path) }

    public var caches: URL { h("Library/Caches") }
    public var derivedData: URL { h("Library/Developer/Xcode/DerivedData") }
    public var deviceSupportFolders: [URL] {
        ["iOS", "watchOS", "tvOS", "visionOS"].map { h("Library/Developer/Xcode/\($0) DeviceSupport") }
    }
    public var wallpaperVideos: URL { h("Library/Application Support/com.apple.wallpaper/aerials/videos") }
    public var huggingFaceHub: URL { h(".cache/huggingface/hub") }
    public var packageCaches: [(tool: String, url: URL, kind: CleanKind)] {
        [("npm", h(".npm"), .rebuilds), ("Yarn", h("Library/Caches/Yarn"), .rebuilds),
         ("pnpm", h("Library/pnpm/store"), .rebuilds), ("pip", h("Library/Caches/pip"), .rebuilds),
         ("Homebrew", h("Library/Caches/Homebrew"), .rebuilds), ("CocoaPods", h("Library/Caches/CocoaPods"), .rebuilds),
         ("Gradle", h(".gradle/caches"), .rebuilds), ("Cargo", h(".cargo/registry"), .rebuilds),
         ("Cargo git", h(".cargo/git"), .rebuilds), ("Go modules", h("go/pkg/mod"), .rebuilds),
         ("Maven", h(".m2/repository"), .redownload), ("Bun", h(".bun/install/cache"), .rebuilds),
         ("uv", h(".cache/uv"), .rebuilds), ("pip", h(".cache/pip"), .rebuilds),
         ("Dart/Flutter", h(".pub-cache"), .redownload), ("Gradle wrapper", h(".gradle/wrapper/dists"), .rebuilds)]
    }
}
