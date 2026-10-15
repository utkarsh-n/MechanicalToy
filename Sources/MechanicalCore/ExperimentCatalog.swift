import Foundation

public enum ExperimentKind: String, CaseIterable, Codable, Sendable {
    case lever, pulley, incline, pendulum, spring
    case gears, crank, hydraulics, flywheel, bicycle, differential, suspension
    case combustion, diesel, electricMotor, steam, locomotive, highSpeedTrain
    case propeller, wing, helicopter, turbofan, rocket, windTurbine, heatPump
}

public enum ExperimentCategory: String, CaseIterable, Codable, Sendable {
    case foundations, transmissions, road, rail, flight, energy

    public var title: String {
        switch self {
        case .foundations: "First principles"
        case .transmissions: "Moving power"
        case .road: "On the road"
        case .rail: "On the rails"
        case .flight: "Into the sky"
        case .energy: "Energy machines"
        }
    }

    public var subtitle: String {
        switch self {
        case .foundations: "Force, motion, work, and stored energy"
        case .transmissions: "Trade speed, force, and direction"
        case .road: "Pedals, pistons, motors, and ride control"
        case .rail: "Steam, traction, and fast electric trains"
        case .flight: "Lift, rotors, jets, and rockets"
        case .energy: "Harvest wind and move heat"
        }
    }
}

public struct ParameterDefinition: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let unit: String
    public let range: ClosedRange<Double>
    public let defaultValue: Double

    public init(id: String, title: String, unit: String, range: ClosedRange<Double>, defaultValue: Double) {
        self.id = id
        self.title = title
        self.unit = unit
        self.range = range
        self.defaultValue = defaultValue
    }
}

public struct Measurement: Identifiable, Codable, Sendable {
    public let id: String
    public let label: String
    public let unit: String
    public let value: Double

    public init(id: String, label: String, unit: String, value: Double) {
        self.id = id
        self.label = label
        self.unit = unit
        self.value = value.isFinite ? value : 0
    }
}

public struct ExperimentDefinition: Identifiable, Sendable {
    public let id: ExperimentKind
    public let title: String
    public let subtitle: String
    public let category: ExperimentCategory
    public let symbol: String
    public let principle: String
    public let equation: String
    public let explanation: String
    public let challenge: String
    public let limitations: String
    public let parameters: [ParameterDefinition]

    public static func find(_ kind: ExperimentKind) -> ExperimentDefinition {
        // The catalog is immutable and has one entry for each enum case.
        catalog.first { $0.id == kind }!
    }

