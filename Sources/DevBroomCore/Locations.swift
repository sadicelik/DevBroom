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
    /// LM Studio keeps models as `<publisher>/<model>` folders; one item per model.
    public var lmStudioModels: [URL] { [h(".lmstudio/models"), h(".cache/lm-studio/models")] }
    /// Ollama models share blobs, so the whole folder is one item.
    public var ollamaModels: URL { h(".ollama/models") }
    /// One `<name>.avd` folder plus `<name>.ini` file per emulator.
    public var androidAVDs: URL { h(".android/avd") }
    public var androidSystemImages: URL { h("Library/Android/sdk/system-images") }
    /// SwiftUI preview simulators, documentation cache, simulator caches: Xcode recreates them.
    public var xcodeExtras: [(label: String, url: URL)] {
        [("SwiftUI previews", h("Library/Developer/XCPGDevices")),
         ("SwiftUI previews", h("Library/Developer/Xcode/UserData/Previews/Simulator Devices")),
         ("Documentation cache", h("Library/Developer/Xcode/DocumentationCache")),
         ("Simulator caches", h("Library/Developer/CoreSimulator/Caches"))]
    }
    public var editorExtensions: [(editor: String, bundleID: String, url: URL)] {
        [("VS Code", "com.microsoft.VSCode", h(".vscode/extensions")),
         ("Cursor", "com.todesktop.230313mzl4w4u92", h(".cursor/extensions"))]
    }
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
