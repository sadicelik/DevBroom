import AppKit
import DevBroomCore
import Observation
import UserNotifications

func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

/// Whole gigabytes for the menu bar ("31 GB").
func wholeGB(_ n: Int64) -> String {
    let gb = (Double(n) / 1e9).rounded()
    guard gb >= 1 else { return bytes(n) }
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = .useGB
    return f.string(fromByteCount: Int64(gb * 1e9))
}

/// `swift run` has no bundle; notifications and SMAppService crash there.
let isBundled = Bundle.main.bundleIdentifier != nil

@MainActor @Observable final class AppModel {
    let settings: AppSettings
    var results: [CategoryResult] = []
    var selected: Set<String> = []
    var freeBytes: Int64?
    var totalBytes: Int64?
    var isScanning = false
    var cleanProgress: (done: Int, total: Int)?
    var isCleaning = false
    /// Shown until the owner dismisses it, even across popover reopenings.
    var lastReport: CleanReport?
    /// Result of "Delete from Trash now" for `lastReport`.
    var trashPurge: (bytes: Int64, failures: [String])?
    var isPurging = false
    /// When the last full scan finished (kept across launches).
    var lastScanned: Date? = UserDefaults.standard.object(forKey: "lastScanned") as? Date

    @ObservationIgnored private(set) var isOpen = false
    @ObservationIgnored private var touched: Set<String> = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var notifier = LowSpaceNotifier(limitBytes: 0)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let home = FileManager.default.homeDirectoryForCurrentUser
    @ObservationIgnored private let store = ScanStore(file: FileManager.default
        .homeDirectoryForCurrentUser.appending(path: "Library/Application Support/DevBroom/scan.json"))
    /// Screenshot mode: fixed example data, never scans, saves or notifies.
    @ObservationIgnored private var isDemo = false

