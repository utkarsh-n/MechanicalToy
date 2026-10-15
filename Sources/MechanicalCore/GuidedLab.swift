import Foundation

public enum GuidedLabID: String, CaseIterable, Identifiable, Sendable {
    case tiltGears, airflow, climateFreshAir, climateThermostat
    case gearOptics, gearSpurDrive, gearWormReduction, gearRackTravel
    public var id: String { rawValue }
}

public enum GuidedLabDestination: String, Sendable {
    case gears, airflow, climate, gearBench
}

/// A complete gear-bench checkpoint. Playback remains an intent owned by the app.
public struct GuidedGearSetup: Equatable, Sendable {
    public let kind: GearKind
    public let inputs: GearTransmissionInputs
    public let startsPaused: Bool

    public init(kind: GearKind, inputs: GearTransmissionInputs, startsPaused: Bool = false) {
        self.kind = kind
        self.inputs = GearTransmission.normalizedInputs(kind: kind, inputs: inputs)
        self.startsPaused = startsPaused
    }
}

/// Intent only: the app owns sensor permission, playback, and the simulation clock.
public enum GuidedLabAction: String, Sendable {
    case none, calibrateTilt, pauseGear, resumeGear
    case runAirflow, doubleAirflow, angleWing, blockAirflow, pauseAirflow, stepAirflow
    case advanceClosedClimate, ventilateClimate, enableAutoHeat, advanceHeatedClimate
    case recenterGearOptics, driveSpur60, driveSpur120, stopSpurDrive, reduceSpurThreeToOne
    case doubleWormStarts, doubleRackSpeed, enlargeRackPinion

    /// Numeric checkpoints restore every input, so a previous manual edit cannot invalidate the guide.
    /// Optical recentering is deliberately separate: it must not replace the selected model or inputs.
    public var gearBenchSetup: GuidedGearSetup? {
        switch self {
        case .driveSpur60:
            GuidedGearSetup(kind: .spur, inputs: GearTransmissionInputs())
        case .driveSpur120:
            GuidedGearSetup(kind: .spur, inputs: GearTransmissionInputs(inputRPM: 120))
        case .stopSpurDrive:
            GuidedGearSetup(kind: .spur, inputs: GearTransmissionInputs(inputRPM: 0))
        case .reduceSpurThreeToOne:
            GuidedGearSetup(kind: .spur, inputs: GearTransmissionInputs(drivenTeeth: 60))
        case .doubleWormStarts:
            GuidedGearSetup(kind: .worm, inputs: GearTransmissionInputs(inputRPM: 120, wormStarts: 2))
        case .doubleRackSpeed:
            GuidedGearSetup(kind: .rackAndPinion, inputs: GearTransmissionInputs(driverTeeth: 16, inputRPM: 120))
        case .enlargeRackPinion:
            GuidedGearSetup(kind: .rackAndPinion, inputs: GearTransmissionInputs(driverTeeth: 24))
        default:
            nil
        }
    }
}

public struct GuidedLabStep: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let instructions: String
    public let expected: String
    public let action: GuidedLabAction
    public let actionTitle: String?

    public init(id: String, title: String, instructions: String, expected: String, action: GuidedLabAction, actionTitle: String? = nil) {
        self.id = id
        self.title = title
        self.instructions = instructions
        self.expected = expected
        self.action = action
        self.actionTitle = actionTitle
    }
}

public struct GuidedLabDefinition: Identifiable, Sendable {
    public let id: GuidedLabID
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let destination: GuidedLabDestination
    public let steps: [GuidedLabStep]

    public var gearBenchSetup: GuidedGearSetup? {
        switch id {
        case .gearOptics:
            GuidedGearSetup(kind: .spur, inputs: GearTransmissionInputs(), startsPaused: true)
        case .gearSpurDrive:
            GuidedGearSetup(kind: .spur, inputs: GearTransmissionInputs())
        case .gearWormReduction:
            GuidedGearSetup(kind: .worm, inputs: GearTransmissionInputs(inputRPM: 120))
        case .gearRackTravel:
            GuidedGearSetup(kind: .rackAndPinion, inputs: GearTransmissionInputs(driverTeeth: 16))
        default:
            nil
        }
    }

