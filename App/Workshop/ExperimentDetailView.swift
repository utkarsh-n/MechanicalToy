import SwiftUI
import MechanicalCore

struct ExperimentDetailView: View {
    let kind: ExperimentKind
    private let revision: UUID
    @Environment(NotebookStore.self) private var store
    @Environment(GuidedLabSession.self) private var guided
    @Environment(InstrumentMotion.self) private var optics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mechanical.haptics") private var haptics = true
    @State private var values: [String: Double]
    @State private var time: Double
    @State private var playing = true
    @State private var speed = 1.0
    @State private var soundEnabled = false
    @State private var motionEnabled = false
    @State private var pressureEnabled = false
    @State private var motionParameter = ""
    @State private var motionBase = 0.0
    @State private var sensors = MotionInput()
    @State private var sound = MechanicalSound()
    @State private var saveNote: String? = nil
    @State private var showingSave = false
    @State private var savedCount = 0
    @State private var scrubStart: Double?
    @State private var active = false
    @State private var presetName = "Custom"

    init(kind: ExperimentKind, configuration: LabConfiguration, revision: UUID, startPaused: Bool) {
        self.kind = kind
        self.revision = revision
        _values = State(initialValue: configuration.values)
        _time = State(initialValue: configuration.time)
        _playing = State(initialValue: !startPaused && configuration.time == 0)
        _motionParameter = State(initialValue: ExperimentDefinition.find(kind).parameters.first?.id ?? "")
    }

    private var experiment: ExperimentDefinition { ExperimentDefinition.find(kind) }
    private var metrics: [MechanicalCore.Measurement] { MechanicalSolver.metrics(for: kind, values: values, time: time) }

