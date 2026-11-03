import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var cutoffDays: Int { didSet { defaults.set(cutoffDays, forKey: "cutoffDays") } }
    public var lowSpaceLimitGB: Int { didSet { defaults.set(lowSpaceLimitGB, forKey: "lowSpaceLimitGB") } }
    public var scanRoots: [URL] { didSet { defaults.set(scanRoots.map(\.path), forKey: "scanRoots") } }
    public private(set) var launchAtLoginError: String?

    public var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                launchAtLoginError = nil
                defaults.set(launchAtLogin, forKey: "launchAtLogin")
            } catch {
                launchAtLoginError = error.localizedDescription
                launchAtLogin = oldValue // re-enters didSet; equal-guard stops it after one revert
            }
        }
    }

    public init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.defaults = defaults
        cutoffDays = defaults.object(forKey: "cutoffDays") as? Int ?? 14
        lowSpaceLimitGB = defaults.object(forKey: "lowSpaceLimitGB") as? Int ?? 15
        scanRoots = (defaults.stringArray(forKey: "scanRoots") ?? [home.path]).map { URL(fileURLWithPath: $0) }
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    }
}
