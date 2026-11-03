import Testing
import Foundation
@testable import DevBroomCore

private struct FakeRunner: CommandRunner {
    var handler: @Sendable (URL, [String]) throws -> (status: Int32, stdout: String)
    func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: String) {
        try handler(executable, args)
    }
}
private struct Boom: Error {}

@Suite struct ToolScannersTests {
    let when = Date(timeIntervalSince1970: 1_793_700_000)

    @Test func parsesDevices() throws {
        let json = """
        {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          {"dataPath": "/x", "dataPathSize": 18337792, "udid": "AAA", "isAvailable": true, "state": "Booted", "name": "iPhone 18 Pro Max", "lastBootedAt": "2026-10-27T10:55:58Z"},
          {"dataPath": "/y", "dataPathSize": 100, "udid": "BBB", "isAvailable": true, "state": "Shutdown", "name": "iPad"}
        ]}}
        """
        let items = try SimctlParser.devices(Data(json.utf8), now: when, cutoffDays: 14).sorted { $0.id < $1.id }
        #expect(items.count == 2)
        #expect(items[0].id == "simdevice:AAA")
        #expect(items[0].tags.contains(.inUse))
        #expect(items[0].lastUsed != nil)
        #expect(items[0].detail == "iOS 26.5")
        #expect(items[0].sizeBytes == 18337792)
        #expect(items[0].method == .simctlDevice(udid: "AAA"))
        #expect(items[1].lastUsed == nil)
        #expect(items[1].tags.isEmpty)
    }

    @Test func parsesRuntimesSkipsUndeletable() throws {
        let json = """
        {"R1": {"build": "24A1", "deletable": true, "identifier": "R1", "lastUsedAt": "2026-10-27T10:55:58Z",
                "platformIdentifier": "com.apple.platform.iphonesimulator", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "sizeBytes": 8067000161, "state": "Ready", "version": "27.0"},
         "R2": {"build": "23F77", "deletable": false, "identifier": "R2",
                "platformIdentifier": "com.apple.platform.iphonesimulator", "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                "sizeBytes": 8494282293, "state": "Ready", "version": "26.5"}}
        """
        let items = try SimctlParser.runtimes(Data(json.utf8), now: when, cutoffDays: 14)
        #expect(items.count == 1)
        #expect(items[0].name == "iOS 27.0")
        #expect(items[0].sizeBytes == 8067000161)
        #expect(items[0].id == "simruntime:R1")
        #expect(items[0].detail == "24A1")
    }

    @Test func dockerReclaimableSums() {
        let lines = """
        {"Type":"Images","Reclaimable":"1.5GB (40%)"}
        {"Type":"Build Cache","Reclaimable":"250MB (10%)"}
        {"Type":"Volumes","Reclaimable":"0B (0%)"}
        """
        #expect(DockerParser.reclaimableBytes(lines) == 1_750_000_000)
    }

    @Test func dockerLocatorOrder() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(ToolLocator.docker(home: home, fileExists: { $0 == "/usr/local/bin/docker" })
                == URL(fileURLWithPath: "/usr/local/bin/docker"))
        #expect(ToolLocator.docker(home: home, fileExists: { _ in false }) == nil)
    }

    @Test func missingSimctlIsUnavailable() async {
        let s = ToolScanners(runner: FakeRunner { _, _ in throw Boom() }, home: URL(fileURLWithPath: "/nonexistent"), now: when, cutoffDays: 14)
        #expect(await s.simDevices().status == .unavailable("Xcode simulator tools not found"))
        #expect(await s.simRuntimes().status == .unavailable("Xcode simulator tools not found"))
    }

    @Test func dockerDaemonDownIsUnavailable() async throws {
        let home = try TempHome()
        let bin = home.url.appendingPathComponent(".docker/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let exe = bin.appendingPathComponent("docker")
        try "#!/bin/sh\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        let s = ToolScanners(runner: FakeRunner { _, _ in (1, "") }, home: home.url, now: when, cutoffDays: 14)
        #expect(await s.docker()?.status == .unavailable("Docker not running"))
    }
}
