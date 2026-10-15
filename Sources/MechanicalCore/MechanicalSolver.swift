import Foundation

/// Small transparent teaching models. All internal calculations use SI units.
/// `time` is simulation time in seconds, independent of inspection animation speed.
public enum MechanicalSolver {
    public static let gravity = 9.80665

    public static func defaults(for kind: ExperimentKind) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: ExperimentDefinition.find(kind).parameters.map { ($0.id, $0.defaultValue) })
    }

    /// Missing or non-finite values use defaults, then physical and geometric bounds apply.
    /// Use this for restored notebook records as well as direct controls.
    public static func normalizedValues(for kind: ExperimentKind, values: [String: Double]) -> [String: Double] {
        var result = defaults(for: kind)
        for parameter in ExperimentDefinition.find(kind).parameters {
            let supplied = values[parameter.id] ?? parameter.defaultValue
            let finite = supplied.isFinite ? supplied : parameter.defaultValue
            result[parameter.id] = min(parameter.range.upperBound, max(parameter.range.lowerBound, finite))
        }
        switch kind {
        case .pulley: result["strands"] = result["strands"]!.rounded()
        case .gears:
            result["driverTeeth"] = result["driverTeeth"]!.rounded()
            result["drivenTeeth"] = result["drivenTeeth"]!.rounded()
        case .bicycle:
            result["frontTeeth"] = result["frontTeeth"]!.rounded()
            result["rearTeeth"] = result["rearTeeth"]!.rounded()
        case .combustion: result["cylinders"] = result["cylinders"]!.rounded()
        case .crank: result["rodLength"] = max(result["rodLength"]!, result["radius"]! * 1.05)
        case .differential:
            if result["turnRadius"]! > 0 {
                result["turnRadius"] = max(result["turnRadius"]!, result["track"]! * 0.55)
            }
        case .rocket: result["propellant"] = min(result["propellant"]!, result["initialMass"]! * 0.95)
        default: break
        }
        return result
    }

    public static func metrics(for kind: ExperimentKind, values: [String: Double], time: Double) -> [Measurement] {
        let inputs = normalizedValues(for: kind, values: values)
        func v(_ key: String) -> Double { inputs[key]! }
        let t = time.isFinite ? min(max(0, time), 1e9) : 0
        let g = gravity
        let tau = 2 * Double.pi
        func rpmToRadians(_ rpm: Double) -> Double { rpm * tau / 60 }
        func m(_ id: String, _ label: String, _ value: Double, _ unit: String = "") -> Measurement {
            Measurement(id: id, label: label, unit: unit, value: value)
        }

        switch kind {
        case .lever:
            let torqueIn = v("effort") * v("effortArm")
            let torqueLoad = v("load") * g * v("loadArm")
            let advantage = v("effortArm") / v("loadArm")
            return [m("outputForce", "Load-end force", v("effort") * advantage, "N"),
                    m("requiredEffort", "Balance effort", v("load") * g / advantage, "N"),
                    m("advantage", "Mechanical advantage", advantage, "×"),
                    m("netTorque", "Net lifting torque", torqueIn - torqueLoad, "N·m"),
                    m("workRatio", "Output / input work", 1, "×")]

        case .pulley:
            let strands = v("strands"), efficiency = v("efficiency") / 100
            let effort = v("mass") * g / (strands * efficiency)
            let speed = v("pullSpeed") / strands
            let inputPower = effort * v("pullSpeed")
            let outputPower = v("mass") * g * speed
            return [m("effort", "Required rope force", effort, "N"), m("loadSpeed", "Load speed", speed, "m/s"),
                    m("advantage", "Force advantage", strands * efficiency, "×"),
                    m("inputPower", "Hand power", inputPower, "W"), m("outputPower", "Lifting power", outputPower, "W"),
                    m("loss", "Dissipated power", inputPower - outputPower, "W")]

        case .incline:
            let angle = v("angle") * .pi / 180
            let weight = v("mass") * g
            let downhill = weight * sin(angle), normal = weight * cos(angle)
            let imbalance = v("push") - downhill
            let frictionLimit = v("friction") * normal
            let friction = -min(abs(imbalance), frictionLimit) * (imbalance < 0 ? -1 : 1)
            let netForce = imbalance + friction
            return [m("downhill", "Downhill gravity", downhill, "N"), m("normal", "Normal force", normal, "N"),
                    m("friction", "Friction · uphill positive", friction, "N"),
                    m("requiredPush", "Push for steady uphill travel", downhill + frictionLimit, "N"),
                    m("acceleration", "Uphill acceleration", netForce / v("mass"), "m/s²"),
                    m("holding", "Static friction holds", abs(imbalance) <= frictionLimit ? 1 : 0, "yes = 1")]

        case .pendulum:
            let length = v("length"), mass = v("mass"), amplitude = v("amplitude") * .pi / 180
            let state = pendulumState(length: length, amplitude: amplitude, time: t)
            let potential = mass * g * length * (1 - cos(state.angle))
            let kinetic = 0.5 * mass * state.speed * state.speed
            return [m("angle", "Bob angle", state.angle * 180 / .pi, "°"), m("speed", "Tangential velocity", state.speed, "m/s"),
                    m("period", "Swing period", state.period, "s"), m("potential", "Gravitational energy", potential, "J"),
                    m("kinetic", "Kinetic energy", kinetic, "J"), m("energy", "Total mechanical energy", potential + kinetic, "J")]

        case .spring:
            let k = v("stiffness"), mass = v("mass"), damping = v("damping")
            let state = dampedRelease(mass: mass, stiffness: k, damping: damping, displacement: v("amplitude"), time: t)
            let springEnergy = 0.5 * k * state.position * state.position
            let kinetic = 0.5 * mass * state.velocity * state.velocity
            let initialEnergy = 0.5 * k * pow(v("amplitude"), 2)
            return [m("displacement", "Displacement", state.position, "m"), m("velocity", "Velocity", state.velocity, "m/s"),
                    m("frequency", "Undamped frequency", sqrt(k / mass) / tau, "Hz"),
                    m("dampingRatio", "Damping ratio", damping / (2 * sqrt(k * mass))),
                    m("springEnergy", "Spring energy", springEnergy, "J"), m("kinetic", "Kinetic energy", kinetic, "J"),
                    m("energy", "Mechanical energy", springEnergy + kinetic, "J"),
                    m("dissipated", "Energy lost to damping", max(0, initialEnergy - springEnergy - kinetic), "J")]

        case .gears:
            let ratio = v("drivenTeeth") / v("driverTeeth"), efficiency = v("efficiency") / 100
            let outputRPM = -v("inputRPM") / ratio
            let outputTorque = v("inputTorque") * ratio * efficiency
            let inputPower = v("inputTorque") * rpmToRadians(v("inputRPM"))
            return [m("outputRPM", "Output speed · opposite direction", outputRPM, "rpm"),
                    m("outputTorque", "Output torque magnitude", outputTorque, "N·m"), m("ratio", "Reduction ratio", ratio, "×"),
                    m("inputPower", "Input power", inputPower, "W"), m("outputPower", "Output power", inputPower * efficiency, "W"),
                    m("loss", "Gear loss", inputPower * (1 - efficiency), "W")]

        case .crank:
            let radius = v("radius"), rod = v("rodLength"), omega = rpmToRadians(v("rpm"))
            let angle = phase(omega * t, modulus: tau)
            let sinAngle = sin(angle), cosAngle = cos(angle)
            let rodProjection = sqrt(max(0, rod * rod - radius * radius * sinAngle * sinAngle))
            let position = radius * cosAngle + rodProjection
            let velocity = -radius * omega * sinAngle - radius * radius * omega * sinAngle * cosAngle / rodProjection
            return [m("pistonTravel", "Travel from top dead center", radius + rod - position, "m"),
                    m("pistonVelocity", "Piston velocity · outward positive", velocity, "m/s"),
                    m("stroke", "Full piston stroke", 2 * radius, "m"),
                    m("rodAngle", "Rod angle", asin(radius * sinAngle / rod) * 180 / .pi, "°"),
                    m("frequency", "Strokes per second", v("rpm") / 30, "1/s")]

        case .hydraulics:
            let inputArea = .pi * pow(v("inputRadius") / 100, 2)
            let outputArea = .pi * pow(v("outputRadius") / 100, 2)
            let pressure = v("force") / inputArea, efficiency = v("efficiency") / 100
            let outputForce = pressure * outputArea * efficiency
            let outputTravel = v("travel") / 100 * inputArea / outputArea
            let inputWork = v("force") * v("travel") / 100
            return [m("pressure", "Ideal fluid pressure", pressure / 1000, "kPa"), m("outputForce", "Output force", outputForce, "N"),
                    m("outputTravel", "Output travel", outputTravel * 100, "cm"), m("areaRatio", "Area ratio", outputArea / inputArea, "×"),
                    m("inputWork", "Input work", inputWork, "J"), m("outputWork", "Output work", outputForce * outputTravel, "J")]

        case .flywheel:
            let inertia = 0.5 * v("mass") * pow(v("radius"), 2)
            let initialOmega = rpmToRadians(v("rpm"))
            let omega = max(0, initialOmega - v("brakeTorque") / inertia * t)
            let energy = 0.5 * inertia * omega * omega
            let stopTime = v("brakeTorque") > 0 ? initialOmega * inertia / v("brakeTorque") : 0
            return [m("inertia", "Moment of inertia", inertia, "kg·m²"), m("currentRPM", "Current speed", omega * 60 / tau, "rpm"),
                    m("energy", "Stored energy", energy, "J"), m("brakePower", "Brake heat rate", v("brakeTorque") * omega, "W"),
                    m("stopTime", "Time to stop · 0 with no brake", stopTime, "s"),
                    m("dissipated", "Energy removed", 0.5 * inertia * initialOmega * initialOmega - energy, "J")]

        case .bicycle:
            let ratio = v("frontTeeth") / v("rearTeeth"), omega = rpmToRadians(v("cadence"))
            let speed = omega * ratio * v("wheelRadius")
            let power = omega > 0 ? v("riderPower") : 0
            let pedalTorque = omega > 0 ? power / omega : 0
            let wheelTorque = pedalTorque / ratio * 0.95
            return [m("speed", "Road speed", speed * 3.6, "km/h"), m("ratio", "Wheel turns per pedal turn", ratio, "×"),
                    m("pedalTorque", "Pedal torque", pedalTorque, "N·m"), m("wheelTorque", "Wheel torque", wheelTorque, "N·m"),
                    m("driveForce", "Forward drive force", wheelTorque / v("wheelRadius"), "N"),
                    m("wheelPower", "Wheel power", power * 0.95, "W")]

        case .differential:
            let split = v("turnRadius") > 0 ? v("track") / (2 * v("turnRadius")) : 0
            let inner = v("carrierRPM") * (1 - split), outer = v("carrierRPM") * (1 + split)
            let axleTorque = v("torque") / 2
            return [m("innerRPM", "Inner wheel speed", inner, "rpm"), m("outerRPM", "Outer wheel speed", outer, "rpm"),
                    m("averageRPM", "Wheel-speed average", (inner + outer) / 2, "rpm"),
                    m("axleTorque", "Torque at each axle", axleTorque, "N·m"),
                    m("inputPower", "Carrier power", v("torque") * rpmToRadians(v("carrierRPM")), "W"),
                    m("outputPower", "Both axles' power", axleTorque * rpmToRadians(inner + outer), "W")]

        case .suspension:
            let mass = v("mass"), k = v("stiffness"), c = v("damping"), omega = tau * v("roadFrequency")
            let denominator = hypot(k - mass * omega * omega, c * omega)
            let numerator = hypot(k, c * omega)
            let exactResonance = denominator < 1e-8 * k
            let gain = min(50, numerator / max(denominator, k / 50))
            let lag = atan2(c * omega, k - mass * omega * omega) - atan2(c * omega, k)
            let roadAmplitude = v("roadAmplitude") / 100, amplitude = roadAmplitude * gain
            let road = roadAmplitude * sin(phase(omega * t, modulus: tau))
            let body = amplitude * sin(phase(omega * t, modulus: tau) - lag)
            return [m("naturalFrequency", "Body natural frequency", sqrt(k / mass) / tau, "Hz"),
                    m("dampingRatio", "Damping ratio", c / (2 * sqrt(k * mass))),
                    m("transmissibility", "Body / road amplitude", gain, "×"),
                    m("bodyTravel", "Body motion", body * 100, "cm"), m("roadTravel", "Road motion", road * 100, "cm"),
                    m("bodyAcceleration", "Body acceleration amplitude", amplitude * omega * omega, "m/s²"),
                    m("resonanceLimit", "Unbounded resonance", exactResonance ? 1 : 0, "yes = 1")]

        case .combustion:
            let displacement = v("displacement") / 1000, rpm = v("rpm"), throttle = v("throttle") / 100
            let efficiency = 1 - pow(v("compression"), -0.4)
            let referenceEfficiency = 1 - pow(10, -0.4)
            let bmep = 1.1e6 * throttle * efficiency / referenceEfficiency
            let torque = rpm > 0 ? bmep * displacement / (4 * .pi) : 0
            let power = torque * rpmToRadians(rpm)
            return [m("torque", "Estimated brake torque", torque, "N·m"), m("power", "Estimated shaft power", power / 1000, "kW"),
                    m("idealEfficiency", "Ideal Otto-cycle ceiling", efficiency * 100, "%"),
                    m("bmep", "Assumed brake mean pressure", rpm > 0 ? bmep / 1e5 : 0, "bar"),
                    m("firingRate", "Total firing events", rpm / 120 * v("cylinders"), "1/s")]

        case .diesel:
            let displacement = v("displacement") / 1000, rpm = v("rpm")
            let bmep = 9e5 * v("throttle") / 100 * (1 + v("boost"))
            let torque = rpm > 0 ? bmep * displacement / (4 * .pi) : 0
            let gamma = 1.4, cutoff = 2.0
            let idealEfficiency = 1 - (pow(cutoff, gamma) - 1) / (gamma * (cutoff - 1) * pow(v("compression"), gamma - 1))
            return [m("torque", "Estimated brake torque", torque, "N·m"),
                    m("power", "Estimated shaft power", torque * rpmToRadians(rpm) / 1000, "kW"),
                    m("idealEfficiency", "Ideal Diesel-cycle ceiling", idealEfficiency * 100, "%"),
                    m("bmep", "Assumed brake mean pressure", rpm > 0 ? bmep / 1e5 : 0, "bar"),
                    m("intakePressure", "Intake absolute pressure", 1 + v("boost"), "bar")]

        case .electricMotor:
            let omega = rpmToRadians(v("rpm")), backEMF = v("motorConstant") * omega
            let current = min(v("currentLimit"), max(0, (v("voltage") - backEMF) / v("resistance")))
            let torque = v("motorConstant") * current
            let mechanical = torque * omega, copper = current * current * v("resistance")
            // A current-limited PWM controller applies only the needed motor voltage.
            // Its ideal battery power equals mechanical power plus winding heat.
            let batteryPower = mechanical + copper
            return [m("torque", "Motor torque", torque, "N·m"), m("current", "Winding current", current, "A"),
                    m("backEMF", "Back EMF", backEMF, "V"), m("mechanicalPower", "Shaft power", mechanical / 1000, "kW"),
                    m("copperLoss", "Copper heat", copper / 1000, "kW"), m("inputPower", "Ideal battery power", batteryPower / 1000, "kW"),
                    m("efficiency", "Motor conversion efficiency", batteryPower > 0 ? mechanical / batteryPower * 100 : 0, "%"),
                    m("noLoadRPM", "Ideal no-load speed", v("voltage") / v("motorConstant") * 60 / tau, "rpm")]

        case .steam:
            let area = .pi * pow(v("radius") / 100, 2), stroke = v("stroke") / 100
            let cutoff = v("cutoff") / 100, absolutePressure = (v("pressure") + 1) * 1e5
            let meanPressure = max(0, absolutePressure * cutoff * (1 + log(1 / cutoff)) - 1e5)
            let sweptRate = area * 2 * stroke * v("rpm") / 60
            let indicatedPower = meanPressure * sweptRate, shaftPower = indicatedPower * 0.85
            let torque = v("rpm") > 0 ? shaftPower / rpmToRadians(v("rpm")) : 0
            return [m("meanPressure", "Mean effective pressure", meanPressure / 1e5, "bar"),
                    m("power", "Shaft power", shaftPower / 1000, "kW"), m("torque", "Mean shaft torque", torque, "N·m"),
                    m("steamVolume", "Admitted volume rate", sweptRate * cutoff * 1000, "L/s"),
                    m("mechanicalLoss", "Mechanical loss", (indicatedPower - shaftPower) / 1000, "kW")]

        case .locomotive:
            let mass = v("mass") * 1000, power = v("power") * 1000, speed = v("speed") / 3.6
            let grip = v("adhesion") * mass * g
            let powerForce = power / max(speed, 0.5)
            let traction = min(grip, powerForce)
            let gradeForce = mass * g * v("grade") / 100
            let rolling = 0.002 * mass * g
            return [m("tractiveForce", "Available wheel force", traction / 1000, "kN"),
                    m("adhesionLimit", "Adhesion limit", grip / 1000, "kN"),
                    m("gradeForce", "Grade resistance", gradeForce / 1000, "kN"),
                    m("acceleration", "Instantaneous forward acceleration", (traction - gradeForce - rolling) / mass, "m/s²"),
                    m("deliveredPower", "Power delivered at this speed", traction * speed / 1000, "kW"),
                    m("adhesionLimited", "Adhesion is limiting", grip < powerForce ? 1 : 0, "yes = 1")]

        case .highSpeedTrain:
            let mass = v("mass") * 1000, speed = v("speed") / 3.6, available = v("power") * 1000
            let drag = 0.5 * 1.225 * v("dragArea") * speed * speed
            let rolling = v("rolling") * mass * g
            let required = (drag + rolling) * speed
            let traction = min(0.2 * mass * g, available / max(speed, 0.5))
            return [m("drag", "Aerodynamic drag", drag / 1000, "kN"), m("rollingForce", "Rolling resistance", rolling / 1000, "kN"),
                    m("requiredPower", "Cruise power required", required / 1000, "kW"),
                    m("powerMargin", "Available power margin", (available - required) / 1000, "kW"),
                    m("acceleration", "Instantaneous acceleration", (traction - drag - rolling) / mass, "m/s²"),
                    m("kineticEnergy", "Train kinetic energy", 0.5 * mass * speed * speed / 1e6, "MJ")]

        case .propeller:
            let area = .pi * pow(v("diameter") / 2, 2), airspeed = v("airSpeed"), density = v("density")
            let airPower = v("rpm") > 0 ? v("power") * 1000 * 0.8 : 0
            let induced = actuatorInducedVelocity(power: airPower, area: area, density: density, airspeed: airspeed)
            let thrust = 2 * density * area * induced * (airspeed + induced)
            let tipSpeed = .pi * v("diameter") * v("rpm") / 60
            return [m("thrust", "Ideal disc thrust", thrust, "N"), m("inducedVelocity", "Induced velocity at disc", induced, "m/s"),
                    m("airPower", "Power added to air", airPower / 1000, "kW"),
                    m("propulsiveEfficiency", "Useful flight power / shaft power", v("power") > 0 ? thrust * airspeed / (v("power") * 1000) * 100 : 0, "%"),
                    m("tipSpeed", "Rotational tip speed", tipSpeed, "m/s"),
                    m("helicalTipMach", "Helical tip Mach · check only", hypot(tipSpeed, airspeed) / 343)]

        case .wing:
            let angle = v("angle") * .pi / 180, stallAngle = 15 * Double.pi / 180
            let liftSlope = tau / (1 + 2 / v("aspectRatio"))
            let absoluteAngle = abs(angle)
            let attachedCL = liftSlope * angle
            let stallCL = liftSlope * stallAngle
            let liftCoefficient: Double
            if absoluteAngle <= stallAngle {
                liftCoefficient = attachedCL
            } else {
                liftCoefficient = (angle < 0 ? -1 : 1) * stallCL * max(0.3, 1 - (absoluteAngle - stallAngle) * 2.5)
            }
            let separationDrag = max(0, absoluteAngle - stallAngle) * 1.5
            let dragCoefficient = 0.02 + liftCoefficient * liftCoefficient / (.pi * v("aspectRatio") * 0.8) + separationDrag
            let dynamicPressure = 0.5 * v("density") * pow(v("speed"), 2)
            let lift = dynamicPressure * v("area") * liftCoefficient
            let drag = dynamicPressure * v("area") * dragCoefficient
            return [m("lift", "Lift", lift, "N"), m("drag", "Drag", drag, "N"),
                    m("liftCoefficient", "Lift coefficient", liftCoefficient), m("dragCoefficient", "Drag coefficient", dragCoefficient),
                    m("liftDragRatio", "Lift / drag", drag > 0 ? lift / drag : 0, "×"),
                    m("dynamicPressure", "Dynamic pressure", dynamicPressure, "Pa"),
                    m("stalled", "Beyond assumed stall angle", absoluteAngle > stallAngle ? 1 : 0, "yes = 1")]

        case .helicopter:
            let area = .pi * pow(v("diameter") / 2, 2), weight = v("mass") * g
            let induced = sqrt(weight / (2 * v("density") * area))
            let idealPower = weight * induced, merit = v("efficiency") / 100
            let required = idealPower / merit
            let shaftPower = v("power") * 1000
            let availableThrust = pow(shaftPower * merit * sqrt(2 * v("density") * area), 2.0 / 3.0)
            return [m("hoverPower", "Shaft power needed to hover", required / 1000, "kW"),
                    m("powerMargin", "Hover power margin", (shaftPower - required) / 1000, "kW"),
                    m("inducedVelocity", "Hover induced velocity", induced, "m/s"),
                    m("discLoading", "Rotor disc loading", weight / area, "N/m²"),
                    m("availableThrust", "Available static thrust", availableThrust / 1000, "kN"),
                    m("thrustWeight", "Available thrust / weight", availableThrust / weight, "×")]

        case .turbofan:
            let coreFlow = v("coreFlow"), fanFlow = coreFlow * v("bypass"), speed = v("airSpeed")
            let coreThrust = coreFlow * (v("jetSpeed") - speed)
            let fanThrust = fanFlow * (v("fanSpeed") - speed)
            let thrust = coreThrust + fanThrust
            let airPower = 0.5 * coreFlow * (pow(v("jetSpeed"), 2) - speed * speed)
                + 0.5 * fanFlow * (pow(v("fanSpeed"), 2) - speed * speed)
            let usefulPower = thrust * speed
            return [m("thrust", "Net momentum thrust", thrust / 1000, "kN"), m("coreThrust", "Core thrust", coreThrust / 1000, "kN"),
                    m("fanThrust", "Bypass thrust", fanThrust / 1000, "kN"), m("totalFlow", "Total air flow", coreFlow + fanFlow, "kg/s"),
                    m("airPower", "Net jet kinetic power", airPower / 1e6, "MW"),
                    m("propulsiveEfficiency", "Propulsive efficiency · motoring only", airPower > 0 && thrust > 0 ? min(100, usefulPower / airPower * 100) : 0, "%")]

        case .rocket:
            let initialMass = v("initialMass"), propellant = v("propellant"), flow = v("massFlow")
            let burnTime = flow > 0 ? propellant / flow : 0
            let burned = min(propellant, flow * t), currentMass = initialMass - burned
            let firing = flow > 0 && propellant > 0 && t < burnTime
            let nozzlePressureForce = (v("exitPressure") - v("ambientPressure")) * 1000 * v("nozzleArea")
            // Negative pressure thrust can reduce thrust; a fully overexpanded imposed
            // operating point is clipped at zero because this teaching model has no reversal.
            let steadyThrust = flow > 0 ? max(0, flow * v("exhaustSpeed") + nozzlePressureForce) : 0
            let thrust = firing ? steadyThrust : 0
            let effectiveExhaust = flow > 0 ? steadyThrust / flow : 0
            let deltaV = effectiveExhaust * log(initialMass / currentMass)
            return [m("thrust", "Current engine thrust", thrust / 1000, "kN"), m("mass", "Current vehicle mass", currentMass, "kg"),
                    m("propellantRemaining", "Propellant remaining", propellant - burned, "kg"),
                    m("burnTime", "Full burn duration", burnTime, "s"),
                    m("idealDeltaV", "Ideal accumulated delta-v", deltaV, "m/s"),
                    m("acceleration", "Vertical acceleration · no drag", thrust / currentMass - g, "m/s²"),
                    m("specificImpulse", "Effective specific impulse", effectiveExhaust / g, "s"),
                    m("burning", "Engine is firing", firing ? 1 : 0, "yes = 1")]

        case .windTurbine:
            let area = .pi * pow(v("radius"), 2)
            let windPower = 0.5 * v("density") * area * pow(v("wind"), 3)
            let rotorPower = windPower * v("coefficient"), electric = rotorPower * v("efficiency") / 100
            return [m("windPower", "Power crossing rotor area", windPower / 1000, "kW"),
                    m("rotorPower", "Rotor mechanical power", rotorPower / 1000, "kW"),
                    m("electricPower", "Electrical output", electric / 1000, "kW"),
                    m("betzLimit", "Ideal Betz power ceiling", windPower * 16 / 27 / 1000, "kW"),
                    m("sweptArea", "Swept area", area, "m²"),
                    m("generatorLoss", "Generator heat", (rotorPower - electric) / 1000, "kW")]

        case .heatPump:
            let hot = max(v("indoor"), v("outdoor")) + 273.15 + 5
            let cold = min(v("indoor"), v("outdoor")) + 273.15 - 5
            let carnot = hot / (hot - cold)
            let cop = max(1, carnot * v("quality") / 100)
            let power = v("power")
            return [m("cop", "Heating COP", cop, "×"), m("carnotCOP", "Carnot heating ceiling", carnot, "×"),
                    m("heatDelivered", "Heat delivered to warm side", cop * power, "kW"),
                    m("heatExtracted", "Heat extracted from cold side", (cop - 1) * power, "kW"),
                    m("electricalInput", "Electrical work", power, "kW"),
                    m("temperatureLift", "Refrigerant temperature lift", hot - cold, "K")]
        }
    }

    /// Exact solution for a linear oscillator released from rest, including c = 0.
    public static func dampedRelease(mass: Double, stiffness: Double, damping: Double, displacement: Double, time: Double) -> (position: Double, velocity: Double) {
        guard mass > 0, stiffness > 0, mass.isFinite, stiffness.isFinite,
              damping.isFinite, displacement.isFinite, time.isFinite else { return (0, 0) }
        let t = max(0, min(time, 1e9)), decay = max(0, damping) / (2 * mass)
        let omegaSquared = stiffness / mass
        let difference = omegaSquared - decay * decay
        if abs(difference) < omegaSquared * 1e-9 {
            let envelope = exp(-decay * t)
            return (displacement * (1 + decay * t) * envelope,
                    -displacement * decay * decay * t * envelope)
        } else if difference > 0 {
            let omega = sqrt(difference), angle = phase(omega * t, modulus: 2 * .pi)
            let envelope = exp(-decay * t)
            return (displacement * envelope * (cos(angle) + decay / omega * sin(angle)),
                    -displacement * envelope * omegaSquared / omega * sin(angle))
        } else {
            let root = sqrt(-difference)
            let slow = -decay + root, fast = -decay - root
            let slowCoefficient = -fast / (slow - fast), fastCoefficient = slow / (slow - fast)
            return (displacement * (slowCoefficient * exp(slow * t) + fastCoefficient * exp(fast * t)),
                    displacement * (slowCoefficient * slow * exp(slow * t) + fastCoefficient * fast * exp(fast * t)))
        }
    }

    /// Momentum-theory solution of P = 2ρA vi (V + vi)² by bounded bisection.
    public static func actuatorInducedVelocity(power: Double, area: Double, density: Double, airspeed: Double) -> Double {
        guard power > 0, area > 0, density > 0,
              power.isFinite, area.isFinite, density.isFinite, airspeed.isFinite else { return 0 }
        let speed = max(0, airspeed)
        var lower = 0.0
        var upper = pow(power / (2 * density * area), 1.0 / 3.0)
        for _ in 0..<56 {
            let middle = (lower + upper) / 2
            let required = 2 * density * area * middle * pow(speed + middle, 2)
            if required > power { upper = middle } else { lower = middle }
        }
        return (lower + upper) / 2
    }

    /// The nonlinear simple pendulum is parameterized by an elliptic integral.
    /// This keeps angle, period, and energy consistent up to quadrature tolerance.
    public static func pendulumState(length: Double, amplitude: Double, time: Double) -> (angle: Double, speed: Double, period: Double) {
        guard length > 0, length.isFinite, amplitude.isFinite, time.isFinite else { return (0, 0, 0) }
        let release = min(abs(amplitude), .pi * 0.9)
        let modulus = sin(release / 2), omega = sqrt(gravity / length)
        var arithmetic = 1.0, geometric = sqrt(1 - modulus * modulus)
        for _ in 0..<16 {
            let nextArithmetic = (arithmetic + geometric) / 2
            geometric = sqrt(arithmetic * geometric)
            arithmetic = nextArithmetic
            if abs(arithmetic - geometric) < 1e-14 { break }
        }
        let quarterIntegral = .pi / (2 * arithmetic)
        let period = 4 * quarterIntegral / omega
        guard release > 1e-12 else { return (0, 0, period) }
        let quarterPhase = phase(max(0, time) * omega / quarterIntegral, modulus: 4)
        let target: Double
        let sign: Double
        if quarterPhase < 1 { target = (1 - quarterPhase) * quarterIntegral; sign = 1 }
        else if quarterPhase < 2 { target = (quarterPhase - 1) * quarterIntegral; sign = -1 }
        else if quarterPhase < 3 { target = (3 - quarterPhase) * quarterIntegral; sign = -1 }
        else { target = (quarterPhase - 3) * quarterIntegral; sign = 1 }
        var phi = target / quarterIntegral * .pi / 2
        for _ in 0..<6 {
            let integral = ellipticIntegral(phi: phi, modulus: modulus)
            let derivative = 1 / sqrt(1 - pow(modulus * sin(phi), 2))
            phi = min(.pi / 2, max(0, phi - (integral - target) / derivative))
        }
        let angle = sign * 2 * asin(modulus * sin(phi))
        let speedMagnitude = sqrt(max(0, 2 * gravity * length * (cos(angle) - cos(release))))
        return (angle, (quarterPhase < 2 ? -1 : 1) * speedMagnitude, period)
    }

    private static func ellipticIntegral(phi: Double, modulus: Double) -> Double {
        // Smooth transformed integrand; Simpson's rule avoids the turning-point singularity.
        let steps = 48, h = phi / Double(steps)
        var sum = 0.0
        for index in 0...steps {
            let value = 1 / sqrt(1 - pow(modulus * sin(Double(index) * h), 2))
            sum += value * (index == 0 || index == steps ? 1 : (index.isMultiple(of: 2) ? 2 : 4))
        }
        return sum * h / 3
    }

    private static func phase(_ value: Double, modulus: Double) -> Double {
        value.truncatingRemainder(dividingBy: modulus)
    }
}
