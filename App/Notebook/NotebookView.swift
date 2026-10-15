import SwiftUI
import MechanicalCore

struct NotebookView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(ToyNavigation.self) private var navigation
    @State private var selected: SavedRun?
    @State private var pair: RunPair?
    private var comparableKinds: [ExperimentKind] {
        ExperimentKind.allCases.filter { kind in store.runs.filter { $0.kind == kind }.count > 1 }
    }
    var body: some View {
        NavigationStack {
            ToyScreen {
                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption(title: "Observe · change · compare")
                    Text("Your discoveries").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Keep a measurement, change one input, and see what moved.")
                        .font(.subheadline).foregroundStyle(ToyTheme.muted)
                }
                if store.runs.isEmpty {
                    ToyPanel(title: "Start a notebook") {
                        Image(systemName: "book.closed").font(.system(size: 38)).foregroundStyle(ToyTheme.copper).padding(.vertical, 10)
                        Text("Save any experiment with the bookmark button in its toolbar. Inputs, measurements, and your observations stay on this iPhone.")
                            .font(.subheadline).foregroundStyle(ToyTheme.muted)
                        Button("Explore the workshop", systemImage: "gearshape.2") { navigation.tab = 0 }
                            .buttonStyle(.glassProminent).frame(minHeight: 44)
                    }
                } else {
                    if !comparableKinds.isEmpty {
                        Menu {
                            ForEach(comparableKinds, id: \.self) { kind in
                                Button(ExperimentDefinition.find(kind).title) {
                                    let runs = store.runs.filter { $0.kind == kind }
                                    pair = RunPair(first: runs[1], second: runs[0])
                                }
                            }
                        } label: { Label("Compare two recent runs", systemImage: "arrow.left.arrow.right").frame(minHeight: 44) }
                        .buttonStyle(.glassProminent).accessibilityIdentifier("notebook.compare")
                    }
                    ForEach(store.runs) { run in
                        Button { selected = run } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: ExperimentDefinition.find(run.kind).symbol)
                                    .font(.title2).foregroundStyle(ToyTheme.copper).frame(width: 36, height: 44)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(run.title).font(.headline).foregroundStyle(ToyTheme.ink)
                                    Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(ToyTheme.muted)
                                    if let result = run.metrics.first {
                                        Text("\(result.label): \(ToyFormat.number(result.value)) \(result.unit)")
                                            .font(.system(.caption, design: .monospaced)).foregroundStyle(ToyTheme.cyan)
                                    }
                                    if !run.note.isEmpty { Text(run.note).font(.caption).foregroundStyle(ToyTheme.muted).lineLimit(2) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(ToyTheme.muted).padding(.top, 14)
                            }.padding(18).background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                        .accessibilityIdentifier("notebook.run.\(run.kind.rawValue)")
                    }
                }
            }
            .navigationTitle("Notebook").navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selected) { run in SavedRunView(run: run) }
        .sheet(item: $pair) { pair in CompareRunView(pair: pair) }
    }
}

private struct SavedRunView: View {
    let run: SavedRun
    @Environment(NotebookStore.self) private var store
    @Environment(ToyNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var note = ""
    private var currentRun: SavedRun { store.runs.first(where: { $0.id == run.id }) ?? run }
    var body: some View {
        NavigationStack {
            ToyScreen {
                Text(run.title).font(.largeTitle.bold())
                Text(run.date.formatted()).font(.subheadline).foregroundStyle(ToyTheme.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135))], spacing: 10) {
                    ForEach(run.metrics) { MetricTile(label: $0.label, value: ToyFormat.number($0.value), unit: $0.unit) }
                }
                ToyPanel(title: "Recorded inputs") {
                    ForEach(ExperimentDefinition.find(run.kind).parameters) { parameter in
                        LabeledContent(parameter.title, value: "\(ToyFormat.number(run.values[parameter.id] ?? parameter.defaultValue)) \(parameter.unit)")
                            .font(.subheadline)
                    }
                    Text("Recorded at \(ToyFormat.number(run.time)) simulation seconds.").font(.caption).foregroundStyle(ToyTheme.muted)
                }
                ToyPanel(title: "Observation") {
                    TextField("What did you notice?", text: $note, axis: .vertical).lineLimit(3...8)
                    Button("Save note") { store.updateNote(run, note: note) }.buttonStyle(.glass).frame(minHeight: 44)
                }
                Button("Restore this experiment", systemImage: "arrow.uturn.backward") {
                    store.restore(run); navigation.open(run.kind); dismiss()
                }.buttonStyle(.glassProminent).frame(minHeight: 44).accessibilityIdentifier("notebook.restore")
                ShareLink(item: currentRun.record) { Label("Share record", systemImage: "square.and.arrow.up").frame(minHeight: 44) }
                    .buttonStyle(.glass)
                Button("Delete record", role: .destructive) { confirmDelete = true }.frame(minHeight: 44)
            }
            .navigationTitle("Saved experiment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { note = run.note }
        .confirmationDialog("Delete this saved experiment?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.delete(run); dismiss() }
        }
    }
}

private struct RunPair: Identifiable {
    var id = UUID()
    var first: SavedRun
    var second: SavedRun
}

private struct CompareRunView: View {
    var pair: RunPair
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ToyScreen {
                Text(pair.first.title).font(.largeTitle.bold())
                Text("Previous → Latest").font(.headline).foregroundStyle(ToyTheme.copper)
                Text("\(pair.first.date.formatted(date: .omitted, time: .shortened)) → \(pair.second.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(ToyTheme.muted)
                ToyPanel(title: "What changed") {
                    ForEach(ExperimentDefinition.find(pair.first.kind).parameters) { parameter in
                        let a = pair.first.values[parameter.id] ?? parameter.defaultValue
                        let b = pair.second.values[parameter.id] ?? parameter.defaultValue
                        VStack(alignment: .leading, spacing: 4) {
                            Text(parameter.title).font(.subheadline.weight(.semibold))
                            Text("\(ToyFormat.number(a)) → \(ToyFormat.number(b)) \(parameter.unit)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(abs(a - b) > 0.0001 ? ToyTheme.copper : ToyTheme.muted)
                        }.padding(.vertical, 3)
                    }
                }
                ToyPanel(title: "Measured response") {
                    ForEach(pair.second.metrics) { result in
                        if let original = pair.first.metrics.first(where: { $0.id == result.id }) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(result.label).font(.subheadline.weight(.semibold))
                                Text("\(ToyFormat.number(original.value)) → \(ToyFormat.number(result.value)) \(result.unit)")
                                    .font(.system(.subheadline, design: .monospaced)).foregroundStyle(ToyTheme.cyan)
                                Text("Change: \(result.value - original.value >= 0 ? "+" : "")\(ToyFormat.number(result.value - original.value)) \(result.unit)")
                                    .font(.caption).foregroundStyle(ToyTheme.muted)
                            }.padding(.vertical, 5)
                        }
                    }
                }
                Text("For oscillators and rockets, time also changes the result. These runs were saved at \(ToyFormat.number(pair.first.time)) s and \(ToyFormat.number(pair.second.time)) s.")
                    .font(.footnote).foregroundStyle(ToyTheme.muted)
            }
            .navigationTitle("Compare runs").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
