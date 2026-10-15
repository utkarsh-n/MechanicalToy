import SwiftUI
import MechanicalCore

/// A deliberately slowed cutaway. The solver supplies the numerical truth;
/// the drawing keeps a complete cycle legible at an iPhone's scale.
struct MechanismStage: View {
    let kind: ExperimentKind
    let values: [String: Double]
    let time: Double
    var tilt: SIMD2<Double> = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            var scaled = context
            let scale = min(size.width / 360, size.height / 280)
            scaled.translateBy(x: (size.width - 360 * scale) / 2, y: (size.height - 280 * scale) / 2)
            scaled.scaleBy(x: scale, y: scale)
            let bench = MechanismDrawing(context: scaled,
                                         values: MechanicalSolver.normalizedValues(for: kind, values: values),
                                         time: time.isFinite ? max(0, time) : 0,
                                         light: reduceMotion ? .zero : sanitizedTilt)
            bench.grid()
            bench.render(kind)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animated cutaway of \(ExperimentDefinition.find(kind).title)")
        .accessibilityValue(accessibleMeasurements)
        .accessibilityHint("Drag across the machine to turn its mechanism. Use the controls below to change the experiment.")
    }

    private var sanitizedTilt: SIMD2<Double> {
        SIMD2(tilt.x.isFinite ? min(1, max(-1, tilt.x)) : 0,
              tilt.y.isFinite ? min(1, max(-1, tilt.y)) : 0)
    }

    private var accessibleMeasurements: String {
        MechanicalSolver.metrics(for: kind, values: values, time: time)
            .prefix(3)
            .map { "\($0.label), \($0.value.formatted(.number.precision(.fractionLength(0...2)))) \($0.unit)" }
            .joined(separator: ". ")
    }
}

private struct MechanismDrawing {
    let context: GraphicsContext
    let values: [String: Double]
    let time: Double
    let light: SIMD2<Double>

    let copper = Color(red: 0.95, green: 0.58, blue: 0.34)
    let cyan = Color(red: 0.25, green: 0.86, blue: 0.96)
    let cream = Color(red: 0.97, green: 0.93, blue: 0.83)
    let steel = Color(red: 0.32, green: 0.42, blue: 0.49)
    let midnight = Color(red: 0.045, green: 0.085, blue: 0.12)

    func value(_ key: String, _ fallback: Double) -> Double {
        let supplied = values[key] ?? fallback
        return supplied.isFinite ? supplied : fallback
    }

    func phase(_ drive: Double, reference: Double = 120) -> Double {
        guard drive > 0 else { return 0 }
        return time * 2 * .pi * min(1.5, max(0.15, drive / reference))
    }

    func render(_ kind: ExperimentKind) {
        switch kind {
        case .lever: lever()
        case .pulley: pulley()
        case .incline: incline()
        case .pendulum: pendulum()
        case .spring: spring()
        case .gears: gears()
        case .crank: crank()
        case .hydraulics: hydraulics()
        case .flywheel: flywheel()
        case .bicycle: bicycle()
        case .differential: differential()
        case .suspension: suspension()
        case .combustion: combustion(diesel: false)
        case .diesel: combustion(diesel: true)
        case .electricMotor: electricMotor()
        case .steam: steam()
        case .locomotive: locomotive()
        case .highSpeedTrain: highSpeedTrain()
        case .propeller: propeller()
        case .wing: wing()
        case .helicopter: helicopter()
        case .turbofan: turbofan()
        case .rocket: rocket()
        case .windTurbine: windTurbine()
        case .heatPump: heatPump()
        }
    }

    func grid() {
        for x in stride(from: 18.0, through: 360, by: 24) {
            line([p(x, 18), p(x, 255)], color: steel.opacity(0.12), width: 0.5)
        }
        for y in stride(from: 18.0, through: 260, by: 24) {
            line([p(18, y), p(342, y)], color: steel.opacity(0.12), width: 0.5)
        }
        // Registration lines make the actual motion legible over the reflective
        // surfaces without turning the whole teaching diagram into a spectacle.
        line([p(180, 65), p(180, 224)], color: cyan.opacity(0.065), width: 0.5, dash: [2, 6])
        label("CUTAWAY · DRAG TO TURN", 180, 267, color: cream.opacity(0.6), size: 8)
    }

    func lever() {
        let effortArm = value("effortArm", 1.2)
        let loadArm = value("loadArm", 0.4)
        let span = max(0.01, effortArm + loadArm)
        let pivotX = 48 + 264 * effortArm / span
        let torque = value("effort", 120) * effortArm - value("load", 20) * MechanicalSolver.gravity * loadArm
        let rotation = min(0.19, max(-0.19, -torque / 1200))
        let left = rotated(p(48, 146), around: p(pivotX, 146), angle: rotation)
        let right = rotated(p(312, 146), around: p(pivotX, 146), angle: rotation)
        polygon([p(pivotX - 18, 202), p(pivotX, 149), p(pivotX + 18, 202)], fill: steel.opacity(0.45), stroke: cream.opacity(0.4))
        line([p(28, 204), p(332, 204)], color: steel, width: 2)
        line([left, right], color: copper, width: 11)
        circle(p(pivotX, 146), 6, fill: midnight, stroke: cream)
        rect(right.x - 21, right.y - 35, 42, 30, fill: copper.opacity(0.22), stroke: copper)
        arrow(p(left.x, left.y - 69), p(left.x, left.y - 10), color: cyan, width: 3)
        arrow(p(right.x, right.y + 7), p(right.x, right.y + 45), color: cyan.opacity(0.7))
        dimension(p(48, 226), p(pivotX, 226), text: "EFFORT ARM")
        dimension(p(pivotX, 241), p(312, 241), text: "LOAD ARM")
        label("\(number(value("effort", 120))) N", left.x, left.y - 83, color: cyan)
        label("\(number(value("load", 20))) kg", right.x, right.y - 45)
        label("PIVOT", pivotX, 187, size: 9)
    }

    func pulley() {
        let strands = Int(value("strands", 2))
        let drive = value("pullSpeed", 0.3)
        let offset = drive > 0 ? sin(phase(drive / Double(strands), reference: 0.4)) * 13 : 0
        let lowerY = 161 + offset
        let spacing = min(34, 150 / Double(strands))
        let left = 151 - Double(strands - 1) * spacing / 2
        let right = left + Double(strands - 1) * spacing
        let wheelRadius = spacing / 2
        let pullX = right + spacing
        line([p(35, 43), p(302, 43)], color: steel, width: 6)
        for index in 0..<strands {
            let x = left + Double(index) * spacing
            line([p(x, 76), p(x, lowerY)], color: cream.opacity(0.8), width: 2)
            if index.isMultiple(of: 2), index + 1 < strands {
                pulleyWheel(p(x + wheelRadius, lowerY), radius: wheelRadius,
                            angle: -phase(drive, reference: 0.4))
            } else if !index.isMultiple(of: 2), index + 1 < strands {
                pulleyWheel(p(x + wheelRadius, 76), radius: wheelRadius,
                            angle: phase(drive, reference: 0.4))
                line([p(x + wheelRadius, 43), p(x + wheelRadius, 76)], color: steel, width: 3)
            }
        }
        pulleyWheel(p(right + wheelRadius, 76), radius: wheelRadius, angle: phase(drive, reference: 0.4))
        line([p(right + wheelRadius, 43), p(right + wheelRadius, 76)], color: steel, width: 3)
        line([p(pullX, 76), p(pullX, 207)], color: cream, width: 2)
        if strands > 1 { line([p(left, 43), p(left, 76)], color: cream, width: 2) }
        line([p(left - 6, lowerY + wheelRadius + 3), p(right + 6, lowerY + wheelRadius + 3)], color: steel, width: 4)
        line([p(151, lowerY + wheelRadius + 3), p(151, lowerY + wheelRadius + 17)], color: copper, width: 3)
        rect(120, lowerY + wheelRadius + 17, 62, 30, fill: copper.opacity(0.2), stroke: copper)
        if drive > 0 {
            arrow(p(pullX + 13, 145), p(pullX + 13, 204), color: cyan, width: 3)
            arrow(p(296, lowerY + 29), p(296, lowerY - 20), color: cyan, width: 3)
        }
        label("PULL", pullX + 36, 128, color: cyan, size: 9)
        label("\(strands) SUPPORTING STRAND\(strands == 1 ? "" : "S")", 158, 25, color: cream, size: 9)
        label("\(number(value("mass", 20))) kg", 151, lowerY + wheelRadius + 33, size: 11)
        label("LIFT", 299, lowerY + 47, color: cyan, size: 9)
    }

