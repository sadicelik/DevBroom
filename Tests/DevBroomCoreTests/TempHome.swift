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
