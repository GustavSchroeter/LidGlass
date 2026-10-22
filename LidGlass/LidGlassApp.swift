import SwiftUI
import AppKit

@main
struct LidGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("LidGlass", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 560)

        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "angle")
                Text(model.sensor.isAvailable ? "\(Int(model.sensor.angle.rounded()))°" : "–")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Owns the long-lived objects. Created exactly once (singleton), so the HID
/// device is never opened twice even if SwiftUI re-creates view structs.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let sensor: LidAngleSensor
    let settings: EffectSettings
    let effect: LidEffectController

    private init() {
        sensor = LidAngleSensor()
        settings = EffectSettings()
        effect = LidEffectController(sensor: sensor, settings: settings)
    }

    func start() {
        sensor.start()
        effect.start()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    /// Closing the main window keeps the app alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
