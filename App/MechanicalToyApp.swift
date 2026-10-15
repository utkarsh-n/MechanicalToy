import SwiftUI
import MechanicalCore

@main
struct MechanicalToyApp: App {
    @State private var store = NotebookStore()
    @State private var navigation = ToyNavigation()
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).environment(navigation)
                .tint(ToyTheme.copper).preferredColorScheme(.dark)
        }
    }
}

@Observable @MainActor
final class ToyNavigation {
    var tab = 0
    var path: [WorkshopRoute] = []
    func open(_ kind: ExperimentKind) { tab = 0; path = [.experiment(kind)] }
    func openGearBench() { tab = 0; path = [.gearBench] }
}

enum WorkshopRoute: Hashable {
    case experiment(ExperimentKind)
    case gearBench
}

struct RootView: View {
    @Environment(ToyNavigation.self) private var navigation
    @Environment(NotebookStore.self) private var store
    @State private var sheet: RootSheet?
    @State private var roomModel = RoomLabModel()
    @State private var guided = GuidedLabSession()
    @State private var optics = InstrumentMotion()
    @AppStorage("mechanical.motionSurfaces") private var motionSurfaces = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            Tab("Workshop", systemImage: "gearshape.2", value: 0) {
                WorkshopView(showingSettings: Binding(get: { sheet == .settings }, set: { sheet = $0 ? .settings : nil }),
                             openGuidedLabs: { sheet = .guidedLabs })
            }
            Tab("Room", systemImage: "wind", value: 1) {
                NavigationStack {
                    if navigation.tab == 1 { RoomLabView(model: roomModel) }
                    else { ToyTheme.background.ignoresSafeArea() }
                }
            }
            Tab("Notebook", systemImage: "book.closed", value: 2) {
                NotebookView()
            }
        }
        .environment(guided)
        .environment(optics)
        .task(id: "\(scenePhase)|\(motionSurfaces)|\(reduceMotion)|\(navigation.tab)") {
            guard scenePhase == .active, motionSurfaces, !reduceMotion, navigation.tab != 2 else { optics.stop(); return }
            optics.stop()
            optics.start()
            let generation = optics.generation
            defer { optics.stop(generation: generation) }
            while !Task.isCancelled {
                optics.sample()
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .settings: ToySettingsView()
            case .guidedLabs: GuidedLabsView(start: startGuidedLab)
            }
        }
        .alert("Notebook", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func startGuidedLab(_ id: GuidedLabID) {
        guided.begin(id)
        let definition = GuidedLabDefinition.find(id)
        switch definition.destination {
        case .gearBench:
            navigation.openGearBench()
        case .gears:
            store.prepareGuidedConfiguration(definition.gearValues)
            navigation.open(.gears)
        case .airflow, .climate:
            guided.busy = true
            let revision = guided.revision
            Task {
                await roomModel.configure(for: id)
                guard guided.selected == id, guided.revision == revision else { return }
                guided.busy = false
                navigation.path = []
                navigation.tab = 1
            }
        }
    }
}

private enum RootSheet: String, Identifiable {
    case settings, guidedLabs
    var id: String { rawValue }
}
