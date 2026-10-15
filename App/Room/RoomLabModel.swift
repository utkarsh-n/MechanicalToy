import Foundation
import Observation
import MechanicalCore

enum RoomLabMode: String, CaseIterable, Identifiable {
    case airflow = "Airflow", climate = "Climate"
    var id: String { rawValue }
}

actor RoomFlowWorker {
    private var solver = RoomAirflow()
    init() { solver.reset(inputs: .init()) }
    func advance(seconds: Double, inputs: RoomFlowInputs) -> RoomFlowFrame {
        guard !Task.isCancelled else { return solver.frame() }
        solver.step(seconds: seconds, inputs: inputs)
        return solver.frame()
    }
    func reset(inputs: RoomFlowInputs) -> RoomFlowFrame {
        solver.reset(inputs: inputs)
        return solver.frame()
    }
}

@MainActor @Observable final class RoomLabModel {
    var mode: RoomLabMode = .airflow
    var paused = false
    var visible = false
    var flowInputs = RoomFlowInputs()
    var climateInputs = RoomEnvironmentInputs()
    var display: RoomFlowDisplay = .dye
    var climate = RoomEnvironment()
    var climateTimeScale: Double = 60
    var frame: RoomFlowFrame
    var generation = 0
    private(set) var configuring = false
    @ObservationIgnored let worker = RoomFlowWorker()
    @ObservationIgnored private var configurationToken: UUID?
    @ObservationIgnored private var configuredGuidedLabID: GuidedLabID?
    @ObservationIgnored private var suppressedFlowSignature: String?

    init() {
        var initial = RoomAirflow()
        initial.reset(inputs: .init())
        frame = initial.frame()
    }

    var flowSignature: String {
        "\(flowInputs.speed)|\(flowInputs.body.rawValue)|\(flowInputs.angle)|\(flowInputs.bodyX)|\(flowInputs.bodyY)"
    }

    func invalidatePendingWork() { generation += 1 }

    func advance(realSeconds: Double, manual: Bool = false) async {
        guard visible, !configuring, !Task.isCancelled, manual || !paused else { return }
        let requestedMode = mode
        let requestedGeneration = generation
        if requestedMode == .airflow {
            let newFrame = await worker.advance(seconds: realSeconds, inputs: flowInputs)
            guard visible, !Task.isCancelled, requestedMode == mode,
                  requestedGeneration == generation, manual || !paused else { return }
            if newFrame.time >= frame.time { frame = newFrame }
        } else {
            climate.step(seconds: realSeconds * climateTimeScale, inputs: climateInputs)
        }
    }

    func refreshFlow() async {
        guard visible, !configuring, !Task.isCancelled else { return }
        guard suppressedFlowSignature != flowSignature else { return }
        suppressedFlowSignature = nil
        let requestedGeneration = generation
        let newFrame = await worker.advance(seconds: 1 / 30, inputs: flowInputs)
        guard visible, !Task.isCancelled, requestedGeneration == generation else { return }
        if newFrame.time >= frame.time { frame = newFrame }
    }

    func reset() async {
        invalidatePendingWork()
        let requestedGeneration = generation
        if mode == .airflow {
            suppressedFlowSignature = flowSignature
            let newFrame = await worker.reset(inputs: flowInputs)
            guard requestedGeneration == generation, !Task.isCancelled else { return }
            invalidatePendingWork()
            frame = newFrame
        } else {
            climate = RoomEnvironment()
            climate.step(seconds: 0.01, inputs: climateInputs)
        }
    }

    /// Rebuild both experiments so a guided restart reproduces the same checkpoint.
    @discardableResult
    func configure(for id: GuidedLabID) async -> Bool {
        let definition = GuidedLabDefinition.find(id)
        guard definition.destination == .airflow || definition.destination == .climate,
              !Task.isCancelled else { return false }
        let token = UUID()
        configurationToken = token
        configuring = true
        invalidatePendingWork()
        paused = true
        mode = definition.destination == .airflow ? .airflow : .climate
        flowInputs = definition.flowSetup
        climateInputs = definition.climateSetup
        climate = RoomEnvironment()
        display = .dye
        climateTimeScale = 60
        configuredGuidedLabID = id
        suppressedFlowSignature = flowSignature
        let requestedGeneration = generation
        defer {
            if configurationToken == token {
                configuring = false
                configurationToken = nil
            }
        }
        let newFrame = await worker.reset(inputs: flowInputs)
        guard configurationToken == token, requestedGeneration == generation,
              !Task.isCancelled else { return false }
        // Invalidate any old refresh result queued before the reset was requested.
        invalidatePendingWork()
        frame = newFrame
        return true
    }

    @discardableResult
    func applyGuidedAction(_ action: GuidedLabAction) async -> Bool {
        guard visible, !configuring, !Task.isCancelled else { return false }
        switch action {
        case .none:
            return true
        case .runAirflow:
            guard mode == .airflow else { return false }
            invalidatePendingWork()
            paused = false
            return true
        case .doubleAirflow, .angleWing, .blockAirflow:
            guard mode == .airflow else { return false }
            invalidatePendingWork()
            if action == .doubleAirflow {
                flowInputs.speed = 10
            } else if action == .angleWing {
                flowInputs.speed = 5
                flowInputs.body = .wing
                flowInputs.angle = 15
            } else {
                flowInputs.body = .block
            }
            suppressedFlowSignature = flowSignature
            let requestedGeneration = generation
            let newFrame = await worker.advance(seconds: 1 / 30, inputs: flowInputs)
            guard visible, mode == .airflow, requestedGeneration == generation,
                  !Task.isCancelled else { return false }
            if newFrame.time >= frame.time { frame = newFrame }
            return true
        case .pauseAirflow:
            guard mode == .airflow else { return false }
            invalidatePendingWork()
            paused = true
            return true
        case .stepAirflow:
            guard mode == .airflow, paused else { return false }
            let requestedGeneration = generation
            let newFrame = await worker.advance(seconds: 0.1, inputs: flowInputs)
            guard visible, mode == .airflow, paused, requestedGeneration == generation,
                  !Task.isCancelled else { return false }
            if newFrame.time >= frame.time { frame = newFrame }
            return true
        case .advanceClosedClimate, .ventilateClimate, .enableAutoHeat, .advanceHeatedClimate:
            guard mode == .climate else { return false }
            invalidatePendingWork()
            paused = true
            switch action {
            case .advanceClosedClimate:
                climate.step(seconds: configuredGuidedLabID == .climateThermostat ? 900 : 600,
                             inputs: climateInputs)
            case .ventilateClimate:
                climateInputs.ventilationACH = 3
                climate.step(seconds: 600, inputs: climateInputs)
            case .enableAutoHeat:
                climateInputs.mode = .auto
                climate.step(seconds: 0.01, inputs: climateInputs)
            case .advanceHeatedClimate:
                climate.step(seconds: 600, inputs: climateInputs)
            default: break
            }
            return true
        default:
            return false
        }
    }
}
