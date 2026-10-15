import SwiftUI
import MechanicalCore

struct GearGalleryView: View {
    var openGuidedLabs: () -> Void = {}
    @Environment(GuidedLabSession.self) private var guided
    @Environment(InstrumentMotion.self) private var optics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("mechanical.haptics") private var haptics = true
    @AppStorage("mechanical.motionSurfaces") private var motionSurfaces = true
    @State private var kind: GearKind = .spur
    @State private var inputs = GearTransmissionInputs()
    @State private var phase = 0.0
    @State private var playing = true
    @State private var visible = false
    @State private var stageVisible = false
    @State private var hologram = true
    @State private var exploded = 0.0
    @State private var orbit = SIMD2<Float>.zero
    @State private var orbitStart: SIMD2<Float>?
    @State private var showingCollection = false
    @State private var configuredGuideRevision: UUID?
    private var result: GearTransmissionResult { GearTransmission.solve(kind: kind, inputs: inputs) }
    private var running: Bool { visible && stageVisible && !showingCollection && scenePhase == .active && playing && !reduceMotion }

    var body: some View {
        ToyScreen {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionCaption(title: "Chrome / hologram")
                    Text(kind.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(kind.subtitle).font(.subheadline).foregroundStyle(ToyTheme.muted)
                }
                Spacer(minLength: 8)
                Button { showingCollection = true } label: {
                    Image(systemName: "square.grid.2x2").frame(width: 48, height: 48)
                }.buttonStyle(.glass).accessibilityLabel("Choose from 12 gear types")
                    .accessibilityIdentifier("gears.collection")
            }
            stage.onScrollVisibilityChange(threshold: 0.1) { stageVisible = $0 }
            transport
            if guidedMatchesBench {
                GuidedLabPanel(session: guided, readings: guidedReadings,
                               apply: applyGuidedStep, restart: restartGuidedLab)
            }
            Button(action: openGuidedLabs) {
                Label("Guided labs", systemImage: "list.bullet.clipboard")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.glass).accessibilityIdentifier("gears.guidedLabs")
            gearSelector
            readings
            ToyPanel(title: "Make a change") {
                TransmissionDriveControl(inputRPM: $inputs.inputRPM,
                    outputLabel: kind.isRack ? "Rack speed" : "Output speed",
                    outputValue: "\(ToyFormat.number(kind.isRack ? result.rackSpeedMMPerSecond : result.outputRPM)) \(kind.isRack ? "mm/s" : "rpm")",
                    tilt: optics.tilt, reducedMotion: reduceMotion)
                ToySlider(title: "Input speed", value: $inputs.inputRPM, range: 0...240, unit: "rpm")
                if kind != .worm {
                    Stepper(value: $inputs.driverTeeth, in: 12...40, step: 1) {
                        Text("Input · \(Int(inputs.driverTeeth)) teeth").monospacedDigit()
                    }.accessibilityIdentifier("gears.driverTeeth")
                }
                if kind != .rackAndPinion && kind != .mitre {
                    Stepper(value: $inputs.drivenTeeth, in: drivenRange, step: 1) {
                        Text("\(kind == .worm ? "Wheel" : "Output") · \(Int(inputs.drivenTeeth)) teeth").monospacedDigit()
                    }.accessibilityIdentifier("gears.drivenTeeth")
                }
                if kind == .mitre { Text("Mitre pairs have equal tooth counts: 1:1.").font(.caption).foregroundStyle(ToyTheme.cyan) }
                if kind == .worm {
                    Stepper(value: $inputs.wormStarts, in: 1...4, step: 1) {
                        Text("Worm · \(Int(inputs.wormStarts)) starts").monospacedDigit()
                    }
                }
                if kind.showsAxialForceEstimate {
                    ToySlider(title: "Helix angle", value: $inputs.helixAngleDegrees, range: 10...40, unit: "°")
                }
                ToySlider(title: "Separate the assembly", value: $exploded, range: 0...1, unit: "")
                    .accessibilityIdentifier("gears.exploded")
                DisclosureGroup("Torque, tooth size & efficiency") {
                    ToySlider(title: "Input torque", value: $inputs.inputTorque, range: 0...20, unit: "N·m")
                    ToySlider(title: "Transverse module", value: $inputs.moduleMM, range: 1...6, unit: "mm")
                    ToySlider(title: "Efficiency", value: $inputs.efficiency, range: 0.3...1, unit: "fraction")
                }.font(.subheadline)
            }
            ToyPanel(title: "What the teeth are doing") {
                Label(kind.axesDescription, systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(ToyTheme.cyan)
                Text(kind.explanation).font(.subheadline)
                Text(kind.application).font(.subheadline).foregroundStyle(ToyTheme.muted)
                Text(result.equation).font(.system(.subheadline, design: .monospaced)).foregroundStyle(ToyTheme.cyan)
                DisclosureGroup("Assumptions & limits") {
                    Text(result.assumptions + "\n\n" + kind.caution + "\n\nThe 3D teeth are schematic surfaces, not manufactured involute contact profiles. The view fits each assembly to the screen; module changes physical size and force readings. Rack graphics repeat along a short track, while the reading is continuous speed. Chrome reflections use a rendered studio environment. The optical cover refracts the rendered image; it does not use the camera.")
                        .font(.caption).foregroundStyle(ToyTheme.muted).padding(.top, 8)
                }.font(.subheadline)
                Link("Gear geometry reference · KHK", destination: URL(string: "https://khkgears.net/new/gear_knowledge/gear_technical_reference/types_of_gears.html")!)
                    .font(.caption)
            }
        }
        .navigationTitle("Gear bench").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            visible = true
            configureGuidedLab()
            if reduceMotion { playing = false }
        }
        .onDisappear { visible = false }
        .onChange(of: guided.revision) { configureGuidedLab() }
        .onChange(of: reduceMotion) { _, value in if value { playing = false } }
        .onChange(of: inputs.driverTeeth) { normalize() }
        .onChange(of: inputs.drivenTeeth) { normalize() }
        .task(id: running) {
            guard running else { return }
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                let dt = min(0.1, max(0, now - previous)); previous = now
                phase += dt * inputs.inputRPM * 2 * .pi / 60 / 8
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
        }
        .sensoryFeedback(.selection, trigger: kind) { _, _ in haptics }
        .sheet(isPresented: $showingCollection) {
            GearCollectionView(selected: kind) { choose($0) }
        }
    }

    private var drivenRange: ClosedRange<Double> {
        (kind == .internalGear ? inputs.driverTeeth + 4 : 12)...80
    }

    private var guidedMatchesBench: Bool { guided.definition?.destination == .gearBench }

    private var guidedReadings: [GuidedLabReading] {
        var values = [
            GuidedLabReading(label: "Input speed", value: ToyFormat.number(inputs.inputRPM), unit: "rpm"),
            GuidedLabReading(label: kind.isRack ? "Rack speed" : "Output speed",
                             value: ToyFormat.number(kind.isRack ? result.rackSpeedMMPerSecond : result.outputRPM),
                             unit: kind.isRack ? "mm/s" : "rpm"),
            GuidedLabReading(label: kind.isRack ? "Rack force" : "Output torque",
                             value: ToyFormat.number(kind.isRack ? result.rackForceNewtons : result.outputTorque),
                             unit: kind.isRack ? "N" : "N·m"),
            GuidedLabReading(label: kind.isRack ? "Pitch diameter" : "Speed reduction",
                             value: ToyFormat.number(kind.isRack ? inputs.driverTeeth * inputs.moduleMM : result.ratio),
                             unit: kind.isRack ? "mm" : ":1")
        ]
        if guided.selected == .gearOptics {
            values += [
                GuidedLabReading(label: "Animation", value: reduceMotion ? "Step only · Reduce Motion" : (playing ? "Running" : "Paused"), unit: ""),
                GuidedLabReading(label: "Phone reflections", value: reduceMotion ? "Off · Reduce Motion" : (motionSurfaces ? optics.status : "Off · enable in settings"), unit: ""),
                GuidedLabReading(label: "Refraction", value: reduceTransparency ? "Off · Reduce Transparency" : "Cover enabled", unit: ""),
                GuidedLabReading(label: "Holo", value: hologram ? "On" : "Off", unit: "")
            ]
        }
        return values
    }

    private func configureGuidedLab() {
        guard guidedMatchesBench, configuredGuideRevision != guided.revision,
              let setup = guided.definition?.gearBenchSetup else { return }
        configuredGuideRevision = guided.revision
        apply(setup, resetView: true)
        if guided.selected == .gearOptics {
            if !reduceMotion { motionSurfaces = true }
            optics.recenter()
        }
    }

    private func applyGuidedStep() {
        guard guidedMatchesBench, !guided.busy, !guided.applied,
              let action = guided.currentStep?.action else { return }
        if action == .recenterGearOptics {
            playing = false
            if !reduceMotion { motionSurfaces = true }
            optics.recenter()
        } else if let setup = action.gearBenchSetup {
            apply(setup, resetView: false)
        } else { return }
        guided.didApply()
    }

    private func apply(_ setup: GuidedGearSetup, resetView: Bool) {
        let geometryChanged = kind != setup.kind
            || inputs.driverTeeth != setup.inputs.driverTeeth
            || inputs.drivenTeeth != setup.inputs.drivenTeeth
            || inputs.moduleMM != setup.inputs.moduleMM
            || inputs.helixAngleDegrees != setup.inputs.helixAngleDegrees
            || inputs.wormStarts != setup.inputs.wormStarts
        kind = setup.kind
        inputs = setup.inputs
        playing = !setup.startsPaused && !reduceMotion
        if resetView || geometryChanged { phase = 0 }
        if resetView {
            orbit = .zero; orbitStart = nil; exploded = 0; hologram = true
            showingCollection = false
        }
    }

    private func restartGuidedLab() {
        guard guidedMatchesBench, !guided.busy, let selected = guided.selected else { return }
        guided.begin(selected)
        configureGuidedLab()
    }

    private var stage: some View {
        VStack(spacing: 10) {
            OpticalInstrumentSurface(tilt: optics.tilt, reducedMotion: reduceMotion) {
                GearMetalStage(kind: kind, inputs: inputs, phase: phase,
                               tilt: SIMD2(Float(optics.tilt.x), Float(optics.tilt.y)), orbit: orbit,
                               exploded: exploded, hologram: hologram, reducedMotion: reduceMotion,
                               reducedTransparency: reduceTransparency)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                        if orbitStart == nil { orbitStart = orbit }
                        let start = orbitStart ?? .zero
                        orbit = SIMD2(start.x + Float(value.translation.width / 180),
                                      min(0.75, max(-0.75, start.y + Float(value.translation.height / 220))))
                    }.onEnded { _ in orbitStart = nil })
                    .accessibilityElement()
                    .accessibilityLabel("\(kind.title) three dimensional transmission")
                    .accessibilityValue("\(result.directionDescription). \(hologram ? "Axis overlay visible" : "Chrome view").")
                    .accessibilityAction(named: "Rotate view left") { orbit.x -= 0.25 }
                    .accessibilityAction(named: "Rotate view right") { orbit.x += 0.25 }
                    .accessibilityAction(named: "Separate assembly") { exploded = exploded > 0 ? 0 : 0.7 }
                    .accessibilityIdentifier("gears.stage")
            }.frame(height: 330)
            HStack(spacing: 6) {
                Image(systemName: "hand.draw")
                Text("Drag to orbit · move iPhone to catch the light")
                Spacer(minLength: 0)
            }.font(.caption).foregroundStyle(ToyTheme.muted)
            Label(optics.status, systemImage: optics.hasReading ? "iphone.radiowaves.left.and.right" : "viewfinder")
                .font(.caption2).foregroundStyle(ToyTheme.cyan)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 9) {
            GlassControls {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { transportButtons }
                    VStack(alignment: .leading, spacing: 8) { transportButtons }
                }
            }
            Text(reduceMotion ? "Reduce Motion is on. Step advances the mechanism; drag still orbits the view." : "Motion shown at ⅛ speed. Readings use the selected rpm.")
                .font(.caption).foregroundStyle(ToyTheme.muted)
        }
    }

    @ViewBuilder private var transportButtons: some View {
        Button { playing.toggle() } label: {
            Label(playing ? "Pause" : "Run", systemImage: playing ? "pause.fill" : "play.fill").frame(minHeight: 44)
        }.buttonStyle(.glassProminent).disabled(reduceMotion).accessibilityIdentifier("gears.play")
        Button { playing = false; phase += .pi / 18 } label: {
            Image(systemName: "forward.frame").frame(width: 44, height: 44)
        }.buttonStyle(.glass).accessibilityLabel("Step gear motion").accessibilityIdentifier("gears.step")
        Button { hologram.toggle() } label: {
            Label("Holo", systemImage: hologram ? "viewfinder.circle.fill" : "viewfinder.circle").frame(minHeight: 44)
        }.buttonStyle(.glass).accessibilityValue(hologram ? "On" : "Off").accessibilityIdentifier("gears.axes")
        Button { orbit = .zero; exploded = 0; optics.recenter() } label: {
            Image(systemName: "scope").frame(width: 44, height: 44)
        }.buttonStyle(.glass).accessibilityLabel("Recenter view and reflections").accessibilityIdentifier("gears.recenter")
    }

    private var gearSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GearKind.allCases) { gear in
                    Button { choose(gear) } label: {
                        Text("\(gear.index + 1) · \(gear.title)").font(.subheadline.weight(gear == kind ? .semibold : .regular))
                            .foregroundStyle(gear == kind ? ToyTheme.cyan : ToyTheme.ink)
                            .padding(.horizontal, 8).frame(minHeight: 44)
                    }.buttonStyle(.glass).accessibilityAddTraits(gear == kind ? .isSelected : [])
                        .accessibilityIdentifier("gears.select.\(gear.rawValue)")
                }
            }.padding(.vertical, 4)
        }
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(result.directionDescription, systemImage: kind.isRack ? "arrow.left.and.right" : "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.subheadline.weight(.medium)).foregroundStyle(ToyTheme.cyan)
            HStack(spacing: 10) {
                MetricTile(label: "Input", value: ToyFormat.number(inputs.inputRPM), unit: "rpm")
                MetricTile(label: kind.isRack ? "Rack speed" : "Output", value: ToyFormat.number(kind.isRack ? result.rackSpeedMMPerSecond : result.outputRPM), unit: kind.isRack ? "mm/s" : "rpm", tint: ToyTheme.copper)
            }
            HStack(spacing: 10) {
                MetricTile(label: kind.isRack ? "Rack force" : "Output torque", value: ToyFormat.number(kind.isRack ? result.rackForceNewtons : result.outputTorque), unit: kind.isRack ? "N" : "N·m")
                if kind.showsAxialForceEstimate {
                    MetricTile(label: kind == .helical || kind == .screw ? "Input axial thrust" : "Ideal net axial force", value: ToyFormat.number(result.axialForceNewtons), unit: "N", tint: ToyTheme.green)
                } else {
                    MetricTile(label: kind.isRack ? "Pitch diameter" : "Speed reduction", value: ToyFormat.number(kind.isRack ? inputs.driverTeeth * inputs.moduleMM : result.ratio), unit: kind.isRack ? "mm" : ":1", tint: ToyTheme.green)
                }
            }
        }.accessibilityIdentifier("gears.readings")
    }

    private func normalize() { inputs = GearTransmission.normalizedInputs(kind: kind, inputs: inputs) }
    private func choose(_ choice: GearKind) {
        if guidedMatchesBench { guided.end() }
        kind = choice; inputs = GearTransmissionInputs()
        if choice == .worm { inputs.inputRPM = 120 }
        if choice == .internalGear { inputs.drivenTeeth = 48 }
        if choice == .rackAndPinion { inputs.driverTeeth = 16 }
        normalize(); phase = 0; orbit = .zero; exploded = 0
    }
}