    var body: some View {
        ToyScreen {
            VStack(alignment: .leading, spacing: 8) {
                SectionCaption(title: experiment.category.title)
                Text(experiment.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(experiment.subtitle).font(.subheadline).foregroundStyle(ToyTheme.muted)
            }
            stage
            transport
            if guided.selected == .tiltGears && kind == .gears {
                GuidedLabPanel(session: guided, readings: guidedReadings,
                               apply: applyGuidedStep, restart: restartGuidedLab)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                ForEach(metrics) { measurement in
                    MetricTile(label: measurement.label, value: ToyFormat.number(measurement.value), unit: measurement.unit)
                }
            }.accessibilityIdentifier("live.measurements")
            ToyPanel(title: "Change the machine") {
                if !MachinePreset.presets(for: kind).isEmpty {
                    Menu {
                        ForEach(MachinePreset.presets(for: kind)) { preset in
                            Button(preset.name) {
                                values = MechanicalSolver.normalizedValues(for: kind, values: preset.values)
                                time = 0; presetName = preset.name
                                sensors.calibrate(); setMotionBaseline(); saveNote = nil
                            }
                        }
                    } label: { Label("\(presetName == "Custom" ? "Load a machine preset" : presetName)", systemImage: "car.side").frame(minHeight: 44) }
                    .buttonStyle(.glass)
                    Text("Generic teaching archetypes; explore the inputs below to design your own.")
                        .font(.caption).foregroundStyle(ToyTheme.muted)
                }
                ForEach(experiment.parameters) { parameter in
                    ToySlider(title: parameter.title, value: parameterBinding(parameter), range: parameter.range, unit: parameter.unit)
                    if parameter.id != experiment.parameters.last?.id { Divider().overlay(.white.opacity(0.07)) }
                }
            }
            sensorPanel
            ToyPanel(title: "Try this") {
                Label(experiment.challenge, systemImage: "hand.point.up.left")
                    .font(.subheadline).foregroundStyle(ToyTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ToyPanel(title: experiment.principle) {
                Text(experiment.equation).font(.system(.headline, design: .monospaced))
                    .foregroundStyle(ToyTheme.copper).textSelection(.enabled)
                Text(experiment.explanation).font(.subheadline).foregroundStyle(ToyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("MODEL ASSUMPTIONS").font(.caption.weight(.semibold)).foregroundStyle(ToyTheme.muted)
                Text(experiment.limitations).font(.footnote).foregroundStyle(ToyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle(experiment.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFavorite(kind) } label: {
                    Image(systemName: store.favorites.contains(kind) ? "star.fill" : "star")
                }.accessibilityLabel(store.favorites.contains(kind) ? "Remove favorite" : "Add favorite")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { playing = false; showingSave = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Save experiment").accessibilityIdentifier("save.experiment")
            }
        }
        .onAppear {
            active = true
            if reduceMotion { playing = false }
            if motionEnabled { setMotionBaseline(); sensors.start(); if pressureEnabled { sensors.startPressure() } }
        }
        .onDisappear {
            active = false; stopServices()
            if revision == store.restoreRevision { store.remember(kind: kind, values: values, time: time) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopServices(); store.remember(kind: kind, values: values, time: time) }
            else if active && motionEnabled { setMotionBaseline(); sensors.start(); if pressureEnabled { sensors.startPressure() } }
        }
        .onChange(of: reduceMotion) { _, enabled in if enabled { playing = false; sound.stop() } }
        .onChange(of: playing) { _, enabled in if !enabled { sound.stop() } }
        .onChange(of: soundEnabled) { _, enabled in if !enabled { sound.stop() } }
        .task(id: "\(scenePhase)|\(active)") { await animate() }
        .sensoryFeedback(.success, trigger: savedCount) { _, _ in haptics }
        .sheet(isPresented: $showingSave) {
            SaveRunSheet(title: experiment.title) { note in
                if store.save(kind: kind, values: values, time: time, note: note) {
                    savedCount += 1; saveNote = "Saved to Notebook"
                } else {
                    saveNote = "Saved for this session"
                }
            }
        }
    }

    private var guidedReadings: [GuidedLabReading] {
        [GuidedLabReading(label: "Phone roll", value: sensors.hasReading ? ToyFormat.number(sensors.roll * 180 / .pi) : "—", unit: "°"),
         GuidedLabReading(label: "Input speed", value: ToyFormat.number(values["inputRPM"] ?? 0), unit: "rpm"),
         GuidedLabReading(label: "Output speed", value: ToyFormat.number(metrics.first(where: { $0.id == "outputRPM" })?.value ?? 0), unit: "rpm"),
         GuidedLabReading(label: "Motion", value: motionEnabled ? sensors.status : "Enable with Calibrate & run", unit: "")]
    }

    private func applyGuidedStep() {
        guard guided.selected == .tiltGears, !guided.busy, !guided.applied,
              let action = guided.currentStep?.action else { return }
        switch action {
        case .calibrateTilt:
            motionParameter = "inputRPM"
            motionEnabled = true
            sensors.start(); sensors.calibrate(); setMotionBaseline()
            playing = true
        case .pauseGear: playing = false
        case .resumeGear: playing = true
        default: return
        }
        guided.didApply()
    }

    private func restartGuidedLab() {
        stopServices()
        motionEnabled = false; pressureEnabled = false; soundEnabled = false
        values = GuidedLabDefinition.find(.tiltGears).gearValues
        time = 0; speed = 1; playing = false; motionParameter = "inputRPM"
        setMotionBaseline(); presetName = "Custom"; saveNote = nil
        guided.begin(.tiltGears)
    }

    private var stage: some View {
        VStack(spacing: 0) {
            OpticalInstrumentSurface(tilt: optics.tilt, reducedMotion: reduceMotion) {
              MechanismStage(kind: kind, values: values, time: time, tilt: optics.tilt)
                .frame(height: 285).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 5).onChanged { drag in
                    if scrubStart == nil { scrubStart = time; playing = false; sound.stop() }
                    time = max(0, (scrubStart ?? time) + Double(drag.translation.width) / 45)
                }.onEnded { _ in scrubStart = nil })
                .accessibilityAction(named: "Advance mechanism") { playing = false; time += 0.15 }
                .accessibilityAction(named: "Rewind mechanism") { playing = false; time = max(0, time - 0.15) }
            }
            HStack {
                Image(systemName: "hand.draw")
                Text("Drag to inspect the motion")
                Spacer()
                Text("\(ToyFormat.number(time)) s").monospacedDigit()
            }.font(.caption).foregroundStyle(ToyTheme.muted).padding(14)
        }
        .background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(ToyTheme.copper.opacity(0.18)))
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassControls {
                HStack(spacing: 10) {
                    Button { playing.toggle() } label: {
                        Label(playing ? "Pause" : "Run", systemImage: playing ? "pause.fill" : "play.fill")
                            .frame(minHeight: 44)
                    }.buttonStyle(.glassProminent).accessibilityIdentifier("transport.play")
                    Button { playing = false; time += 0.1 } label: {
                        Image(systemName: "forward.frame").frame(width: 44, height: 44)
                    }.buttonStyle(.glass).accessibilityLabel("Step forward")
                    Menu {
                        ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { rate in
                            Button("\(ToyFormat.number(rate))×") { speed = rate }
                        }
                    } label: {
                        Text("\(ToyFormat.number(speed))×").font(.system(.subheadline, design: .monospaced))
                            .frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.glass).accessibilityLabel("Animation speed, \(ToyFormat.number(speed)) times")
                    Spacer(minLength: 0)
                    Button {
                        values = MechanicalSolver.defaults(for: kind); time = 0
                        presetName = "Custom"
                        sensors.calibrate(); setMotionBaseline(); saveNote = nil
                    } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).accessibilityLabel("Reset experiment")
                }
            }
            if let saveNote { Label(saveNote, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(ToyTheme.green) }
            Text("Rotating cutaways are slowed for inspection; measurements use the selected physical inputs.")
                .font(.caption).foregroundStyle(ToyTheme.muted)
        }
    }

    private var sensorPanel: some View {
        ToyPanel(title: "Use your iPhone") {
            Toggle("Tilt controls the experiment", isOn: $motionEnabled)
                .disabled(!sensors.available)
                .onChange(of: motionEnabled) { _, enabled in
                    if enabled { setMotionBaseline(); sensors.start() }
                    else { sensors.stop(); pressureEnabled = false }
                }
            if sensors.available {
                Text(motionEnabled ? sensors.status : "Enable motion, hold the phone comfortably, then tilt left or right.")
                    .font(.footnote).foregroundStyle(ToyTheme.muted)
            } else {
                Label("Motion hardware is unavailable here. All experiments work with touch.", systemImage: "hand.tap")
                    .font(.footnote).foregroundStyle(ToyTheme.muted)
            }
            if motionEnabled {
                Picker("Tilt changes", selection: $motionParameter) {
                    ForEach(experiment.parameters) { Text($0.title).tag($0.id) }
                }.onChange(of: motionParameter) { _, _ in sensors.calibrate(); setMotionBaseline() }
                Button("Calibrate here", systemImage: "scope") { sensors.calibrate(); setMotionBaseline() }
                    .buttonStyle(.glass).frame(minHeight: 44)
                Text("±45° of calibrated roll changes the selected input by half its range. Pause freezes the machine and its inputs.")
                    .font(.caption).foregroundStyle(ToyTheme.muted)
                HStack {
                    MetricTile(label: "Phone roll", value: ToyFormat.number(sensors.roll * 180 / .pi), unit: "°")
                    MetricTile(label: "Acceleration", value: ToyFormat.number(sensors.acceleration), unit: "g")
                }
                MetricTile(label: "Gyroscope speed", value: ToyFormat.number(sensors.angularSpeed), unit: "rad/s")
                if sensors.pressureAvailable {
                    Toggle("Read ambient pressure", isOn: $pressureEnabled).onChange(of: pressureEnabled) { _, enabled in
                        if enabled { sensors.startPressure() } else { sensors.stopPressure() }
                    }
                    if let pressure = sensors.pressureKPa { MetricTile(label: "Measured pressure", value: ToyFormat.number(pressure), unit: "kPa") }
                    if let error = sensors.pressureError { Text(error).font(.caption).foregroundStyle(ToyTheme.copper) }
                    Text("Barometer values are observed only. The simulated atmosphere and room use their own inputs.")
                        .font(.caption).foregroundStyle(ToyTheme.muted)
                }
            }
            Divider()
            Toggle("Mechanical sound", isOn: $soundEnabled)
            Text("A quiet pulse follows the moving drive and stops at rest. Uses silent-mode settings and mixes with other audio.")
                .font(.caption).foregroundStyle(ToyTheme.muted)
            if let error = sound.error { Text(error).font(.caption).foregroundStyle(ToyTheme.copper) }
        }
    }

    private func parameterBinding(_ parameter: ParameterDefinition) -> Binding<Double> {
        Binding(get: { values[parameter.id] ?? parameter.defaultValue }, set: { newValue in
            values[parameter.id] = min(parameter.range.upperBound, max(parameter.range.lowerBound, newValue))
            if motionParameter == parameter.id { sensors.calibrate(); setMotionBaseline() }
            saveNote = nil
            presetName = "Custom"
        })
    }
    private func setMotionBaseline() { motionBase = values[motionParameter] ?? 0 }
    private func stopServices() { sensors.stop(); sound.stop() }
    private func animate() async {
        guard active, scenePhase == .active else { return }
        var last = ContinuousClock.now
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(33)) } catch { break }
            guard active, scenePhase == .active else { continue }
            let now = ContinuousClock.now
            let duration = last.duration(to: now).components
            let dt = min(0.1, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
            last = now
            guard playing else { continue }
            time += max(0, dt) * speed
            if motionEnabled {
                sensors.poll()
                if sensors.hasReading, let parameter = experiment.parameters.first(where: { $0.id == motionParameter }) {
                    let amount = sensors.roll / (.pi / 2) * (parameter.range.upperBound - parameter.range.lowerBound)
                    values[parameter.id] = min(parameter.range.upperBound, max(parameter.range.lowerBound, motionBase + amount))
                }
            }
            updateSound()
        }
    }

