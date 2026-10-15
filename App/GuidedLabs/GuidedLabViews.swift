import SwiftUI
import MechanicalCore

struct GuidedLabReading: Identifiable {
    var label: String
    var value: String
    var unit: String
    var id: String { label }
}

/// Guidance stays beside the actual machine and its live measurements.
/// Applying an action records setup; it never asserts a sensor or physics test passed.
struct GuidedLabPanel: View {
    var session: GuidedLabSession
    var readings: [GuidedLabReading]
    var apply: () -> Void
    var restart: () -> Void

    var body: some View {
        if let definition = session.definition {
            ToyPanel(title: "Guided lab") {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: definition.symbol)
                        .font(.title3).foregroundStyle(ToyTheme.copper)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(definition.title).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(session.finished ? "\(definition.steps.count) steps explored" : stepCounter(definition))
                            .font(.caption.weight(.medium)).foregroundStyle(ToyTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if session.finished {
                    completed
                } else if let step = session.currentStep {
                    ProgressView(value: Double(session.stepIndex), total: Double(max(1, definition.steps.count)))
                        .tint(ToyTheme.copper)
                        .accessibilityLabel("Guide progress")
                        .accessibilityValue(stepCounter(definition))
                    Text(step.title).font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("guided.step.title")
                    Text(step.instructions).font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    expected(step.expected)
                    liveReadings
                    stepControls(step, definition: definition)
                }

                secondaryControls
            }
        }
    }

    private func stepCounter(_ definition: GuidedLabDefinition) -> String {
        "Step \(min(definition.steps.count, max(1, session.stepIndex + 1))) of \(definition.steps.count)"
    }

    private var completed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Lab explored", systemImage: "eye")
                .font(.title3.weight(.semibold)).foregroundStyle(ToyTheme.cyan)
                .accessibilityIdentifier("guided.finished")
            Text("Keep experimenting with the live controls, or restart the guide to compare what you observe.")
                .font(.subheadline).foregroundStyle(ToyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            liveReadings
        }
    }

    private func expected(_ response: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Expected response").font(.caption.weight(.semibold)).foregroundStyle(ToyTheme.copper)
            Text(response).font(.subheadline).foregroundStyle(ToyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guided.expected")
    }

    @ViewBuilder private var liveReadings: some View {
        if !readings.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("Live readings").font(.caption.weight(.semibold)).foregroundStyle(ToyTheme.muted)
                ForEach(readings) { reading in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(reading.label).font(.caption).foregroundStyle(ToyTheme.muted).fixedSize()
                            Spacer(minLength: 0)
                            readingValue(reading).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reading.label).font(.caption).foregroundStyle(ToyTheme.muted)
                            readingValue(reading).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("guided.reading.\(reading.id)")
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(ToyTheme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("guided.readings")
        }
    }

    private func readingValue(_ reading: GuidedLabReading) -> some View {
        Text("\(reading.value)\(reading.unit.isEmpty ? "" : " \(reading.unit)")")
            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
            .foregroundStyle(ToyTheme.cyan).monospacedDigit()
    }

    @ViewBuilder
    private func stepControls(_ step: GuidedLabStep, definition: GuidedLabDefinition) -> some View {
        let needsAction = requiresAction(step)
        let manualCheckpoint = definition.destination == .gearBench && step.action.gearBenchSetup != nil
        let canContinue = !session.busy && (!needsAction || session.applied || manualCheckpoint)
        let nextTitle = session.stepIndex + 1 >= definition.steps.count ? "Finish lab" : "Next step"

        if session.busy {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small).tint(ToyTheme.cyan)
                Text("Applying controls…").font(.caption).foregroundStyle(ToyTheme.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("guided.busy")
        } else if needsAction && session.applied {
            Text("Action applied. Watch the response, then continue.")
                .font(.caption).foregroundStyle(ToyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        } else if manualCheckpoint {
            Text("Use the live controls or apply the exact checkpoint, then observe before continuing.")
                .font(.caption).foregroundStyle(ToyTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }

        GlassControls {
            VStack(spacing: 10) {
                if needsAction {
                    Button {
                        guard !session.busy, !session.applied else { return }
                        apply()
                    } label: {
                        Label(step.actionTitle ?? "Apply this step", systemImage: "hand.tap")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(session.applied || session.busy)
                    .accessibilityIdentifier("guided.action")
                }
                Button {
                    guard canContinue else { return }
                    session.next()
                } label: {
                    Label(nextTitle, systemImage: session.stepIndex + 1 >= definition.steps.count ? "flag" : "arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
                .disabled(!canContinue)
                .accessibilityIdentifier("guided.next")
            }
        }
    }

    private func requiresAction(_ step: GuidedLabStep) -> Bool {
        if case .none = step.action { return false }
        return true
    }

    private var secondaryControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                restartButton
                Spacer(minLength: 0)
                endButton
            }
            VStack(alignment: .leading, spacing: 8) {
                restartButton
                endButton
            }
        }
    }

    private var restartButton: some View {
        Button {
            guard !session.busy else { return }
            restart()
        } label: {
            Label("Restart guide", systemImage: "arrow.counterclockwise")
                .font(.subheadline).frame(minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(session.busy)
        .accessibilityIdentifier("guided.restart")
    }

    private var endButton: some View {
        Button {
            guard !session.busy else { return }
            session.end()
        } label: {
            Text("End guide").font(.subheadline).frame(minHeight: 44)
        }
        .buttonStyle(.glass)
        .disabled(session.busy)
        .accessibilityIdentifier("guided.end")
    }
}

struct GuidedLabsView: View {
    var start: (GuidedLabID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var starting: GuidedLabID?

    var body: some View {
        NavigationStack {
            ToyScreen {
                VStack(alignment: .leading, spacing: 9) {
                    SectionCaption(title: "Set up · observe · change")
                    Text("Follow the cause and effect.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Each guide opens the working lab, sets its controls, and helps you inspect a response. Use the live controls to explore beyond the guide.")
                        .font(.subheadline).foregroundStyle(ToyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Gear bench").font(.title2.bold())
                ForEach(GuidedLabDefinition.catalog.filter { $0.destination == .gearBench }) { definition in
                    labCard(definition)
                }
                Text("Workshop & Room").font(.title2.bold())
                ForEach(GuidedLabDefinition.catalog.filter { $0.destination != .gearBench }) { definition in
                    labCard(definition)
                }
            }
            .navigationTitle("Guided labs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(starting != nil)
                }
            }
        }
        .accessibilityIdentifier("guided.catalog")
    }

    private func labCard(_ definition: GuidedLabDefinition) -> some View {
        ToyPanel(title: "") {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: definition.symbol)
                    .font(.system(size: 28)).foregroundStyle(ToyTheme.copper)
                    .frame(width: 40, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(definition.title).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(definition.subtitle).font(.subheadline).foregroundStyle(ToyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(definition.steps.count) guided steps")
                        .font(.caption).foregroundStyle(ToyTheme.muted)
                }
                Spacer(minLength: 0)
            }
            Button {
                guard starting == nil else { return }
                starting = definition.id
                start(definition.id)
                dismiss()
            } label: {
                Label("One-tap setup", systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(starting != nil)
            .accessibilityLabel("Start \(definition.title) with one-tap setup")
            .accessibilityIdentifier("guided.start.\(definition.id.rawValue)")
        }
    }
}
