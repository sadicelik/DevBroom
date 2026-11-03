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
    public var packageCaches: [(tool: String, url: URL)] {
        [("npm", h(".npm")), ("Yarn", h("Library/Caches/Yarn")), ("pnpm", h("Library/pnpm/store")),
         ("pip", h("Library/Caches/pip")), ("Homebrew", h("Library/Caches/Homebrew")),
         ("CocoaPods", h("Library/Caches/CocoaPods")), ("Gradle", h(".gradle/caches"))]
    }
}