    public var gearValues: [String: Double] {
        var values = MechanicalSolver.defaults(for: .gears)
        values["inputRPM"] = 600
        values["driverTeeth"] = 20
        values["drivenTeeth"] = 40
        return MechanicalSolver.normalizedValues(for: .gears, values: values)
    }

    public var flowSetup: RoomFlowInputs {
        var inputs = RoomFlowInputs()
        inputs.body = .wing
        inputs.angle = 0
        inputs.speed = 5
        inputs.bodyX = 0.47
        inputs.bodyY = 0.5
        return inputs
    }

    public var climateSetup: RoomEnvironmentInputs {
        var inputs = RoomEnvironmentInputs()
        inputs.mode = .off
        inputs.outdoorTemperature = id == .climateThermostat ? 8 : 22
        inputs.outdoorHumidity = 65
        inputs.ventilationACH = 0
        inputs.windowOpening = id == .climateThermostat ? 0.5 : 0
        inputs.occupants = id == .climateThermostat ? 0 : 4
        inputs.conductance = 85
        inputs.targetTemperature = 21
        return inputs
    }

    public static func find(_ id: GuidedLabID) -> GuidedLabDefinition {
        catalog.first { $0.id == id }!
    }

    public static let catalog: [GuidedLabDefinition] = [
        GuidedLabDefinition(
            id: .tiltGears,
            title: "Tilt a gear pair",
            subtitle: "Turn your iPhone into a calibrated speed control.",
            symbol: "iphone.gen3.radiowaves.left.and.right",
            destination: .gears,
            steps: [
                step("calibrate", "Choose your neutral position",
                     "Hold the iPhone comfortably with its screen toward you. Calibrate and run, then wait for Live iPhone motion. The selected input is Input speed. If motion is unavailable, use its slider instead.",
                     "At neutral: input 600 rpm, output −300 rpm, and output torque 9.5 N·m. The two gears turn in opposite directions.",
                     .calibrateTilt, "Calibrate & run"),
                step("positiveRoll", "Make a small positive tilt",
                     "Watch Phone roll and gently rock the phone until it reads about +10°. Hold it there briefly so the filtered reading settles. Scroll back to the cutaway to inspect the gears.",
                     "Input speed approaches 733 rpm and output speed −367 rpm. The output stays at half the input speed; efficiency changes torque, not the tooth ratio.",
                     .none),
                step("negativeRoll", "Tilt through neutral",
                     "Return to the calibrated position, then rock in the opposite direction until Phone roll is about −10°. Keep the same calibration.",
                     "Input speed approaches 467 rpm and output speed −233 rpm. The calibrated input changes by about 133 rpm for each 10° of roll.",
                     .none),
                step("pause", "Freeze the cause and effect",
                     "Pause, then move the phone. Compare the input value and the cutaway before and after the movement.",
                     "The simulation clock and tilt-controlled input stay fixed. Pause intentionally stops polling motion into the experiment.",
                     .pauseGear, "Pause gears"),
                step("resume", "Resume the same experiment",
                     "Return to your calibrated neutral position before resuming. Then repeat a gentle tilt. You can recalibrate later at any comfortable position.",
                     "The clock runs and tilt changes Input speed again. Rotating cutaways are slowed for inspection; numerical rpm is the physical operating input.",
                     .resumeGear, "Resume gears")
            ]),
        GuidedLabDefinition(
            id: .airflow,
            title: "Shape an airstream",
            subtitle: "Follow tracer bands around a wing, a wall, and a block.",
            symbol: "wind",
            destination: .airflow,
            steps: [
                step("run", "Start a gentle flow",
                     "Run the wind room with Body set to Wing, Body angle 0°, Inlet speed 5 m/s, and Show field set to Tracers. Let the bands travel from the inlet toward the outlet.",
                     "Cyan bands travel around the body. With the centered wing, expect mean speed around 4.5 m/s and peak speed around 5–6 m/s after settling.",
                     .runAirflow, "Run at 5 m/s"),
                step("double", "Double the inlet speed",
                     "Change only Inlet speed to 10 m/s. Watch how quickly the tracer bands travel, and compare Mean air speed and Peak air speed.",
                     "With the centered 0° wing, expect mean speed around 9 m/s and peak speed around 10–11 m/s after settling. Tracers move faster; the color scale adjusts with inlet speed.",
                     .doubleAirflow, "Set 10 m/s"),
                step("angle", "Give the wing an angle",
                     "Return Inlet speed to 5 m/s and set Body angle to 15°. Drag the copper wing toward a wall, leaving a narrow path for the air.",
                     "The path bends around the wing, and air accelerates through the constricted gap. Show field → Speed makes slower and faster regions easier to compare.",
                     .angleWing, "Wing at 15°"),
                step("block", "Exchange the wing for a block",
                     "Choose Body → Block while keeping the current position, 15° angle, and 5 m/s inlet. Compare the flow path and wake with the wing.",
                     "A different obstruction produces a different path around it. This coarse 2D experiment illustrates blockage; it does not supply a certified lift or drag measurement.",
                     .blockAirflow, "Use a block"),
                step("pause", "Hold the field still",
                     "Pause the airflow so you can inspect the tracer bands, arrows, and numerical values. Choose Tracers or Speed without advancing time.",
                     "Elapsed simulation time and the transported field stop advancing. You can still change the display or move the body.",
                     .pauseAirflow, "Pause airflow"),
                step("step", "Advance one small interval",
                     "Step the paused model once. Compare the tracer positions before and after. Step also works when Reduce Motion prevents continuous playback.",
                     "The airflow advances by 0.1 simulated second, then remains paused for inspection.",
                     .stepAirflow, "Step 0.1 s")
            ]),
        GuidedLabDefinition(
            id: .climateFreshAir,
            title: "People and fresh air",
            subtitle: "Watch accumulation, then introduce ventilation.",
            symbol: "person.2.wave.2",
            destination: .climate,
            steps: [
                step("closed", "Give four people ten minutes",
                     "Start at 22°C and 700 ppm CO₂. Climate controller is Off, Outdoor temperature 22°C, Fresh air fan 0, Window opening 0, and there are 4 occupants. Advance ten simulated minutes with these inputs.",
                     "CO₂ rises to about 850 ppm: the four people add 150 ppm over ten minutes. They also add heat and water vapor; those are separate balances.",
                     .advanceClosedClimate, "Advance 10 min"),
                step("ventilate", "Exchange three room volumes per hour",
                     "Keep the four people and closed window, set Fresh air fan to 3 ACH, and advance ten more simulated minutes. Do not reset between these two checkpoints.",
                     "CO₂ falls from 850 to about 799 ppm. Fresh air removes CO₂ while the occupants continue adding it; the instantaneous value does not jump to outdoor air.",
                     .ventilateClimate, "Ventilate for 10 min"),
                step("equilibrium", "A source and a sink find balance",
                     "Tap Run in the room's playback controls with 4 occupants and the fan at 3 ACH. Observe the CO₂ trend, then change the fan or occupants to explore the new balance.",
                     "With these original inputs, CO₂ approaches 720 ppm rather than 420 ppm outdoors. The occupants' steady source balances the ventilation loss.",
                     .none)
            ]),
        GuidedLabDefinition(
            id: .climateThermostat,
            title: "A thermostat meets an open window",
            subtitle: "Heat loss, controller power, and an achievable equilibrium.",
            symbol: "thermometer.medium",
            destination: .climate,
            steps: [
                step("cold", "Let cold outdoor air in",
                     "Start at 22°C with no occupants. Set Climate controller Off, Outdoor temperature 8°C, Fresh air fan 0, Window opening 0.5, and Envelope heat loss 85 W/K. Advance fifteen simulated minutes.",
                     "The room cools to about 18.0°C. The half-open window adds 6 air changes per hour, and both ventilation and the envelope remove heat.",
                     .advanceClosedClimate, "Cool for 15 min"),
                step("auto", "Ask the thermostat to heat",
                     "Keep the cold outdoor air and half-open window. Set Climate controller to Auto with Thermostat at 21°C. Inspect Heating / cooling before advancing further.",
                     "Heating is positive and initially reaches the 3.0 kW limit. The room is more than 2°C below target, so this proportional controller requests full heat.",
                     .enableAutoHeat, "Enable Auto at 21°C"),
                step("heat", "Give the heater ten minutes",
                     "Advance ten simulated minutes without changing the window, occupants, fan, or thermostat. Compare Room temperature with the previous checkpoint.",
                     "The room warms to about 18.4°C and Heating / cooling remains +3.0 kW. Available power and thermal inertia make warming gradual.",
                     .advanceHeatedClimate, "Heat for 10 min"),
                step("balance", "Why it settles below the target",
                     "Tap Run in the room's playback controls with the same inputs and observe heating back off as the error becomes smaller. Try closing the window and compare the resulting heat demand.",
                     "The original setup approaches 19.2°C with about 2.75 kW of heat. This proportional controller needs a temperature error to supply power; it does not eliminate that steady error.",
                     .none)
            ]),
        GuidedLabDefinition(
            id: .gearOptics,
            title: "Move the light, freeze the gears",
            subtitle: "Tilt-driven chrome reflections and a refractive optical cover.",
            symbol: "sparkles",
            destination: .gearBench,
            steps: [
                step("recenter", "Choose a comfortable neutral position",
                     "Setup selects a paused spur pair with 20 input teeth, 40 output teeth, and 60 input rpm. Hold the iPhone comfortably with its screen toward you, then recenter the optical motion. Check for Live phone reflections beneath the model.",
                     "The gears are visually frozen. Readings remain 60 input rpm, −30 output rpm, 2:1 reduction, and 9.5 N·m output torque. Pause freezes animation; the selected operating readings and optical motion remain available.",
                     .recenterGearOptics, "Recenter reflections"),
                step("tilt", "Move the phone; watch the surfaces",
                     "Slowly tilt left and right, then forward and back. Watch the bright bands on the teeth and inside the bores. Look through the bowed cover for small shifts in outlines and subtle colored fringes at bright edges.",
                     "Chrome highlights and perspective shift with phone movement; the cover refracts the rendered scene. The frozen gears and 60 / −30 rpm readings remain unchanged. Compare the surface effects by eye as you move the phone.",
                     .none),
                step("inspect", "Compare Holo and another viewing angle",
                     "Toggle Holo to compare the chrome view with stronger holographic edges and local shaft markers. Drag the model to orbit, then gently tilt again. If automatic motion is absent, check Guide & settings → Motion-reactive surfaces; Reduce Motion disables automatic tilt, and Reduce Transparency removes the refractive cover.",
                     "Orbit changes the viewing angle, Holo changes the visual aids, and tilt changes reflections. None changes tooth counts, speed, or torque. The readings remain 60 input rpm and −30 output rpm.",
                     .none)
            ]),
        GuidedLabDefinition(
            id: .gearSpurDrive,
            title: "Drive a spur pair",
            subtitle: "Turn the crown and trade speed for torque.",
            symbol: "gearshape.2",
            destination: .gearBench,
            steps: [
                step("baseline", "Feel the drive crown at 60 rpm",
                     "Setup runs a 20-tooth input gear and a 40-tooth output gear. Scroll to Make a change and drag around the drive crown's outer rim toward 60. Its position sets input speed; the gears keep running after you lift your finger. Use the checkpoint button for an exact value.",
                     "At 60 input rpm: −30 output rpm, 2:1 reduction, and 9.5 N·m output torque. The larger spur gear turns at half the speed in the opposite direction. Animation runs at ⅛ speed; numerical readings show physical operating speed.",
                     .driveSpur60, "Set 60 rpm checkpoint"),
                step("double", "Double the speed with the crown",
                     "Drag the crown toward 120 rpm, watching its input number and the output readout. The checkpoint button restores the same tooth counts, 5 N·m input torque, and 95% efficiency at exactly 120 rpm. Light detents are available when haptics are enabled.",
                     "At 120 input rpm: −60 output rpm. Both speeds double; the 2:1 ratio and 9.5 N·m output torque stay fixed. Tilt may move the reflections without changing these transmission readings.",
                     .driveSpur120, "Set 120 rpm checkpoint"),
                step("stop", "Bring the drive to zero",
                     "Turn the crown down to 0 rpm, or use the exact checkpoint. Watch both gears while leaving playback running. This tests the drive input rather than the Pause control.",
                     "Input and output speed both become 0 rpm, so the gears stop. The ideal applied-torque estimate remains 9.5 N·m, but shaft power is zero at zero speed. The model does not calculate static tooth contact or holding strength.",
                     .stopSpurDrive, "Set 0 rpm checkpoint"),
                step("ratio", "Make the output gear larger",
                     "Return input speed to 60 rpm and increase Output teeth from 40 to 60, keeping Input teeth at 20. The checkpoint button restores that complete setup. Compare the output speed and torque with the first step.",
                     "The reduction becomes 3:1: output slows to −20 rpm and estimated output torque rises to 14.25 N·m. At the same 5 N·m input torque and 95% efficiency, slower output receives greater torque.",
                     .reduceSpurThreeToOne, "Set 3:1 checkpoint")
            ]),
        GuidedLabDefinition(
            id: .gearWormReduction,
            title: "Many worm turns, one slow wheel",
            subtitle: "Count thread starts and inspect a large reduction.",
            symbol: "arrow.trianglehead.2.clockwise.rotate.90",
            destination: .gearBench,
            steps: [
                step("single", "Watch a single-start worm",
                     "Setup runs a 1-start worm at 120 rpm against a 40-tooth wheel, with 5 N·m input torque and 95% efficiency. Watch the screw rotate while the wheel creeps forward. A single-start worm advances the wheel by one tooth per worm turn.",
                     "Output is −3 rpm with 40:1 reduction and 190 N·m estimated output torque. Animation runs at ⅛ speed, so one visible wheel revolution takes about 160 seconds. Small wheel movement is expected; the selected physical speed is still 3 rpm.",
                     .none),
                step("starts", "Give the worm a second start",
                     "Increase Worm starts from 1 to 2, or use the checkpoint button. Keep the 40-tooth wheel and 120 input rpm. Compare the wheel's movement and the numerical reduction with the first step.",
                     "Output doubles to −6 rpm; reduction falls to 20:1 and estimated output torque falls to 95 N·m. Each worm turn now advances two wheel teeth. At the display's ⅛ speed, a visible wheel revolution takes about 80 seconds.",
                     .doubleWormStarts, "Set 2-start checkpoint"),
                step("axes", "Inspect the skew shafts",
                     "Move Separate the assembly and drag to orbit around the screw and wheel. Compare the skew shafts with the parallel shafts in the spur lab. Use Holo or separation to reveal the local positive shaft arrows.",
                     "The worm and wheel axes are at right angles but do not intersect. The minus sign follows the local shaft arrows; clockwise comparisons require looking along each shaft. This model tests reduction, not back-driving or self-locking: real worm behavior also depends on lead angle, friction, and lubrication.",
                     .none)
            ]),
        GuidedLabDefinition(
            id: .gearRackTravel,
            title: "Turn rotation into travel",
            subtitle: "Watch a pinion drive a rack, then compare speed and force.",
            symbol: "arrow.left.and.right",
            destination: .gearBench,
            steps: [
                step("baseline", "Follow a moving rack",
                     "Setup runs a 16-tooth pinion at 60 rpm with 3 mm module, 5 N·m input torque, and 95% efficiency. Watch the rotating pinion advance the straight rack. One full pinion turn advances the rack by one pitch circumference.",
                     "Pitch diameter is 48 mm, rack speed is about 150.8 mm/s, and rack force is about 197.9 N. Positive input moves the rack right in this view. Animation runs at ⅛ speed, and the short rack graphic repeats; travel has no modeled end stops.",
                     .none),
                step("double", "Double the crown speed",
                     "Turn the drive crown toward 120 rpm, or use the exact checkpoint button. Keep 16 pinion teeth and 3 mm module. Compare rack speed and force with the first step.",
                     "Rack speed doubles to about 301.6 mm/s. Pitch diameter remains 48 mm and rack force remains about 197.9 N because torque and pinion radius are unchanged. Power doubles with speed; the display repeats the rack rather than resetting physical speed.",
                     .doubleRackSpeed, "Set 120 rpm checkpoint"),
                step("larger", "Enlarge the pinion at the original speed",
                     "Return input speed to 60 rpm and increase Input teeth to 24, keeping 3 mm module, 5 N·m input torque, and 95% efficiency. The checkpoint button restores all these inputs. Compare the faster travel with the smaller force.",
                     "Pitch diameter becomes 72 mm. Rack speed rises to about 226.2 mm/s while force falls to about 131.9 N. The larger pinion travels farther per turn but delivers less force at the same torque; force × speed remains the same output power.",
                     .enlargeRackPinion, "Set 24-tooth checkpoint")
            ])
    ]

    private static func step(_ id: String, _ title: String, _ instructions: String, _ expected: String, _ action: GuidedLabAction, _ actionTitle: String? = nil) -> GuidedLabStep {
        GuidedLabStep(id: id, title: title, instructions: instructions, expected: expected, action: action, actionTitle: actionTitle)
    }
}
