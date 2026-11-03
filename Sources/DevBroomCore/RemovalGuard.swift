import Foundation

/// The single allow-list check every Trash removal must pass (spec section 10).
public struct RemovalGuard: Sendable {
    private let home: [String]
    private let categoryFolders: [[String]]
    private let exact: [[String]]
    private let scanRoots: [[String]]

    public init(locations: Locations, scanRoots: [URL]) {
        home = Self.parts(locations.home)
        categoryFolders = ([locations.caches, locations.derivedData, locations.wallpaperVideos]
            + locations.deviceSupportFolders).map(Self.parts)
        exact = locations.packageCaches.map { Self.parts($0.url) }
        self.scanRoots = scanRoots.map(Self.parts)
    }

    private static func parts(_ url: URL) -> [String] { url.standardizedFileURL.pathComponents }

    public func allows(_ url: URL) -> Bool {
        guard url.isFileURL, !url.pathComponents.contains("..") else { return false }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return false }
        let p = Self.parts(url)
        if exact.contains(p) { return true }
        if categoryFolders.contains(where: { p.count == $0.count + 1 && p.starts(with: $0) }) { return true }
        guard p.last == "node_modules" else { return false }
        // Components are judged relative to home, or to the scan root when outside home.
        let base: [String]
        if p.starts(with: home), p.count > home.count {
            base = home
            if p[home.count] == "Library" { return false }
        } else if let root = scanRoots.first(where: { p.count > $0.count && p.starts(with: $0) }) {
            base = root
        } else { return false }
        guard scanRoots.contains(where: { p.count > $0.count && p.starts(with: $0) }) else { return false }
        return !p.dropFirst(base.count).contains { $0.hasPrefix(".") }
    }
}
