import AppKit
import DevBroomCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Stepper("Recently used: \(settings.cutoffDays) days", value: $settings.cutoffDays, in: 1...365)
            Stepper("Notify below: \(settings.lowSpaceLimitGB) GB free", value: $settings.lowSpaceLimitGB, in: 1...500)
            Section("Scan roots for node_modules") {
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
