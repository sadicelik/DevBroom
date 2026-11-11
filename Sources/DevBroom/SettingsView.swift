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
