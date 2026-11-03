import Foundation

public enum ItemOutcome: Equatable, Sendable {
    case trashed(bytes: Int64), deleted(bytes: Int64), alreadyGone, failed(String)
}

public struct CleanReport: Sendable {
    public var outcomes: [String: ItemOutcome] = [:]
    public var trashedBytes: Int64 = 0
    public var deletedBytes: Int64 = 0
    public var failures: [(name: String, reason: String)] = []
}

/// The only code that removes anything: Trash for files (guard-checked), vendor tools for permanent deletes.
public struct Cleaner: Sendable {
    private let removalGuard: RemovalGuard
    private let runner: CommandRunner
    private let home: URL
    private let trash: @Sendable (URL) throws -> Void

    public init(removalGuard: RemovalGuard, runner: CommandRunner, home: URL,
                trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.removalGuard = removalGuard; self.runner = runner; self.home = home; self.trash = trash
    }

    public func clean(_ items: [CleanItem], progress: (Int, Int) -> Void) async -> CleanReport {
        var report = CleanReport()
        for (i, item) in items.enumerated() {
            let outcome = await remove(item)
            report.outcomes[item.id] = outcome
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

    private func remove(_ item: CleanItem) async -> ItemOutcome {
        switch item.method {
        case .trash(let url):
            guard FileManager.default.fileExists(atPath: url.path) else { return .alreadyGone }
            guard removalGuard.allows(url) else { return .failed("Refused by safety guard") }
            do { try trash(url); return .trashed(bytes: item.sizeBytes) }
            catch { return .failed(error.localizedDescription) }
        case .simctlDevice(let udid):
            return await run(ToolLocator.xcrun, ["simctl", "delete", udid], item)
        case .simctlRuntime(let id):
            return await run(ToolLocator.xcrun, ["simctl", "runtime", "delete", id], item)
        case .dockerPrune:
            guard let docker = ToolLocator.docker(home: home) else { return .failed("Docker not found") }
            return await run(docker, ["system", "prune", "-a", "-f"], item)
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
