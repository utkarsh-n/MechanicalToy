import SwiftUI

struct ToySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mechanical.haptics") private var haptics = true
    @AppStorage("mechanical.motionSurfaces") private var motionSurfaces = true
    @Environment(InstrumentMotion.self) private var optics
    var body: some View {
        NavigationStack {
            Form {
                Section("Feel the controls") {
                    Toggle("Haptic feedback", isOn: $haptics)
                    Toggle("Motion-reactive surfaces", isOn: $motionSurfaces)
                        .accessibilityIdentifier("settings.motionSurfaces")
                    Button("Recenter reflections") { optics.recenter() }
                    Text("Move your iPhone to shift chrome reflections, holographic edges, and the view into the gear bench. Optical movement leaves the experiment’s inputs unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Light detents mark input changes. Sound is enabled separately inside each experiment.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("How to play") {
                    Label("Choose a mechanism. Drag its cutaway to inspect a cycle.", systemImage: "hand.draw")
                    Label("Change one input and watch the measurements respond.", systemImage: "slider.horizontal.3")
                    Label("Enable Tilt and calibrate your comfortable phone position.", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    Label("Save two runs and compare them in Notebook.", systemImage: "book.closed")
                }
                Section("The room") {
                    Text("Airflow explores a 2D grid with velocity, pressure projection, and transported smoke. Move and rotate a body to see the wake.")
                    Text("Climate explores room temperature, humidity, and carbon dioxide with a separate mass and heat balance model. The iPhone does not measure any of these room quantities.")
                }
                Section("Accessibility") {
                    Text("System Reduce Motion starts cutaways paused. Step and drag still work. System Reduce Transparency uses opaque surfaces where possible. Controls support VoiceOver, large text, and typed numeric values.")
                }
                Section("Models and privacy") {
                    Text("These are learning models. Each experiment lists its assumptions. Cutaway rotations are slowed for inspection, while measurements use the physical inputs.")
                    Text("No account, network service, or analytics. Notes are stored on this iPhone. Motion-reactive surfaces use phone movement while the app is visible and the setting is on. Experiment tilt and optional pressure have separate controls. All sensors stop when the app backgrounds.")
                    Text("Mechanical Toy · Native SwiftUI · Metal · Core Motion")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("References") {
                    Link("NASA: Lift and aerodynamics", destination: URL(string: "https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/lift-equation/")!)
                    Link("NASA: The ideal rocket equation", destination: URL(string: "https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/ideal-rocket-equation/")!)
                    Link("US Department of Energy: Heat pumps", destination: URL(string: "https://www.energy.gov/energysaver/heat-pump-systems")!)
                    Link("Apple: Liquid Glass design", destination: URL(string: "https://developer.apple.com/design/human-interface-guidelines/materials")!)
                }
            }
            .navigationTitle("Guide & settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
