import AppKit
import DevBroomCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Stepper("Recently used: \(settings.cutoffDays) days", value: $settings.cutoffDays, in: 1...365)
            Stepper("Notify below: \(settings.lowSpaceLimitGB) GB free", value: $settings.lowSpaceLimitGB, in: 1...500)
            Section("Project scan roots") {
                ForEach(settings.scanRoots, id: \.self) { root in
                    HStack {
                        Text(root.path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove") { settings.scanRoots.removeAll { $0 == root } }
                    }
                }
                Button("Add Folder…", action: addRoots)
            }
            Section {
                if settings.hiddenItems.isEmpty {
                    Text("Right-click an item in the panel and choose Hide from DevBroom to stop it being offered.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(settings.hiddenItems.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending },
                        id: \.key) { id, name in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).lineLimit(1)
                            Text(id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Unhide") { settings.hiddenItems[id] = nil }
                    }
                }
            } header: {
                Text("Hidden items")
            } footer: {
                if !settings.hiddenItems.isEmpty {
                    Text("Unhidden items show again after the next scan.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Show guide again") { settings.guideSeen = false }
            } footer: {
                Text("Shows the three welcome cards again in the panel.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin).disabled(!isBundled)
                if !isBundled {
                    Text("Available in the installed app").font(.caption).foregroundStyle(.secondary)
                }
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .background(WindowGrabber { SettingsWindow.window = $0; SettingsWindow.bringToFront() })
    }

    private func addRoots() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        settings.scanRoots += panel.urls.filter { !settings.scanRoots.contains($0) }
    }
}

/// DevBroom has no Dock icon, so macOS opens its Settings window behind other apps, possibly on another display.
/// This brings it to the front on the screen the mouse is on.
@MainActor enum SettingsWindow {
    static weak var window: NSWindow?
    /// Off while rendering README screenshots, so the off-screen render window is never shown.
    static var isEnabled = true

    static func bringToFront() {
        guard isEnabled else { return }
        NSApp.activate(ignoringOtherApps: true)
        // On first open the window doesn't exist yet; WindowGrabber calls this again once it does.
        DispatchQueue.main.async {
            guard let w = window else { return }
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
               w.screen != screen {
                let f = screen.visibleFrame
                w.setFrameOrigin(NSPoint(x: f.midX - w.frame.width / 2, y: f.midY - w.frame.height / 2))
            }
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
        }
    }
}

/// Hands the hosting NSWindow to `found` once the view is in a window.
private struct WindowGrabber: NSViewRepresentable {
    let found: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { found(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
