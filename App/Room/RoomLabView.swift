import SwiftUI
import MechanicalCore

struct RoomLabView: View {
    @State var model = RoomLabModel()
    @Environment(GuidedLabSession.self) private var guided
    @Environment(InstrumentMotion.self) private var optics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var running: Bool { model.visible && scenePhase == .active && !model.paused && !reduceMotion }

    var body: some View {
        @Bindable var model = model
        ToyScreen {
            VStack(alignment: .leading, spacing: 8) {
                SectionCaption(title: "The room is your experiment")
                Text("Make the invisible move.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Watch air find a path. Then balance heat, fresh air, humidity, and people.")
                    .font(.subheadline).foregroundStyle(ToyTheme.muted)
            }
            Picker("Room experiment", selection: $model.mode) {
                ForEach(RoomLabMode.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(guided.busy || model.configuring)

            OpticalInstrumentSurface(tilt: optics.tilt, reducedMotion: reduceMotion) {
                if model.mode == .airflow { airflowStage } else { climateStage }
            }
            if guidedMatchesMode {
                GuidedLabPanel(session: guided, readings: guidedReadings,
                               apply: applyGuidedStep, restart: restartGuidedLab)
            }
            playbackControls
            if reduceMotion {
                Label("Reduce Motion is on. Use Step to advance the model.", systemImage: "hand.tap")
                    .font(.caption).foregroundStyle(ToyTheme.muted)
            }
            if model.mode == .airflow {
                flowMetrics
                airflowControls
                airflowExplanation
            } else {
                climateMetrics
                climateControls
                climateExplanation
            }
        }
        .navigationTitle("Room")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.visible = true }
        .onDisappear { model.visible = false; model.invalidatePendingWork() }
        .onChange(of: model.mode) {
            if !model.configuring { model.invalidatePendingWork() }
            if let destination = guided.definition?.destination,
               destination == .airflow || destination == .climate, !guidedMatchesMode {
                guided.end()
            }
        }
        .onChange(of: model.paused) {
            if !model.configuring { model.invalidatePendingWork() }
        }
        .onChange(of: scenePhase) { model.invalidatePendingWork() }
        .onChange(of: reduceMotion) { model.invalidatePendingWork() }
        .task(id: "\(running)|\(model.mode.rawValue)|\(model.generation)") {
            guard running else { return }
            var lastTime = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                let dt = min(0.1, max(1 / 30, now - lastTime))
                lastTime = now
                await model.advance(realSeconds: dt)
                do { try await Task.sleep(for: .milliseconds(model.mode == .airflow ? 35 : 100)) }
                catch { return }
            }
        }
        .task(id: model.flowSignature) {
            if !running { await model.refreshFlow() }
        }
    }

    private var guidedMatchesMode: Bool {
        guard let destination = guided.definition?.destination else { return false }
        return (destination == .airflow && model.mode == .airflow)
            || (destination == .climate && model.mode == .climate)
    }

    private var guidedReadings: [GuidedLabReading] {
        if model.mode == .airflow {
            return [
                GuidedLabReading(label: "Inlet", value: ToyFormat.number(model.flowInputs.speed), unit: "m/s"),
                GuidedLabReading(label: "Mean", value: model.frame.meanSpeed.formatted(.number.precision(.fractionLength(1))), unit: "m/s"),
                GuidedLabReading(label: "Peak", value: model.frame.peakSpeed.formatted(.number.precision(.fractionLength(1))), unit: "m/s"),
                GuidedLabReading(label: "Time", value: model.frame.time.formatted(.number.precision(.fractionLength(1))), unit: "s")
            ]
        }
        return [
            GuidedLabReading(label: "Room", value: model.climate.temperature.formatted(.number.precision(.fractionLength(1))), unit: "°C"),
            GuidedLabReading(label: "CO₂", value: model.climate.co2PPM.formatted(.number.precision(.fractionLength(0))), unit: "ppm"),
            GuidedLabReading(label: "Heat", value: (model.climate.hvacPower / 1_000).formatted(.number.precision(.fractionLength(1))), unit: "kW"),
            GuidedLabReading(label: "Time", value: (model.climate.elapsed / 60).formatted(.number.precision(.fractionLength(1))), unit: "min")
        ]
    }

