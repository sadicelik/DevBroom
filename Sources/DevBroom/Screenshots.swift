import AppKit
import DevBroomCore
import SwiftUI

/// `DevBroom --render-screenshots <dir>`: draws the README screenshots off-screen from example data, then quits.
/// Needs no Screen Recording permission and never shows the owner's real files.
@MainActor enum Screenshots {
    static func renderIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-screenshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let defaults = UserDefaults(suiteName: "DevBroomScreenshots")!
        defer { defaults.removePersistentDomain(forName: "DevBroomScreenshots") }
        let settings = AppSettings(defaults: defaults, home: URL(fileURLWithPath: "/Users/you"), registrar: { _ in })
        settings.hiddenItems = ["/Users/you/code/client-app/node_modules": "client-app"]
        let model = AppModel(demoSettings: settings, results: demoResults(), freeBytes: 21_400_000_000,
                             totalBytes: 245_100_000_000)

        render(PopoverView(model: model), width: 424, to: dir.appending(path: "popover.png"))
        render(CleanSheet(model: model, items: model.selectedItems, recentlyUnticked: [], dismiss: {}).padding(12),
               width: 424, to: dir.appending(path: "clean-summary.png"))
        render(SettingsView(settings: settings), width: 440, to: dir.appending(path: "settings.png"))
        var report = CleanReport()
        let trashed = model.selectedItems.filter { !$0.method.isPermanent }
        report.trashedBytes = trashed.reduce(0) { $0 + $1.sizeBytes }
        report.trashedItems = trashed.map { TrashedItem(url: URL(fileURLWithPath: "/Users/you/.Trash/\($0.name)"), bytes: $0.sizeBytes) }
        model.lastReport = report
        render(CleanSheet(model: model, items: [], recentlyUnticked: [], dismiss: {}).padding(12),
               width: 424, to: dir.appending(path: "clean-done.png"))
        defaults.removePersistentDomain(forName: "DevBroomScreenshots")  // exit(0) skips the defer
        exit(0)
    }

    private static func render(_ view: some View, width: CGFloat, to file: URL) {
        let host = NSHostingView(rootView: view.frame(width: width - 24)
            .background(Color(nsColor: .windowBackgroundColor)))
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))  // let SwiftUI finish its first layout pass
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }

    private static func demoResults() -> [CategoryResult] {
        let gb: Int64 = 1_000_000_000
        func ago(_ days: Double) -> Date { Date().addingTimeInterval(-days * 86_400) }
        func item(_ c: CategoryID, _ name: String, _ detail: String, _ size: Double, _ days: Double,
                  method: RemovalMethod? = nil, tags: Set<ItemTag> = [], kind: CleanKind? = nil) -> CleanItem {
            let id = "/Users/you/demo/\(c.rawValue)/\(name)"
            return CleanItem(id: id, category: c, name: name, detail: detail, sizeBytes: Int64(size * Double(gb)),
                             lastUsed: ago(days), method: method ?? .trash(URL(fileURLWithPath: id)),
                             tags: days < 14 ? tags.union([.recentlyUsed]) : tags, kindOverride: kind)
        }
        let r: [(CategoryID, [CleanItem])] = [
            (.derivedData, [item(.derivedData, "WeatherApp", "", 6.2, 40), item(.derivedData, "Notes", "", 3.1, 3)]),
            (.packageCaches, [item(.packageCaches, "npm", "~/.npm", 2.4, 30), item(.packageCaches, "Gradle", "~/.gradle/caches", 3.6, 22),
                              item(.packageCaches, "Maven", "~/.m2/repository", 1.1, 60, kind: .redownload)]),
            (.appCaches, [item(.appCaches, "Google Chrome", "com.google.Chrome", 1.8, 1, tags: [.appRunning]),
                          item(.appCaches, "Slack", "com.tinyspeck.slackmacgap", 0.7, 25)]),
            (.nodeModules, [item(.nodeModules, "landing-page", "~/code/landing-page", 1.3, 95), item(.nodeModules, "dashboard", "~/code/dashboard", 0.9, 2)]),
            (.projectBuilds, [item(.projectBuilds, "weather-app · Android build", "~/code/weather-app/app", 2.7, 48),
                              item(.projectBuilds, "ml-tools · Python .venv", "~/code/ml-tools", 1.6, 70)]),
            (.deviceSupport, [item(.deviceSupport, "iPhone15,2 18.5 (22F76)", "iOS DeviceSupport", 4.4, 120)]),
            (.aiModels, [item(.aiModels, "facebook/nllb-200-distilled-600M", "~/.cache/huggingface/hub", 2.5, 33)]),
            (.simRuntimes, [item(.simRuntimes, "iOS 18.5", "22F77", 8.4, 90, method: .simctlRuntime(identifier: "demo"))]),
            (.simDevices, [item(.simDevices, "iPhone 16", "iOS 18.5", 1.9, 90, method: .simctlDevice(udid: "demo"))]),
        ]
        return r.map { CategoryResult(id: $0.0, items: $0.1.sorted { $0.sizeBytes > $1.sizeBytes }, status: .fresh) }
            .sorted { CategoryID.allCases.firstIndex(of: $0.id)! < CategoryID.allCases.firstIndex(of: $1.id)! }
    }
}
