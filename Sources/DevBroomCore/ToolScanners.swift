import Foundation

private func parseISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    let plain = ISO8601DateFormatter()
    let frac = ISO8601DateFormatter()
    frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return plain.date(from: s) ?? frac.date(from: s)
}

private func int64(_ v: Any?) -> Int64 { (v as? NSNumber)?.int64Value ?? 0 }

public enum SimctlParser {
    private static func dict(_ json: Data) throws -> [String: Any] {
        guard let d = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return d
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-26-5` -> `iOS 26.5`
    static func osVersion(_ runtimeKey: String) -> String {
        let tail = runtimeKey.split(separator: ".").last.map(String.init) ?? runtimeKey
        let parts = tail.split(separator: "-").map(String.init)
        guard let platform = parts.first else { return tail }
        return ([platform] + [parts.dropFirst().joined(separator: ".")]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func devices(_ json: Data, now: Date, cutoffDays: Int) throws -> [CleanItem] {
        guard let byRuntime = try dict(json)["devices"] as? [String: [[String: Any]]] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return byRuntime.flatMap { runtime, devs in
            devs.compactMap { d -> CleanItem? in
                guard let udid = d["udid"] as? String else { return nil }
                let last = parseISO(d["lastBootedAt"] as? String)
                var tags = Set<ItemTag>()
                if d["state"] as? String == "Booted" { tags.insert(.inUse) }
                if isRecentlyUsed(last, now: now, cutoffDays: cutoffDays) { tags.insert(.recentlyUsed) }
                return CleanItem(id: "simdevice:\(udid)", category: .simDevices,
                                 name: d["name"] as? String ?? udid, detail: osVersion(runtime),
                                 sizeBytes: int64(d["dataPathSize"]), lastUsed: last,
                                 method: .simctlDevice(udid: udid), tags: tags)
            }
        }
    }

    /// `bootedRuntimeKeys`: runtime identifiers that have a Booted device (from the devices JSON).
    public static func runtimes(_ json: Data, now: Date, cutoffDays: Int,
                                bootedRuntimeKeys: Set<String> = []) throws -> [CleanItem] {
        let platforms = ["iphonesimulator": "iOS", "watchsimulator": "watchOS",
                         "appletvsimulator": "tvOS", "xrsimulator": "visionOS"]
        return try dict(json).values.compactMap { v -> CleanItem? in
            guard let r = v as? [String: Any], r["deletable"] as? Bool != false,
                  let id = r["identifier"] as? String else { return nil }
            let plat = (r["platformIdentifier"] as? String)?.split(separator: ".").last.map(String.init) ?? ""
            let last = parseISO(r["lastUsedAt"] as? String)
            var tags = Set<ItemTag>()
            if let key = r["runtimeIdentifier"] as? String, bootedRuntimeKeys.contains(key) { tags.insert(.inUse) }
            if isRecentlyUsed(last, now: now, cutoffDays: cutoffDays) { tags.insert(.recentlyUsed) }
            return CleanItem(id: "simruntime:\(id)", category: .simRuntimes,
                             name: "\(platforms[plat] ?? plat) \(r["version"] as? String ?? "")",
                             detail: r["build"] as? String ?? "", sizeBytes: int64(r["sizeBytes"]),
                             lastUsed: last, method: .simctlRuntime(identifier: id), tags: tags)
        }
    }

    static func bootedRuntimeKeys(_ devicesJSON: Data) -> Set<String> {
        guard let by = (try? dict(devicesJSON))?["devices"] as? [String: [[String: Any]]] else { return [] }
        return Set(by.filter { $0.value.contains { $0["state"] as? String == "Booted" } }.keys)
    }
}

public enum DockerParser {
    public static func reclaimableBytes(_ dfJSONLines: String) -> Int64 {
        dfJSONLines.split(whereSeparator: \.isNewline).reduce(0) { sum, line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let r = o["Reclaimable"] as? String else { return sum }
            return sum + parseSize(r)
        }
    }

    /// "1.5GB (40%)" -> 1_500_000_000 (decimal units); unparseable -> 0.
    static func parseSize(_ s: String) -> Int64 {
        let token = s.split(separator: " ").first.map(String.init) ?? ""
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("B", 1)]
        for (u, mult) in units where token.hasSuffix(u) {
            guard let n = Double(token.dropLast(u.count)) else { return 0 }
            return Int64((n * mult).rounded())
        }
        return 0
    }
}

public struct ToolScanners: Sendable {
    let runner: CommandRunner
    let home: URL
    let now: Date
    let cutoffDays: Int
    /// `xcode-select -p`, run once per scanner: without developer tools any `xcrun` call pops an install dialog.
    private let developerTools: Task<Bool, Never>

    public init(runner: CommandRunner, home: URL, now: Date, cutoffDays: Int) {
        self.runner = runner; self.home = home; self.now = now; self.cutoffDays = cutoffDays
        developerTools = Task { (try? await runner.run(ToolLocator.xcodeSelect, ["-p"]))?.status == 0 }
    }

    private static let simMissing = "Xcode simulator tools not found"
    private static let noXcode = "Xcode not installed"

    private func simctl(_ args: [String]) async -> Data? {
        guard await developerTools.value, let out = try? await runner.run(ToolLocator.xcrun, ["simctl"] + args), out.status == 0 else { return nil }
        return Data(out.stdout.utf8)
    }

    public func simDevices() async -> CategoryResult {
        guard await developerTools.value else { return CategoryResult(id: .simDevices, items: [], status: .unavailable(Self.noXcode)) }
        guard let json = await simctl(["list", "devices", "--json"]),
              let items = try? SimctlParser.devices(json, now: now, cutoffDays: cutoffDays)
        else { return CategoryResult(id: .simDevices, items: [], status: .unavailable(Self.simMissing)) }
        return CategoryResult(id: .simDevices, items: items, status: .fresh)
    }

    public func simRuntimes() async -> CategoryResult {
        guard await developerTools.value else { return CategoryResult(id: .simRuntimes, items: [], status: .unavailable(Self.noXcode)) }
        let devices = await simctl(["list", "devices", "--json"])
        guard let json = await simctl(["runtime", "list", "--json"]) else {
            // `simctl runtime` arrived in Xcode 15; older simctl still lists devices.
            let why = devices == nil ? Self.simMissing : "Simulator runtimes need Xcode 15 or later"
            return CategoryResult(id: .simRuntimes, items: [], status: .unavailable(why))
        }
        let booted = devices.map(SimctlParser.bootedRuntimeKeys) ?? []
        guard let items = try? SimctlParser.runtimes(json, now: now, cutoffDays: cutoffDays, bootedRuntimeKeys: booted)
        else { return CategoryResult(id: .simRuntimes, items: [], status: .unavailable(Self.simMissing)) }
        return CategoryResult(id: .simRuntimes, items: items, status: .fresh)
    }

    public func docker() async -> CategoryResult? {
        guard let exe = ToolLocator.docker(home: home) else { return nil }
        guard let out = try? await runner.run(exe, ["system", "df", "--format", "{{json .}}"]), out.status == 0 else {
            return CategoryResult(id: .docker, items: [], status: .unavailable("Docker not running"))
        }
        let raw = home.appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
        var detail = ""
        if let n = (try? raw.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize {
            detail = "Docker disk uses " + ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
        }
        let item = CleanItem(id: "docker", category: .docker, name: "Images, build cache, stopped containers",
                             detail: detail, sizeBytes: DockerParser.reclaimableBytes(out.stdout),
                             lastUsed: nil, method: .dockerPrune, tags: [])
        return CategoryResult(id: .docker, items: [item], status: .fresh)
    }
}