private struct GearCollectionView: View {
    let selected: GearKind
    let choose: (GearKind) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ToyScreen {
                Text("Twelve ways to transmit motion").font(.title2.bold())
                Text("Choose a pair, turn it, then separate its axes. Each model opens with a working setup.")
                    .font(.subheadline).foregroundStyle(ToyTheme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(GearKind.allCases) { gear in
                        Button { choose(gear); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                GearTypeGlyph(kind: gear).frame(height: 80).accessibilityHidden(true)
                                Text("\(gear.index + 1) / \(gear.title)").font(.headline).foregroundStyle(ToyTheme.ink)
                                Text(gear.axesDescription).font(.caption).foregroundStyle(ToyTheme.muted)
                            }.padding(14).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                                .background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(gear == selected ? ToyTheme.cyan : .white.opacity(0.12)))
                        }.buttonStyle(.plain).accessibilityIdentifier("gears.catalog.\(gear.rawValue)")
                    }
                }
            }.navigationTitle("Gear collection").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct GearTypeGlyph: View {
    let kind: GearKind
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.height * 0.34, size.width * 0.25)
            func ring(_ c: CGPoint, _ r: Double, _ inward: Bool = false) {
                var path = Path()
                for i in 0...64 {
                    let angle = Double(i) * .pi / 32
                    let tip = i % 4 < 2
                    let rr = r * (tip ? 1 : 0.85)
                    let point = CGPoint(x: c.x + cos(angle) * rr, y: c.y + sin(angle) * rr)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.fill(path, with: .linearGradient(Gradient(colors: [ToyTheme.ink, ToyTheme.muted, ToyTheme.panel, ToyTheme.ink]), startPoint: CGPoint(x: c.x-r, y: c.y-r), endPoint: CGPoint(x: c.x+r, y: c.y+r)))
                context.stroke(path, with: .color(ToyTheme.cyan.opacity(0.7)), lineWidth: 1)
                let bore = Path(ellipseIn: CGRect(x: c.x-r*0.32, y: c.y-r*0.32, width: r*0.64, height: r*0.64))
                context.fill(bore, with: .color(ToyTheme.background))
            }
            if kind == .rackAndPinion {
                ring(CGPoint(x: center.x, y: center.y-9), radius)
                let rail = Path(roundedRect: CGRect(x: center.x-radius*1.6, y: center.y+radius-9, width: radius*3.2, height: 9), cornerRadius: 2)
                context.fill(rail, with: .color(ToyTheme.muted))
            } else if kind == .worm || kind == .screw {
                ring(CGPoint(x: center.x+15, y: center.y+10), radius)
                let rail = Path(roundedRect: CGRect(x: center.x-radius*1.5, y: center.y-radius-7, width: radius*3, height: 15), cornerRadius: 6)
                context.fill(rail, with: .color(ToyTheme.muted))
                for x in stride(from: center.x-radius, to: center.x+radius, by: 8) {
                    var line = Path(); line.move(to: CGPoint(x: x, y: center.y-radius-7)); line.addLine(to: CGPoint(x: x+6, y: center.y-radius+8))
                    context.stroke(line, with: .color(ToyTheme.ink), lineWidth: 2)
                }
            } else if kind == .internalGear {
                let outer = Path(ellipseIn: CGRect(x: center.x-radius*1.3, y: center.y-radius*1.3, width: radius*2.6, height: radius*2.6))
                context.stroke(outer, with: .color(ToyTheme.muted), lineWidth: 8)
                ring(CGPoint(x: center.x+radius*0.45, y: center.y), radius*0.5)
            } else {
                ring(CGPoint(x: center.x-radius*0.58, y: center.y+6), radius)
                ring(CGPoint(x: center.x+radius*0.85, y: center.y-6), radius*0.62)
                if kind != .spur {
                    var stripe = Path(); stripe.move(to: CGPoint(x: center.x-radius*1.1, y: center.y+radius*0.4)); stripe.addLine(to: CGPoint(x: center.x, y: center.y-radius*0.4))
                    context.stroke(stripe, with: .color(ToyTheme.cyan.opacity(0.8)), lineWidth: 2)
                }
            }
        }
    }
}
