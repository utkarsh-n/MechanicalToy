# Shared implementation contracts

Core module: `MechanicalCore` (Foundation only). App deployment iOS 27, Swift 6.

`ExperimentKind: String, CaseIterable, Codable, Sendable` cases: lever, pulley, incline, pendulum, spring, gears, crank, hydraulics, flywheel, bicycle, differential, suspension, combustion, diesel, electricMotor, steam, locomotive, highSpeedTrain, propeller, wing, helicopter, turbofan, rocket, windTurbine, heatPump.

`ExperimentCategory: String, CaseIterable, Codable, Sendable` cases: foundations, transmissions, road, rail, flight, energy. Has `title: String` and `subtitle: String`.

`ExperimentDefinition: Identifiable, Sendable`: id (ExperimentKind), title, subtitle, category, symbol, principle, equation, explanation, challenge, limitations (all String except category/id); parameters [ParameterDefinition]. Static `catalog: [ExperimentDefinition]`; static `find(_ kind: ExperimentKind) -> ExperimentDefinition`.

`ParameterDefinition: Identifiable, Sendable`: id, title, unit (String), range (ClosedRange<Double>), defaultValue (Double).

`Measurement: Identifiable, Codable, Sendable`: id, label, unit (String), value (Double).

`MechanicalSolver.metrics(for kind: ExperimentKind, values: [String: Double], time: Double) -> [Measurement]`. `MechanicalSolver.defaults(for kind: ExperimentKind) -> [String: Double]`. Solver clamps invalid inputs. Agents may add public helpers.

Bench renderer owned by bench agent: `MechanismStage(kind: ExperimentKind, values: [String: Double], time: Double)` SwiftUI View. Frame supplied by parent. Renders unique annotated cutaways using Canvas; no timers or services inside. Parent handles a drag to scrub time. Agent may create support files under App/Rendering. Avoid dependencies on theme; colors local or `ToyTheme` names below.

Room owned by room agent: `RoomLabView()` SwiftUI View, owns its room model and lifetime. Core files `Room*.swift`, tests `RoomTests.swift`, App/Room/* (including Metal). Uses root theme or local colors. Accessible native controls, pause/reset, moveable obstacles, airflow and HVAC modes; no actual environmental sensor claims.

Root owns App shell, catalog/detail/notebook views, sensor/audio/haptic services, theme, project configuration and resources. Root theme: `ToyTheme.background`, `.panel`, `.ink`, `.muted`, `.copper`, `.cyan`, `.green`. `ToyPanel(title: String, content: () -> Content)` generic View. `ToySlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String)` generic native slider. `MetricTile(label: String, value: String, unit: String, tint: Color = ToyTheme.cyan)`.

Do not modify files owned by other agents. Write progress/API messages promptly. Core catalog parameter keys should be shared with renderer agent as soon as available. Do not build Xcode concurrently; root owns native build. Agents can run separate Swift package tests when coordinated.
