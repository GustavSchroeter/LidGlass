import Foundation
import IOKit
import IOKit.hid

/// Reads the MacBook lid angle from Apple's HID orientation sensor.
///
/// Device: VendorID 0x05AC, ProductID 0x8104, UsagePage 0x0020 (Sensor), Usage 0x008A (Orientation).
/// The angle is read via a feature report (ID 1): degrees = report[2] << 8 | report[1].
@MainActor
@Observable
final class LidAngleSensor {
    /// Current lid angle in degrees (0 = closed).
    private(set) var angle: Double = 0
    /// False if no sensor was found or it cannot be read (e.g. some M1 models).
    private(set) var isAvailable = false

    @ObservationIgnored private var manager: IOHIDManager?
    @ObservationIgnored private var device: IOHIDDevice?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var consecutiveFailures = 0

    private static let vendorID = 0x05AC
    private static let productID = 0x8104
    private static let usagePage = 0x0020
    private static let usage = 0x008A
    private static let reportID: CFIndex = 1
    private static let pollInterval: TimeInterval = 1.0 / 60.0

    init() {
        // Intentionally empty: the device is opened in start(), never here.
    }

    /// Opens the HID device and starts polling. Safe to call more than once.
    func start() {
        guard !started else { return }
        started = true

        guard let device = openDevice() else {
            isAvailable = false
            return
        }
        self.device = device
        isAvailable = true

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        manager = nil
        started = false
        isAvailable = false
    }

    // MARK: - Private

    private func openDevice() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: Self.usagePage,
            kIOHIDPrimaryUsageKey: Self.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            return nil
        }

        // Several interfaces may match – use the first one that delivers a valid report.
        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
                continue
            }
            if let value = Self.readAngle(from: candidate) {
                angle = value
                return candidate
            }
            IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        return nil
    }

    private func poll() {
        guard let device else { return }
        if let value = Self.readAngle(from: device) {
            consecutiveFailures = 0
            if !isAvailable { isAvailable = true }
            if value != angle { angle = value }
        } else {
            consecutiveFailures += 1
            // About 2 seconds without a readable report → report as unavailable.
            if consecutiveFailures > 120, isAvailable {
                isAvailable = false
            }
        }
    }

    private static func readAngle(from device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, reportID, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }
        let raw = UInt16(report[2]) << 8 | UInt16(report[1])
        return Double(raw)
    }
}
