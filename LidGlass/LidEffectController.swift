import AppKit
import QuartzCore

/// State machine for the close animation: idle → capturing → showing → fading → idle.
/// Driven by a 60 Hz timer in the .common run loop mode.
@MainActor
@Observable
final class LidEffectController {
    enum Phase: Equatable {
        case idle, capturing, showing, fading
    }

    private(set) var phase: Phase = .idle
    private(set) var lastError: String?
    private(set) var hasScreenAccess = CGPreflightScreenCaptureAccess()

    @ObservationIgnored let sensor: LidAngleSensor
    @ObservationIgnored let settings: EffectSettings

    @ObservationIgnored private let capturer = ScreenCapturer()
    @ObservationIgnored private var overlay: OverlayWindow?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    // Timing
    @ObservationIgnored private var lastTick: CFTimeInterval = 0

    // Idle tracking
    @ObservationIgnored private var restAngle: Double?
    @ObservationIgnored private var lastAngle: Double = -1
    @ObservationIgnored private var lastAngleChange: CFTimeInterval = 0

    // Animation
    @ObservationIgnored private var startAngle: Double = 0
    @ObservationIgnored private var displayedDelta: Double = 0
    @ObservationIgnored private var fadeStart: CFTimeInterval = 0
    @ObservationIgnored private var captureToken = 0

    // Preview (simulated lid movement)
    @ObservationIgnored private var isPreview = false
    @ObservationIgnored private var previewStart: CFTimeInterval = 0

    private static let tickInterval: TimeInterval = 1.0 / 60.0
    private static let smoothingTimeConstant = 0.035
    private static let fadeDuration = 0.18
    private static let restSettleTime = 0.6
    private static let stallTime = 1.5
    private static let triggerDrop = 2.0
    private static let minRestAngle = 20.0

    private static let previewOpen = 110.0
    private static let previewClosed = 12.0
    private static let previewCloseDuration = 1.1
    private static let previewHoldDuration = 0.4
    private static let previewOpenDuration = 0.8
    private static let previewTotalDuration = 2.4