    func incline() {
        let angle = value("angle", 25) * .pi / 180
        let rise = min(171, 260 * tan(angle))
        let start = p(42, 220)
        let end = p(306, 220 - rise)
        polygon([start, end, p(306, 220)], fill: steel.opacity(0.22), stroke: steel)
        let metrics = MechanicalSolver.metrics(for: .incline, values: values, time: time)
        let acceleration = metrics.first(where: { $0.id == "acceleration" })?.value ?? 0
        let holding = metrics.first(where: { $0.id == "holding" })?.value == 1
        let distance = holding ? 0.48 : 0.48 + 0.06 * sin(time * min(2, abs(acceleration)) * (acceleration < 0 ? -1 : 1))
        let center = p(start.x + (end.x - start.x) * distance - 8 * sin(angle), start.y + (end.y - start.y) * distance - 23 * cos(angle))
        rotatedRect(center: center, width: 53, height: 39, angle: -atan2(rise, 264), fill: copper.opacity(0.28), stroke: copper)
        let pushLength = min(67, value("push", 100) / 5)
        arrow(center, p(center.x + pushLength * cos(angle), center.y - pushLength * sin(angle)), color: cyan, width: 3)
        arrow(center, p(center.x, center.y + 54), color: cream.opacity(0.7))
        let friction = metrics.first(where: { $0.id == "friction" })?.value ?? 0
        let frictionLength = min(46, abs(friction) / 3) * (friction < 0 ? -1 : 1)
        arrow(p(center.x + 10, center.y + 9), p(center.x + 10 + frictionLength * cos(angle), center.y + 9 - frictionLength * sin(angle)), color: copper.opacity(0.8))
        label("PUSH", center.x + 71 * cos(angle), center.y - 71 * sin(angle) - 12, color: cyan)
        label("WEIGHT", center.x + 31, center.y + 54, size: 9)
        label("\(number(value("angle", 25)))°", 87, 207, color: cyan, size: 12)
        label(holding ? "STATIC FRICTION HOLDS" : "FRICTION OPPOSES SLIDING", 183, 241, size: 9)
    }

