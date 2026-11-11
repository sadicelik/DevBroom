import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var cutoffDays: Int { didSet { defaults.set(cutoffDays, forKey: "cutoffDays") } }
    public var lowSpaceLimitGB: Int { didSet { defaults.set(lowSpaceLimitGB, forKey: "lowSpaceLimitGB") } }
    public var scanRoots: [URL] { didSet { defaults.set(scanRoots.map(\.path), forKey: "scanRoots") } }
    /// Items the owner hid ("Hide from DevBroom"): item id to the name shown in Settings.
    public var hiddenItems: [String: String] { didSet { defaults.set(hiddenItems, forKey: "hiddenItems") } }
    public private(set) var launchAtLoginError: String?

    @ObservationIgnored private let registrar: (Bool) throws -> Void
    @ObservationIgnored private var isReverting = false

    public var launchAtLogin: Bool {
        didSet {
            // The @Observable setter re-fires didSet on revert, so skip that re-entry.
            guard !isReverting, launchAtLogin != oldValue else { return }
            do {
                try registrar(launchAtLogin)
                launchAtLoginError = nil
                defaults.set(launchAtLogin, forKey: "launchAtLogin")
            } catch {
                launchAtLoginError = error.localizedDescription
                isReverting = true
                launchAtLogin = oldValue
                isReverting = false
            }
        }
    }

    public init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                registrar: @escaping (Bool) throws -> Void = { on in
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                }) {
        self.defaults = defaults
        self.registrar = registrar
        cutoffDays = defaults.object(forKey: "cutoffDays") as? Int ?? 14
        lowSpaceLimitGB = defaults.object(forKey: "lowSpaceLimitGB") as? Int ?? 15
        scanRoots = (defaults.stringArray(forKey: "scanRoots") ?? [home.path]).map { URL(fileURLWithPath: $0) }
        hiddenItems = defaults.dictionary(forKey: "hiddenItems") as? [String: String] ?? [:]
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
    }
}
