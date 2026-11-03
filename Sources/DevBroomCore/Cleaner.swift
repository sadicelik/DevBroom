import Foundation

public enum ItemOutcome: Equatable, Sendable {
    case trashed(bytes: Int64), deleted(bytes: Int64), alreadyGone, failed(String)
}

public struct CleanReport: Sendable {
    public var outcomes: [String: ItemOutcome] = [:]
    public var trashedBytes: Int64 = 0
    public var deletedBytes: Int64 = 0
    public var failures: [(name: String, reason: String)] = []
    /// Where each trashed item ended up, so "Delete from Trash now" removes exactly these and nothing else.
    public var trashedItems: [(url: URL, bytes: Int64)] = []
    public init() {}
}

/// Permanently deletes items DevBroom itself moved to the Trash. Anything not directly inside a Trash folder
/// (`~/.Trash/x` or `/Volumes/V/.Trashes/<uid>/x`) is refused.
public func deleteFromTrash(_ items: [(url: URL, bytes: Int64)]) -> (bytes: Int64, failures: [String]) {
    var bytes: Int64 = 0, failures: [String] = []
    for (url, size) in items {
        let parent = url.standardizedFileURL.deletingLastPathComponent()
        guard parent.lastPathComponent == ".Trash" || parent.deletingLastPathComponent().lastPathComponent == ".Trashes" else {
            failures.append("\(url.lastPathComponent): not in the Trash"); continue
        }
        guard FileManager.default.fileExists(atPath: url.path) else { continue }  // already emptied
        do { try FileManager.default.removeItem(at: url); bytes += size }
        catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
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
            if let landed { report.trashedItems.append((landed, item.sizeBytes)) }
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
