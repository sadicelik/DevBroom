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
    private func result(_ id: CategoryID, _ items: [CleanItem],
                        gitTracks: (URL) -> Bool = { gitTracksFiles(in: $0) }) -> CategoryResult {
        CategoryResult(id: id, items: items.filter {
            if case .trash(let u) = $0.method { return removalGuard.allows(u, gitTracks: gitTracks) }
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
            var it = try makeItem(.packageCaches, $0.url, name: $0.tool, detail: abbreviate($0.url.path))
            if $0.kind == .redownload { it.kindOverride = .redownload }
            return it
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

    public func xcodeExtras() throws -> CategoryResult {
        var items: [CleanItem] = []
        for (label, folder) in locations.xcodeExtras {
            for u in try children(folder) where isVisibleFolder(u) {
                items.append(try makeItem(.xcodeExtras, u, name: "\(label): \(u.lastPathComponent)", detail: abbreviate(folder.standardizedFileURL.path)))
            }
        }
        return result(.xcodeExtras, items)
    }

    /// Emulators (`<name>.avd`; its `<name>.ini` goes to the Trash with it) and SDK system images per Android version.
    public func androidEmulators() throws -> CategoryResult {
        var items: [CleanItem] = []
        for u in try children(locations.androidAVDs) where u.pathExtension == "avd" && isVisibleFolder(u) {
            var it = try makeItem(.androidEmulators, u, name: u.deletingPathExtension().lastPathComponent, detail: "Emulator")
            // A running emulator holds *.lock files in its folder.
            let names = (try? FileManager.default.contentsOfDirectory(atPath: u.path)) ?? []
            if names.contains(where: { $0.hasSuffix(".lock") }) { it.tags.insert(.inUse) }
            items.append(it)
        }
        for u in try children(locations.androidSystemImages) where isVisibleFolder(u) {
            items.append(try makeItem(.androidEmulators, u, name: "System image \(u.lastPathComponent)", detail: abbreviate(u.standardizedFileURL.path)))
        }
        return result(.androidEmulators, items)
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

    public func oldExtensions() throws -> CategoryResult {
        var items: [CleanItem] = []
        for ed in locations.editorExtensions {
            for folder in removableExtensionFolders(in: ed.url).sorted() {
                guard let p = parseExtensionFolder(folder) else { continue }
                let version = folder.dropFirst(p.id.count + 1).prefix { $0 != "-" }
                var it = try makeItem(.oldExtensions, ed.url.appending(path: folder), name: "\(p.id) \(version) · \(ed.editor)", detail: p.id)
                if runningBundleIDs.contains(ed.bundleID) { it.tags.insert(.appRunning) }
                items.append(it)
            }
        }
        return result(.oldExtensions, items)
    }

    public func wallpaper() throws -> CategoryResult {
        let items = try children(locations.wallpaperVideos).map {
            try makeItem(.wallpaper, $0, name: $0.lastPathComponent, detail: "")
        }
        return result(.wallpaper, items)
    }

    /// One walk of the scan roots for node_modules, build folders and model hubs, plus the HF cache.
    public func projects() throws -> [CategoryResult] {
        let library = locations.home.appendingPathComponent("Library").standardizedFileURL.path
        var nodes: [CleanItem] = [], builds: [CleanItem] = [], models: [CleanItem] = []
        var seen: Set<String> = []
        // Per-call memos: git answers by build folder, newest modification by usage folder.
        var gitMemo: [String: Bool] = [:]
        var usageMemo: [String: Date?] = [:]
        func tracked(_ u: URL) -> Bool {
            let key = u.standardizedFileURL.path
            if let c = gitMemo[key] { return c }
            let r = gitTracksFiles(in: u)
            gitMemo[key] = r
            return r
        }
        let packageCachePaths = Set(locations.packageCaches.map { $0.url.standardizedFileURL.path })
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
                if packageCachePaths.contains(u.standardizedFileURL.path) { en.skipDescendants(); continue }
                if projectBuildFolderNames.contains(name), let eco = buildEcosystem(of: u, home: locations.home) {
                    // Git-tracked candidates are not listed but are walked into like any other folder (spec 4.2).
                    if !tracked(u) {
                        en.skipDescendants()
                        guard seen.insert(u.standardizedFileURL.path).inserted else { continue }
                        let marker = u.deletingLastPathComponent()
                        let project = projectFolder(forMarkerFolder: marker, scanRoot: root)
                        var it = try makeItem(.projectBuilds, u, name: "\(project.lastPathComponent) · \(eco.rawValue) \(name)",
                                              detail: abbreviate(marker.standardizedFileURL.path))
                        try setUsage(&it, memo: &usageMemo)
                        builds.append(it)
                        continue
                    }
                }
                if name == "hub" {
                    let hits = try children(u).filter { modelDisplayName($0.lastPathComponent) != nil }
                    if !hits.isEmpty {
                        en.skipDescendants()
                        for m in hits where seen.insert(m.standardizedFileURL.path).inserted { models.append(try modelItem(m)) }
                        continue
                    }
                }
                if name.hasPrefix(".") || u.standardizedFileURL.path == library { en.skipDescendants(); continue }
                if name == "node_modules" {
                    en.skipDescendants()
                    let parent = u.deletingLastPathComponent()
                    // Only project folders; skips global installs like ~/n/lib/node_modules.
                    guard exists(parent.appendingPathComponent("package.json")),
                          seen.insert(u.standardizedFileURL.path).inserted else { continue }
                    var it = try makeItem(.nodeModules, u, name: parent.lastPathComponent, detail: abbreviate(parent.standardizedFileURL.path))
                    try setUsage(&it, memo: &usageMemo)
                    nodes.append(it)
                }
            }
        }
        for m in try children(locations.huggingFaceHub) where modelDisplayName(m.lastPathComponent) != nil {
            if seen.insert(m.standardizedFileURL.path).inserted { models.append(try modelItem(m)) }
        }
        for root in locations.lmStudioModels {
            for publisher in try children(root) where isVisibleFolder(publisher) {
                // Resolved path: an old LM Studio folder may be a link to the new one; list each model once.
                for m in try children(publisher) where isVisibleFolder(m) && seen.insert(m.resolvingSymlinksInPath().path).inserted {
                    models.append(try makeItem(.aiModels, m, name: "\(publisher.lastPathComponent)/\(m.lastPathComponent)",
                                               detail: "LM Studio"))
                }
            }
        }
        if exists(locations.ollamaModels), seen.insert(locations.ollamaModels.standardizedFileURL.path).inserted {
            models.append(try makeItem(.aiModels, locations.ollamaModels, name: "All Ollama models",
                                       detail: "Ollama keeps models together. Remove single ones with ollama rm."))
        }
        return [result(.nodeModules, nodes, gitTracks: tracked), result(.projectBuilds, builds, gitTracks: tracked),
                result(.aiModels, models, gitTracks: tracked)]
    }

    private func modelItem(_ u: URL) throws -> CleanItem {
        try makeItem(.aiModels, u, name: modelDisplayName(u.lastPathComponent) ?? u.lastPathComponent, detail: abbreviate(u.standardizedFileURL.path))
    }

    /// lastUsed from the item's usage folder (see `usageFolder`), so scan and re-check share one rule.
    private func setUsage(_ it: inout CleanItem, memo: inout [String: Date?]) throws {
        guard let (folder, skipping) = usageFolder(for: it, scanRoots: scanRoots) else { return }
        let key = folder.standardizedFileURL.path + "|" + skipping.sorted().joined(separator: ",")
        let lastUsed: Date?
        if let c = memo[key] { lastUsed = c } else {
            lastUsed = try folderStats(folder, skipping: skipping).newestModification
            memo[key] = .some(lastUsed)
        }
        it.lastUsed = lastUsed
        it.tags.remove(.recentlyUsed)
        if isRecentlyUsed(lastUsed, now: now, cutoffDays: cutoffDays) { it.tags.insert(.recentlyUsed) }
    }

    // MARK: helpers

    private func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    private func isVisibleFolder(_ u: URL) -> Bool {
        !u.lastPathComponent.hasPrefix(".") && (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

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
