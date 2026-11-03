import AppKit
import Foundation

public struct FileScanners: Sendable {
    let locations: Locations
    let scanRoots: [URL]
    let now: Date
    let cutoffDays: Int
    let runningBundleIDs: Set<String>
    let removalGuard: RemovalGuard

    public init(locations: Locations, scanRoots: [URL], now: Date, cutoffDays: Int, runningBundleIDs: Set<String>) {
        self.locations = locations; self.scanRoots = scanRoots; self.now = now
        self.cutoffDays = cutoffDays; self.runningBundleIDs = runningBundleIDs
        removalGuard = RemovalGuard(locations: locations, scanRoots: scanRoots)
    }

    /// Lists only what the Cleaner's guard would allow, so scanner and guard never disagree.
    private func result(_ id: CategoryID, _ items: [CleanItem]) -> CategoryResult {
        CategoryResult(id: id, items: items.filter {
            if case .trash(let u) = $0.method { return removalGuard.allows(u) }
            return true
        }, status: .fresh)
    }

    public func derivedData() throws -> CategoryResult {
        let items = try children(locations.derivedData).map { u in
            var name = u.lastPathComponent
            if let i = name.lastIndex(of: "-") { name = String(name[..<i]) }
            return try makeItem(.derivedData, u, name: name, detail: "")
        }
        return result(.derivedData, items)
    }

    public func packageCaches() throws -> CategoryResult {
        let items = try locations.packageCaches.filter { exists($0.url) }.map {
            try makeItem(.packageCaches, $0.url, name: $0.tool, detail: abbreviate($0.url.path))
        }
        return result(.packageCaches, items)
    }

    public func appCaches() throws -> CategoryResult {
        let pkg = Set(locations.packageCaches.map { $0.url.standardizedFileURL.path })
        let items = try children(locations.caches).compactMap { u -> CleanItem? in
            let id = u.lastPathComponent
            if id.hasPrefix("com.apple.") || pkg.contains(u.standardizedFileURL.path) { return nil }
            var it = try makeItem(.appCaches, u, name: appName(id) ?? id, detail: id)
            if runningBundleIDs.contains(id) { it.tags.insert(.appRunning) }
            return it
        }
        return result(.appCaches, items)
    }

    public func deviceSupport() throws -> CategoryResult {
        var items: [CleanItem] = []
        for folder in locations.deviceSupportFolders {
            for u in try children(folder) {
                items.append(try makeItem(.deviceSupport, u, name: u.lastPathComponent, detail: folder.lastPathComponent))
            }
        }
        return result(.deviceSupport, items)
    }

    public func wallpaper() throws -> CategoryResult {
        let items = try children(locations.wallpaperVideos).map {
            try makeItem(.wallpaper, $0, name: $0.lastPathComponent, detail: "")
        }
        return result(.wallpaper, items)
    }

    public func nodeModules() throws -> CategoryResult {
        let library = locations.home.appendingPathComponent("Library").standardizedFileURL.path
        var items: [CleanItem] = []
        var seen: Set<String> = []
        for root in scanRoots {
            guard let en = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }) else { continue }
            var n = 0
            for case let u as URL in en {
                n += 1
                if n % 1000 == 0 { try Task.checkCancellation() }
                guard let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      v.isDirectory == true, v.isSymbolicLink != true else { continue }
                let name = u.lastPathComponent
                if name.hasPrefix(".") || u.standardizedFileURL.path == library { en.skipDescendants(); continue }
                if name == "node_modules" {
                    en.skipDescendants()
                    let parent = u.deletingLastPathComponent()
                    // Only project folders; skips global installs like ~/n/lib/node_modules.
                    guard exists(parent.appendingPathComponent("package.json")),
                          seen.insert(u.standardizedFileURL.path).inserted else { continue }
                    let lastUsed = try folderStats(parent, skipping: ["node_modules"]).newestModification
                    var it = try makeItem(.nodeModules, u, name: parent.lastPathComponent, detail: abbreviate(parent.path))
                    it.lastUsed = lastUsed
                    it.tags.remove(.recentlyUsed)
                    if isRecentlyUsed(lastUsed, now: now, cutoffDays: cutoffDays) { it.tags.insert(.recentlyUsed) }
                    items.append(it)
                }
            }
        }
        return result(.nodeModules, items)
    }

    // MARK: helpers

    private func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    private func children(_ dir: URL) throws -> [URL] {
        guard exists(dir) else { return [] }
        let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        return all.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
    }

    private func abbreviate(_ path: String) -> String {
        let h = locations.home.path
        return path == h ? "~" : path.hasPrefix(h + "/") ? "~" + path.dropFirst(h.count) : path
    }

    private func appName(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    private func makeItem(_ c: CategoryID, _ u: URL, name: String, detail: String) throws -> CleanItem {
        let s = try folderStats(u)
        let std = u.standardizedFileURL
        return CleanItem(id: std.path, category: c, name: name, detail: detail, sizeBytes: s.allocatedBytes,
                         lastUsed: s.newestModification, method: .trash(std),
                         tags: isRecentlyUsed(s.newestModification, now: now, cutoffDays: cutoffDays) ? [.recentlyUsed] : [])
    }
}
