import Foundation

public enum RoomClimateMode: String, CaseIterable, Codable, Sendable {
    case off, heat, cool, auto
    public var title: String { rawValue.capitalized }
}

/// A well-mixed 80 m³ room. This is a teaching model, not an HVAC sizing tool.
public struct RoomEnvironmentInputs: Sendable {
    public var outdoorTemperature: Double = 8
    public var outdoorHumidity: Double = 65
    public var targetTemperature: Double = 21
    public var occupants: Double = 2
    public var ventilationACH: Double = 0.6
    public var windowOpening: Double = 0
    public var conductance: Double = 85
    public var mode: RoomClimateMode = .auto
    public init() {}

    public var airChangesPerHour: Double {
        clamped(ventilationACH, 0...6) + 12 * clamped(windowOpening, 0...1)
    }

    private func clamped(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }

    public var bounded: Self {
        var result = self
        result.outdoorTemperature = clamped(outdoorTemperature, -15...40)
        result.outdoorHumidity = clamped(outdoorHumidity, 5...100)
        result.targetTemperature = clamped(targetTemperature, 15...28)
        result.occupants = clamped(occupants, 0...8)
        result.ventilationACH = clamped(ventilationACH, 0...6)
        result.windowOpening = clamped(windowOpening, 0...1)
        result.conductance = clamped(conductance, 20...300)
        return result
    }
}

public struct RoomEnvironment: Sendable {
    public static let volume = 80.0
    public static let outdoorCO2 = 420.0
    /// Furnishings and walls add thermal inertia to the air.
    public static let thermalCapacity = 650_000.0
    public private(set) var temperature: Double = 22
    public private(set) var humidityRatio: Double
    public private(set) var co2PPM: Double = 700
    public private(set) var elapsed: Double = 0
    public private(set) var hvacPower: Double = 0
    public private(set) var envelopePower: Double = 0
    public private(set) var ventilationPower: Double = 0
    public private(set) var condensedWater: Double = 0

    public init(temperature: Double = 22, relativeHumidity: Double = 45, co2PPM: Double = 700) {
        self.temperature = temperature.isFinite ? min(50, max(-20, temperature)) : 22
        let humidity = relativeHumidity.isFinite ? min(100, max(0, relativeHumidity)) : 45
        self.humidityRatio = Self.saturationRatio(at: self.temperature) * humidity / 100
        self.co2PPM = co2PPM.isFinite ? min(20_000, max(Self.outdoorCO2, co2PPM)) : 700
    }

    public var relativeHumidity: Double {
        min(100, max(0, humidityRatio / Self.saturationRatio(at: temperature) * 100))
    }

    /// Tetens saturation pressure and humidity ratio at standard sea-level pressure.
    public static func saturationRatio(at temperature: Double) -> Double {
        let t = min(60, max(-40, temperature.isFinite ? temperature : 20))
        let pressure = 610.78 * exp(17.2694 * t / (t + 237.29))
        return 0.622 * pressure / (101_325 - pressure)
    }

    /// Exact first-order mixing updates; one-second thermal/controller substeps avoid overshoot.
    public mutating func step(seconds: Double, inputs rawInputs: RoomEnvironmentInputs) {
        guard seconds.isFinite, seconds > 0 else { return }
        let inputs = rawInputs.bounded
        var remaining = min(seconds, 3_600)
        while remaining > 0 {
            let dt = min(remaining, 1)
            advance(dt, inputs)
            remaining -= dt
            elapsed += dt
        }
    }

    private mutating func advance(_ dt: Double, _ inputs: RoomEnvironmentInputs) {
        let error = inputs.targetTemperature - temperature
        let requested = min(3_000, max(-3_000, error * 1_500))
        switch inputs.mode {
        case .off: hvacPower = 0
        case .heat: hvacPower = max(0, requested)
        case .cool: hvacPower = min(0, requested)
        case .auto: hvacPower = requested
        }
        let mixingRate = inputs.airChangesPerHour / 3_600
        let airMass = 1.204 * Self.volume
        let ventilationConductance = airMass * 1_006 * mixingRate
        envelopePower = inputs.conductance * (inputs.outdoorTemperature - temperature)
        ventilationPower = ventilationConductance * (inputs.outdoorTemperature - temperature)
        let loss = inputs.conductance + ventilationConductance
        let source = hvacPower + inputs.occupants * 75
        let equilibrium = inputs.outdoorTemperature + source / loss
        temperature = equilibrium + (temperature - equilibrium) * exp(-loss * dt / Self.thermalCapacity)

        let co2Source = inputs.occupants * 0.000005 / Self.volume * 1_000_000
        co2PPM = mix(co2PPM, ambient: Self.outdoorCO2, source: co2Source, rate: mixingRate, dt: dt)
        // Each occupant supplies 54 g water/hour; cooling removes a simple latent load.
        let occupantWater = inputs.occupants * 0.000015
        let latentRemoval = max(0, -hvacPower) * 0.12 / 2_450_000
        let outdoorWater = Self.saturationRatio(at: inputs.outdoorTemperature) * inputs.outdoorHumidity / 100
        humidityRatio = max(0, mix(humidityRatio, ambient: outdoorWater,
                                  source: (occupantWater - latentRemoval) / airMass,
                                  rate: mixingRate, dt: dt))
        let saturated = Self.saturationRatio(at: temperature)
        if humidityRatio > saturated {
            condensedWater += (humidityRatio - saturated) * airMass
            humidityRatio = saturated
        }
        co2PPM = max(Self.outdoorCO2, co2PPM)
    }

    private func mix(_ value: Double, ambient: Double, source: Double, rate: Double, dt: Double) -> Double {
        guard rate > 0.0000001 else { return value + source * dt }
        let decay = exp(-rate * dt)
        return ambient + (value - ambient) * decay + source / rate * (1 - decay)
    }
}
