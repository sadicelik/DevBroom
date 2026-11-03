import Foundation

public struct ScanStore: Sendable {
    public let file: URL
    public init(file: URL) { self.file = file }

    /// [] if the file is missing or corrupt.
    public func load() -> [CategoryResult] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([CategoryResult].self, from: data)) ?? []
    }

    public func save(_ results: [CategoryResult]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(results).write(to: file, options: .atomic)
    }
}
