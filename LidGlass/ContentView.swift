import SwiftUI
import AppKit

struct ContentView: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            AngleDisplay(model: model)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            SettingsPanel(model: model)
                .frame(width: 340)
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}

// MARK: - Left: big angle readout

private struct AngleDisplay: View {
    let model: AppModel

    private var sensor: LidAngleSensor { model.sensor }

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(sensor.isAvailable ? "\(Int(sensor.angle.rounded()))°" : "–°")
                .font(.system(size: 144, weight: .thin, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(sensor.isAvailable ? .primary : .secondary)

            Text(statusText)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
    }

    private var statusText: String {
        guard sensor.isAvailable else {
            return "Sensor not available\nThis Mac has no readable lid angle sensor. Preview still works."
        }
        switch model.effect.phase {
        case .idle:
            return model.settings.enabled ? "Watching the lid" : "Close animation is off"
        case .capturing:
            return "Taking screenshot…"
        case .showing:
            return "Animating"
        case .fading:
            return "Fading out"
        }
    }
}

// MARK: - Right: settings inspector

private struct SettingsPanel: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        let effect = model.effect

        Form {
            Section {
                Toggle("Animate when closing the lid", isOn: $settings.enabled)
                    .disabled(!model.sensor.isAvailable && !settings.enabled)
                if !model.sensor.isAvailable {
                    Label("Sensor not available", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Section("Look") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Direction")
                        Spacer()
                        Text(settings.directionLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.left")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.direction, in: EffectSettings.Range.direction)
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded { model.settings.direction = 0 }
                            )
                            .help("Double-click to reset to straight back")
                        Image(systemName: "arrow.down.right")
                            .foregroundStyle(.secondary)
                    }
                }

                ValueSlider(title: "Tilt", value: $settings.tilt,
                            range: EffectSettings.Range.tilt) { String(format: "%.2f", $0) }
                ValueSlider(title: "Blur", value: $settings.blur,
                            range: EffectSettings.Range.blur) { "\(Int($0.rounded())) pt" }
                ValueSlider(title: "Darken", value: $settings.darken,
                            range: EffectSettings.Range.darken) { "\(Int(($0 * 100).rounded())) %" }

                HStack {
                    Spacer()
                    Button("Defaults") { model.settings.resetToDefaults() }
                }
            }

            Section("Screen Recording") {
                if effect.hasScreenAccess {
                    Label("Permission granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LidGlass needs Screen Recording permission to take the screenshot used by the animation. The image is kept in memory only and never saved. After granting, quit and reopen the app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Allow Screen Recording…") { effect.requestScreenAccess() }
                    }
                }
            }

            Section {
                Button {
                    effect.preview()
                } label: {
                    Label("Preview", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(effect.phase != .idle)

                if let error = effect.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}
