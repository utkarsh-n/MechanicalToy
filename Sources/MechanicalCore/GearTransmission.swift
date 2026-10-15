import Foundation

/// The twelve geometries in the gear reference, in the same order as its numbered examples.
public enum GearKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case spur, helical, doubleHelical, bevel, screw, spiralBevel
    case worm, mitre, internalGear, rackAndPinion, herringbone, hypoid

    public var id: String { rawValue }
    /// Zero-based index for the matching rendering geometry.
    public var index: Int { Self.allCases.firstIndex(of: self)! }
    public var isRack: Bool { self == .rackAndPinion }

    /// Other geometries need bearing/contact data that this teaching model does not contain.
    public var showsAxialForceEstimate: Bool {
        [.helical, .screw, .doubleHelical, .herringbone].contains(self)
    }

    public var title: String {
        switch self {
        case .spur: "Spur gear"
        case .helical: "Helical gear"
        case .doubleHelical: "Double helical gear"
        case .bevel: "Bevel gear"
        case .screw: "Screw gear"
        case .spiralBevel: "Spiral bevel gear"
        case .worm: "Worm gear"
        case .mitre: "Mitre gear"
        case .internalGear: "Internal gear"
        case .rackAndPinion: "Rack and pinion"
        case .herringbone: "Herringbone gear"
        case .hypoid: "Hypoid gear"
        }
    }

    public var subtitle: String {
        switch self {
        case .spur: "Straight teeth · opposite rotation"
        case .helical: "Angled teeth · axial thrust"
        case .doubleHelical: "Opposing helices · a central relief gap"
        case .bevel: "Conical teeth · turn a corner"
        case .screw: "Crossed helices · skew shafts"
        case .spiralBevel: "Curved conical teeth · progressive contact"
        case .worm: "A screw drives a wheel · large reduction"
        case .mitre: "Equal bevel gears · a 1:1 corner"
        case .internalGear: "Teeth inside a ring · same rotation"
        case .rackAndPinion: "Rotation becomes straight travel"
        case .herringbone: "Continuous chevrons · balanced thrust"
        case .hypoid: "Offset shafts · curved sliding contact"
        }
    }

    public var explanation: String {
        switch self {
        case .spur:
            "Straight teeth run along the shaft. With fixed parallel shafts, each external gear pushes its partner in the opposite direction. Tooth counts set the speed ratio."
        case .helical:
            "An angled tooth enters contact progressively across the face. Its load has a component along the shaft: increasing the helix angle increases that axial thrust at a fixed tangential force."
        case .doubleHelical:
            "Two opposite-handed helices share one gear, with a relief groove between them. If both halves carry equal load, their axial forces cancel while the tooth-count ratio stays unchanged."
        case .bevel:
            "Conical pitch surfaces meet where the shaft axes intersect. This pair changes the direction of a drive, with the illustrated shafts at a right angle. Unequal tooth counts also change speed."
        case .screw:
            "Also called crossed helical gears, this is a pair of helical cylinders on skew shafts. Their teeth slide through a small contact region. The illustrated equal helices use a shaft angle of 2β. A screw gear pair differs from the few-start worm drive."
        case .spiralBevel:
            "Curved teeth wrap around conical gear surfaces. Contact develops progressively across the teeth while the intersecting shafts redirect rotation. The spiral tooth form does not alter the tooth-count ratio."
        case .worm:
            "One turn of a single-start worm advances the wheel by one tooth. A worm with more starts advances more teeth each turn, increasing output speed and reducing the torque multiplication."
        case .mitre:
            "A mitre pair is a bevel pair with equal tooth counts. It redirects rotation through a corner while keeping the speed magnitude unchanged. The output torque still falls when efficiency is below one."
        case .internalGear:
            "A pinion meshes with teeth on the inside of a ring. On fixed parallel shafts, both members turn in the same direction. The ring's larger tooth count gives a slower output."
        case .rackAndPinion:
            "The pinion's pitch circle rolls along a straight toothed rack. Each complete turn moves the rack by one pitch circumference. A larger pinion travels farther per turn but delivers less force at the same torque."
        case .herringbone:
            "Opposite-handed teeth join into continuous V shapes without a central groove. Like a double helical pair, equal loading of the two halves balances their opposing axial thrust."
        case .hypoid:
            "The pinion shaft passes above or below the wheel's axis instead of intersecting it. The offset permits different drive packaging, with additional sliding along the curved tooth contact."
        }
    }

    public var application: String {
        switch self {
        case .spur: "Simple reducers, mechanical toys, and timing mechanisms."
        case .helical: "Vehicle transmissions and industrial speed reducers."
        case .doubleHelical: "Large power transmissions where thrust balance matters."
        case .bevel: "Right-angle drives and the gears inside differentials."
        case .screw: "Compact skew-shaft drives carrying modest loads."
        case .spiralBevel: "Aircraft accessory drives and right-angle vehicle drives."
        case .worm: "Positioning drives, compact reducers, and tuning mechanisms."
        case .mitre: "Equal-speed right-angle drives and shaft redirection."
        case .internalGear: "Planetary gearboxes and compact enclosed reductions."
        case .rackAndPinion: "Steering racks, linear stages, and machine-tool feeds."
        case .herringbone: "Heavy machinery and high-power balanced transmissions."
        case .hypoid: "Final drives in rear-wheel-drive vehicles and offset gearboxes."
        }
    }

    public var axesDescription: String {
        switch self {
        case .spur, .helical, .doubleHelical, .internalGear, .herringbone: "Parallel shafts"
        case .bevel, .spiralBevel, .mitre: "Intersecting shafts · 90° in this view"
        case .screw: "Skew shafts · angle follows the two helices"
        case .worm: "Skew shafts · typically a right angle"
        case .rackAndPinion: "Rotating shaft and a straight sliding rack"
        case .hypoid: "Offset shafts · nonparallel and nonintersecting"
        }
    }

    public var caution: String {
        switch self {
        case .spur: "Tooth shape, backlash, noise, and tooth strength are not solved."
        case .helical: "Thrust is an ideal magnitude on the input shaft; its direction depends on helix hand and drive direction."
        case .doubleHelical, .herringbone: "Zero net thrust assumes equal loading of both halves. Manufacturing and alignment errors can leave residual thrust."
        case .bevel, .spiralBevel: "The corner is schematic. Bearing loads and a manufacturable tooth contact pattern need more geometry."
        case .screw: "Compatible helix hands and angles are required in a real pair. Sliding friction and contact stress are not solved."
        case .worm: "A worm is not automatically self-locking. Back-driving depends on lead angle, friction, lubrication, and other losses."
        case .mitre: "The driven tooth count follows the driver to preserve the defining 1:1 ratio."
        case .internalGear: "The ring stays larger than the pinion. This simple count constraint does not check tooth interference."
        case .rackAndPinion: "Travel is ideal and unbounded. The view repeats the rack; it does not model end stops or tooth strength."
        case .hypoid: "Offset, sliding friction, tooth contact, and bearing loads need a full gear design; only the speed ratio is solved here."
        }
    }
}

