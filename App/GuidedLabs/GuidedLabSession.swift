import Foundation
import Observation
import MechanicalCore

@Observable @MainActor
final class GuidedLabSession {
    var selected: GuidedLabID?
    var stepIndex = 0
    var applied = false
    var busy = false
    var finished = false
    var revision = UUID()

    var definition: GuidedLabDefinition? { selected.map(GuidedLabDefinition.find) }
    var currentStep: GuidedLabStep? {
        guard let definition, definition.steps.indices.contains(stepIndex) else { return nil }
        return definition.steps[stepIndex]
    }

    func begin(_ id: GuidedLabID) {
        selected = id; stepIndex = 0; applied = false; busy = false; finished = false
        revision = UUID()
    }

    func didApply() { applied = true; busy = false }

    func next() {
        guard !busy, let definition, let currentStep,
              applied || currentStep.action == .none
                || (definition.destination == .gearBench && currentStep.action.gearBenchSetup != nil) else { return }
        if stepIndex + 1 < definition.steps.count {
            stepIndex += 1; applied = false
        } else { finished = true }
    }

    func end() {
        selected = nil; stepIndex = 0; applied = false; busy = false; finished = false
        revision = UUID()
    }
}
