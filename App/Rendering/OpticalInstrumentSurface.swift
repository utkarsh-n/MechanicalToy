import SwiftUI

/// The machine is content; this is its optical housing. Reflections respond to
/// gravity independently of simulated time, so a paused machine still feels held.
struct OpticalInstrumentSurface<Content: View>: View {
    let tilt: SIMD2<Double>
    let reducedMotion: Bool
    private let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(tilt: SIMD2<Double>, reducedMotion: Bool, @ViewBuilder content: () -> Content) {
        self.tilt = tilt
        self.reducedMotion = reducedMotion
        self.content = content()
    }

    private var light: SIMD2<Double> {
        guard !reducedMotion else { return .zero }
        return SIMD2(bounded(tilt.x), bounded(tilt.y))
    }

    private func bounded(_ value: Double) -> Double {
        value.isFinite ? min(1, max(-1, value)) : 0
    }

    var body: some View {
        content
            .offset(x: light.x * 3.4, y: light.y * 2.8)
            .background { housing }
            .overlay { opticalEdges.allowsHitTesting(false).accessibilityHidden(true) }
            .clipShape(.rect(cornerRadius: 25))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
    }

    private var housing: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25)
                .fill(chromeGradient)
            RoundedRectangle(cornerRadius: 21)
                .inset(by: 4)
                .fill(Color(red: 0.034, green: 0.055, blue: 0.077))
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: 21)
                    .inset(by: 5)
                    .fill(RadialGradient(colors: [.white.opacity(0.12), .cyan.opacity(0.025), .clear],
                                         center: UnitPoint(x: 0.25 + light.x * 0.28,
                                                           y: 0.12 + light.y * 0.23),
                                         startRadius: 0, endRadius: 430))
            }
        }
        .accessibilityHidden(true)
    }

    private var chromeGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: .white.opacity(0.78), location: 0),
            .init(color: Color(red: 0.40, green: 0.51, blue: 0.59), location: 0.12),
            .init(color: Color(red: 0.09, green: 0.13, blue: 0.18), location: 0.34),
            .init(color: .white.opacity(0.65), location: 0.49),
            .init(color: Color(red: 0.15, green: 0.21, blue: 0.28), location: 0.55),
            .init(color: Color(red: 0.53, green: 0.64, blue: 0.71), location: 0.82),
            .init(color: .white.opacity(0.85), location: 1)
        ], startPoint: UnitPoint(x: -0.18 + light.x * 0.3, y: light.y * 0.25),
           endPoint: UnitPoint(x: 1.15 + light.x * 0.15, y: 1 + light.y * 0.2))
    }

    private var opticalEdges: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 25)
                    .strokeBorder(.white.opacity(0.19), lineWidth: 0.7)
                RoundedRectangle(cornerRadius: 21)
                    .inset(by: 5)
                    .strokeBorder(.black.opacity(0.8), lineWidth: 1)
                if !reduceTransparency {
                    spectralEdge(size: geometry.size)
                }
                Canvas { context, size in
                    drawRegistration(context: &context, size: size)
                }
            }
        }
    }

    private func spectralEdge(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .inset(by: 2)
                .stroke(AngularGradient(colors: [.clear, .cyan.opacity(0.85), .blue.opacity(0.35),
                                                .purple.opacity(0.7), .pink.opacity(0.52), .clear,
                                                .mint.opacity(0.6), .white.opacity(0.8), .clear],
                                        center: UnitPoint(x: 0.5 + light.x * 0.2,
                                                          y: 0.5 + light.y * 0.2),
                                        startAngle: .degrees(light.x * 35 - light.y * 25),
                                        endAngle: .degrees(360 + light.x * 35 - light.y * 25)),
                        lineWidth: 1.4)
            // Three different depths split a white glint into spectral echoes.
            ForEach(0..<3, id: \.self) { depth in
                let separation = Double(depth) * 1.6
                RoundedRectangle(cornerRadius: 22)
                    .inset(by: 4 + Double(depth) * 0.65)
                    .stroke(LinearGradient(stops: [
                        .init(color: .clear, location: 0.13),
                        .init(color: spectralColor(depth).opacity(0.02), location: 0.28),
                        .init(color: spectralColor(depth).opacity(depth == 0 ? 0.82 : 0.46), location: 0.39),
                        .init(color: .clear, location: 0.45),
                        .init(color: .clear, location: 0.66),
                        .init(color: spectralColor(depth).opacity(0.32), location: 0.75),
                        .init(color: .clear, location: 0.84)
                    ], startPoint: UnitPoint(x: -0.2 + light.x * 0.4, y: light.y * 0.32),
                       endPoint: UnitPoint(x: 1.2 + light.x * 0.25, y: 1 + light.y * 0.3)),
                            lineWidth: depth == 0 ? 2.3 : 1.2)
                    .offset(x: light.x * separation, y: light.y * separation)
            }
        }
        .blendMode(.screen)
    }

    private func spectralColor(_ depth: Int) -> Color {
        depth == 0 ? .white : depth == 1 ? .cyan : Color(red: 0.72, green: 0.51, blue: 1)
    }

    private func drawRegistration(context: inout GraphicsContext, size: CGSize) {
        let width = Double(size.width), height = Double(size.height)
        guard width > 55, height > 55 else { return }
        let corners = [CGPoint(x: 14, y: 14), CGPoint(x: width - 14, y: 14),
                       CGPoint(x: 14, y: height - 14), CGPoint(x: width - 14, y: height - 14)]
        for (index, point) in corners.enumerated() {
            let boss = Path(ellipseIn: CGRect(x: point.x - 4.7, y: point.y - 4.7, width: 9.4, height: 9.4))
            context.fill(boss, with: .linearGradient(Gradient(colors: [.white.opacity(0.72),
                                                                       Color(red: 0.15, green: 0.22, blue: 0.28),
                                                                       .white.opacity(0.45)]),
                                                       startPoint: CGPoint(x: point.x - 5 + light.x * 3, y: point.y - 5 + light.y * 3),
                                                       endPoint: CGPoint(x: point.x + 5, y: point.y + 5)))
            context.stroke(boss, with: .color(.black.opacity(0.7)), lineWidth: 0.8)
            var notch = Path()
            notch.move(to: CGPoint(x: point.x - 2.2, y: point.y + 1.1))
            notch.addLine(to: CGPoint(x: point.x + 2.2, y: point.y - 1.1))
            context.stroke(notch, with: .color(.black.opacity(0.85)), lineWidth: 1)

            let dx = index.isMultiple(of: 2) ? 1.0 : -1.0
            let dy = index < 2 ? 1.0 : -1.0
            let offsetX = point.x + dx * (8 + light.x * 1.7)
            let offsetY = point.y + dy * (8 + light.y * 1.7)
            var bracket = Path()
            bracket.move(to: CGPoint(x: offsetX, y: offsetY + dy * 10))
            bracket.addLine(to: CGPoint(x: offsetX, y: offsetY))
            bracket.addLine(to: CGPoint(x: offsetX + dx * 10, y: offsetY))
            context.stroke(bracket, with: .color(.cyan.opacity(reduceTransparency ? 0.6 : 0.36)), lineWidth: 0.7)
        }
    }
}
