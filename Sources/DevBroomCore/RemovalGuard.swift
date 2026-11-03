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
        let hub: [String]
        let extensionFolders: [[String]]

        enum Match { case no, other, build }

        func match(_ p: [String]) -> Match {
            // Never inside an app bundle (e.g. VS Code's bundled node_modules).
            if p.contains(where: { $0.lowercased().hasSuffix(".app") }) { return .no }
            if p.count >= 2, extensionFolders.contains(Array(p.dropLast())) { return .other }
            if exact.contains(p) { return .other }
            if categoryFolders.contains(where: { p.count == $0.count + 1 && p.starts(with: $0) }) { return .other }
            guard let last = p.last, p.count >= 2 else { return .no }
            let isModel = last.hasPrefix("models--") || last.hasPrefix("datasets--")
            if isModel, p.count == hub.count + 1, p.starts(with: hub) { return .other }
            let isBuild = projectBuildFolderNames.contains(last)
            guard last == "node_modules" || isBuild || (isModel && p[p.count - 2] == "hub"),
                  scanRoots.contains(where: { p.count > $0.count && p.starts(with: $0) }) else { return .no }
            let dotOK: Bool
            if p.starts(with: home), p.count > home.count {
                // Inside home: judged relative to home; ~/Library excluded (APFS is case-insensitive).
                if p[home.count].lowercased() == "library" { return .no }
                dotOK = !p.dropFirst(home.count).dropLast().contains { $0.hasPrefix(".") }
            } else {
                // Outside home: every component counts.
                dotOK = !p.dropFirst().dropLast().contains { $0.hasPrefix(".") }
            }
            // The last component may start with a dot only for .hvigor / .venv.
            guard dotOK, !last.hasPrefix(".") || last == ".hvigor" || last == ".venv" else { return .no }
            return isBuild ? .build : .other
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
                  scanRoots: scanRoots.map(f), hub: f(locations.huggingFaceHub),
                  extensionFolders: locations.editorExtensions.map { f($0.url) })
        }
        plain = make { $0.standardizedFileURL.pathComponents }
        resolved = make { $0.resolvingSymlinksInPath().pathComponents }
        editorExtensionFolders = locations.editorExtensions.map { $0.url.standardizedFileURL.pathComponents }
    }

    /// `gitTracks` defaults to the real check; scans may pass a cached one. The Cleaner never does.
    public func allows(_ url: URL, gitTracks: (URL) -> Bool = { gitTracksFiles(in: $0) }) -> Bool {
        guard url.isFileURL, !url.pathComponents.contains("..") else { return false }
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return false }
        let a = plain.match(url.standardizedFileURL.pathComponents)
        let b = resolved.match(url.resolvingSymlinksInPath().pathComponents)
        guard a != .no, b != .no else { return false }
        if isEditorExtensionChild(url) { return removableExtensionFolders(in: url.deletingLastPathComponent()).contains(url.lastPathComponent) }
        if a == .build || b == .build {
            return buildEcosystem(of: url.standardizedFileURL) != nil && !gitTracks(url)
        }
        return true
    }

    private let editorExtensionFolders: [[String]]

    private func isEditorExtensionChild(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.pathComponents
        return p.count >= 2 && editorExtensionFolders.contains(Array(p.dropLast()))
    }
}
