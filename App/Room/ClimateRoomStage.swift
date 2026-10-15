import SwiftUI
import MechanicalCore

struct ClimateRoomStage: View {
    var climate: RoomEnvironment
    var inputs: RoomEnvironmentInputs

    private var roomColor: Color {
        climate.temperature > 22 ? ToyTheme.copper : ToyTheme.cyan
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    let room = CGRect(x: size.width * 0.13, y: size.height * 0.24,
                                      width: size.width * 0.72, height: size.height * 0.62)
                    let outline = Path(roundedRect: room, cornerRadius: 4)
                    context.fill(outline, with: .color(roomColor.opacity(0.12)))
                    context.stroke(outline, with: .color(ToyTheme.muted.opacity(0.65)), lineWidth: 5)
                    let windowHeight = room.height * 0.34
                    let window = CGRect(x: room.minX - 3, y: room.midY - windowHeight * 0.5,
                                        width: 6, height: windowHeight)
                    context.fill(Path(window), with: .color(ToyTheme.cyan))
                    let opening = CGRect(x: room.minX - 4, y: window.minY, width: 8,
                                         height: windowHeight * inputs.windowOpening)
                    context.fill(Path(opening), with: .color(ToyTheme.background))
                    let heatpump = CGRect(x: room.maxX - room.width * 0.18, y: room.minY + 18,
                                          width: room.width * 0.12, height: room.height * 0.28)
                    context.fill(Path(roundedRect: heatpump, cornerRadius: 6), with: .color(ToyTheme.panel))
                    context.stroke(Path(roundedRect: heatpump, cornerRadius: 6),
                                   with: .color(climate.hvacPower >= 0 ? ToyTheme.copper : ToyTheme.cyan), lineWidth: 2)
                    let dotCount = max(0, Int(inputs.occupants))
                    for person in 0..<dotCount {
                        let columns = max(1, min(4, dotCount))
                        let x = room.minX + 30 + CGFloat(person % columns) * (room.width - 66) / CGFloat(max(3, columns))
                        let y = room.maxY - 22 - CGFloat(person / columns) * 28
                        let head = CGRect(x: x - 3.5, y: y - 15, width: 7, height: 7)
                        context.fill(Path(ellipseIn: head), with: .color(ToyTheme.ink))
                        let body = Path(roundedRect: CGRect(x: x - 4, y: y - 6, width: 8, height: 15), cornerRadius: 3)
                        context.fill(body, with: .color(ToyTheme.ink.opacity(0.75)))
                    }
                    func arrow(from a: CGPoint, to b: CGPoint, color: Color, width: CGFloat) {
                        var path = Path()
                        path.move(to: a); path.addLine(to: b)
                        let angle = atan2(b.y - a.y, b.x - a.x)
                        path.move(to: CGPoint(x: b.x - cos(angle - .pi / 6) * 8, y: b.y - sin(angle - .pi / 6) * 8))
                        path.addLine(to: b)
                        path.addLine(to: CGPoint(x: b.x - cos(angle + .pi / 6) * 8, y: b.y - sin(angle + .pi / 6) * 8))
                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                    if inputs.airChangesPerHour > 0.01 {
                        let strength = CGFloat(min(4, 1 + inputs.airChangesPerHour * 0.2))
                        arrow(from: CGPoint(x: room.minX - 25, y: room.midY - 12),
                              to: CGPoint(x: room.minX + 26, y: room.midY - 12), color: ToyTheme.cyan, width: strength)
                        arrow(from: CGPoint(x: room.midX, y: room.minY + 20),
                              to: CGPoint(x: room.midX, y: room.minY - 18), color: ToyTheme.cyan, width: strength)
                    }
                    let heatLoss = climate.envelopePower + climate.ventilationPower
                    if abs(heatLoss) > 5 {
                        let y = room.maxY - 34
                        let left = CGPoint(x: room.maxX - 16, y: y), right = CGPoint(x: room.maxX + 22, y: y)
                        arrow(from: heatLoss < 0 ? left : right, to: heatLoss < 0 ? right : left,
                              color: ToyTheme.copper, width: 2)
                    }
                    for line in 0..<5 {
                        let y = heatpump.minY + 8 + CGFloat(line) * 5
                        var slit = Path()
                        slit.move(to: CGPoint(x: heatpump.minX + 5, y: y))
                        slit.addLine(to: CGPoint(x: heatpump.maxX - 5, y: y))
                        context.stroke(slit, with: .color(ToyTheme.muted), lineWidth: 1)
                    }
                }
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CLIMATE ROOM").font(.system(.caption2, design: .monospaced, weight: .bold)).tracking(1.5)
                            Text("80 m³ · one well-mixed zone").font(.caption2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("OUTDOOR").font(.system(.caption2, design: .monospaced, weight: .bold))
                            Text("\(Int(inputs.outdoorTemperature)) °C · \(Int(inputs.outdoorHumidity))% RH").font(.caption2)
                        }
                    }.foregroundStyle(ToyTheme.muted)
                    Spacer()
                    Text("\(climate.temperature.formatted(.number.precision(.fractionLength(1)))) °C")
                        .font(.system(.title, design: .monospaced, weight: .semibold)).foregroundStyle(roomColor)
                        .monospacedDigit().offset(y: geometry.size.height * -0.015)
                    Spacer()
                    HStack {
                        Label("Fresh air", systemImage: "arrow.right").foregroundStyle(ToyTheme.cyan)
                        Spacer()
                        Label("Heat", systemImage: "arrow.right").foregroundStyle(ToyTheme.copper)
                    }.font(.caption2)
                }.padding(14)
            }
            .background(ToyTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)))
        }
    }
}
