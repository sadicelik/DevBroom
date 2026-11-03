import Foundation

public func freeBytes(at volume: URL) -> Int64? {
    let v = try? volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return v?.volumeAvailableCapacityForImportantUsage
}

public struct LowSpaceNotifier: Sendable {
    public var limitBytes: Int64
    public private(set) var isBelow = false
    public init(limitBytes: Int64) { self.limitBytes = limitBytes }

    /// True only on the transition from at-or-above the limit to below it.
    public mutating func update(freeBytes: Int64) -> Bool {
        let below = freeBytes < limitBytes
        defer { isBelow = below }
        return below && !isBelow
    }
}
