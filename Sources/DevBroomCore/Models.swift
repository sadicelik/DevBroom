import Foundation

public enum CleanKind: String, Codable, Sendable { case rebuilds, redownload }

public enum CategoryID: String, Codable, CaseIterable, Sendable {
    case derivedData, packageCaches, appCaches, nodeModules, projectBuilds, deviceSupport, wallpaper, aiModels,
         oldExtensions, simDevices, simRuntimes, docker

    public var title: String {
        switch self {
        case .derivedData: "Xcode DerivedData"
        case .packageCaches: "Package caches"
        case .appCaches: "App caches"
        case .nodeModules: "node_modules"
        case .projectBuilds: "Project builds"
        case .deviceSupport: "iOS DeviceSupport"
        case .wallpaper: "Wallpaper downloads"
        case .aiModels: "AI model downloads"
        case .oldExtensions: "Old editor extensions"
        case .simDevices: "Simulator devices"
        case .simRuntimes: "Simulator runtimes"
        case .docker: "Docker"
        }
    }

    public var kind: CleanKind {
        switch self {
        case .derivedData, .packageCaches, .appCaches, .nodeModules, .projectBuilds, .oldExtensions: .rebuilds
        default: .redownload
        }
    }
}

public enum RemovalMethod: Codable, Hashable, Sendable {
    case trash(URL)
    case simctlDevice(udid: String)
    case simctlRuntime(identifier: String)
    case dockerPrune

    public var isPermanent: Bool {
        if case .trash = self { return false }
        return true
    }
}

public enum ItemTag: String, Codable, Sendable { case recentlyUsed, appRunning, inUse }

public struct CleanItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var category: CategoryID
    public var name: String
    public var detail: String
    public var sizeBytes: Int64
    public var lastUsed: Date?
    public var method: RemovalMethod
    public var tags: Set<ItemTag>
    public var kindOverride: CleanKind?
    public var kind: CleanKind { kindOverride ?? category.kind }

    public init(id: String, category: CategoryID, name: String, detail: String, sizeBytes: Int64,
                lastUsed: Date?, method: RemovalMethod, tags: Set<ItemTag>,
                kindOverride: CleanKind? = nil) {
        self.id = id; self.category = category; self.name = name; self.detail = detail
        self.sizeBytes = sizeBytes; self.lastUsed = lastUsed; self.method = method; self.tags = tags
        self.kindOverride = kindOverride
    }
}

public enum CategoryStatus: Codable, Hashable, Sendable { case fresh, notUpdated, unavailable(String) }

public struct CategoryResult: Codable, Identifiable, Sendable {
    public var id: CategoryID
    public var items: [CleanItem]
    public var status: CategoryStatus
    public var sizeBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    public init(id: CategoryID, items: [CleanItem], status: CategoryStatus) {
        self.id = id; self.items = items; self.status = status
    }
}
