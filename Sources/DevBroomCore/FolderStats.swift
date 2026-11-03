import Foundation

public struct FolderStats: Sendable {
    public var allocatedBytes: Int64
    public var newestModification: Date?
}

private let statKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]

/// Sums allocated size and newest mtime under `url` (or of `url` itself if a file).
/// Never follows symlinks; unreadable entries are skipped.
public func folderStats(_ url: URL, skipping: Set<String> = []) throws -> FolderStats {
    var stats = FolderStats(allocatedBytes: 0, newestModification: nil)
    func add(_ v: URLResourceValues) {
        stats.allocatedBytes += Int64(v.totalFileAllocatedSize ?? 0)
        if let m = v.contentModificationDate, m > (stats.newestModification ?? .distantPast) { stats.newestModification = m }
    }
    // A folder's own mtime is not usage; only count the root when it is a file.
    if let v = try? url.resourceValues(forKeys: Set(statKeys.dropLast() + [.isDirectoryKey])), v.isDirectory != true { add(v) }
    guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: statKeys, options: [],
                                                  errorHandler: { _, _ in true }) else { return stats }
    var n = 0
    for case let u as URL in en {
        n += 1
        if n % 1000 == 0 { try Task.checkCancellation() }
        guard let v = try? u.resourceValues(forKeys: Set(statKeys)) else { continue }
        if v.isSymbolicLink == true { en.skipDescendants(); continue }
        if skipping.contains(u.lastPathComponent) { en.skipDescendants(); continue }
        add(v)
    }
    return stats
}
