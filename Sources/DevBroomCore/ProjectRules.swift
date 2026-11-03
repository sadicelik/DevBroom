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

private let developerToolsInstalled: Bool = run("/usr/bin/xcode-select", ["-p"])?.status == 0

/// True if git tracks a file in `folder`, or if that cannot be ruled out (fails closed).
/// False when developer tools are missing (check skipped), when no ancestor has a `.git` entry,
/// or when `git ls-files` exits 0 with empty output. A non-zero exit or launch failure gives true.
public func gitTracksFiles(in folder: URL) -> Bool {
    // Never run /usr/bin/git without developer tools: the stub opens an install dialog.
    guard developerToolsInstalled else { return false }
    var cur = folder.standardizedFileURL
    while !FileManager.default.fileExists(atPath: cur.appending(path: ".git").path) {
        if cur.pathComponents.count <= 1 { return false }
        cur = cur.deletingLastPathComponent().standardizedFileURL
    }
    guard let r = run("/usr/bin/git", ["-C", folder.path, "ls-files", "--", "."]) else { return true }
    return !(r.status == 0 && r.out.isEmpty)
}

/// Nearest of `m` and its ancestors strictly below `scanRoot` that holds a `.git` entry; else `m`.
public func projectFolder(forMarkerFolder m: URL, scanRoot: URL) -> URL {
    let root = scanRoot.standardizedFileURL.pathComponents
    var cur = m.standardizedFileURL
    while cur.pathComponents.count > root.count, cur.pathComponents.starts(with: root) {
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

/// Folder whose newest file counts as "project in use" for a trash item, and names to leave out of that scan.
public func usageFolder(for item: CleanItem, scanRoots: [URL]) -> (folder: URL, skipping: Set<String>)? {
    guard case .trash(let url) = item.method else { return nil }
    let parent = url.deletingLastPathComponent()
    switch item.category {
    case .nodeModules: return (parent, ["node_modules"])
    case .projectBuilds:
        let comps = url.standardizedFileURL.pathComponents
        let root = scanRoots.first { comps.starts(with: $0.standardizedFileURL.pathComponents) }
        let project = root.map { projectFolder(forMarkerFolder: parent, scanRoot: $0) } ?? parent
        return (project, projectBuildFolderNames.union(["node_modules"]))
    default: return (url, [])
    }
}