    public static let catalog: [ExperimentDefinition] = [
        entry(.lever, "Lever", "A longer arm buys more force", .foundations, "scalemass", "Torque balances around a pivot.", "τ = F × r · Fout = Fin × rin / rout", "Moving the effort farther from the pivot increases torque. The load end travels a shorter distance, so an ideal lever preserves work.", "Lift 20 kg with less than 80 N. How far must the effort arm extend?", "Rigid, massless beam; perpendicular forces; no pivot friction. Net torque describes the tendency to move, not a solved beam trajectory.", [
            p("effort", "Applied effort", "N", 0...500, 100), p("effortArm", "Effort arm", "m", 0.1...3, 1.5), p("loadArm", "Load arm", "m", 0.1...2, 0.5), p("load", "Load mass", "kg", 1...100, 20)
        ]),
        entry(.pulley, "Pulley block", "Exchange rope travel for lifting force", .foundations, "arrow.up.and.down", "Supporting rope segments share the load.", "Fin = mg / (nη) · vload = vrope / n", "More supporting strands reduce the force at your hand. You must pull proportionally more rope. Losses raise the required effort without creating energy.", "Raise 100 kg using less than 300 N, then compare rope and load speed.", "Equal strand tension, massless rope, constant efficiency, steady lift. Strands count only the segments directly supporting the moving block.", [
            p("mass", "Load mass", "kg", 1...500, 100), p("strands", "Supporting strands", "", 1...8, 4), p("efficiency", "Efficiency", "%", 30...100, 90), p("pullSpeed", "Rope speed", "m/s", 0...2, 0.4)
        ]),
        entry(.incline, "Inclined plane", "Gravity splits into two directions", .foundations, "triangle", "The slope sets downhill force and normal load.", "F∥ = mg sin θ · N = mg cos θ · f ≤ μN", "A shallow ramp lowers the force needed to raise a mass. Friction can hold the block at rest until the imbalance exceeds its available friction force.", "Find the steepest slope on which the block stays still with zero push.", "A rigid block, constant gravity, and one coefficient for static and kinetic friction. Acceleration is along the ramp; the animation is explanatory.", [
            p("mass", "Block mass", "kg", 1...100, 10), p("angle", "Ramp angle", "°", 0...60, 20), p("friction", "Friction coefficient", "", 0...1, 0.25), p("push", "Uphill push", "N", 0...1000, 0)
        ]),
        entry(.pendulum, "Pendulum", "Trade height for speed", .foundations, "metronome", "Gravity supplies a restoring torque.", "T ≈ 2π√(L/g) · E = mgL(1 − cos θ₀)", "Release the bob from a chosen angle. Longer pendulums swing more slowly. At the bottom, the lost gravitational energy becomes motion. The small-angle period equation is shown; the model also accounts for larger swings.", "Double the period. Does doubling the bob mass help?", "Massless rod and point bob, no drag. Nonlinear pendulum trajectory evaluated with an elliptic integral and numerical quadrature; conserved energy determines tangential speed.", [
            p("length", "Pendulum length", "m", 0.2...3, 1.2), p("amplitude", "Release angle", "°", 0...60, 25), p("mass", "Bob mass", "kg", 0.1...10, 1)
        ]),
        entry(.spring, "Spring oscillator", "Feel stiffness and damping", .foundations, "waveform.path", "The spring pulls back; the damper removes energy.", "mẍ + cẋ + kx = 0 · E = ½kx² + ½mv²", "Displace the mass, release it from rest, and watch stored spring energy become kinetic energy. Damping dissipates energy as heat and can stop oscillation entirely.", "Find critical damping, then double the mass and predict what changes.", "Linear spring, viscous damping, one degree of freedom. Exact underdamped, critically damped, and overdamped release solutions; displacement is relative to equilibrium.", [
            p("stiffness", "Spring stiffness", "N/m", 5...500, 80), p("mass", "Mass", "kg", 0.1...20, 2), p("amplitude", "Release displacement", "m", 0...0.5, 0.25), p("damping", "Damping", "N·s/m", 0...100, 2)
        ]),
        entry(.gears, "Gear pair", "Slow down to multiply torque", .transmissions, "gearshape.2", "Meshing teeth impose a speed ratio.", "ωout = −ωin Nin/Nout · τout = τin Nout/Nin × η", "Teeth at the contact point share the same tangential speed. The larger gear turns more slowly and carries more torque. External gears turn in opposite directions.", "Make three times the torque. Check whether output power also triples.", "Two external spur gears, fixed tooth counts, no backlash. Efficiency removes power; it does not change the geometric speed ratio.", [
            p("inputRPM", "Input speed", "rpm", 0...1200, 120), p("driverTeeth", "Driver teeth", "", 8...60, 20), p("drivenTeeth", "Driven teeth", "", 8...80, 40), p("inputTorque", "Input torque", "N·m", 0...50, 5), p("efficiency", "Efficiency", "%", 50...100, 95)
        ]),
        entry(.crank, "Slider crank", "Rotation becomes reciprocation", .transmissions, "arrow.trianglehead.2.clockwise.rotate.90", "A connecting rod constrains piston position.", "x = r cos θ + √(l² − r² sin² θ) · stroke = 2r", "A crank drives a piston through a connecting rod. The finite rod length makes the piston spend unequal amounts of time in different parts of its stroke.", "Shorten the rod and inspect piston speed at the same crank speed.", "Rigid links, no clearance or friction. Rod length is constrained to at least 1.05 crank radii. Kinematics only: there is no solved force or combustion pressure.", [
            p("radius", "Crank radius", "m", 0.02...0.2, 0.06), p("rodLength", "Rod length", "m", 0.08...0.8, 0.22), p("rpm", "Crank speed", "rpm", 0...600, 60)
        ]),
        entry(.hydraulics, "Hydraulic press", "Pressure connects two pistons", .transmissions, "drop.circle", "Incompressible fluid transmits pressure.", "p = Fin/Ain · Fout = pAoutη · xout = xin Ain/Aout", "A larger output piston delivers more force but moves less far. Volume conservation connects both pistons, while efficiency accounts for the lost work.", "Multiply force by ten. What happens to output travel?", "Incompressible fluid, no leakage or hose compliance, equal fluid height. Efficiency is a lumped force loss; cylinder pressures are ideal.", [
            p("force", "Input force", "N", 0...1000, 150), p("inputRadius", "Input radius", "cm", 0.5...5, 1), p("outputRadius", "Output radius", "cm", 1...15, 4), p("travel", "Input travel", "cm", 0...30, 12), p("efficiency", "Efficiency", "%", 50...100, 95)
        ]),
        entry(.flywheel, "Flywheel", "Store motion as rotational energy", .transmissions, "circle.dotted.circle", "Inertia resists changes in rotational speed.", "I = ½mr² · E = ½Iω² · α = −τbrake/I", "Spin a solid disc, then apply constant braking torque. Energy rises with the square of speed and the square of radius. The brake cannot reverse the wheel after it stops.", "Double speed, then double radius. Compare their effect on stored energy.", "Uniform solid disc, fixed axis, constant brake torque, no bearing drag. The shown speed decays from its initial setting with elapsed simulation time.", [
            p("mass", "Disc mass", "kg", 0.5...100, 10), p("radius", "Disc radius", "m", 0.05...1, 0.3), p("rpm", "Initial speed", "rpm", 0...3000, 600), p("brakeTorque", "Brake torque", "N·m", 0...50, 0)
        ]),
        entry(.bicycle, "Bicycle drivetrain", "Find a gear for the hill", .road, "bicycle", "A chain transfers torque and angular speed.", "v = ωpedal (Nfront/Nrear) rwheel · Fdrive = Pwheel/v", "A large front chainring advances more chain each revolution. A larger rear sprocket slows the wheel and multiplies torque. Compare speed and drive force at the same rider power.", "Keep cadence fixed and choose the strongest climbing gear.", "Steady pedaling, 95% chain efficiency, no road resistance. At zero cadence, delivered power and drive force are zero; rider power is a steady operating input, not an acceleration model.", [
            p("cadence", "Pedal cadence", "rpm", 0...150, 80), p("frontTeeth", "Front teeth", "", 24...60, 48), p("rearTeeth", "Rear teeth", "", 10...50, 20), p("wheelRadius", "Wheel radius", "m", 0.2...0.4, 0.34), p("riderPower", "Rider power", "W", 0...1200, 200)
        ]),
        entry(.differential, "Open differential", "Two wheel speeds, one average", .road, "arrow.triangle.branch", "The carrier sets the average axle speed.", "(ωL + ωR)/2 = ωcarrier · τL = τR = τin/2", "In a turn the outer wheel follows a longer path. The differential allows this speed difference while passing equal torque to both axles.", "Tighten the turn and watch the outer wheel speed rise while their average stays fixed.", "Ideal open differential, no tire slip or losses. Left turns only; radius zero means straight travel. The demonstration does not model traction on ice or limited-slip devices.", [
            p("carrierRPM", "Carrier speed", "rpm", 0...1200, 200), p("turnRadius", "Turn radius · 0 is straight", "m", 0...50, 8), p("track", "Track width", "m", 0.8...2.5, 1.5), p("torque", "Input torque", "N·m", 0...1000, 200)
        ]),
        entry(.suspension, "Suspension", "Isolate the body from the road", .road, "car.side", "A spring and damper filter road motion.", "X/Y = √[(k² + (cω)²)/((k − mω²)² + (cω)²)]", "Drive a sinusoidal road beneath one suspended mass. Near resonance the body can move more than the road. Damping tames resonance but also transmits fast vibration.", "Find resonance, then reduce body travel with damping.", "Linear single-mass quarter-car model at steady state. No tire, bump stops, transient buildup, or wheel hop. Undamped exact resonance is capped for display and marked by the resonance metric.", [
            p("mass", "Supported mass", "kg", 100...600, 300), p("stiffness", "Spring stiffness", "N/m", 5000...60000, 18000), p("damping", "Damper coefficient", "N·s/m", 0...8000, 1800), p("roadAmplitude", "Road amplitude", "cm", 0...10, 2), p("roadFrequency", "Road frequency", "Hz", 0...8, 1.2)
        ]),
        entry(.combustion, "Four-stroke petrol", "From city engine to sports car", .road, "flame", "Compression, combustion, expansion, exhaust.", "ηOtto = 1 − 1/r^(γ−1) · P = BMEP × Vd × rpm/120", "Follow intake, compression, power, and exhaust through two crank revolutions. Increase displacement and throttle for more torque, or speed for more power at a fixed mean pressure.", "Compare a 1 L city engine with a 5 L sports engine at the same throttle and rpm.", "Ideal Otto efficiency is a ceiling, not measured fuel economy. Brake mean effective pressure is a stated teaching estimate: 11 bar × throttle × ηOtto/ηOtto(10). No knock, valve timing, torque curve, or rev limiter.", [
            p("displacement", "Total displacement", "L", 0.6...6.5, 2), p("rpm", "Crank speed", "rpm", 0...9000, 2400), p("throttle", "Throttle", "%", 0...100, 60), p("compression", "Compression ratio", "", 6...14, 10), p("cylinders", "Cylinder count", "", 1...12, 4)
        ]),
        entry(.diesel, "Turbo diesel", "Compression ignition and boost", .road, "truck.box", "Compressed hot air ignites injected fuel.", "P = BMEP × Vd × rpm/120 · τ = BMEP × Vd/(4π)", "Diesel fuel is injected near the end of compression. Boost raises intake air density in this simplified model, allowing more fuel and more torque for the same displacement.", "Match the petrol engine's power at half its rpm. Explore displacement and boost.", "Four-stroke ideal Diesel cycle with fixed cutoff ratio 2 and γ = 1.4. Estimated BMEP is 9 bar × throttle × (1 + boost). No turbo lag, smoke limit, injection map, or exhaust chemistry.", [
            p("displacement", "Total displacement", "L", 1...16, 3), p("rpm", "Crank speed", "rpm", 0...5000, 1800), p("throttle", "Fuel command", "%", 0...100, 60), p("boost", "Boost above atmosphere", "bar", 0...2.5, 0.8), p("compression", "Compression ratio", "", 12...24, 18)
        ]),
        entry(.electricMotor, "Electric motor", "Torque meets back EMF", .road, "bolt.circle", "Current makes torque; rotation makes voltage.", "E = kω · I = min(Ilimit, max(0, (V − E)/R)) · τ = kI", "At rest the motor can produce torque without mechanical power. As speed rises, back EMF opposes the supply voltage, limiting current. Beyond no-load speed there is no motoring torque.", "Find the no-load speed, then lower voltage. Compare stall torque and copper heat.", "Ideal DC/brushless equivalent with equal torque and back-EMF constants in SI. Lossless current-limited PWM supply, no friction or iron loss, no regeneration. RPM is an imposed operating point; battery power equals shaft power plus copper heat.", [
            p("voltage", "Supply voltage", "V", 0...400, 48), p("currentLimit", "Current limit", "A", 0...300, 80), p("resistance", "Winding resistance", "Ω", 0.05...2, 0.2), p("motorConstant", "Torque constant", "N·m/A", 0.02...1, 0.12), p("rpm", "Rotor speed", "rpm", 0...20000, 2000)
        ]),
        entry(.steam, "Steam cylinder", "Expand pressure into motion", .rail, "cloud", "Steam admitted early expands through the stroke.", "pmean = pabs c(1 + ln(1/c)) − patm · P = pmean A × 2s × rpm/60", "The valve admits steam for a fraction of the stroke, then expansion continues pushing the piston. Shorter cutoff uses less fresh steam while reducing mean pressure and torque.", "Halve cutoff. Compare mean pressure, power, and admitted volume.", "Double-acting cylinder, isothermal ideal expansion, 1 bar exhaust, no clearance or condensation, 85% mechanical efficiency. Boiler generation and real steam properties are omitted.", [
            p("pressure", "Boiler gauge pressure", "bar", 0...20, 10), p("radius", "Piston radius", "cm", 2...30, 12), p("stroke", "Piston stroke", "cm", 5...80, 40), p("rpm", "Crank speed", "rpm", 0...500, 120), p("cutoff", "Admission cutoff", "%", 10...100, 50)
        ]),
        entry(.locomotive, "Locomotive traction", "Power cannot bypass adhesion", .rail, "tram", "Rail traction is limited by grip and power.", "Ftraction = min(μmg, P/v) · Fgrade = mg × grade/100", "At low speed the wheels can slip before the engine runs out of power. At higher speed the same power supplies less force. A grade consumes force before the train can accelerate.", "Pull away on a 2% grade. Then reduce adhesion to a wet-rail value.", "Powered locomotive mass only, all wheels assumed driven; constant available wheel power. A 0.5 m/s reference limits starting force, representing finite gearing. No wagons, curves, or traction-control map.", [
            p("mass", "Locomotive mass", "t", 20...200, 80), p("power", "Power at wheels", "kW", 0...6000, 2000), p("speed", "Forward speed", "km/h", 0...180, 20), p("adhesion", "Rail adhesion", "", 0.03...0.4, 0.25), p("grade", "Uphill grade", "%", 0...6, 1)
        ]),
        entry(.highSpeedTrain, "High-speed train", "Air dominates the fast end", .rail, "tram.fill", "Aerodynamic power demand grows with speed cubed.", "Fdrag = ½ρCdAv² · Prequired = (Fdrag + Crrmg)v", "At low speed rolling resistance matters. As speed rises, drag rises with its square, so maintaining speed demands roughly cubic aerodynamic power.", "Double speed from 150 to 300 km/h. How much more power is needed?", "Level track, fixed air density 1.225 kg/m³, constant drag area and rolling coefficient. No tunnel pressure waves, crosswind, pantograph drag changes, or power limits at launch.", [
            p("mass", "Train mass", "t", 100...800, 400), p("power", "Available wheel power", "kW", 0...16000, 8000), p("speed", "Cruise speed", "km/h", 0...400, 250), p("dragArea", "Drag coefficient × area", "m²", 2...20, 8), p("rolling", "Rolling coefficient", "", 0.0005...0.004, 0.0015)
        ]),
        entry(.propeller, "Propeller", "Move more air by less", .flight, "fan", "An actuator disc accelerates a stream of air.", "T = 2ρAvi(V + vi) · P = T(V + vi)", "At fixed shaft power, a larger disc can produce more static thrust by spreading the momentum change over more air. Forward speed changes the stream through the disc.", "Increase diameter without increasing power. Watch induced speed and static thrust.", "Ideal actuator disc with 80% shaft-to-air efficiency; rotor speed is shown for kinematics and tip-speed checks. No blade geometry, pitch, compressibility, or RPM-dependent torque map. Zero RPM disables thrust.", [
            p("diameter", "Propeller diameter", "m", 0.3...4, 1.8), p("rpm", "Rotor speed", "rpm", 0...4000, 2200), p("power", "Shaft power", "kW", 0...500, 100), p("airSpeed", "Forward airspeed", "m/s", 0...120, 0), p("density", "Air density", "kg/m³", 0.3...1.5, 1.225)
        ]),
        entry(.wing, "Wing and stall", "Angle helps until flow separates", .flight, "airplane", "Lift depends on airspeed, area, and angle.", "L = ½ρv²SCL · CD = 0.02 + CL²/(πAR × 0.8)", "Raise angle of attack and lift increases through the attached-flow range. Beyond 15° this illustrative wing loses lift and gains separation drag. Speed increases both lift and drag quadratically.", "Find the best lift-to-drag ratio, then deliberately stall the wing.", "Symmetric finite wing, low-speed incompressible flow. A teaching lift slope and post-stall curve are assumed, not a measured airfoil polar. No ground effect, trim, or aircraft mass.", [
            p("speed", "Airspeed", "m/s", 0...120, 40), p("angle", "Angle of attack", "°", -25...35, 6), p("area", "Wing area", "m²", 0.5...80, 16), p("aspectRatio", "Aspect ratio", "", 2...16, 8), p("density", "Air density", "kg/m³", 0.3...1.5, 1.225)
        ]),
        entry(.helicopter, "Helicopter hover", "A rotor holds up its weight", .flight, "fanblades", "Hover requires continuous downward momentum.", "vi = √(W/(2ρA)) · Pideal = Wvi", "The rotor must push air downward to support the helicopter. A larger rotor needs less induced velocity and less ideal power for the same weight.", "Make the available power margin positive by changing rotor diameter or mass.", "Uniform actuator disc in hover, fixed figure of merit, no climb dynamics. Available thrust is the equivalent static actuator-disc thrust. No ground effect, blade profile, tail rotor, or autorotation.", [
            p("mass", "Aircraft mass", "kg", 100...12000, 1500), p("diameter", "Rotor diameter", "m", 3...22, 10), p("power", "Available shaft power", "kW", 0...3000, 500), p("density", "Air density", "kg/m³", 0.3...1.5, 1.225), p("efficiency", "Rotor figure of merit", "%", 40...90, 70)
        ]),
        entry(.turbofan, "Turbofan", "One hot core, a much larger fan", .flight, "wind", "Thrust is the outgoing momentum minus incoming momentum.", "F = ṁcore(Vjet − V) + Bṁcore(Vfan − V)", "The turbine powers the compressor and fan. Bypass air supplies thrust without passing through combustion. A high bypass ratio moves a large mass of air with a smaller speed increase.", "Raise bypass ratio while keeping exhaust speeds fixed. Inspect thrust and jet power.", "Steady two-stream momentum balance, no fuel mass or nozzle pressure thrust. Core and fan exit speeds are imposed. Compressor temperature, fuel use, and full Brayton-cycle efficiency are not solved.", [
            p("coreFlow", "Core air mass flow", "kg/s", 0...150, 40), p("bypass", "Bypass ratio", "", 0...15, 8), p("jetSpeed", "Core exhaust speed", "m/s", 100...1000, 650), p("fanSpeed", "Fan exhaust speed", "m/s", 50...500, 300), p("airSpeed", "Flight speed", "m/s", 0...350, 220)
        ]),
        entry(.rocket, "Rocket engine", "Carry your oxidizer into vacuum", .flight, "paperplane", "Expelled propellant changes momentum as mass falls.", "F = ṁve + (pe − pa)Ae · Δv = veff ln(m₀/m)", "A rocket supplies its own working fluid. Lower ambient pressure can add nozzle pressure thrust. As propellant is consumed, the same thrust accelerates a lighter vehicle; burnout stops thrust.", "Change ambient pressure from sea level to vacuum and compare thrust. Then watch burnout.", "Fixed mass flow, exhaust speed, and nozzle pressures; propellant is limited to 95% of initial mass. Delta-v is ideal without gravity or drag; vertical acceleration subtracts constant Earth gravity. Not an orbital flight model.", [
            p("initialMass", "Initial vehicle mass", "kg", 100...500000, 30000), p("propellant", "Usable propellant", "kg", 0...400000, 20000), p("massFlow", "Propellant flow", "kg/s", 0...3000, 100), p("exhaustSpeed", "Exhaust speed", "m/s", 500...4500, 3000), p("exitPressure", "Nozzle exit pressure", "kPa", 0...300, 80), p("ambientPressure", "Ambient pressure", "kPa", 0...101.325, 101.325), p("nozzleArea", "Nozzle exit area", "m²", 0.01...8, 0.8)
        ]),
        entry(.windTurbine, "Wind turbine", "The wind must keep moving", .energy, "fanblades.fill", "Swept area and wind speed set the available power.", "Pwind = ½ρπr²v³ · Pelectric = Pwind Cpη · Cp ≤ 16/27", "A rotor harvests some of the passing air's kinetic energy. It cannot extract all of it: the air must still leave the disc. Wind speed enters cubed, while radius enters squared.", "Double wind speed, then radius. Compare their effect on output power.", "Steady uniform wind, no cut-in, cut-out, gusts, or rotor-speed control. Power coefficient is bounded by the ideal Betz limit; generator efficiency is separate.", [
            p("wind", "Wind speed", "m/s", 0...25, 8), p("radius", "Rotor radius", "m", 0.5...80, 20), p("coefficient", "Power coefficient", "", 0...16.0/27.0, 0.42), p("density", "Air density", "kg/m³", 0.3...1.5, 1.225), p("efficiency", "Generator efficiency", "%", 50...100, 93)
        ]),
        entry(.heatPump, "Heat pump", "Use work to move existing heat", .energy, "thermometer.medium", "Delivered heat includes electrical work and extracted heat.", "COPCarnot = Th/(Th − Tc) · Qhot = COP × W · Qcold = Qhot − W", "A compressor spends electrical work to move heat from a colder source to a warmer sink. A smaller temperature lift needs less work per unit of delivered heat. The warmer of the two reservoirs receives heat; when outdoors is warmer, this represents indoor cooling.", "Keep indoor temperature fixed and lower outdoor temperature. Track the COP and heat delivered.", "Hot-side refrigerant is 5°C above the warmer reservoir and cold side 5°C below the colder one. Quality scales the Carnot ceiling with COP ≥ 1. No frost, defrost, capacity map, or refrigerant cycle.", [
            p("indoor", "Indoor temperature", "°C", 10...30, 21), p("outdoor", "Outdoor temperature", "°C", -25...35, 5), p("power", "Compressor power", "kW", 0...10, 1.5), p("quality", "Fraction of Carnot COP", "%", 10...60, 40)
        ])
    ]

    private static func p(_ id: String, _ title: String, _ unit: String, _ range: ClosedRange<Double>, _ value: Double) -> ParameterDefinition {
        ParameterDefinition(id: id, title: title, unit: unit, range: range, defaultValue: value)
    }

    private static func entry(_ id: ExperimentKind, _ title: String, _ subtitle: String, _ category: ExperimentCategory, _ symbol: String, _ principle: String, _ equation: String, _ explanation: String, _ challenge: String, _ limitations: String, _ parameters: [ParameterDefinition]) -> ExperimentDefinition {
        ExperimentDefinition(id: id, title: title, subtitle: subtitle, category: category, symbol: symbol, principle: principle, equation: equation, explanation: explanation, challenge: challenge, limitations: limitations, parameters: parameters)
    }
}