public struct GearTransmissionInputs: Codable, Equatable, Sendable {
    public var driverTeeth: Double
    public var drivenTeeth: Double
    public var inputRPM: Double
    /// Nonnegative applied torque magnitude in newton metres.
    public var inputTorque: Double
    /// A chosen lumped efficiency, rather than one predicted from tooth geometry.
    public var efficiency: Double
    /// Transverse pitch module in millimetres: pitch diameter = module × tooth count.
    public var moduleMM: Double
    public var helixAngleDegrees: Double
    public var wormStarts: Double

    public init(driverTeeth: Double = 20, drivenTeeth: Double = 40, inputRPM: Double = 60,
                inputTorque: Double = 5, efficiency: Double = 0.95, moduleMM: Double = 3,
                helixAngleDegrees: Double = 25, wormStarts: Double = 1) {
        self.driverTeeth = driverTeeth
        self.drivenTeeth = drivenTeeth
        self.inputRPM = inputRPM
        self.inputTorque = inputTorque
        self.efficiency = efficiency
        self.moduleMM = moduleMM
        self.helixAngleDegrees = helixAngleDegrees
        self.wormStarts = wormStarts
    }
}

public struct GearTransmissionResult: Sendable {
    /// Signed speed using the local shaft convention described in `directionDescription`.
    public let outputRPM: Double
    public let outputTorque: Double
    /// Input turns per output turn; a rack has no rotary reduction and reports 1.
    public let ratio: Double
    public let rackSpeedMMPerSecond: Double
    public let rackForceNewtons: Double
    /// Only meaningful when `kind.showsAxialForceEstimate` is true; otherwise not evaluated.
    public let axialForceNewtons: Double
    public let directionDescription: String
    public let equation: String
    public let assumptions: String
}

