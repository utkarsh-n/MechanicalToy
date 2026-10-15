import SwiftUI

enum ToyTheme {
    static let background = Color(red: 0.028, green: 0.048, blue: 0.066)
    static let panel = Color(red: 0.065, green: 0.092, blue: 0.114)
    static let ink = Color(red: 0.96, green: 0.95, blue: 0.89)
    static let muted = Color(red: 0.62, green: 0.72, blue: 0.77)
    static let copper = Color(red: 1, green: 0.65, blue: 0.36)
    static let cyan = Color(red: 0.35, green: 0.88, blue: 0.94)
    static let green = Color(red: 0.55, green: 0.91, blue: 0.70)
}

enum ToyFormat {
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if abs(value) < 0.000_001 { return "0" }
        if abs(value) >= 100_000 || abs(value) < 0.001 { return String(format: "%.2e", value) }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

struct ToyScreen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(20).padding(.bottom, 20)
                .frame(maxWidth: .infinity)
        }
        .background(ToyTheme.background.ignoresSafeArea())
        .foregroundStyle(ToyTheme.ink)
    }
}

struct ToyPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty { SectionCaption(title: title) }
            content
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.07)))
    }
}

struct SectionCaption: View {
    var title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .tracking(1.6).foregroundStyle(ToyTheme.muted)
    }
}

struct MetricTile: View {
    var label: String
    var value: String
    var unit: String
    var tint: Color = ToyTheme.cyan
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(ToyTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(.title2, design: .monospaced, weight: .semibold)).monospacedDigit()
                Text(unit).font(.caption)
            }
            .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 17))
        .accessibilityElement(children: .combine)
    }
}

struct ToySlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit: String
    @AppStorage("mechanical.haptics") private var haptics = true
    @State private var editing = false
    @State private var draft = ""
    private var step: Double { (range.upperBound - range.lowerBound) / 100 }
    private var detent: Int { Int((value - range.lowerBound) / max(step, 0.000_001)) }
    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline)
                Spacer()
                Button {
                    draft = String(format: "%.4g", value); editing = true
                } label: {
                    Text("\(ToyFormat.number(value)) \(unit)")
                        .font(.system(.subheadline, design: .monospaced, weight: .medium))
                        .monospacedDigit().foregroundStyle(ToyTheme.cyan)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Enter \(title)")
                .accessibilityValue("\(ToyFormat.number(value)) \(unit)")
            }
            Slider(value: $value, in: range)
                .tint(ToyTheme.cyan).accessibilityLabel(title)
                .accessibilityValue("\(ToyFormat.number(value)) \(unit)")
            HStack {
                Button { value = max(range.lowerBound, value - step) } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44)
                }.disabled(value <= range.lowerBound).accessibilityLabel("Decrease \(title)")
                Spacer()
                Text("\(ToyFormat.number(range.lowerBound)) – \(ToyFormat.number(range.upperBound)) \(unit)")
                    .font(.caption2).foregroundStyle(ToyTheme.muted)
                Spacer()
                Button { value = min(range.upperBound, value + step) } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }.disabled(value >= range.upperBound).accessibilityLabel("Increase \(title)")
            }.buttonStyle(.glass)
        }
        .sensoryFeedback(.selection, trigger: detent) { _, _ in haptics }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    TextField("Value in \(unit)", text: $draft).keyboardType(.numbersAndPunctuation)
                        .accessibilityLabel(title)
                    Text("Allowed: \(ToyFormat.number(range.lowerBound)) to \(ToyFormat.number(range.upperBound)) \(unit)")
                        .foregroundStyle(.secondary)
                }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            if let parsed = Double(draft), parsed.isFinite {
                                value = min(range.upperBound, max(range.lowerBound, parsed)); editing = false
                            }
                        }.disabled(Double(draft).map { !$0.isFinite } ?? true)
                    }
                }
            }.presentationDetents([.medium])
        }
    }
}

struct GlassControls<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            content.padding(10).background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 22))
        } else {
            GlassEffectContainer(spacing: 12) { content }
        }
    }
}
