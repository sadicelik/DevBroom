import Foundation

/// The single allow-list check every Trash removal must pass (spec section 10).
/// An item must pass on its standardized path and again on its fully symlink-resolved path
/// (against symlink-resolved locations), so a symlinked parent cannot smuggle it in.
public struct RemovalGuard: Sendable {
    private struct Rules: Sendable {
        let home: [String]
        let categoryFolders: [[String]]
        let exact: [[String]]
        let scanRoots: [[String]]

        func allows(_ p: [String]) -> Bool {
            // Never inside an app bundle (e.g. VS Code's bundled node_modules).
            if p.contains(where: { $0.lowercased().hasSuffix(".app") }) { return false }
            if exact.contains(p) { return true }
            if categoryFolders.contains(where: { p.count == $0.count + 1 && p.starts(with: $0) }) { return true }
            guard p.last == "node_modules",
                  scanRoots.contains(where: { p.count > $0.count && p.starts(with: $0) }) else { return false }
            if p.starts(with: home), p.count > home.count {
                // Inside home: judged relative to home; ~/Library excluded (APFS is case-insensitive).
                if p[home.count].lowercased() == "library" { return false }
                return !p.dropFirst(home.count).contains { $0.hasPrefix(".") }
            }
            // Outside home: every component counts.
            return !p.dropFirst().contains { $0.hasPrefix(".") }
        }
    }

    private let plain: Rules
    private let resolved: Rules

    public init(locations: Locations, scanRoots: [URL]) {
        func make(_ f: (URL) -> [String]) -> Rules {
            Rules(home: f(locations.home),
                  categoryFolders: ([locations.caches, locations.derivedData, locations.wallpaperVideos]
                    + locations.deviceSupportFolders).map(f),
                  exact: locations.packageCaches.map { f($0.url) },
                  scanRoots: scanRoots.map(f))
        }
        plain = make { $0.standardizedFileURL.pathComponents }
        resolved = make { $0.resolvingSymlinksInPath().pathComponents }
    }

    public func allows(_ url: URL) -> Bool {
        guard url.isFileURL, !url.pathComponents.contains("..") else { return false }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return false }
        return plain.allows(url.standardizedFileURL.pathComponents)
            && resolved.allows(url.resolvingSymlinksInPath().pathComponents)
    }
}