/// Fixed-shaft kinematics and elementary force estimates for exploration, not gear sizing.
public enum GearTransmission {
    /// Controls and renderers can share the solver's safe, finite, integral geometry.
    public static func normalizedInputs(kind: GearKind, inputs: GearTransmissionInputs) -> GearTransmissionInputs {
        let defaults = GearTransmissionInputs()
        func bounded(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
        }
        var result = inputs
        result.driverTeeth = bounded(inputs.driverTeeth, 6...200, defaults.driverTeeth).rounded()
        result.drivenTeeth = bounded(inputs.drivenTeeth, 6...200, defaults.drivenTeeth).rounded()
        result.inputRPM = bounded(inputs.inputRPM, -1200...1200, defaults.inputRPM)
        result.inputTorque = bounded(inputs.inputTorque, 0...500, defaults.inputTorque)
        result.efficiency = bounded(inputs.efficiency, 0...1, defaults.efficiency)
        result.moduleMM = bounded(inputs.moduleMM, 0.5...12, defaults.moduleMM)
        result.helixAngleDegrees = bounded(inputs.helixAngleDegrees, 0...60, defaults.helixAngleDegrees)
        result.wormStarts = bounded(inputs.wormStarts, 1...8, defaults.wormStarts).rounded()
        if kind == .mitre { result.drivenTeeth = result.driverTeeth }
        if kind == .internalGear {
            result.driverTeeth = min(result.driverTeeth, 196)
            result.drivenTeeth = max(result.drivenTeeth, result.driverTeeth + 4)
        }
        return result
    }

    public static func solve(kind: GearKind, inputs: GearTransmissionInputs) -> GearTransmissionResult {
        let values = normalizedInputs(kind: kind, inputs: inputs)
        let pitchRadiusMetres = values.moduleMM * values.driverTeeth / 2000
        let tangentialInputForce = values.inputTorque / pitchRadiusMetres
        let helixRadians = values.helixAngleDegrees * .pi / 180
        let axialForce = (kind == .helical || kind == .screw) ? tangentialInputForce * tan(helixRadians) : 0
        let basicAssumptions = "Rigid fixed shafts; steady motion; no backlash, elastic deflection, or tooth-strength calculation. η is a chosen torque/power efficiency, not a prediction. Module is transverse (d = mN)."

        if kind.isRack {
            let speed = values.inputRPM * 2 * .pi / 60 * pitchRadiusMetres * 1000
            let force = tangentialInputForce * values.efficiency
            return GearTransmissionResult(
                outputRPM: 0, outputTorque: 0, ratio: 1,
                rackSpeedMMPerSecond: speed, rackForceNewtons: force, axialForceNewtons: 0,
                directionDescription: "Positive input turns move the rack right; negative input turns move it left in this view.",
                equation: "r = mN/2 · v = (2πn/60)r · F = ηT/r",
                assumptions: basicAssumptions + " Rack output is translation: rotary output readings are zero and ratio is 1. Travel has no end stops. Force is a magnitude; its travel direction follows input rotation.")
        }

        let ratio = kind == .worm ? values.drivenTeeth / values.wormStarts : values.drivenTeeth / values.driverTeeth
        let sameDirection = kind == .internalGear
        let outputRPM = values.inputRPM / ratio * (sameDirection ? 1 : -1)
        let outputTorque = values.inputTorque * ratio * values.efficiency
        let direction: String
        switch kind {
        case .internalGear: direction = "Same direction on the fixed parallel shafts."
        case .spur, .helical, .doubleHelical, .herringbone: direction = "Opposite directions on the fixed parallel shafts."
        default: direction = "The sign follows the local shaft arrows in this view; clockwise comparisons require looking along each shaft."
        }
        let equation: String
        switch kind {
        case .worm: equation = "i = Nwheel / starts · |nout| = |nin|/i · Tout = ηTin i"
        case .mitre: equation = "Nout = Nin · i = 1 · |nout| = |nin| · Tout = ηTin"
        default: equation = "i = Nout/Nin · nout = " + (sameDirection ? "+" : "−") + "nin/i · Tout = ηTin i"
        }
        var assumptions = basicAssumptions
        switch kind {
        case .helical, .screw:
            assumptions += " Input-shaft axial thrust magnitude uses Fa = (Tin/rin) tan β, ignoring mesh friction; helix hand determines the direction."
        case .doubleHelical, .herringbone:
            assumptions += " Equal loading of opposite-handed halves cancels ideal net axial thrust."
        case .internalGear:
            assumptions += " The ring is at least four teeth larger than the pinion; tooth interference is not evaluated."
        case .mitre:
            assumptions += " Both tooth counts are equal. Bearing loads are not evaluated."
        case .worm:
            assumptions += " The worm is the input. Its starts replace input tooth count. Lead angle, thrust, and self-locking are not evaluated."
        case .bevel, .spiralBevel, .hypoid:
            assumptions += " Local shaft signs are schematic; axial bearing loads and tooth contact are not evaluated."
        default: break
        }
        return GearTransmissionResult(
            outputRPM: outputRPM, outputTorque: outputTorque, ratio: ratio,
            rackSpeedMMPerSecond: 0, rackForceNewtons: 0, axialForceNewtons: axialForce,
            directionDescription: direction, equation: equation, assumptions: assumptions)
    }
}
