import Foundation
import Observation
import MechanicalCore

struct LabConfiguration: Codable {
    var values: [String: Double]
    var time: Double
}

struct SavedRun: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var kind: ExperimentKind
    var values: [String: Double]
    var time: Double
    var metrics: [MechanicalCore.Measurement]
    var note: String

    var title: String { ExperimentDefinition.find(kind).title }
    var record: String {
        let definition = ExperimentDefinition.find(kind)
        let inputs = definition.parameters.map { "\($0.title): \(ToyFormat.number(values[$0.id] ?? $0.defaultValue)) \($0.unit)" }.joined(separator: "\n")
        let results = metrics.map { "\($0.label): \(ToyFormat.number($0.value)) \($0.unit)" }.joined(separator: "\n")
        return "Mechanical Toy — \(title)\n\(date.formatted())\n\nINPUTS\n\(inputs)\n\nRESULTS AT \(ToyFormat.number(time)) s\n\(results)\n\n\(definition.equation)\n\(definition.limitations)\n\n\(note)"
    }
}

@Observable @MainActor
final class NotebookStore {
    private struct Archive: Codable {
        var version = 1
        var runs: [SavedRun] = []
        var sessions: [String: LabConfiguration] = [:]
        var favorites: Set<ExperimentKind> = []
    }
    private var archive = Archive()
    private let url: URL
    var error: String?
    var restoreRevision = UUID()
    var restoredKind: ExperimentKind?
    private var canPersist = true
    var runs: [SavedRun] { archive.runs }
    var favorites: Set<ExperimentKind> { archive.favorites }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appending(path: "MechanicalToy/notebook-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard loaded.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            archive = loaded
        } catch {
            canPersist = false
            self.error = "The saved notebook could not be read. Its file has been preserved; new changes are kept in memory for this session. \(error.localizedDescription)"
        }
    }

    func configuration(for kind: ExperimentKind) -> LabConfiguration {
        let cached = archive.sessions[kind.rawValue]
        return LabConfiguration(values: MechanicalSolver.normalizedValues(for: kind, values: cached?.values ?? [:]),
                                time: max(0, cached?.time ?? 0))
    }

    func remember(kind: ExperimentKind, values: [String: Double], time: Double) {
        archive.sessions[kind.rawValue] = LabConfiguration(values: MechanicalSolver.normalizedValues(for: kind, values: values), time: time.isFinite ? max(0, time) : 0)
        persist()
    }

    @discardableResult
    func save(kind: ExperimentKind, values: [String: Double], time: Double, note: String) -> Bool {
        let values = MechanicalSolver.normalizedValues(for: kind, values: values)
        let run = SavedRun(kind: kind, values: values, time: time,
                           metrics: MechanicalSolver.metrics(for: kind, values: values, time: time), note: note)
        archive.runs.insert(run, at: 0)
        return persist()
    }

    func restore(_ run: SavedRun) {
        remember(kind: run.kind, values: run.values, time: run.time)
        restoredKind = run.kind
        restoreRevision = UUID()
    }

    func prepareGuidedConfiguration(_ values: [String: Double]) {
        remember(kind: .gears, values: values, time: 0)
        restoredKind = .gears
        restoreRevision = UUID()
    }
    func delete(_ run: SavedRun) { archive.runs.removeAll { $0.id == run.id }; persist() }
    func updateNote(_ run: SavedRun, note: String) {
        guard let index = archive.runs.firstIndex(where: { $0.id == run.id }) else { return }
        archive.runs[index].note = note; persist()
    }
    func toggleFavorite(_ kind: ExperimentKind) {
        if archive.favorites.contains(kind) { archive.favorites.remove(kind) }
        else { archive.favorites.insert(kind) }; persist()
    }

    @discardableResult
    private func persist() -> Bool {
        guard canPersist else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            return true
        } catch {
            self.error = "Could not save the notebook. Changes are kept for this session: \(error.localizedDescription)"
            return false
        }
    }
}