    init(sensor: LidAngleSensor, settings: EffectSettings) {
        self.sensor = sensor
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        lastTick = CACurrentMediaTime()

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermission()
            }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenParametersChanged()
            }
        })

        refreshPermission()
        capturer.warmUp()
    }

    // MARK: - Permission

    func refreshPermission() {
        hasScreenAccess = CGPreflightScreenCaptureAccess()
    }

    func requestScreenAccess() {
        if !CGRequestScreenCaptureAccess() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        refreshPermission()
    }

    // MARK: - Preview

    /// Captures the screen and plays a simulated lid movement (sensor not used).
    /// Works even if the effect is switched off.
    func preview(after delay: TimeInterval = 0) {
        guard phase == .idle else { return }
        if delay > 0 {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                self.preview()
            }
            return
        }
        isPreview = true
        startAngle = Self.previewOpen
        beginCapture()
    }

    // MARK: - Tick

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now

        // Track when the real sensor angle last changed.
        if sensor.isAvailable, sensor.angle != lastAngle {
            lastAngle = sensor.angle
            lastAngleChange = now
        }

        switch phase {
        case .idle:
            tickIdle(now: now)
        case .capturing:
            break
        case .showing:
            tickShowing(now: now, dt: dt)
        case .fading:
            tickFading(now: now)
        }

        updateActivity()
    }

    private func tickIdle(now: CFTimeInterval) {
        guard settings.enabled, sensor.isAvailable else {
            restAngle = nil
            return
        }
        let angle = sensor.angle

        guard let rest = restAngle else {
            restAngle = angle
            return
        }

        // Rest angle follows when the lid opens further or stays still for 0.6 s.
        if angle > rest || now - lastAngleChange >= Self.restSettleTime {
            restAngle = angle
            return
        }

        if rest > Self.minRestAngle, angle <= rest - Self.triggerDrop {
            isPreview = false
            startAngle = rest
            beginCapture()
        }
    }

    private func tickShowing(now: CFTimeInterval, dt: CFTimeInterval) {
        guard let overlay else {
            finish()
            return
        }

        let angle: Double
        if isPreview {
            let elapsed = now - previewStart
            angle = Self.previewAngle(at: elapsed)
            if elapsed >= Self.previewTotalDuration {
                beginFade(now: now)
                return
            }
        } else {
            guard sensor.isAvailable else {
                beginFade(now: now)
                return
            }
            angle = sensor.angle
        }

        // Smooth the coarse (1°) sensor values exponentially (τ ≈ 35 ms).
        let target = max(0, startAngle - angle)
        let k = 1 - exp(-dt / Self.smoothingTimeConstant)
        displayedDelta += (target - displayedDelta) * k

        overlay.apply(
            delta: displayedDelta,
            tilt: settings.tilt,
            direction: settings.direction,
            blur: settings.blur,
            dim: settings.darken
        )

        if !isPreview {
            let reopened = angle >= startAngle - 1
            let stalled = now - lastAngleChange >= Self.stallTime && angle > 10
            if reopened || stalled {
                beginFade(now: now)
            }
        }
    }

    private func tickFading(now: CFTimeInterval) {
        let progress = (now - fadeStart) / Self.fadeDuration
        if progress >= 1 {
            finish()
        } else {
            overlay?.alphaValue = CGFloat(1 - progress)
        }
    }

    // MARK: - Transitions

    private func beginCapture() {
        guard let screen = NSScreen.builtIn else {
            lastError = CaptureError.noScreen.localizedDescription
            resetToIdle()
            return
        }
        phase = .capturing
        captureToken += 1
        let token = captureToken

        Task {
            do {
                let image = try await self.capturer.capture(screen: screen)
                guard self.phase == .capturing, self.captureToken == token else { return }
                self.lastError = nil
                self.show(image: image, on: screen)
            } catch {
                guard self.phase == .capturing, self.captureToken == token else { return }
                self.refreshPermission()
                self.lastError = "Screenshot failed: \(error.localizedDescription)"
                self.resetToIdle()
            }
        }
    }

    private func show(image: CGImage, on screen: NSScreen) {
        let window = overlay ?? OverlayWindow(screen: screen)
        overlay = window
        window.fit(to: screen)
        window.setImage(image)
        displayedDelta = 0
        window.apply(delta: 0, tilt: settings.tilt, direction: settings.direction,
                     blur: settings.blur, dim: settings.darken)
        window.present()

        previewStart = CACurrentMediaTime()
        phase = .showing
    }

    private func beginFade(now: CFTimeInterval) {
        fadeStart = now
        phase = .fading
    }

    private func finish() {
        overlay?.dismiss() // orderOut + contents = nil
        resetToIdle()
    }

    private func resetToIdle() {
        phase = .idle
        isPreview = false
        displayedDelta = 0
        // New rest angle = where the lid is now.
        restAngle = sensor.isAvailable ? sensor.angle : nil
        lastAngleChange = CACurrentMediaTime()
    }

    private func screenParametersChanged() {
        capturer.invalidateCache()
        if phase == .showing || phase == .fading {
            finish()
        } else if phase == .capturing {
            captureToken += 1
            resetToIdle()
        }
        overlay = nil
    }

    // MARK: - Background activity

    /// Keeps timers running at full rate in the background (no App Nap) while the
    /// effect is active – but explicitly ALLOWS system sleep.
    private func updateActivity() {
        let needed = settings.enabled || phase != .idle
        if needed, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "LidGlass follows the lid angle"
            )
        } else if !needed, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }

    // MARK: - Helpers

    /// Simulated lid: 110° → 12° in 1.1 s (smoothstep), hold 0.4 s, back to 110° in 0.8 s.
    private static func previewAngle(at t: Double) -> Double {
        let closeEnd = previewCloseDuration
        let holdEnd = closeEnd + previewHoldDuration
        let openEnd = holdEnd + previewOpenDuration

        if t <= closeEnd {
            let s = OverlayWindow.smoothstep(t / previewCloseDuration)
            return previewOpen + (previewClosed - previewOpen) * s
        } else if t <= holdEnd {
            return previewClosed
        } else if t <= openEnd {
            let s = OverlayWindow.smoothstep((t - holdEnd) / previewOpenDuration)
            return previewClosed + (previewOpen - previewClosed) * s
        } else {
            return previewOpen
        }
    }
}
