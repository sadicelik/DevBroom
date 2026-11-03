import AppKit
import SwiftUI

@main
struct DevBroomApp: App {
    @State private var model: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(systemName: "trash")
            Text(model.freeBytes.map(wholeGB) ?? "")
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView(settings: model.settings) }
    }
}
