import AppKit
import QuartzCore
import CoreImage

/// Borderless full-screen window above everything (incl. menu bar and Dock)
/// that shows the screenshot in perspective.
@MainActor
final class OverlayWindow: NSWindow {
    private let rootLayer = CALayer()
    private let imageLayer = CALayer()
    private let dimLayer = CALayer()

    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setUp()
        fit(to: screen)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func setUp() {
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        // Layer-hosting content view with Core Image filters enabled.
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.layer = rootLayer
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        view.autoresizingMask = [.width, .height]
        contentView = view

        rootLayer.backgroundColor = NSColor.black.cgColor
        rootLayer.masksToBounds = true

        imageLayer.contentsGravity = .resize
        imageLayer.masksToBounds = false
        imageLayer.isDoubleSided = true

        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setDefaults()
            blur.name = "blur"
            blur.setValue(0.0, forKey: kCIInputRadiusKey)
            imageLayer.filters = [blur]
        }

        dimLayer.backgroundColor = NSColor.black.cgColor
        dimLayer.opacity = 0

        imageLayer.addSublayer(dimLayer)
        rootLayer.addSublayer(imageLayer)
    }

    /// Positions the window and layers on the given screen.
    func fit(to screen: NSScreen) {
        setFrame(screen.frame, display: false)
        let size = screen.frame.size

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        rootLayer.frame = CGRect(origin: .zero, size: size)
        rootLayer.contentsScale = screen.backingScaleFactor

        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / (size.height * 1.6)
        rootLayer.sublayerTransform = perspective

        imageLayer.transform = CATransform3DIdentity
        imageLayer.bounds = CGRect(origin: .zero, size: size)
        imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        imageLayer.position = CGPoint(x: size.width * 0.5, y: 0)
        imageLayer.contentsScale = screen.backingScaleFactor

        dimLayer.frame = imageLayer.bounds

        CATransaction.commit()
    }

    func setImage(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        CATransaction.commit()
    }

    /// Shows the overlay immediately without animation.
    func present() {
        alphaValue = 1
        orderFrontRegardless()
    }

    /// Removes the overlay and frees the screenshot from memory.
    func dismiss() {
        orderOut(nil)
        setImage(nil)
        alphaValue = 1
    }

    /// Applies the per-frame transformation.
    /// - Parameters:
    ///   - delta: how far the lid has closed since the start (degrees)
    ///   - tilt: tilt strength
    ///   - direction: −1 (left) … +1 (right)
    ///   - blur: maximum blur radius (pt)
    ///   - dim: maximum darkening (0 … 1)
    func apply(delta: Double, tilt: Double, direction: Double, blur: Double, dim: Double) {
        let size = rootLayer.bounds.size
        let degrees = min(75, max(0, delta * tilt))
        let radians = degrees * .pi / 180
        let dir = min(1, max(-1, direction))

        let anchorX = 0.5 - 0.5 * dir

        let back = CATransform3DMakeRotation(CGFloat(-radians * (1 - abs(dir))), 1, 0, 0)
        let side = CATransform3DMakeRotation(CGFloat(radians * dir), 0, 1, 0)
        let roll = CATransform3DMakeRotation(CGFloat(-radians * dir * 0.25), 0, 0, 1)
        let transform = CATransform3DConcat(CATransform3DConcat(back, side), roll)

        let blurRadius = blur * Self.smoothstep(min(1, delta / 45))
        let dimAmount = dim * min(1, delta / 90)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.anchorPoint = CGPoint(x: anchorX, y: 0)
        imageLayer.position = CGPoint(x: size.width * anchorX, y: 0)
        imageLayer.transform = transform
        imageLayer.setValue(blurRadius, forKeyPath: "filters.blur.inputRadius")
        dimLayer.opacity = Float(min(1, max(0, dimAmount)))
        CATransaction.commit()
    }

    static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}
