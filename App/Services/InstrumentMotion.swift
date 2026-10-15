import CoreMotion
import Observation
import UIKit

/// One foreground-only source for optical effects. It never changes a simulation input.
@Observable @MainActor
final class InstrumentMotion {
    private(set) var tilt = SIMD2<Double>.zero
    private(set) var hasReading = false
    private(set) var active = false
    private(set) var status = "Touch to explore"
    private(set) var generation = UUID()
    let available: Bool
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var reference: SIMD2<Double>?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var orientation: UIInterfaceOrientation = .portrait

    init() { available = manager.isDeviceMotionAvailable }

    func start() {
        guard available else { status = "Motion unavailable · drag to explore"; return }
        guard !active else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        generation = UUID()
        active = true; hasReading = false; reference = nil; tilt = .zero
        startedAt = Date(); status = "Waiting for phone movement"
    }

    func sample() {
        guard active else { return }
        guard let sample = manager.deviceMotion else {
            if Date().timeIntervalSince(startedAt) > 3 { status = "No motion samples · use touch" }
            return
        }
        let currentOrientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }?
            .effectiveGeometry.interfaceOrientation ?? .portrait
        if currentOrientation != orientation {
            orientation = currentOrientation; reference = nil; tilt = .zero
        }
        let gravity = sample.gravity
        let horizontal: Double
        switch orientation {
        case .landscapeLeft: horizontal = gravity.y
        case .landscapeRight: horizontal = -gravity.y
        case .portraitUpsideDown: horizontal = -gravity.x
        default: horizontal = gravity.x
        }
        let reading = SIMD2(horizontal, gravity.z)
        if reference == nil { reference = reading }
        let difference = (reading - (reference ?? reading)) * 2.2
        let next = SIMD2(min(1, max(-1, difference.x)), min(1, max(-1, difference.y)))
        tilt += (next - tilt) * 0.20
        hasReading = true; status = "Live phone reflections"
    }

    func recenter() { reference = nil; tilt = .zero; hasReading = false }

    func stop(generation expected: UUID? = nil) {
        if let expected, expected != generation { return }
        manager.stopDeviceMotionUpdates()
        generation = UUID()
        active = false; hasReading = false; reference = nil; tilt = .zero
        status = "Motion reflections off"
    }
}
