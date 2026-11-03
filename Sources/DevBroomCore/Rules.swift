import Foundation

public func isRecentlyUsed(_ lastUsed: Date?, now: Date, cutoffDays: Int) -> Bool {
    guard let lastUsed else { return false }
    return now.timeIntervalSince(lastUsed) < Double(cutoffDays) * 86_400
}

public func defaultTicked(_ item: CleanItem, now: Date, cutoffDays: Int) -> Bool {
    item.kind == .rebuilds
        && !isRecentlyUsed(item.lastUsed, now: now, cutoffDays: cutoffDays)
        && item.tags.isDisjoint(with: [.appRunning, .inUse])
}
