import Foundation

public enum Ecosystem: String, Sendable {
    case harmonyOS = "HarmonyOS", gradle = "Android", flutter = "Flutter", xcode = "Xcode", rust = "Rust", python = "Python"
}

public let projectBuildFolderNames: Set<String> = ["build", "oh_modules", ".hvigor", "target", ".venv"]

private func exists(_ url: URL, _ name: String) -> Bool {
    FileManager.default.fileExists(atPath: url.appending(path: name).path)
}

/// Spec 4.2 marker table. Markers live in the folder's parent (for `.venv`: inside the folder).
public func buildEcosystem(of folder: URL) -> Ecosystem? {
    let parent = folder.deletingLastPathComponent()
    switch folder.lastPathComponent {
    case "build":
        if exists(parent, "hvigorfile.ts") { return .harmonyOS }
        if exists(parent, "build.gradle") || exists(parent, "build.gradle.kts") { return .gradle }
        if exists(parent, "pubspec.yaml") { return .flutter }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        return names.contains { $0.hasSuffix(".xcodeproj") } ? .xcode : nil
    case "oh_modules": return exists(parent, "oh-package.json5") ? .harmonyOS : nil
    case ".hvigor": return exists(parent, "hvigorfile.ts") ? .harmonyOS : nil
    case "target": return exists(parent, "Cargo.toml") ? .rust : nil
    case ".venv": return exists(folder, "pyvenv.cfg") ? .python : nil
    default: return nil
    }
}

private func run(_ path: String, _ args: [String]) -> (status: Int32, out: Data)? {
    let p = Process()
    p.executableURL = URL(filePath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, data)
}

/// True only if git works and tracks at least one file in `folder`. Any failure gives false.
public func gitTracksFiles(in folder: URL) -> Bool {
    // Never run /usr/bin/git without developer tools: the stub opens an install dialog.
    guard run("/usr/bin/xcode-select", ["-p"])?.status == 0,
          let r = run("/usr/bin/git", ["-C", folder.path, "ls-files", "--", "."]) else { return false }
    return r.status == 0 && !r.out.isEmpty
}

public func projectFolder(forMarkerFolder m: URL, scanRoot: URL) -> URL {
    let root = scanRoot.standardizedFileURL.pathComponents
    var cur = m.standardizedFileURL
    while cur.pathComponents.count >= root.count, cur.pathComponents.starts(with: root) {
        if FileManager.default.fileExists(atPath: cur.appending(path: ".git").path) { return cur }
        cur = cur.deletingLastPathComponent()
    }
    return m
}

public func modelDisplayName(_ folderName: String) -> String? {
    for (prefix, suffix) in [("models--", ""), ("datasets--", " (dataset)")] where folderName.hasPrefix(prefix) {
        let rest = folderName.dropFirst(prefix.count)
        guard !rest.isEmpty else { return nil }
        return rest.replacingOccurrences(of: "--", with: "/") + suffix
    }
    return nil
}
