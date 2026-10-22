import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

extension NSScreen {
    /// The CoreGraphics display ID of this screen.
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// The built-in display (MacBook panel), falling back to the main screen.
    static var builtIn: NSScreen? {
        for screen in NSScreen.screens {
            if let id = screen.displayID, CGDisplayIsBuiltin(id) != 0 {
                return screen
            }
        }
        return NSScreen.main
    }
}

enum CaptureError: LocalizedError {
    case noScreen
    case displayNotFound
    case noPermission

    nonisolated var errorDescription: String? {
        switch self {
        case .noScreen: "No display found."
        case .displayNotFound: "The built-in display is not available for capture."
        case .noPermission: "Screen Recording permission is missing."
        }
    }
}

/// Takes a single screenshot of a display with ScreenCaptureKit.
/// The image only ever lives in memory – nothing is written to disk.
@MainActor
final class ScreenCapturer {
    private var cachedDisplay: SCDisplay?
    private var cachedDisplayID: CGDirectDisplayID?
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.invalidateCache()
            }
        }
    }

    func invalidateCache() {
        cachedDisplay = nil
        cachedDisplayID = nil
    }

    /// Fetches the SCDisplay ahead of time so the first real capture is fast.
    func warmUp() {
        guard CGPreflightScreenCaptureAccess(), let screen = NSScreen.builtIn, let id = screen.displayID else { return }
        Task {
            _ = try? await self.display(for: id)
        }
    }

    func capture(screen: NSScreen) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.noPermission }
        guard let id = screen.displayID else { throw CaptureError.noScreen }

        let display = try await display(for: id)
        let scale = screen.backingScaleFactor

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int((screen.frame.width * scale).rounded())
        config.height = Int((screen.frame.height * scale).rounded())
        config.captureResolution = .best
        config.showsCursor = true
        config.scalesToFit = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func display(for id: CGDirectDisplayID) async throws -> SCDisplay {
        if let cachedDisplay, cachedDisplayID == id {
            return cachedDisplay
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw CaptureError.displayNotFound
        }
        cachedDisplay = display
        cachedDisplayID = id
        return display
    }
}
