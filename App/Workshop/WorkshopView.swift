import SwiftUI
import MechanicalCore

struct WorkshopView: View {
    @Environment(ToyNavigation.self) private var navigation
    @Environment(NotebookStore.self) private var store
    @Environment(InstrumentMotion.self) private var optics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @Binding var showingSettings: Bool
    var openGuidedLabs: () -> Void
    @State private var search = ""
    @State private var category: ExperimentCategory?
    @State private var favoritesOnly = false
    @State private var homeVisible = false
    @State private var heroVisible = false
    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 12)]

    private var filtered: [ExperimentDefinition] {
        ExperimentDefinition.catalog.filter {
            (category == nil || category == $0.category) &&
            (!favoritesOnly || store.favorites.contains($0.id)) &&
            (search.isEmpty || "\($0.title) \($0.subtitle) \($0.category.title) \($0.category.subtitle)".localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.path) {
            ToyScreen {
                if search.isEmpty && category == nil && !favoritesOnly {
                    introduction
                    guidedLabsButton
                    hero
                }
                filters
                if filtered.isEmpty {
                    ContentUnavailableView("No experiments found", systemImage: "magnifyingglass", description: Text("Try another search or choose All."))
                } else {
                    ForEach(ExperimentCategory.allCases, id: \.self) { group in
                        let items = filtered.filter { $0.category == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(group.title).font(.title2.bold())
                                    Spacer()
                                    Text("\(items.count)").font(.system(.caption, design: .monospaced)).foregroundStyle(ToyTheme.copper)
                                }
                                Text(group.subtitle).font(.subheadline).foregroundStyle(ToyTheme.muted)
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(items) { item in ExperimentCard(experiment: item, favorite: store.favorites.contains(item.id)) }
                                }
                            }
                        }
                    }
                }
                Text("Touch a machine. Change one thing. Watch what follows.")
                    .font(.footnote).foregroundStyle(ToyTheme.muted).padding(.vertical, 8)
            }
            .onAppear { homeVisible = true }
            .onDisappear { homeVisible = false }
            .navigationTitle("Mechanical Toy").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Find a mechanism or machine")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings and guide")
                }
            }
            .navigationDestination(for: WorkshopRoute.self) { route in
                switch route {
                case .experiment(let kind):
                    ExperimentDetailView(kind: kind, configuration: store.configuration(for: kind), revision: store.restoreRevision, startPaused: store.restoredKind == kind)
                        .id(store.restoreRevision)
                case .gearBench:
                    GearGalleryView(openGuidedLabs: openGuidedLabs)
                }
            }
        }
    }

    private var guidedLabsButton: some View {
        Button(action: openGuidedLabs) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard").font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Guided labs").font(.headline)
                    Text("\(GuidedLabDefinition.catalog.count) experiments · setup, steps, expected readings").font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
            }.padding(8).frame(minHeight: 44)
        }.buttonStyle(.glassProminent).accessibilityIdentifier("guided.open")
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MAKE THE INVISIBLE MOVE").font(.system(.caption, design: .monospaced, weight: .semibold))
                .tracking(1.8).foregroundStyle(ToyTheme.copper)
            Text("Everything starts with a moving part.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("A workbench for forces, machines, and the air around them.")
                .font(.subheadline).foregroundStyle(ToyTheme.muted)
        }
    }

    private var hero: some View {
        NavigationLink(value: WorkshopRoute.gearBench) {
          VStack(alignment: .leading, spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !homeVisible || !heroVisible || reduceMotion || scenePhase != .active || navigation.tab != 0 || !navigation.path.isEmpty)) { context in
                OpticalInstrumentSurface(tilt: optics.tilt, reducedMotion: reduceMotion) {
                    GearMetalStage(kind: .helical, inputs: GearTransmissionInputs(),
                        phase: reduceMotion ? 0.4 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) * 0.7,
                        tilt: SIMD2(Float(optics.tilt.x), Float(optics.tilt.y)), orbit: .zero,
                        exploded: 0, hologram: true, reducedMotion: reduceMotion, reducedTransparency: reduceTransparency)
                }.frame(height: 225).accessibilityHidden(true)
            }
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    SectionCaption(title: "New / Gear bench")
                    Text("Twelve ways to transmit motion").font(.headline).foregroundStyle(ToyTheme.ink)
                    Text("Orbit, separate, tilt. Catch the light.").font(.caption).foregroundStyle(ToyTheme.muted)
                }
                Spacer()
                Image(systemName: "arrow.up.right").frame(width: 44, height: 44).foregroundStyle(ToyTheme.cyan)
            }.padding(18)
          }
          .background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 26))
          .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(ToyTheme.cyan.opacity(0.25)))
        }
        .buttonStyle(.plain).accessibilityLabel("Open gear bench. Twelve interactive gear types.")
        .accessibilityIdentifier("gears.open")
        .onScrollVisibilityChange(threshold: 0.1) { heroVisible = $0 }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassControls {
                HStack(spacing: 8) {
                    filterButton("All", selected: category == nil && !favoritesOnly) { category = nil; favoritesOnly = false }
                    filterButton("Favorites", selected: favoritesOnly) { favoritesOnly.toggle() }
                    ForEach(ExperimentCategory.allCases, id: \.self) { group in
                        filterButton(group.title, selected: category == group) { category = category == group ? nil : group }
                    }
                }
            }.padding(.vertical, 3)
        }.contentMargins(.horizontal, 1)
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? ToyTheme.copper : ToyTheme.ink)
                .padding(.horizontal, 6).frame(minHeight: 44)
        }.buttonStyle(.glass).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ExperimentCard: View {
    var experiment: ExperimentDefinition
    var favorite: Bool
    var body: some View {
        NavigationLink(value: WorkshopRoute.experiment(experiment.id)) {
            VStack(alignment: .leading, spacing: 9) {
                MechanismStage(kind: experiment.id, values: MechanicalSolver.defaults(for: experiment.id), time: 0.6)
                    .frame(height: 114).accessibilityHidden(true).allowsHitTesting(false)
                HStack(alignment: .firstTextBaseline) {
                    Text(experiment.title).font(.headline).foregroundStyle(ToyTheme.ink)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(ToyTheme.copper) }
                }
                Text(experiment.subtitle).font(.caption).foregroundStyle(ToyTheme.muted)
                    .lineLimit(2).frame(minHeight: 30, alignment: .topLeading)
                HStack(spacing: 5) {
                    Image(systemName: "hand.draw").font(.caption)
                    Text("Explore").font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption)
                }.foregroundStyle(ToyTheme.copper)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(ToyTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.065)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(experiment.title). \(experiment.subtitle)\(favorite ? ". Favorite" : "")")
        .accessibilityIdentifier("experiment.\(experiment.id.rawValue)")
    }
}
