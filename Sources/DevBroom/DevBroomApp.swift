import AppKit
import SwiftUI

@main
struct DevBroomApp: App {
    @State private var model: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Screenshots.renderIfRequested()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(nsImage: BroomIcon.image(warning: model.isLowOnSpace))
            Text(model.freeBytes.map(wholeGB) ?? "")
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView(settings: model.settings) }
    }
}