    private func applyGuidedStep() {
        guard guidedMatchesMode, !guided.busy, !guided.applied,
              let selected = guided.selected, let action = guided.currentStep?.action else { return }
        let revision = guided.revision
        guided.busy = true
        Task {
            let applied = await model.applyGuidedAction(action)
            guard guided.selected == selected, guided.revision == revision else { return }
            guided.busy = false
            if applied { guided.didApply() }
        }
    }

    private func restartGuidedLab() {
        guard guidedMatchesMode, !guided.busy, let selected = guided.selected else { return }
        guided.begin(selected)
        let revision = guided.revision
        guided.busy = true
        Task {
            _ = await model.configure(for: selected)
            guard guided.selected == selected, guided.revision == revision else { return }
            guided.busy = false
        }
    }

    private var airflowStage: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                AirflowFieldView(frame: model.frame, referenceSpeed: model.flowInputs.speed,
                                 display: model.display, reducedMotion: reduceMotion,
                                 tilt: SIMD2(Float(optics.tilt.x), Float(optics.tilt.y)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("WIND ROOM").font(.system(.caption2, design: .monospaced, weight: .bold)).tracking(1.5)
                    Text("12 × 8 m · \(model.frame.width) × \(model.frame.height) cells")
                        .font(.system(.caption2, design: .monospaced))
                }
                .padding(10).foregroundStyle(ToyTheme.ink)
                .background(ToyTheme.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .padding(12)
                VStack {
                    Spacer()
                    HStack {
                        Label("Inlet", systemImage: "arrow.right").font(.caption2)
                        Spacer()
                        Label("Outlet", systemImage: "arrow.right").font(.caption2)
                    }
                }.padding(14).foregroundStyle(ToyTheme.ink)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 8).onChanged { drag in
                model.flowInputs.bodyX = min(0.78, max(0.22, drag.location.x / geometry.size.width))
                model.flowInputs.bodyY = min(0.78, max(0.22, 1 - drag.location.y / geometry.size.height))
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Wind room with a \(model.flowInputs.body.title.lowercased()). Air flows from left to right around the body.\(AirflowFieldView.isMetalAvailable ? "" : " Software flow view. Metal is unavailable.")")
            .accessibilityValue("Mean speed \(model.frame.meanSpeed.formatted(.number.precision(.fractionLength(1)))) meters per second. Angle \(Int(model.flowInputs.angle)) degrees.")
            .accessibilityHint("Use the position and angle controls below to move the body.")
        }
        .aspectRatio(1.5, contentMode: .fit)
    }

