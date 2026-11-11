import Foundation

/// How the items inside an opened row are ordered.
public enum ItemSort: String, CaseIterable, Sendable {
    case size = "Size", lastUsed = "Last used", name = "Name"
}

/// Items of one row, filtered by `query` (name, detail or path, case-insensitive) and sorted.
/// `.lastUsed` puts the longest-unused first; never-used items count as oldest.
public func arrange(_ items: [CleanItem], by sort: ItemSort, matching query: String = "") -> [CleanItem] {
    let q = query.trimmingCharacters(in: .whitespaces)
    let found = q.isEmpty ? items : items.filter {
        $0.name.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q)
            || $0.id.localizedCaseInsensitiveContains(q)
    }
    switch sort {
    case .size: return found.sorted { $0.sizeBytes > $1.sizeBytes }
    case .lastUsed: return found.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
    case .name: return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// The result without items the owner chose to hide ("Hide from DevBroom"); hidden ids match `CleanItem.id` exactly.
public func removingHidden(_ result: CategoryResult, hidden: some Collection<String>) -> CategoryResult {
    let set = Set(hidden)
    var r = result
    r.items.removeAll { set.contains($0.id) }
    return r
}
