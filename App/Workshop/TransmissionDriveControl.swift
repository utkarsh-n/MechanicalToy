import SwiftUI

/// A calibrated drive crown. Optical light follows the phone; the shaft input
/// changes only when the user turns this control or uses its accessible actions.
struct TransmissionDriveControl: View {
    @Binding var inputRPM: Double
    let outputLabel: String
    let outputValue: String
    let tilt: SIMD2<Double>
    let reducedMotion: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("mechanical.haptics") private var haptics = true
    @State private var dragging = false
    @State private var detentEvent = 0

    private var rpm: Double { inputRPM.isFinite ? min(240, max(0, inputRPM)) : 0 }
    private var light: SIMD2<Double> {
        guard !reducedMotion else { return .zero }
        return SIMD2(tilt.x.isFinite ? min(1, max(-1, tilt.x)) : 0,
                     tilt.y.isFinite ? min(1, max(-1, tilt.y)) : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { dial; values }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 14) { dial; values }
            }
            Label(dragging ? "Turning the input shaft" : "Drag the crown to drive the transmission", systemImage: "arrow.clockwise")
                .font(.caption).foregroundStyle(dragging ? ToyTheme.cyan : ToyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.13), lineWidth: 0.8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transmission drive, input rpm")
        .accessibilityValue(formattedRPM)
        .accessibilityHint("\(outputLabel) \(outputValue). Adjust to change input by five revolutions per minute. The range is zero to two hundred forty.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setRPM(rpm + 5)
            case .decrement: setRPM(rpm - 5)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Increase input by five rpm") { setRPM(rpm + 5) }
        .accessibilityAction(named: "Decrease input by five rpm") { setRPM(rpm - 5) }
        .accessibilityIdentifier("gears.drive")
        .sensoryFeedback(.selection, trigger: detentEvent) { _, _ in haptics }
        .onDisappear { dragging = false }
    }

    private var formattedRPM: String { rpm.formatted(.number.precision(.fractionLength(0...1))) }