    private var climateStage: some View {
        ClimateRoomStage(climate: model.climate, inputs: model.climateInputs)
            .aspectRatio(1.5, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A well mixed room with \(Int(model.climateInputs.occupants)) occupants.")
            .accessibilityValue("Temperature \(model.climate.temperature.formatted(.number.precision(.fractionLength(1)))) degrees Celsius, humidity \(Int(model.climate.relativeHumidity)) percent, carbon dioxide \(Int(model.climate.co2PPM)) parts per million.")
    }

    private var playbackControls: some View {
        GlassControls {
            HStack(spacing: 10) {
                Button {
                    model.paused.toggle()
                } label: {
                    Label(model.paused ? "Run" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill")
                        .frame(minHeight: 44)
                }.buttonStyle(.glassProminent).tint(ToyTheme.cyan)
                    .disabled(reduceMotion)
                Button {
                    Task { await model.advance(realSeconds: model.mode == .airflow ? 0.1 : 1, manual: true) }
                } label: {
                    Label("Step", systemImage: "forward.end.fill").frame(minHeight: 44)
                }.buttonStyle(.glass)
                    .disabled(!model.paused && !reduceMotion)
                    .accessibilityLabel(model.mode == .airflow ? "Advance airflow one tenth of a second" : "Advance climate \(Int(model.climateTimeScale)) seconds")
                Spacer(minLength: 0)
                Button {
                    Task { await model.reset() }
                } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).accessibilityLabel("Reset \(model.mode.rawValue.lowercased()) experiment")
            }
        }
        .disabled(guided.busy || model.configuring)
    }

    private var flowMetrics: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricTile(label: "Mean air speed", value: model.frame.meanSpeed.formatted(.number.precision(.fractionLength(1))), unit: "m/s")
                MetricTile(label: "Peak air speed", value: model.frame.peakSpeed.formatted(.number.precision(.fractionLength(1))), unit: "m/s", tint: ToyTheme.copper)
            }
            HStack {
                Text("Drag the chrome body to redirect the flow.")
                Spacer()
                Text("\(model.frame.time.formatted(.number.precision(.fractionLength(1)))) s").monospacedDigit()
            }.font(.caption).foregroundStyle(ToyTheme.muted)
        }
    }

    private var airflowControls: some View {
        @Bindable var model = model
        return ToyPanel(title: "Shape the flow") {
            Picker("Body", selection: $model.flowInputs.body) {
                ForEach(RoomBody.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Show field", selection: $model.display) {
                ForEach(RoomFlowDisplay.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Text(flowLegend).font(.caption).foregroundStyle(ToyTheme.muted)
            ToySlider(title: "Inlet speed", value: $model.flowInputs.speed, range: 0...14, unit: "m/s")
            ToySlider(title: "Body angle", value: $model.flowInputs.angle, range: -40...40, unit: "°")
            DisclosureGroup("Position controls") {
                ToySlider(title: "Across the room", value: $model.flowInputs.bodyX, range: 0.22...0.78, unit: "fraction")
                ToySlider(title: "Height in the room", value: $model.flowInputs.bodyY, range: 0.22...0.78, unit: "fraction")
            }.font(.subheadline)
        }
    }

    private var flowLegend: String {
        switch model.display {
        case .dye: "Cyan tracer bands are transported by the solved air velocity. Arrows show local direction."
        case .speed: "Dark is slower; cyan to amber is faster. Arrows show local direction."
        case .curl: "Amber is counterclockwise spin; blue is clockwise spin. This is vorticity, not turbulence."
        }
    }

    private var airflowExplanation: some View {
        ToyPanel(title: "Try a small change") {
            Text("Start with the wing at 0°. Increase its angle, move it toward a wall, then switch to a block. Where does air accelerate? Where does the tracer slow down?")
                .font(.subheadline)
            Text("∇ · u ≈ 0     ∂c/∂t + u · ∇c = 0")
                .font(.system(.subheadline, design: .monospaced)).foregroundStyle(ToyTheme.cyan)
            DisclosureGroup("How this room works") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A staggered grid advects velocity and tracers, then solves pressure to reduce divergence. The floor, ceiling, and chrome body block flow; the left side supplies air and the right side lets it out.")
                    Text("Mean divergence: \(model.frame.divergence.formatted(.number.precision(.fractionLength(3)))) s⁻¹. This reports the numerical residual, not a measured force.")
                        .monospacedDigit()
                    Text("This coarse 2D model uses artificial viscosity of 0.035 m²/s. It illustrates flow paths and blockage; it does not predict certified lift, drag, real turbulence, compressibility, or 3D vehicle aerodynamics. Phone sensors do not measure this airflow.")
                }.font(.caption).foregroundStyle(ToyTheme.muted).padding(.top, 8)
            }.font(.subheadline)
        }
    }

    private var climateMetrics: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricTile(label: "Room temperature", value: model.climate.temperature.formatted(.number.precision(.fractionLength(1))), unit: "°C", tint: ToyTheme.copper)
                MetricTile(label: "Relative humidity", value: model.climate.relativeHumidity.formatted(.number.precision(.fractionLength(0))), unit: "%")
            }
            HStack(spacing: 10) {
                MetricTile(label: "Carbon dioxide", value: model.climate.co2PPM.formatted(.number.precision(.fractionLength(0))), unit: "ppm")
                MetricTile(label: "Heating / cooling", value: (model.climate.hvacPower / 1_000).formatted(.number.precision(.fractionLength(1))), unit: "kW", tint: ToyTheme.green)
            }
            HStack {
                Text("\(model.climateInputs.airChangesPerHour.formatted(.number.precision(.fractionLength(1)))) air changes / hour")
                Spacer()
                Text("\((model.climate.elapsed / 60).formatted(.number.precision(.fractionLength(1)))) min elapsed")
            }.font(.caption).foregroundStyle(ToyTheme.muted).monospacedDigit()
        }
    }

    private var climateControls: some View {
        @Bindable var model = model
        return ToyPanel(title: "Balance the room") {
            Picker("Climate controller", selection: $model.climateInputs.mode) {
                ForEach(RoomClimateMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            ToySlider(title: "Thermostat", value: $model.climateInputs.targetTemperature, range: 15...28, unit: "°C")
            ToySlider(title: "Fresh air fan", value: $model.climateInputs.ventilationACH, range: 0...6, unit: "ACH")
            ToySlider(title: "Window opening", value: $model.climateInputs.windowOpening, range: 0...1, unit: "fraction")
            Stepper(value: $model.climateInputs.occupants, in: 0...8, step: 1) {
                Label("\(Int(model.climateInputs.occupants)) occupants", systemImage: "person.2")
            }.accessibilityLabel("Occupants").accessibilityValue("\(Int(model.climateInputs.occupants))")
            Picker("Simulation speed", selection: $model.climateTimeScale) {
                Text("1× time").tag(1.0)
                Text("1 min / sec").tag(60.0)
                Text("5 min / sec").tag(300.0)
            }.pickerStyle(.menu)
            DisclosureGroup("Outdoor air & insulation") {
                ToySlider(title: "Outdoor temperature", value: $model.climateInputs.outdoorTemperature, range: -15...40, unit: "°C")
                ToySlider(title: "Outdoor humidity", value: $model.climateInputs.outdoorHumidity, range: 5...100, unit: "%")
                ToySlider(title: "Envelope heat loss", value: $model.climateInputs.conductance, range: 20...300, unit: "W/K")
            }.font(.subheadline)
        }
    }

    private var climateExplanation: some View {
        ToyPanel(title: "Every control has a tradeoff") {
            Text("Add people with the fan off: heat, moisture, and CO₂ accumulate. Open the window: CO₂ approaches outdoor air, while the room moves toward the outdoor temperature. Let the thermostat work against that change.")
                .font(.subheadline)
            Text("C · dT/dt = Qhvac + Qpeople − UA · ΔT − ρcp · q · ΔT")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(ToyTheme.cyan)
            DisclosureGroup("Model & assumptions") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("One well-mixed 80 m³ zone, 650 kJ/K effective thermal mass, a 3 kW proportional heat/cool controller, and independent water-vapor and CO₂ balances. Outdoor CO₂ is fixed at 420 ppm. Each person adds 75 W, 54 g water/hour, and 18 L CO₂/hour. Window exchange is an illustrative linear 0–12 ACH.")
                    Text("Heating/cooling is signed: positive adds heat, negative removes it. Cooling has a simplified latent removal term. Condensed water: \((model.climate.condensedWater * 1_000).formatted(.number.precision(.fractionLength(1)))) g.")
                    Text("Envelope heat flow: \(Int(model.climate.envelopePower)) W. Ventilation heat flow: \(Int(model.climate.ventilationPower)) W. Negative values remove heat.")
                    Text("The climate room is separate from the airflow experiment. It does not resolve local temperature gradients or real HVAC equipment. These are simulated values; the iPhone is not measuring room temperature, humidity, or air quality. Use this model for learning, not engineering or health decisions.")
                }.font(.caption).foregroundStyle(ToyTheme.muted).padding(.top, 8)
            }.font(.subheadline)
        }
    }
}
