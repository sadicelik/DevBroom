import Foundation

public enum ItemOutcome: Equatable, Sendable {
    case trashed(bytes: Int64), deleted(bytes: Int64), alreadyGone, failed(String)
}

public struct CleanReport: Sendable {
    /// Ties a "Delete from Trash now" result to the clean it belongs to.
    public let id = UUID()
    public var outcomes: [String: ItemOutcome] = [:]
    public var trashedBytes: Int64 = 0
    public var deletedBytes: Int64 = 0
    public var failures: [(name: String, reason: String)] = []
    /// Where each trashed item ended up, so "Delete from Trash now" removes exactly these and nothing else.
    public var trashedItems: [TrashedItem] = []
    public init() {}
}

/// An item DevBroom moved to the Trash, with the file identity it had when it landed there.
public struct TrashedItem: Sendable {
    public let url: URL
    public let bytes: Int64
    public let identity: FileIdentity?
    /// Records the identity the item has right now (call just after it lands in the Trash).
    public init(url: URL, bytes: Int64) {
        self.url = url; self.bytes = bytes; identity = FileIdentity(url)
    }
}

/// Device + inode + creation time: tells "the item DevBroom trashed" apart from a later item at the same path.
public struct FileIdentity: Sendable, Equatable {
    let device: Int64, inode: UInt64, birth: Double
    public init?(_ url: URL) {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        device = Int64(st.st_dev); inode = UInt64(st.st_ino)
        birth = Double(st.st_birthtimespec.tv_sec) + Double(st.st_birthtimespec.tv_nsec) / 1e9
    }
}

/// True if `folder` is this user's Trash for the volume `item` is on (`~/.Trash` or `/Volumes/V/.Trashes/<uid>`).
public func isUserTrash(_ folder: URL, for item: URL) -> Bool {
    guard let trash = try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
                                                    appropriateFor: item, create: false) else { return false }
    return folder.resolvingSymlinksInPath().standardizedFileURL.path
        == trash.resolvingSymlinksInPath().standardizedFileURL.path
}

/// Permanently deletes items DevBroom itself moved to the Trash. Refuses anything not directly inside the user's
/// Trash, and anything whose identity changed since it was trashed (put back, emptied, replaced by another item).
public func deleteFromTrash(_ items: [TrashedItem],
                            isTrash: (URL, URL) -> Bool = isUserTrash) -> (bytes: Int64, failures: [String]) {
    var bytes: Int64 = 0, failures: [String] = []
    for item in items {
        let url = item.url, name = url.lastPathComponent
        guard isTrash(url.standardizedFileURL.deletingLastPathComponent(), url) else {
            failures.append("\(name): not in the Trash"); continue
        }
        guard let now = FileIdentity(url) else { continue }  // already emptied or put back
        guard let then = item.identity, then == now else {
            failures.append("\(name): changed since cleaning, left in the Trash"); continue
        }
        do { try FileManager.default.removeItem(at: url); bytes += item.bytes }
        catch { failures.append("\(name): \(error.localizedDescription)") }
    }
    return (bytes, failures)
}

/// The only code that removes anything: Trash for files (guard-checked), vendor tools for permanent deletes.
public struct Cleaner: Sendable {
    private let removalGuard: RemovalGuard
    private let runner: CommandRunner
    private let home: URL
    /// Moves an item to the Trash and returns where it ended up (nil if unknown).
    private let trash: @Sendable (URL) throws -> URL?

    public init(removalGuard: RemovalGuard, runner: CommandRunner, home: URL,
                trash: @escaping @Sendable (URL) throws -> URL? = { url in
                    var out: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &out)
                    return out as URL?
                }) {
        self.removalGuard = removalGuard; self.runner = runner; self.home = home; self.trash = trash
    }

    public func clean(_ items: [CleanItem], progress: (Int, Int) -> Void) async -> CleanReport {
        var report = CleanReport()
        for (i, item) in items.enumerated() {
            let (outcome, landed) = await remove(item)
            report.outcomes[item.id] = outcome
            if let landed { report.trashedItems.append(TrashedItem(url: landed, bytes: item.sizeBytes)) }
            switch outcome {
            case .trashed(let b): report.trashedBytes += b
            case .deleted(let b): report.deletedBytes += b
            case .failed(let why): report.failures.append((item.name, why))
            case .alreadyGone: break
            }
            progress(i + 1, items.count)
        }
        return report
    }

    /// The outcome, plus where a trashed item ended up.
    private func remove(_ item: CleanItem) async -> (ItemOutcome, URL?) {
        switch item.method {
        case .trash(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { return (.alreadyGone, nil) }
            guard removalGuard.allows(url) else { return (.failed("Refused by safety guard"), nil) }
            do { return (.trashed(bytes: item.sizeBytes), try trash(url)) }
            catch { return (.failed(error.localizedDescription), nil) }
        case .simctlDevice(let udid):
            return (await run(ToolLocator.xcrun, ["simctl", "delete", udid], item), nil)
        case .simctlRuntime(let id):
            return (await run(ToolLocator.xcrun, ["simctl", "runtime", "delete", id], item), nil)
        case .dockerPrune:
            guard let docker = ToolLocator.docker(home: home) else { return (.failed("Docker not found"), nil) }
            return (await run(docker, ["system", "prune", "-a", "-f"], item), nil)
        }
    }

    private func run(_ tool: URL, _ args: [String], _ item: CleanItem) async -> ItemOutcome {
        do {
            let r = try await runner.run(tool, args)
            return r.status == 0 ? .deleted(bytes: item.sizeBytes)
                                 : .failed("\(tool.lastPathComponent) exited with \(r.status)")
        } catch { return .failed(error.localizedDescription) }
    }
}