    func pendulum() {
        let length = max(0.1, value("length", 1))
        let amplitude = min(70, value("amplitude", 25)) * .pi / 180
        let theta = MechanicalSolver.pendulumState(length: length, amplitude: amplitude, time: time).angle
        let origin = p(180, 48)
        let drawingLength = 123 + 15 * log(length + 1)
        let bob = p(origin.x + drawingLength * sin(theta), origin.y + drawingLength * cos(theta))
        if time > 0 {
            for index in 1...5 {
                let previous = MechanicalSolver.pendulumState(length: length, amplitude: amplitude,
                                                               time: max(0, time - Double(index) * 0.035)).angle
                circle(p(origin.x + drawingLength * sin(previous), origin.y + drawingLength * cos(previous)),
                       2.4, fill: cyan.opacity(0.27 - Double(index) * 0.035))
            }
        }
        var arc = Path()
        arc.addArc(center: origin, radius: drawingLength, startAngle: .radians(.pi / 2 - amplitude), endAngle: .radians(.pi / 2 + amplitude), clockwise: false)
        context.stroke(arc, with: .color(cyan.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        line([p(135, 45), p(225, 45)], color: steel, width: 6)
        line([origin, p(180, 220)], color: steel.opacity(0.45), width: 1, dash: [3, 5])
        line([origin, bob], color: cream, width: 3)
        circle(origin, 6, fill: copper, stroke: cream)
        let bobRadius = min(25, 13 + value("mass", 1) * 1.5)
        metal(Path(ellipseIn: CGRect(x: bob.x - bobRadius, y: bob.y - bobRadius,
                                    width: bobRadius * 2, height: bobRadius * 2)), tint: copper)
        circle(bob, bobRadius - 3, stroke: .white.opacity(0.3), lineWidth: 0.7)
        arrow(bob, p(bob.x, bob.y + 44), color: cyan)
        label("g", bob.x + 18, bob.y + 41, color: cyan)
        label("\(number(length)) m", 122, 111, size: 11)
        label("GRAVITY EXCHANGES HEIGHT & SPEED", 180, 239, size: 9)
    }

    func spring() {
        let stiffness = max(1, value("stiffness", 80))
        let mass = max(0.01, value("mass", 2))
        let damping = max(0, value("damping", 0.6))
        let displacement = MechanicalSolver.dampedRelease(mass: mass, stiffness: stiffness, damping: damping,
                                                           displacement: value("amplitude", 0.2), time: time).position
        let y = 174 + min(41, max(-41, displacement * 100))
        line([p(112, 42), p(249, 42)], color: steel, width: 6)
        coil(from: p(180, 48), to: p(180, y - 26), width: 20, turns: 9, color: copper)
        rect(148, y - 23, 64, 47, fill: copper.opacity(0.2), stroke: copper)
        line([p(251, 88), p(251, 231)], color: steel.opacity(0.6), width: 1)
        for index in 0..<8 { line([p(246, 88 + Double(index) * 19), p(256, 88 + Double(index) * 19)], color: steel, width: 1) }
        arrow(p(114, y), p(114, y - displacement * 100 - 1), color: cyan, width: 3)
        label("RESTORING", 64, 137, color: cyan, size: 9)
        label("FORCE", 64, 150, color: cyan, size: 9)
        label("\(number(mass)) kg", 180, y, size: 12)
        label("STIFFNESS \(number(stiffness)) N/m", 180, 239, size: 9)
    }

    func gears() {
        let teethA = max(8, value("driverTeeth", 20))
        let teethB = max(8, value("drivenTeeth", 40))
        let ratio = teethB / teethA
        let rA = 107 / (1 + ratio)
        let rB = 107 - rA
        let angle = phase(value("inputRPM", 120))
        let a = p(180 - rB, 142)
        let b = p(180 + rA, 142)
        gear(a, radius: rA, teeth: Int(teethA), angle: angle, tint: copper)
        gear(b, radius: rB, teeth: Int(teethB), angle: -angle / ratio + .pi / teethB, tint: copper)
        if value("inputRPM", 120) > 0 {
            rotationTrack(a, radius: rA + 11, angle: angle, direction: 1)
            rotationTrack(b, radius: rB + 11, angle: -angle / ratio + .pi / teethB, direction: -1)
        }
        arrow(p(a.x - rA - 13, 107), p(a.x - rA - 13, 160), color: cyan)
        arrow(p(b.x + rB + 13, 165), p(b.x + rB + 13, 111), color: cyan)
        label("DRIVER", a.x, 219, color: cyan)
        label("\(Int(teethA)) TEETH", a.x, 234, size: 10)
        label("DRIVEN", b.x, 219, color: cyan)
        label("\(Int(teethB)) TEETH", b.x, 234, size: 10)
        label("TEETH TRADE SPEED FOR TORQUE", 180, 38, size: 9)
    }

    func crank() {
        let rawRadius = value("radius", 0.05)
        let rawRod = value("rodLength", 0.18)
        let scale = min(48 / rawRadius, 150 / rawRod)
        let radius = rawRadius * scale
        let rod = rawRod * scale
        let angle = phase(value("rpm", 120))
        let center = p(94, 152)
        let pin = polar(center, radius, angle)
        let sliderX = center.x + radius * cos(angle) + sqrt(max(0, rod * rod - pow(radius * sin(angle), 2)))
        rect(186, 116, 132, 72, fill: steel.opacity(0.11), stroke: steel)
        line([p(53, 152), p(327, 152)], color: cyan.opacity(0.25), width: 1, dash: [4, 5])
        circle(center, radius, fill: copper.opacity(0.07), stroke: copper.opacity(0.5))
        line([center, pin], color: copper, width: 10)
        line([pin, p(sliderX, 152)], color: cream, width: 7)
        rect(sliderX - 13, 121, 26, 62, fill: copper.opacity(0.35), stroke: copper)
        circle(center, 6, fill: midnight, stroke: copper)
        circle(pin, 5, fill: midnight, stroke: cream)
        arrow(p(204, 209), p(303, 209), color: cyan)
        label("LINEAR STROKE", 254, 227, color: cyan, size: 9)
        label("CRANK", 87, 223, size: 10)
        label("CONNECTING ROD", 206, 73, size: 9)
    }

    func hydraulics() {
        let inputR = max(0.5, value("inputRadius", 2))
        let outputR = max(1, value("outputRadius", 6))
        let widthA = min(55, 16 + inputR * 7)
        let widthB = min(105, 24 + outputR * 10)
        let travel = min(28, value("travel", 5) * 2.5)
        let yA = 122 + travel * (0.5 + 0.5 * sin(time * 0.8))
        let yB = 126 - travel * pow(inputR / outputR, 2) * (0.5 + 0.5 * sin(time * 0.8))
        rect(82 - widthA / 2, 91, widthA, 108, fill: cyan.opacity(0.07), stroke: steel)
        rect(265 - widthB / 2, 70, widthB, 129, fill: cyan.opacity(0.07), stroke: steel)
        line([p(82, 192), p(82, 218), p(265, 218), p(265, 191)], color: steel, width: 18)
        line([p(82, 191), p(82, 218), p(265, 218), p(265, 190)], color: cyan.opacity(0.6), width: 11)
        rect(83 - widthA / 2, yA, widthA - 2, 77 - (yA - 122), fill: cyan.opacity(0.28))
        rect(266 - widthB / 2, yB, widthB - 2, 73 - (yB - 126), fill: cyan.opacity(0.28))
        line([p(82 - widthA / 2, yA), p(82 + widthA / 2, yA)], color: copper, width: 8)
        line([p(265 - widthB / 2, yB), p(265 + widthB / 2, yB)], color: copper, width: 8)
        line([p(82, yA), p(82, yA - 29)], color: copper, width: 5)
        line([p(265, yB), p(265, yB - 29)], color: copper, width: 8)
        arrow(p(82, 52), p(82, yA - 34), color: cyan, width: 2)
        arrow(p(265, yB - 35), p(265, 36), color: cyan, width: 4)
        arrow(p(135, 218), p(205, 218), color: cream, width: 1)
        label("SMALL PISTON", 82, 239, size: 9)
        label("LARGE PISTON", 265, 239, size: 9)
        label("SAME FLUID PRESSURE", 175, 178, color: cyan, size: 8)
    }

    func flywheel() {
        let radius = min(91, 56 + 35 * sqrt(value("radius", 0.3)))
        let rpm = value("rpm", 600)
        let inertia = 0.5 * value("mass", 20) * pow(value("radius", 0.3), 2)
        let deceleration = value("brakeTorque", 0) / max(0.001, inertia)
        let omega = rpm * 2 * .pi / 60
        let elapsed = deceleration > 0 ? min(time, omega / deceleration) : time
        let inspectionScale = rpm > 0 ? min(1.5, max(0.15, rpm / 600)) * 60 / rpm : 0
        let angle = (omega * elapsed - 0.5 * deceleration * elapsed * elapsed) * inspectionScale
        let center = p(176, 143)
        circle(center, radius, fill: copper.opacity(0.07), stroke: copper, lineWidth: 13)
        circle(center, radius - 14, stroke: copper.opacity(0.5))
        for index in 0..<8 {
            line([polar(center, 13, angle + Double(index) * .pi / 4), polar(center, radius - 12, angle + Double(index) * .pi / 4)], color: copper, width: 5)
        }
        circle(center, 14, fill: midnight, stroke: cream, lineWidth: 3)
        arrow(p(176 + radius + 19, 111), p(176 + radius + 19, 167), color: cyan, width: 3)
        let brakeX = center.x - radius - 15
        rect(brakeX, 126, 17, 34, fill: steel.opacity(0.4), stroke: cream.opacity(0.5))
        label("BRAKE", brakeX + 4, 182, size: 9)
        label("ENERGY IN THE RIM", 180, 243, size: 10)
        label("\(number(value("mass", 20))) kg", 179, 39, color: cyan)
    }

    func bicycle() {
        let angle = phase(value("cadence", 70), reference: 90)
        let ratio = value("frontTeeth", 44) / max(1, value("rearTeeth", 18))
        let rear = p(86, 174), front = p(280, 174), pedal = p(174, 178)
        wheel(rear, radius: 59, angle: angle * ratio)
        wheel(front, radius: 59, angle: angle * ratio)
        line([rear, p(145, 100), pedal, rear, p(225, 106), pedal], color: copper, width: 5)
        line([p(225, 106), front, p(216, 90), p(245, 84)], color: copper, width: 5)
        line([p(131, 96), p(161, 96)], color: cream, width: 5)
        gear(pedal, radius: 23, teeth: 20, angle: angle, tint: copper)
        gear(rear, radius: 12, teeth: 12, angle: angle * ratio, tint: copper)
        line([p(86, 161), p(174, 153), p(190, 166), p(181, 200), p(86, 187)], color: cream.opacity(0.7), width: 2)
        let crankPin = polar(pedal, 32, angle)
        line([pedal, crankPin], color: cream, width: 4)
        line([p(crankPin.x - 8, crankPin.y), p(crankPin.x + 8, crankPin.y)], color: cyan, width: 5)
        arrow(p(211, 55), p(281, 55), color: cyan, width: 2)
        label("CHAIN MULTIPLIES CADENCE", 180, 247, size: 9)
        label("\(Int(value("frontTeeth", 44))) : \(Int(value("rearTeeth", 18)))", 129, 219, color: cyan, size: 11)
    }

    func differential() {
        let angle = phase(value("carrierRPM", 150), reference: 180)
        let turnRadius = value("turnRadius", 10)
        let difference = turnRadius > 0 ? value("track", 1.6) / (2 * turnRadius) : 0
        let center = p(169, 144)
        rect(38, 136, 75, 17, fill: copper.opacity(0.2), stroke: copper)
        arrow(p(41, 119), p(102, 119), color: cyan)
        circle(center, 60, fill: steel.opacity(0.14), stroke: steel, lineWidth: 4)
        gear(center, radius: 45, teeth: 28, angle: angle, tint: copper)
        line([p(171, 88), p(171, 57), p(280, 57)], color: cream, width: 7)
        line([p(171, 201), p(171, 228), p(280, 228)], color: cream, width: 7)
        gear(p(169, 121), radius: 17, teeth: 12, angle: angle * difference, tint: cyan)
        gear(p(169, 166), radius: 17, teeth: 12, angle: -angle * difference, tint: cyan)
        wheel(p(285, 57), radius: 24, angle: angle * (1 - difference), tyre: false)
        wheel(p(285, 228), radius: 24, angle: angle * (1 + difference), tyre: false)
        label("INNER", 282, 97, color: cyan, size: 9)
        label("OUTER", 282, 188, color: cyan, size: 9)
        label("INPUT", 72, 94, size: 10)
        label("PLANET GEARS ALLOW DIFFERENT SPEEDS", 180, 25, size: 8)
    }

    func suspension() {
        let frequency = value("roadFrequency", 1.5)
        let amplitude = value("roadAmplitude", 4) * 2
        let metrics = MechanicalSolver.metrics(for: .suspension, values: values, time: time)
        let roadMotion = metrics.first(where: { $0.id == "roadTravel" })?.value ?? 0
        let bodyMotion = metrics.first(where: { $0.id == "bodyTravel" })?.value ?? 0
        // Diagram travel is bounded; the measurement preserves the exact model amplitude.
        let bodyOffset = min(25, max(-25, bodyMotion * 2))
        let axle = p(184, 200 - min(24, max(-24, roadMotion * 2)))
        let top = 76 - bodyOffset
        rect(81, top - 23, 217, 42, fill: copper.opacity(0.16), stroke: copper)
        line([p(91, top + 18), p(143, axle.y), axle], color: steel, width: 5)
        line([p(285, top + 18), p(225, axle.y), axle], color: steel, width: 5)
        coil(from: p(162, top + 20), to: p(162, axle.y - 12), width: 13, turns: 7, color: copper)
        line([p(207, top + 19), p(207, axle.y - 12)], color: cream.opacity(0.8), width: 4)
        rect(198, top + 44, 18, 46, fill: steel.opacity(0.75), stroke: cream.opacity(0.6))
        wheel(axle, radius: 33, angle: time * 2)
        var ground: [CGPoint] = []
        for x in stride(from: 25.0, through: 335, by: 5) { ground.append(p(x, 236 - amplitude * sin((x - 184) / 40 + 2 * .pi * frequency * time))) }
        line(ground, color: steel, width: 3)
        label("SPRING", 104, 141, color: copper, size: 9)
        label("DAMPER", 264, 141, size: 9)
        arrow(p(308, top - 18), p(308, top + 32), color: cyan)
        label("BODY", 309, top - 34, color: cyan, size: 9)
    }

    func combustion(diesel: Bool) {
        let rpm = value("rpm", diesel ? 1800 : 2400)
        let angle = phase(rpm, reference: 2400)
        let cycle = (angle.truncatingRemainder(dividingBy: 4 * .pi) + 4 * .pi).truncatingRemainder(dividingBy: 4 * .pi)
        let stroke = min(3, Int(cycle / .pi))
        let strokeNames = ["INTAKE", "COMPRESSION", "POWER", "EXHAUST"]
        let center = p(180, 209)
        let pin = polar(center, 23, angle - .pi / 2)
        let pistonY = 138 - 23 * cos(angle)
        let burn = stroke == 2 && value("throttle", 60) > 0 && rpm > 0
        rect(143, 54, 74, 123, fill: steel.opacity(0.10), stroke: steel, lineWidth: 3)
        rect(147, 58, 66, max(1, pistonY - 58), fill: burn ? copper.opacity(0.5) : cyan.opacity(stroke == 0 ? 0.2 : 0.07))
        rect(146, pistonY, 68, 20, fill: copper.opacity(0.33), stroke: copper, lineWidth: 2)
        line([p(153, pistonY + 6), p(208, pistonY + 6)], color: cream.opacity(0.55), width: 1)
        line([p(180, pistonY + 20), pin], color: cream, width: 7)
        circle(center, 30, fill: copper.opacity(0.1), stroke: copper)
        line([center, pin], color: copper, width: 8)
        circle(pin, 5, fill: midnight, stroke: cream)
        line([p(154, 56), p(154, 40), p(95, 40)], color: cyan.opacity(stroke == 0 ? 1 : 0.3), width: 7)
        line([p(206, 56), p(206, 40), p(267, 40)], color: copper.opacity(stroke == 3 ? 1 : 0.3), width: 7)
        arrow(p(91, 40), p(129, 40), color: cyan, width: 2)
        arrow(p(230, 40), p(272, 40), color: copper, width: 2)
        if diesel {
            line([p(180, 28), p(180, 63)], color: cream, width: 5)
            if burn {
                for index in -2...2 { line([p(180, 63), p(180 + Double(index) * 8, 95)], color: copper, width: 2, dash: [2, 4]) }
            }
            circle(p(86, 95), 24, fill: steel.opacity(0.15), stroke: copper)
            gear(p(86, 95), radius: 16, teeth: 10, angle: angle * 1.6, tint: copper)
            label("BOOST", 86, 132, color: cyan, size: 9)
            label("INJECTOR", 238, 72, size: 8)
        } else {
            line([p(180, 27), p(180, 63)], color: cream, width: 4)
            if burn { polygon([p(179, 65), p(171, 79), p(181, 77), p(177, 93), p(191, 72), p(182, 74)], fill: cream) }
            label("SPARK", 238, 74, size: 9)
        }
        for index in 0..<4 {
            rect(33 + Double(index) * 79, 247, 70, 3, fill: index == stroke ? cyan : steel.opacity(0.4))
            label(strokeNames[index], 68 + Double(index) * 79, 236, color: index == stroke ? cyan : cream.opacity(0.45), size: 8)
        }
        label("\(number(value("compression", diesel ? 18 : 10))) : 1", 87, 174, color: cyan, size: 13)
        label("COMPRESSION", 87, 190, size: 8)
        label(diesel ? "FUEL IGNITES IN HOT AIR" : "FOUR STROKES · TWO TURNS", 273, 174, size: 8)
    }

    func electricMotor() {
        let center = p(181, 142)
        let angle = phase(value("rpm", 1500), reference: 1800)
        circle(center, 82, fill: steel.opacity(0.09), stroke: steel, lineWidth: 5)
        for index in 0..<6 {
            let position = polar(center, 66, Double(index) * .pi / 3)
            rotatedRect(center: position, width: 30, height: 26, angle: Double(index) * .pi / 3, fill: copper.opacity(0.24), stroke: copper)
            for winding in -2...2 {
                let local = rotated(p(position.x + Double(winding) * 4, position.y), around: position, angle: Double(index) * .pi / 3)
                circle(local, 8, stroke: copper.opacity(0.55), lineWidth: 1)
            }
        }
        rotatedRect(center: center, width: 88, height: 27, angle: angle, fill: cyan.opacity(0.22), stroke: cyan, lineWidth: 2)
        label("N", polar(center, 29, angle).x, polar(center, 29, angle).y, color: cyan, size: 13)
        label("S", polar(center, 29, angle + .pi).x, polar(center, 29, angle + .pi).y, color: copper, size: 13)
        circle(center, 8, fill: midnight, stroke: cream, lineWidth: 2)
        arrow(p(54, 191), p(54, 100), color: cyan, width: 2)
        arrow(p(310, 100), p(310, 191), color: cyan, width: 2)
        label("STATOR", 180, 39, color: copper, size: 9)
        label("MAGNETIC TORQUE", 180, 241, color: cyan, size: 10)
        label("\(number(value("voltage", 48))) V", 53, 71, color: cyan, size: 11)
        label("ROTOR", 304, 215, size: 9)
    }

    func steam() {
        let angle = phase(value("rpm", 180), reference: 180)
        let crank = p(275, 164)
        let pin = polar(crank, 32, angle)
        let pistonX = 129 + 31 * cos(angle)
        let poweredLeft = sin(angle) < 0
        rect(68, 117, 116, 83, fill: steel.opacity(0.12), stroke: steel, lineWidth: 3)
        rect(73, 121, max(2, pistonX - 75), 75, fill: cyan.opacity(poweredLeft ? 0.3 : 0.06))
        rect(pistonX + 7, 121, max(2, 178 - pistonX), 75, fill: cyan.opacity(poweredLeft ? 0.06 : 0.3))
        rect(pistonX - 5, 120, 12, 77, fill: copper.opacity(0.7), stroke: copper)
        line([p(pistonX, 161), pin], color: cream, width: 6)
        wheel(crank, radius: 41, angle: angle, tyre: false)
        circle(pin, 5, fill: midnight, stroke: cream)
        rect(92, 72, 74, 25, fill: copper.opacity(0.15), stroke: copper)
        rect(111 + 10 * sin(angle), 76, 24, 17, fill: copper.opacity(0.65))
        line([p(99, 98), p(84, 98), p(84, 117)], color: cyan, width: 4)
        line([p(159, 98), p(172, 98), p(172, 117)], color: cyan, width: 4)
        arrow(p(129, 30), p(129, 67), color: cyan, width: 3)
        label("STEAM IN", 190, 47, color: cyan, size: 9)
        label("SLIDE VALVE", 239, 85, size: 9)
        label("DOUBLE ACTING", 120, 222, size: 9)
        label("EXHAUST", 62, 82, size: 8)
        label("\(number(value("pressure", 8))) bar", 274, 226, color: cyan, size: 11)
    }

    func locomotive() {
        let speed = value("speed", 40)
        let angle = phase(speed, reference: 55)
        let centers = [p(116, 202), p(181, 202), p(246, 202)]
        rect(61, 97, 218, 58, fill: copper.opacity(0.12), stroke: copper, lineWidth: 2)
        circle(p(61, 126), 29, fill: copper.opacity(0.12), stroke: copper, lineWidth: 2)
        rect(268, 79, 52, 86, fill: steel.opacity(0.24), stroke: cream.opacity(0.7))
        rect(278, 91, 31, 26, fill: cyan.opacity(0.1), stroke: cyan.opacity(0.5))
        rect(83, 75, 18, 25, fill: copper.opacity(0.25), stroke: copper)
        rect(178, 81, 25, 17, fill: copper.opacity(0.22), stroke: copper)
        line([p(40, 168), p(326, 168)], color: steel, width: 9)
        for center in centers { wheel(center, radius: 30, angle: angle, tyre: false) }
        let pins = centers.map { polar($0, 17, angle) }
        line(pins, color: cream, width: 6)
        for pin in pins { circle(pin, 4, fill: midnight, stroke: copper) }
        rect(41, 181, 37, 25, fill: copper.opacity(0.3), stroke: copper)
        line([p(59, 193), pins[0]], color: cream, width: 5)
        line([p(27, 235), p(336, 235)], color: steel, width: 3)
        for index in 0..<11 {
            let travel = (time * max(0, speed) * 0.8).truncatingRemainder(dividingBy: 30)
            line([p(24 + Double(index) * 30 - travel, 240), p(38 + Double(index) * 30 - travel, 240)], color: steel.opacity(0.6), width: 3)
        }
        for index in 0..<4 {
            let lift = (time * 12 + Double(index) * 15).truncatingRemainder(dividingBy: 58)
            circle(p(92 - lift * 0.4, 72 - lift), 5 + lift * 0.09, fill: cream.opacity(max(0, 0.23 - lift / 290)))
        }
        arrow(p(152, 53), p(229, 53), color: cyan, width: 3)
        label("COUPLED DRIVING WHEELS", 187, 251, size: 9)
        label("BOILER", 170, 125, size: 11)
    }

    func highSpeedTrain() {
        let speed = value("speed", 250)
        let angle = phase(speed, reference: 260)
        polygon([p(40, 130), p(266, 130), p(320, 158), p(326, 184), p(42, 184)], fill: steel.opacity(0.19), stroke: cream.opacity(0.7), lineWidth: 2)
        polygon([p(258, 138), p(279, 138), p(304, 156), p(260, 156)], fill: cyan.opacity(0.2), stroke: cyan)
        line([p(41, 171), p(314, 171)], color: copper, width: 3)
        for x in stride(from: 63.0, through: 228, by: 33) { rect(x, 142, 25, 15, fill: cyan.opacity(0.1), stroke: steel) }
        line([p(182, 127), p(205, 94), p(177, 74), p(215, 74)], color: copper, width: 3)
        line([p(30, 69), p(334, 69)], color: cyan.opacity(0.6), width: 1)
        for x in [85.0, 111, 237, 263] { wheel(p(x, 195), radius: 12, angle: angle, tyre: false) }
        line([p(28, 211), p(335, 211)], color: steel, width: 3)
        arrow(p(274, 110), p(330, 110), color: cyan, width: 3)
        arrow(p(325, 228), p(259, 228), color: copper, width: 2)
        label("DRAG ∝ SPEED²", 280, 246, color: copper, size: 9)
        label("ELECTRIC TRACTION", 110, 235, color: cyan, size: 9)
        label("OVERHEAD POWER", 90, 54, color: cyan, size: 9)
    }

    func propeller() {
        let angle = phase(value("rpm", 1800), reference: 1800)
        let center = p(157, 141)
        let radius = min(87, max(47, value("diameter", 1.8) * 36))
        let metrics = MechanicalSolver.metrics(for: .propeller, values: values, time: time)
        let thrust = metrics.first(where: { $0.id == "thrust" })?.value ?? 0
        let induced = metrics.first(where: { $0.id == "inducedVelocity" })?.value ?? 0
        let airflow = value("airSpeed", 0) + induced
        if airflow > 0 {
            for y in [69.0, 105, 178, 214] { flowLine(from: p(27, y), to: p(326, y), offset: time * min(3, airflow / 15), tint: cyan.opacity(0.5)) }
        }
        circle(center, radius + 6, stroke: copper.opacity(0.2), lineWidth: 1, dash: [3, 5])
        for index in 0..<3 { blade(center, radius: radius, angle: angle + Double(index) * 2 * .pi / 3, width: 20) }
        circle(center, 13, fill: steel, stroke: cream, lineWidth: 2)
        rect(152, 133, 111, 15, fill: steel.opacity(0.65), stroke: steel)
        circle(center, 9, fill: copper, stroke: cream)
        if thrust > 0 { arrow(p(244, 140), p(319, 140), color: cyan, width: 4) }
        label("THRUST", 283, 121, color: cyan, size: 10)
        label("ACCELERATING AIR", 184, 242, size: 9)
        label("PROPELLER DISC", 117, 37, color: copper, size: 9)
    }

    func wing() {
        let degrees = value("angle", 7)
        let angle = -degrees * .pi / 180
        let stalled = abs(degrees) > 15
        let center = p(182, 147)
        let points = [p(70, 147), p(85, 136), p(126, 126), p(172, 128), p(287, 147), p(203, 152), p(115, 155), p(74, 151)].map { rotated($0, around: center, angle: angle) }
        for index in 0..<(value("speed", 40) > 0 ? 6 : 0) {
            let y = 65 + Double(index) * 31
            var points: [CGPoint] = []
            for x in stride(from: 23.0, through: 338, by: 7) {
                let lift = exp(-pow((x - 165) / 85, 2)) * (y < 142 ? -18 : 10)
                let separationSide = degrees >= 0 ? y < 142 : y > 142
                let separated = stalled && separationSide && x > 170 ? sin((x - 170) / 18 + time * 2) * 9 : 0
                points.append(p(x, y + lift + separated))
            }
            line(points, color: cyan.opacity(stalled && (degrees >= 0 ? y < 142 : y > 142) ? 0.3 : 0.5), width: 1.3)
            arrow(p(37 + (time * 15).truncatingRemainder(dividingBy: 35), y), p(58 + (time * 15).truncatingRemainder(dividingBy: 35), y), color: cyan.opacity(0.7), width: 1)
        }
        polygon(points, fill: copper.opacity(0.35), stroke: copper, lineWidth: 2)
        let liftLength = value("speed", 40) > 0 ? (stalled ? 34.0 : 76.0) * min(1, abs(degrees) / 7) * (degrees < 0 ? -1 : 1) : 0
        arrow(center, p(182, 147 - liftLength), color: cyan, width: 3)
        if value("speed", 40) > 0 { arrow(center, p(stalled ? 122 : 151, 147), color: copper, width: 3) }
        label("LIFT", 213, 147 - liftLength, color: cyan, size: 10)
        label("\(number(degrees))°", 68, 180, color: cream, size: 11)
        label(stalled ? "STALL · FLOW SEPARATES" : "AIRFOIL TURNS THE AIR DOWN", 180, 241, color: stalled ? copper : cream, size: 9)
    }

    func helicopter() {
        let drive = value("power", 300)
        let angle = phase(drive, reference: 350)
        let body = p(190, 155)
        ellipse(145, 129, 89, 48, fill: copper.opacity(0.18), stroke: copper, lineWidth: 2)
        polygon([p(215, 135), p(231, 147), p(231, 157), p(210, 154)], fill: cyan.opacity(0.18), stroke: cyan)
        line([p(147, 154), p(69, 143), p(55, 125)], color: copper, width: 9)
        line([p(180, 129), p(180, 104)], color: cream, width: 4)
        ellipse(55, 90, 257, 27, stroke: copper.opacity(0.25), lineWidth: 1, dash: [4, 4])
        let rotorA = p(180 + cos(angle) * 124, 104 + sin(angle) * 12)
        let rotorB = p(180 - cos(angle) * 124, 104 - sin(angle) * 12)
        line([rotorA, rotorB], color: copper, width: 7)
        line([p(162, 175), p(151, 189), p(224, 189)], color: cream, width: 3)
        wheel(p(61, 140), radius: 15, angle: -angle * 2, tyre: false)
        if drive > 0 {
            for x in [99.0, 145, 240, 284] { arrow(p(x, 119), p(x + 8, 225), color: cyan.opacity(0.65), width: 2) }
            arrow(p(body.x + 8, 126), p(body.x + 8, 40), color: cyan, width: 3)
        }
        label("LIFT", 228, 53, color: cyan, size: 10)
        label("ROTOR DOWNWASH", 180, 242, color: cyan, size: 9)
        label("TAIL ROTOR", 64, 179, size: 8)
    }

    func turbofan() {
        let flow = value("coreFlow", 40)
        let fanAngle = phase(flow, reference: 45)
        let bypass = value("bypass", 8)
        polygon([p(42, 79), p(271, 79), p(316, 102), p(316, 184), p(271, 207), p(42, 207)], fill: steel.opacity(0.13), stroke: steel, lineWidth: 2)
        polygon([p(94, 116), p(264, 116), p(286, 134), p(286, 151), p(264, 170), p(94, 170)], fill: midnight, stroke: copper.opacity(0.6))
        line([p(36, 143), p(306, 143)], color: cream.opacity(0.65), width: 5)
        for index in -3...3 {
            let y = 143 + Double(index) * 17 + sin(fanAngle) * 4
            line([p(75, y - 6), p(83, y + 6)], color: copper, width: 5)
        }
        for index in 0..<6 {
            let x = 118 + Double(index) * 11
            line([p(x, 125), p(x + 5, 137)], color: cream.opacity(0.8), width: 3)
            line([p(x, 150), p(x + 5, 161)], color: cream.opacity(0.8), width: 3)
        }
        rect(190, 119, 37, 47, fill: copper.opacity(0.16), stroke: copper)
        for index in 0..<4 {
            let x = 196 + Double(index) * 8
            line([p(x, 124), p(x + 3, 133), p(x - 2, 144), p(x + 3, 155)], color: copper.opacity(0.5 + 0.5 * abs(sin(fanAngle))), width: 2)
        }
        for x in [244.0, 257, 270] { line([p(x, 124), p(x - 6, 162)], color: copper, width: 4) }
        if flow > 0 {
            for y in [95.0, 191] { flowLine(from: p(25, y), to: p(334, y), offset: time, tint: cyan.opacity(0.8), width: min(5, 1 + bypass / 4)) }
            arrow(p(282, 143), p(335, 143), color: copper, width: 4)
        }
        label("FAN", 78, 228, size: 9)
        label("COMPRESS", 145, 228, size: 8)
        label("BURN", 208, 228, color: copper, size: 9)
        label("TURBINE", 268, 228, size: 9)
        label("BYPASS AIR", 187, 59, color: cyan, size: 9)
        label("CORE JET", 304, 162, color: copper, size: 8)
    }

    func rocket() {
        let metrics = MechanicalSolver.metrics(for: .rocket, values: values, time: time)
        let firing = metrics.first(where: { $0.id == "burning" })?.value == 1
        let thrust = metrics.first(where: { $0.id == "thrust" })?.value ?? 0
        let remaining = metrics.first(where: { $0.id == "propellantRemaining" })?.value ?? 0
        let flow = firing ? max(0, value("massFlow", 20)) : 0
        let pressureRatio = value("exitPressure", 70) / max(1, value("ambientPressure", 101))
        rect(134, 44, 91, 79, fill: copper.opacity(0.12), stroke: copper, lineWidth: 2)
        line([p(152, 44), p(152, 74)], color: cyan, width: 3)
        line([p(207, 44), p(207, 74)], color: cyan, width: 3)
        for index in 0..<(firing ? 7 : 0) {
            let x = 146 + Double(index) * 11
            let shimmer = sin(time * 5 + Double(index)) * 4
            line([p(x, 77), p(x + shimmer, 111)], color: copper.opacity(0.7), width: 3, dash: [3, 4])
        }
        polygon([p(134, 123), p(167, 145), p(138, 196), p(222, 196), p(193, 145), p(225, 123)], fill: copper.opacity(0.2), stroke: copper, lineWidth: 3)
        if flow > 0 {
            let width = min(61, max(28, 41 * pressureRatio))
            let length = min(49, 24 + flow / 3)
            polygon([p(146, 195), p(214, 195), p(180 + width / 2, 219), p(180, 195 + length), p(180 - width / 2, 219)], fill: cyan.opacity(0.18), stroke: cyan.opacity(0.6))
            arrow(p(180, 165), p(180, 241), color: cyan, width: 3)
        }
        if thrust > 0 { arrow(p(276, 158), p(276, 65), color: cyan, width: 4) }
        label("THRUST", 279, 47, color: cyan, size: 11)
        label("CHAMBER", 73, 91, size: 9)
        label("THROAT", 72, 146, size: 9)
        label("EXPANSION", 74, 184, size: 8)
        line([p(106, 143), p(164, 143)], color: cream.opacity(0.35), width: 1)
        label(firing ? "EXHAUST CARRIES MOMENTUM" : "ENGINE OFF · \(number(remaining)) kg REMAINS", 180, 254, size: 8)
    }

    func windTurbine() {
        let wind = max(0, value("wind", 10))
        let angle = phase(wind, reference: 12)
        let center = p(194, 112)
        if wind > 0 {
            for y in [71.0, 112, 151, 195] { flowLine(from: p(22, y), to: p(332, y), offset: time * wind / 10, tint: cyan.opacity(0.5)) }
        }
        polygon([p(188, 125), p(201, 125), p(214, 239), p(178, 239)], fill: steel.opacity(0.4), stroke: steel)
        for index in 0..<3 { blade(center, radius: 85, angle: angle + Double(index) * 2 * .pi / 3, width: 11) }
        circle(center, 13, fill: copper, stroke: cream)
        line([p(177, 242), p(218, 242)], color: cream.opacity(0.4), width: 3)
        label("WIND → ROTATION → ELECTRICITY", 181, 256, size: 8)
        label("GENERATOR", 288, 49, color: copper, size: 9)
        line([p(275, 60), p(207, 105)], color: copper.opacity(0.5), width: 1)
    }

    func heatPump() {
        let indoor = value("indoor", 21)
        let outdoor = value("outdoor", 5)
        let drive = value("power", 2)
        let outsideCold = outdoor <= indoor
        let leftColor = outsideCold ? cyan : copper
        let rightColor = outsideCold ? copper : cyan
        rect(35, 83, 77, 110, fill: leftColor.opacity(0.07), stroke: leftColor.opacity(0.6))
        rect(249, 83, 77, 110, fill: rightColor.opacity(0.07), stroke: rightColor.opacity(0.6))
        coil(from: p(73, 93), to: p(73, 181), width: 26, turns: 7, color: leftColor)
        coil(from: p(287, 93), to: p(287, 181), width: 26, turns: 7, color: rightColor)
        line([p(73, 83), p(73, 58), p(163, 58)], color: leftColor, width: 5)
        line([p(199, 58), p(286, 58), p(286, 83)], color: rightColor, width: 5)
        line([p(286, 193), p(286, 219), p(202, 219)], color: rightColor, width: 5)
        line([p(159, 219), p(73, 219), p(73, 193)], color: leftColor, width: 5)
        circle(p(181, 58), 20, fill: steel.opacity(0.3), stroke: cream)
        gear(p(181, 58), radius: 13, teeth: 10, angle: phase(drive, reference: 3), tint: copper)
        polygon([p(159, 209), p(180, 219), p(159, 229)], fill: leftColor.opacity(0.3), stroke: leftColor)
        polygon([p(202, 209), p(180, 219), p(202, 229)], fill: rightColor.opacity(0.3), stroke: rightColor)
        if drive > 0 {
            arrow(p(outsideCold ? 123 : 146, 58), p(outsideCold ? 146 : 123, 58), color: leftColor, width: 1)
            arrow(p(outsideCold ? 227 : 208, 219), p(outsideCold ? 208 : 227, 219), color: rightColor, width: 1)
            arrow(p(outsideCold ? 18 : 58, 137), p(outsideCold ? 58 : 18, 137), color: leftColor, width: outsideCold ? 3 : 4)
            arrow(p(outsideCold ? 301 : 340, 137), p(outsideCold ? 340 : 301, 137), color: rightColor, width: outsideCold ? 4 : 3)
            arrow(p(181, 130), p(181, 87), color: cream, width: 2)
        }
        label("WORK IN", 181, 148, size: 9)
        label("\(number(drive)) kW", 181, 163, color: cyan, size: 12)
        label("COMPRESSOR", 181, 25, size: 9)
        label("OUTDOORS", 74, 69, color: leftColor, size: 8)
        label("INDOORS", 289, 69, color: rightColor, size: 8)
        label("\(number(outdoor))°C", 74, 201, color: leftColor, size: 11)
        label("\(number(indoor))°C", 289, 201, color: rightColor, size: 11)
        label("EXPANSION VALVE", 180, 242, size: 8)
    }
}

private extension MechanismDrawing {
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    func polar(_ center: CGPoint, _ radius: Double, _ angle: Double) -> CGPoint {
        p(center.x + radius * cos(angle), center.y + radius * sin(angle))
    }

    func rotated(_ point: CGPoint, around center: CGPoint, angle: Double) -> CGPoint {
        let x = point.x - center.x, y = point.y - center.y
        return p(center.x + x * cos(angle) - y * sin(angle), center.y + x * sin(angle) + y * cos(angle))
    }

    func line(_ points: [CGPoint], color: Color, width: Double = 2, dash: [CGFloat] = []) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
        if width >= 4, dash.isEmpty, isMetal(color) {
            var shadow = context
            shadow.translateBy(x: 1.6, y: 2)
            shadow.stroke(path, with: .color(.black.opacity(0.65)), style: style)
            let bounds = path.boundingRect.insetBy(dx: -width, dy: -width)
            context.stroke(path, with: chrome(in: bounds, tint: color), style: style)
            context.stroke(path, with: .color(.white.opacity(0.16)),
                           style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
        } else {
            context.stroke(path, with: .color(color), style: style)
        }
    }

    func polygon(_ points: [CGPoint], fill: Color, stroke: Color? = nil, lineWidth: Double = 1) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        if fill != .clear, let stroke, isMetal(stroke) { metal(path, tint: stroke) }
        else { context.fill(path, with: .color(fill)) }
        if let stroke { context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round)) }
    }

    func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, fill: Color = .clear, stroke: Color? = nil, lineWidth: Double = 1) {
        let path = Path(roundedRect: CGRect(x: x, y: y, width: width, height: max(0, height)), cornerRadius: 2)
        if fill != .clear, let stroke, isMetal(stroke) { metal(path, tint: stroke) }
        else { context.fill(path, with: .color(fill)) }
        if let stroke { context.stroke(path, with: .color(stroke), lineWidth: lineWidth) }
    }

    func rotatedRect(center: CGPoint, width: Double, height: Double, angle: Double, fill: Color, stroke: Color, lineWidth: Double = 1) {
        let corners = [p(center.x - width / 2, center.y - height / 2), p(center.x + width / 2, center.y - height / 2), p(center.x + width / 2, center.y + height / 2), p(center.x - width / 2, center.y + height / 2)]
        polygon(corners.map { rotated($0, around: center, angle: angle) }, fill: fill, stroke: stroke, lineWidth: lineWidth)
    }

    func circle(_ center: CGPoint, _ radius: Double, fill: Color = .clear, stroke: Color? = nil, lineWidth: Double = 2, dash: [CGFloat] = []) {
        ellipse(center.x - radius, center.y - radius, radius * 2, radius * 2, fill: fill, stroke: stroke, lineWidth: lineWidth, dash: dash)
    }

    func ellipse(_ x: Double, _ y: Double, _ width: Double, _ height: Double, fill: Color = .clear, stroke: Color? = nil, lineWidth: Double = 2, dash: [CGFloat] = []) {
        let path = Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height))
        context.fill(path, with: .color(fill))
        if let stroke {
            if isMetal(stroke), dash.isEmpty {
                context.stroke(path, with: chrome(in: path.boundingRect, tint: stroke),
                               style: StrokeStyle(lineWidth: lineWidth, dash: dash))
                context.stroke(path, with: .color(.white.opacity(0.2)), lineWidth: 0.6)
            } else {
                context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth, dash: dash))
            }
        }
    }

    func label(_ text: String, _ x: Double, _ y: Double, color: Color? = nil, size: Double = 10) {
        context.draw(Text(text).font(.system(size: size, weight: .medium, design: .monospaced)).foregroundStyle(color ?? cream), at: p(x, y))
    }

    func arrow(_ from: CGPoint, _ to: CGPoint, color: Color, width: Double = 2) {
        let distance = hypot(to.x - from.x, to.y - from.y)
        guard distance > 2 else { return }
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = min(8, distance * 0.3)
        line([from, to], color: color, width: width)
        line([polar(to, head, angle + 2.65), to, polar(to, head, angle - 2.65)], color: color, width: width)
    }

    func dimension(_ from: CGPoint, _ to: CGPoint, text: String) {
        line([from, to], color: cream.opacity(0.5), width: 1)
        line([p(from.x, from.y - 4), p(from.x, from.y + 4)], color: cream.opacity(0.5), width: 1)
        line([p(to.x, to.y - 4), p(to.x, to.y + 4)], color: cream.opacity(0.5), width: 1)
        label(text, (from.x + to.x) / 2, from.y - 10, color: cream.opacity(0.65), size: 8)
    }

    func coil(from: CGPoint, to: CGPoint, width: Double, turns: Int, color: Color) {
        var points = [from, p(from.x, from.y + 6)]
        let available = to.y - from.y - 12
        for index in 0..<(turns * 2) {
            points.append(p(from.x + (index.isMultiple(of: 2) ? -width : width), from.y + 6 + available * Double(index + 1) / Double(turns * 2 + 1)))
        }
        points.append(p(to.x, to.y - 6)); points.append(to)
        line(points, color: color, width: 2.5)
    }

    func gear(_ center: CGPoint, radius: Double, teeth: Int, angle: Double, tint: Color) {
        let toothCount = min(64, max(8, teeth))
        let depth = min(5, radius * 0.13)
        var points: [CGPoint] = []
        for index in 0..<(toothCount * 4) {
            let toothRadius = index % 4 == 1 || index % 4 == 2 ? radius + depth : radius - depth
            points.append(polar(center, toothRadius, angle + Double(index) * 2 * .pi / Double(toothCount * 4)))
        }
        var outline = Path()
        if let first = points.first {
            outline.move(to: first)
            for point in points.dropFirst() { outline.addLine(to: point) }
            outline.closeSubpath()
        }
        metal(outline, tint: tint)
        circle(center, radius * 0.73, stroke: midnight.opacity(0.75), lineWidth: 1)
        circle(center, radius * 0.73 - 1, stroke: .white.opacity(0.42), lineWidth: 0.6)
        for index in 0..<4 {
            let spokeAngle = angle + Double(index) * .pi / 2
            line([polar(center, 9, spokeAngle), polar(center, radius * 0.67, spokeAngle)],
                 color: midnight.opacity(0.74), width: max(2, radius * 0.075))
        }
        // An index on the material gives the eye something to follow per turn.
        circle(polar(center, radius * 0.57, angle), max(1.5, radius * 0.035), fill: cyan)
        circle(center, max(5, radius * 0.13), fill: midnight, stroke: cream, lineWidth: 1.5)
    }

    func wheel(_ center: CGPoint, radius: Double, angle: Double, tyre: Bool = true) {
        circle(center, radius, fill: steel.opacity(0.05), stroke: tyre ? steel : copper, lineWidth: tyre ? 5 : 3)
        for index in 0..<8 { line([polar(center, 5, angle + Double(index) * .pi / 4), polar(center, radius - 4, angle + Double(index) * .pi / 4)], color: tyre ? cream.opacity(0.65) : copper.opacity(0.8), width: 1.5) }
        circle(center, 5, fill: midnight, stroke: cream, lineWidth: 1.5)
    }

    func pulleyWheel(_ center: CGPoint, radius: Double, angle: Double) {
        metal(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2)), tint: copper)
        circle(center, radius - 4, stroke: midnight.opacity(0.6), lineWidth: 1.4)
        circle(center, radius - 6, stroke: .white.opacity(0.4), lineWidth: 0.6)
        for index in 0..<4 { line([center, polar(center, radius - 8, angle + Double(index) * .pi / 2)], color: copper.opacity(0.6), width: 2) }
        circle(center, 4, fill: midnight, stroke: cream)
    }

    func blade(_ center: CGPoint, radius: Double, angle: Double, width: Double) {
        let points = [p(center.x + 9, center.y - 4), p(center.x + radius * 0.4, center.y - width), p(center.x + radius, center.y - width * 0.32), p(center.x + radius * 0.94, center.y + width * 0.18), p(center.x + radius * 0.45, center.y + width * 0.35), p(center.x + 9, center.y + 5)]
        polygon(points.map { rotated($0, around: center, angle: angle) }, fill: copper.opacity(0.28), stroke: copper, lineWidth: 2)
    }

    func flowLine(from: CGPoint, to: CGPoint, offset: Double, tint: Color, width: Double = 1.5) {
        line([from, to], color: tint.opacity(0.5), width: width)
        let length = to.x - from.x
        guard length > 0 else { return }
        let travel = (offset * 28).truncatingRemainder(dividingBy: 74)
        for index in 0..<4 {
            let x = from.x + Double(index) * 74 + travel
            if x < to.x - 18 { arrow(p(x, from.y), p(x + 16, from.y), color: tint, width: width) }
        }
    }

    func isMetal(_ color: Color) -> Bool {
        color == copper || color == steel || color == cream
    }

    func chrome(in bounds: CGRect, tint: Color) -> GraphicsContext.Shading {
        let start = p(bounds.minX - bounds.width * 0.16 + light.x * bounds.width * 0.35,
                      bounds.minY + light.y * bounds.height * 0.3)
        let end = p(bounds.maxX + bounds.width * 0.12 + light.x * bounds.width * 0.2,
                    bounds.maxY + light.y * bounds.height * 0.25)
        return .linearGradient(Gradient(stops: [
            .init(color: Color(red: 0.22, green: 0.31, blue: 0.38), location: 0),
            .init(color: Color(red: 0.85, green: 0.93, blue: 0.97), location: 0.19),
            .init(color: .white, location: 0.26),
            .init(color: Color(red: 0.27, green: 0.36, blue: 0.43), location: 0.36),
            .init(color: Color(red: 0.10, green: 0.16, blue: 0.22), location: 0.47),
            .init(color: tint.opacity(0.6), location: 0.53),
            .init(color: Color(red: 0.58, green: 0.71, blue: 0.79), location: 0.65),
            .init(color: .white.opacity(0.96), location: 0.78),
            .init(color: Color(red: 0.30, green: 0.42, blue: 0.50), location: 1)
        ]), startPoint: start, endPoint: end)
    }

    func metal(_ path: Path, tint: Color) {
        var shadow = context
        shadow.translateBy(x: 1.5, y: 2.5)
        shadow.fill(path, with: .color(.black.opacity(0.65)))
        context.fill(path, with: chrome(in: path.boundingRect, tint: tint))
        context.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 0.7)
        // A cool spectral seam reads as reflected light, rather than changing
        // the force/flow colours that carry meaning in the model.
        context.stroke(path, with: .linearGradient(Gradient(colors: [.clear, cyan.opacity(0.5),
                                                                    .clear, .purple.opacity(0.27), .clear]),
                                                   startPoint: p(path.boundingRect.minX + light.x * 20, path.boundingRect.minY),
                                                   endPoint: p(path.boundingRect.maxX, path.boundingRect.maxY + light.y * 20)),
                       lineWidth: 1.1)
    }

    func rotationTrack(_ center: CGPoint, radius: Double, angle: Double, direction: Double) {
        circle(center, radius, stroke: cyan.opacity(0.16), lineWidth: 0.6, dash: [1, 4])
        for index in 0..<7 {
            let trailAngle = angle - direction * Double(index) * 0.11
            circle(polar(center, radius, trailAngle), index == 0 ? 2.4 : 1.2,
                   fill: cyan.opacity(index == 0 ? 0.95 : 0.44 - Double(index) * 0.055))
        }
        let tip = polar(center, radius, angle + direction * 0.16)
        let from = polar(center, radius, angle + direction * 0.06)
        arrow(from, tip, color: cyan.opacity(0.8), width: 1)
    }
}