    private func updateSound() {
        guard soundEnabled else { sound.stop(); return }
        let current = metrics
        if kind == .flywheel, let rpm = current.first(where: { $0.id == "currentRPM" })?.value {
            sound.update(rate: max(1, rpm / 60), enabled: rpm > 0.01); return
        }
        if kind == .rocket, let thrust = current.first(where: { $0.id == "thrust" })?.value, thrust <= 0 {
            sound.stop(); return
        }
        let keys = ["inputRPM", "carrierRPM", "cadence", "rpm", "pullSpeed", "coreFlow", "massFlow", "wind", "speed", "power", "voltage"]
        let drive = keys.compactMap { key in experiment.parameters.first(where: { $0.id == key }) }.first
        guard let drive else { sound.stop(); return }
        let amount = values[drive.id] ?? drive.defaultValue
        let normalized = (amount - drive.range.lowerBound) / max(0.001, drive.range.upperBound - drive.range.lowerBound)
        sound.update(rate: 1 + normalized * 8, enabled: amount > 0.000_001)
    }
}

private struct SaveRunSheet: View {
    var title: String
    var save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                Text("Save the current inputs and measurements for \(title).")
                TextField("What did you notice?", text: $note, axis: .vertical).lineLimit(3...5)
            }
            .navigationTitle("Save experiment").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(note); dismiss() }.accessibilityIdentifier("save.confirm") }
            }
        }.presentationDetents([.medium, .large])
    }
}
