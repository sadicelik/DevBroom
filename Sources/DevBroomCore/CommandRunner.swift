import Foundation

public protocol CommandRunner: Sendable {
    func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: String)
}

public enum ToolLocator {
    public static let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
    public static let xcodeSelect = URL(fileURLWithPath: "/usr/bin/xcode-select")

    public static func docker(home: URL,
                              fileExists: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> URL? {
        let candidates = [home.appending(path: ".docker/bin/docker").path,
                          "/usr/local/bin/docker",
                          "/opt/homebrew/bin/docker",
                          "/Applications/Docker.app/Contents/Resources/bin/docker"]
        return candidates.first(where: fileExists).map { URL(fileURLWithPath: $0) }
    }
}

public struct ProcessRunner: CommandRunner {
    public init() {}

    private final class Box: @unchecked Sendable { let p = Process() }

    public func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: String) {
        let box = Box()
        box.p.executableURL = executable
        box.p.arguments = args
        let pipe = Pipe()
        box.p.standardOutput = pipe
        box.p.standardError = FileHandle.nullDevice
        return try await withTaskCancellationHandler {
            try box.p.run()
            // Read to EOF off the cooperative pool so a full pipe never blocks the child.
            let data = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
            box.p.waitUntilExit()
            return (box.p.terminationStatus, String(decoding: data, as: UTF8.self))
        } onCancel: {
            if box.p.isRunning { box.p.terminate() }
        }
    }
}
