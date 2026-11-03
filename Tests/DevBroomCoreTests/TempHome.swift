import Foundation

struct TempHome {
    let url: URL

    init() throws {
        let d = FileManager.default.temporaryDirectory.appending(path: "DevBroomTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        url = d.resolvingSymlinksInPath()
    }

    @discardableResult
    func make(_ relPath: String, bytes: Int = 1024, modified: Date? = nil) throws -> URL {
        let f = url.appending(path: relPath)
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: f)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: f.path) }
        return f
    }

    @discardableResult
    func dir(_ relPath: String) throws -> URL {
        let d = url.appending(path: relPath)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}

extension TempHome {
    static let gitAvailable: Bool = {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/xcode-select"); p.arguments = ["-p"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }()

    /// Runs git in `dir` with a hermetic config; fails the calling test if git exits non-zero.
    func git(_ dir: URL, _ args: String...) throws {
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/git")
        p.arguments = ["-C", dir.path, "-c", "user.name=t", "-c", "user.email=t@t",
                       "-c", "core.excludesFile=/dev/null", "-c", "commit.gpgsign=false"] + args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        struct GitFailed: Error { let args: [String] }
        guard p.terminationStatus == 0 else { throw GitFailed(args: args) }
    }
}
