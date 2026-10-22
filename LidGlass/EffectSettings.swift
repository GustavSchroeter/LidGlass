import Foundation

/// User settings for the close animation, persisted in UserDefaults.
@MainActor
@Observable
final class EffectSettings {
    enum Defaults {
        static let enabled = false
        static let direction = 0.0
        static let tilt = 0.7
        static let blur = 14.0
        static let darken = 0.5
    }

    enum Range {
        static let direction = -1.0...1.0
        static let tilt = 0.2...1.0
        static let blur = 0.0...40.0
        static let darken = 0.0...1.0
    }

    private enum Key {
        static let enabled = "animateOnClose"
        static let direction = "direction"
        static let tilt = "tilt"
        static let blur = "blur"
        static let darken = "darken"
    }

    @ObservationIgnored private let store = UserDefaults.standard

    /// "Animate when closing the lid"
    var enabled: Bool { didSet { store.set(enabled, forKey: Key.enabled) } }
    /// −1 = swing away to the left, 0 = straight back, +1 = swing away to the right.
    var direction: Double { didSet { store.set(direction, forKey: Key.direction) } }
    /// Strength of the tilt relative to the lid movement.
    var tilt: Double { didSet { store.set(tilt, forKey: Key.tilt) } }
    /// Maximum blur radius in points.
    var blur: Double { didSet { store.set(blur, forKey: Key.blur) } }
    /// Maximum darkening (0 … 1).
    var darken: Double { didSet { store.set(darken, forKey: Key.darken) } }

    init() {
        store.register(defaults: [
            Key.enabled: Defaults.enabled,
            Key.direction: Defaults.direction,
            Key.tilt: Defaults.tilt,
            Key.blur: Defaults.blur,
            Key.darken: Defaults.darken,
        ])
        enabled = store.bool(forKey: Key.enabled)
        direction = Self.clamp(store.double(forKey: Key.direction), Range.direction)
        tilt = Self.clamp(store.double(forKey: Key.tilt), Range.tilt)
        blur = Self.clamp(store.double(forKey: Key.blur), Range.blur)
        darken = Self.clamp(store.double(forKey: Key.darken), Range.darken)
    }

    /// Resets the look of the effect (not the on/off switch).
    func resetToDefaults() {
        direction = Defaults.direction
        tilt = Defaults.tilt
        blur = Defaults.blur
        darken = Defaults.darken
    }

    var directionLabel: String {
        let d = direction
        if abs(d) < 0.01 { return "Straight back" }
        if d <= -0.995 { return "Left" }
        if d >= 0.995 { return "Right" }
        let percent = Int((abs(d) * 100).rounded())
        return d < 0 ? "Left \(percent)%" : "Right \(percent)%"
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