    init() {
        settings = AppSettings()
        store.load().forEach(land)
        totalBytes = (try? home.resourceValues(forKeys: [.volumeTotalCapacityKey]))?.volumeTotalCapacity.map(Int64.init)
        if isBundled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        refreshFreeSpace()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { self.refreshFreeSpace() }
        }
    }

    init(demoSettings: AppSettings, results: [CategoryResult], freeBytes: Int64, totalBytes: Int64) {
        settings = demoSettings
        isDemo = true
        self.results = results
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        lastScanned = Date().addingTimeInterval(-120)
        selected = Set(results.flatMap(\.items)
            .filter { defaultTicked($0, now: Date(), cutoffDays: demoSettings.cutoffDays) }.map(\.id))
    }

    // MARK: free space

    func refreshFreeSpace() {
        guard let free = DevBroomCore.freeBytes(at: home) else { return }
        freeBytes = free
        notifier.limitBytes = Int64(settings.lowSpaceLimitGB) * 1_000_000_000
        guard notifier.update(freeBytes: free), isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Disk space low: \(bytes(free)) left"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "lowSpace", content: content, trigger: nil))
    }

    // MARK: scan

    func popoverOpened() {
        isOpen = true
        if !isDemo { rescan() }
    }

    func popoverClosed() {
        isOpen = false
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func rescan() {
        refreshFreeSpace()
        scanTask?.cancel()
        for i in results.indices { results[i].status = .notUpdated }
        isScanning = true
        let now = Date()
        let files = FileScanners(locations: Locations(home: home), scanRoots: settings.scanRoots, now: now,
                                 cutoffDays: settings.cutoffDays,
                                 runningBundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
        let tools = ToolScanners(runner: ProcessRunner(), home: home, now: now, cutoffDays: settings.cutoffDays)
        scanTask = Task {
            await withTaskGroup(of: (CategoryID, ScanOutcome).self) { group in
                for id in CategoryID.allCases where id != .projectBuilds && id != .aiModels {
                    group.addTask { (id, await Self.scan(id, files: files, tools: tools)) }
                }
                for await (id, outcome) in group {
                    if Task.isCancelled { break }
                    switch outcome {
                    case .result(let rs): rs.forEach(land)
                    case .hidden: results.removeAll { $0.id == id }; save()
                    case .cancelled: break
                    }
                }
            }
            if !Task.isCancelled {
                isScanning = false
                lastScanned = Date()
                if !isDemo { UserDefaults.standard.set(lastScanned, forKey: "lastScanned") }
            }
        }
    }

    private enum ScanOutcome: Sendable { case result([CategoryResult]), hidden, cancelled }

    private nonisolated static func scan(_ id: CategoryID, files: FileScanners, tools: ToolScanners) async -> ScanOutcome {
        let work: @Sendable () throws -> [CategoryResult]
        switch id {
        case .simDevices: return .result([await tools.simDevices()])
        case .simRuntimes: return .result([await tools.simRuntimes()])
        case .docker: return await tools.docker().map { ScanOutcome.result([$0]) } ?? .hidden
        case .projectBuilds, .aiModels: return .cancelled  // landed by the .nodeModules job
        case .derivedData: work = { [try files.derivedData()] }
        case .packageCaches: work = { [try files.packageCaches()] }
        case .appCaches: work = { [try files.appCaches()] }
        case .nodeModules: work = { try files.projects() }
        case .deviceSupport: work = { [try files.deviceSupport()] }
        case .oldExtensions: work = { [try files.oldExtensions()] }
        case .wallpaper: work = { [try files.wallpaper()] }
        }
        // Detached keeps the file walk off the main actor; it does not inherit cancellation, so forward it.
        let task = Task.detached(priority: .utility) { try work() }
        do {
            return .result(try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() })
        } catch is CancellationError {
            return .cancelled
        } catch {
            let ids: [CategoryID] = id == .nodeModules ? [.nodeModules, .projectBuilds, .aiModels] : [id]
            return .result(ids.map { CategoryResult(id: $0, items: [], status: .unavailable(error.localizedDescription)) })
        }
    }

    private func land(_ fresh: CategoryResult) {
        var r = removingHidden(fresh, hidden: settings.hiddenItems.keys)
        r.items = r.items.filter { !$0.name.hasPrefix(".") }.sorted { $0.sizeBytes > $1.sizeBytes }
        if let i = results.firstIndex(where: { $0.id == r.id }) { results[i] = r } else {
            results.append(r)
            results.sort { CategoryID.allCases.firstIndex(of: $0.id)! < CategoryID.allCases.firstIndex(of: $1.id)! }
        }
        let now = Date()
        for item in r.items where !touched.contains(item.id) {
            if defaultTicked(item, now: now, cutoffDays: settings.cutoffDays) { selected.insert(item.id) } else { selected.remove(item.id) }
        }
        save()
    }

    private func save() { if !isDemo { try? store.save(results) } }

    // MARK: selection

    /// "Hide from DevBroom": never offered, ticked, counted or cleaned again until unhidden in Settings.
    func hide(_ item: CleanItem) {
        settings.hiddenItems[item.id] = item.name
        selected.remove(item.id)
        for i in results.indices { results[i] = removingHidden(results[i], hidden: [item.id]) }
        save()
    }

    /// Free space is below the low-space alert limit (menu bar icon turns orange).
    var isLowOnSpace: Bool {
        guard let free = freeBytes else { return false }
        return free < Int64(settings.lowSpaceLimitGB) * 1_000_000_000
    }

    func toggle(item: CleanItem) {
        touched.insert(item.id)
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    func toggle(category: CategoryResult) {
        let ids = category.items.map(\.id)
        let allOn = ids.allSatisfy(selected.contains)
        touched.formUnion(ids)
        if allOn { selected.subtract(ids) } else { selected.formUnion(ids) }
    }

    var selectedItems: [CleanItem] { results.flatMap(\.items).filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    // MARK: clean

    /// Spec section 5: items from a stale category are re-checked; newly recent ones are unticked. Returns their names.
    func recheckBeforeClean() async -> [String] {
        let cutoff = settings.cutoffDays, now = Date()
        let stale = Set(results.filter { $0.status == .notUpdated }.map(\.id))
        var unticked: [String] = []
        for item in selectedItems where stale.contains(item.category) {
            guard !isRecentlyUsed(item.lastUsed, now: now, cutoffDays: cutoff),
                  let (target, skipping) = usageFolder(for: item, scanRoots: settings.scanRoots) else { continue }
            let newest = await Task.detached {
                try? folderStats(target, skipping: skipping).newestModification
            }.value
            if isRecentlyUsed(newest ?? nil, now: now, cutoffDays: cutoff) {
                selected.remove(item.id)
                touched.insert(item.id)
                unticked.append(item.name)
            }
        }
        return unticked
    }

    /// Runs in the model, not the view, so closing the popover neither loses the result nor allows a second clean.
    func clean(_ items: [CleanItem]) {
        guard !isCleaning, !isPurging else { return }
        isCleaning = true
        lastReport = nil
        trashPurge = nil
        cleanProgress = (0, items.count)
        let cleaner = Cleaner(removalGuard: RemovalGuard(locations: Locations(home: home), scanRoots: settings.scanRoots),
                              runner: ProcessRunner(), home: home)
        Task {
            let report = await cleaner.clean(items) { @Sendable n, m in
                Task { @MainActor in self.cleanProgress = (n, m) }
            }
            selected.subtract(items.map(\.id))
            lastReport = report
            cleanProgress = nil
            isCleaning = false
            refreshFreeSpace()
            if isOpen { rescan() }  // no background scanning (spec section 4)
        }
    }

    /// Permanently deletes exactly what the last clean moved to the Trash (owner confirmed in the sheet).
    func deleteTrashed() {
        guard let report = lastReport, !report.trashedItems.isEmpty, trashPurge == nil, !isPurging else { return }
        isPurging = true
        let items = report.trashedItems
        Task {
            let result = await Task.detached { deleteFromTrash(items) }.value
            if lastReport?.id == report.id { trashPurge = result }  // never show it under a newer clean
            isPurging = false
            refreshFreeSpace()
        }
    }
}
