import CoreMotion
import Observation
import Foundation

@Observable @MainActor
final class MotionInput {
    private let manager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private var calibratedRoll = 0.0
    private var calibratedPitch = 0.0
    private var startedAt = Date()
    let available: Bool
    let pressureAvailable = CMAltimeter.isRelativeAltitudeAvailable()
    private(set) var active = false
    private(set) var hasReading = false
    private(set) var roll = 0.0
    private(set) var pitch = 0.0
    private(set) var acceleration = 0.0
    private(set) var angularSpeed = 0.0
    private(set) var pressureKPa: Double?
    private(set) var pressureError: String?
    private(set) var status = "Manual input"

    init() { available = manager.isDeviceMotionAvailable }

    func start() {
        guard available else { status = "Motion hardware unavailable. Use the controls."; return }
        guard !active else { return }
        if CMMotionActivityManager.authorizationStatus() == .denied {
            status = "Motion permission denied. Enable it in iPhone Settings or use touch."; return
        }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        startedAt = Date(); active = true; hasReading = false
        status = "Waiting for iPhone motion…"
    }

    func poll() {
        guard active else { return }
        guard let sample = manager.deviceMotion else {
            if Date().timeIntervalSince(startedAt) > 3 {
                status = "No motion samples. Check Motion permission in Settings; touch remains available."
            }
            return
        }
        if !hasReading {
            calibratedRoll = sample.attitude.roll; calibratedPitch = sample.attitude.pitch
            roll = 0; pitch = 0
        }
        hasReading = true; status = "Live iPhone motion"
        let rawRoll = sample.attitude.roll - calibratedRoll
        let rawPitch = sample.attitude.pitch - calibratedPitch
        // atan2 keeps a calibrated offset continuous when an attitude wraps at ±π.
        let relativeRoll = atan2(sin(rawRoll), cos(rawRoll))
        let relativePitch = atan2(sin(rawPitch), cos(rawPitch))
        roll += 0.18 * (relativeRoll - roll)
        pitch += 0.18 * (relativePitch - pitch)
        let a = sample.userAcceleration
        acceleration = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
        let w = sample.rotationRate
        angularSpeed = sqrt(w.x * w.x + w.y * w.y + w.z * w.z)
    }

    func calibrate() {
        guard let sample = manager.deviceMotion else { return }
        calibratedRoll = sample.attitude.roll; calibratedPitch = sample.attitude.pitch
        roll = 0; pitch = 0
    }

    func startPressure() {
        guard pressureAvailable else { return }
        pressureError = nil
        altimeter.startRelativeAltitudeUpdates(to: .main) { @Sendable [weak self] reading, error in
            let pressure = reading?.pressure.doubleValue
            let message = error?.localizedDescription
            MainActor.assumeIsolated {
                self?.pressureKPa = pressure
                self?.pressureError = message
            }
        }
    }

    func stopPressure() {
        altimeter.stopRelativeAltitudeUpdates(); pressureKPa = nil; pressureError = nil
    }

    func stop() {
        manager.stopDeviceMotionUpdates(); stopPressure()
        active = false; hasReading = false; status = "Manual input"
    }
}
