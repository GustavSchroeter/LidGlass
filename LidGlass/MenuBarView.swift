import SwiftUI
import AppKit

struct MenuBarView: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var settings = model.settings

        Toggle("Close Animation", isOn: $settings.enabled)

        Button("Preview Close Animation") {
            // Short delay so the menu is gone before the screenshot is taken.
            model.effect.preview(after: 0.3)
        }
        .disabled(model.effect.phase != .idle)

        Divider()

        Button("Open LidGlass…") {
            NSApp.activate()
            openWindow(id: "main")
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