    private var values: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INPUT DRIVE").font(.system(.caption2, design: .monospaced, weight: .semibold))
                .tracking(1.4).foregroundStyle(ToyTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formattedRPM).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(ToyTheme.ink)
                Text("rpm").font(.caption).foregroundStyle(ToyTheme.muted)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.turn.down.right").font(.caption.weight(.semibold))
                    .foregroundStyle(ToyTheme.cyan).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(outputLabel).font(.caption).foregroundStyle(ToyTheme.muted)
                    Text(outputValue).font(.system(.headline, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(ToyTheme.cyan)
                }
            }
        }
    }

    private var dial: some View {
        Canvas { context, size in
            drawDial(context: &context, diameter: min(size.width, size.height))
        }
        .frame(width: 128, height: 128)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let dx = value.location.x - 64, dy = value.location.y - 64
            guard dx.isFinite, dy.isFinite, hypot(dx, dy) >= 18 else { return }
            dragging = true
            var degrees = atan2(dy, dx) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            let sweep: Double
            if degrees >= 135 { sweep = degrees }
            else if degrees <= 45 { sweep = degrees + 360 }
            else { sweep = degrees < 90 ? 405 : 135 }
            setRPM((sweep - 135) / 270 * 240)
        }.onEnded { _ in dragging = false })
        .accessibilityHidden(true)
    }

    private func setRPM(_ value: Double) {
        guard value.isFinite else { return }
        let next = (min(240, max(0, value)) * 2).rounded() / 2
        if Int(next / 5) != Int(rpm / 5) { detentEvent += 1 }
        inputRPM = next
    }

    private func drawDial(context: inout GraphicsContext, diameter: CGFloat) {
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let radius = diameter / 2
        let outer = Path(ellipseIn: CGRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2))
        var shadow = context
        shadow.translateBy(x: 0, y: 2)
        shadow.fill(outer, with: .color(.black.opacity(0.65)))
        context.fill(outer, with: chrome(center: center, radius: radius))
        context.stroke(outer, with: .color(.white.opacity(0.48)), lineWidth: 0.7)
        for grip in 0..<60 {
            let angle = Double(grip) * 6
            var knurl = Path()
            knurl.move(to: point(angle, radius - 3.4, center))
            knurl.addLine(to: point(angle, radius - 1.2, center))
            context.stroke(knurl, with: .color(.black.opacity(0.42)), lineWidth: 0.8)
        }

        for inset in [3.0, 5, 7] {
            let ring = Path(ellipseIn: CGRect(x: inset, y: inset, width: diameter - 2 * inset, height: diameter - 2 * inset))
            context.stroke(ring, with: .color(inset == 5 ? .black.opacity(0.56) : .white.opacity(0.24)), lineWidth: 0.65)
        }
        let face = Path(ellipseIn: CGRect(x: 9, y: 9, width: diameter - 18, height: diameter - 18))
        context.fill(face, with: .linearGradient(Gradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.16),
                                                                   Color(red: 0.024, green: 0.045, blue: 0.065)]),
                                                 startPoint: CGPoint(x: 22 + light.x * 16, y: 10 + light.y * 15),
                                                 endPoint: CGPoint(x: diameter, y: diameter)))
        context.stroke(face, with: .color(dragging ? ToyTheme.cyan.opacity(0.6) : .black.opacity(0.9)), lineWidth: 1)

        let scaleRadius = radius - 14
        let fullScale = Path { path in
            path.addArc(center: center, radius: scaleRadius, startAngle: .degrees(135),
                        endAngle: .degrees(405), clockwise: false)
        }
        context.stroke(fullScale, with: .color(.white.opacity(0.12)), lineWidth: 1)
        let pointerAngle = 135 + rpm / 240 * 270
        let activeScale = Path { path in
            path.addArc(center: center, radius: scaleRadius, startAngle: .degrees(135),
                        endAngle: .degrees(pointerAngle), clockwise: false)
        }
        context.stroke(activeScale, with: .color(ToyTheme.cyan.opacity(0.68)),
                       style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        for tick in 0...48 {
            let angle = 135 + Double(tick) / 48 * 270
            let major = tick.isMultiple(of: 12)
            let medium = tick.isMultiple(of: 3)
            var mark = Path()
            mark.move(to: point(angle, scaleRadius - (major ? 7 : medium ? 4.5 : 2.5), center))
            mark.addLine(to: point(angle, scaleRadius, center))
            context.stroke(mark, with: .color(.white.opacity(major ? 0.94 : medium ? 0.54 : 0.26)),
                           lineWidth: major ? 1.3 : 0.7)
            if major {
                context.draw(Text("\(tick * 5)").font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86)), at: point(angle, scaleRadius - 14, center))
            }
        }

        // The needle is a moving mechanical part; the glints are optical parts.
        let tip = point(pointerAngle, scaleRadius - 21, center)
        var needle = Path()
        needle.move(to: point(pointerAngle + 90, 3, center))
        needle.addLine(to: point(pointerAngle + 90, 0.8, tip))
        needle.addLine(to: point(pointerAngle - 90, 0.8, tip))
        needle.addLine(to: point(pointerAngle - 90, 3, center))
        needle.closeSubpath()
        context.fill(needle, with: chrome(center: center, radius: 8))
        context.stroke(needle, with: .color(.white.opacity(0.72)), lineWidth: 0.6)
        context.fill(Path(ellipseIn: CGRect(x: tip.x - 1.8, y: tip.y - 1.8, width: 3.6, height: 3.6)),
                     with: .color(ToyTheme.cyan))
        let hub = Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14))
        context.fill(hub, with: chrome(center: center, radius: 7))
        context.stroke(hub, with: .color(.black.opacity(0.85)), lineWidth: 1)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6)),
                     with: .color(.black.opacity(0.8)))

        if !reduceTransparency {
            let reflection = -115 + light.x * 38 + light.y * 22
            for layer in 0..<3 {
                let glint = Path { path in
                    path.addArc(center: CGPoint(x: center.x + light.x * Double(layer),
                                                y: center.y + light.y * Double(layer)),
                                radius: radius - 1.5 - Double(layer) * 1.7,
                                startAngle: .degrees(reflection - 26), endAngle: .degrees(reflection + 19), clockwise: false)
                }
                let tint = layer == 0 ? Color.white : layer == 1 ? ToyTheme.cyan : Color(red: 0.74, green: 0.52, blue: 1)
                context.stroke(glint, with: .color(tint.opacity(layer == 0 ? 0.88 : 0.54)),
                               style: StrokeStyle(lineWidth: layer == 0 ? 1.3 : 0.8, lineCap: .round))
            }
        }
    }

    private func chrome(center: CGPoint, radius: CGFloat) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [Color(red: 0.87, green: 0.93, blue: 0.96),
                                           Color(red: 0.30, green: 0.40, blue: 0.48), .white,
                                           Color(red: 0.11, green: 0.18, blue: 0.24),
                                           Color(red: 0.65, green: 0.77, blue: 0.83), .white]),
                        startPoint: CGPoint(x: center.x - radius + light.x * radius * 0.3,
                                            y: center.y - radius + light.y * radius * 0.3),
                        endPoint: CGPoint(x: center.x + radius + light.x * radius * 0.2,
                                          y: center.y + radius))
    }

    private func point(_ degrees: Double, _ radius: CGFloat, _ center: CGPoint) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }
}
