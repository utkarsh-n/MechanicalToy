# Mechanical Toy

An iPhone-only native SwiftUI instrument for learning mechanics by touching, tilting, watching, and measuring.

## Visual direction

Dark midnight workbench, warm copper moving parts, cyan force and flow vectors, cream labels. Large moving cutaways sit above native controls. The machine is the hero. Quiet grid lines, visible pivots, scale marks, and synchronized measurements make the causal relationship legible. Glass is reserved for navigation and floating controls; explanatory content uses solid surfaces. Native iOS 27 SwiftUI tab bars, navigation, sliders, menus, sheets, and Liquid Glass buttons. Dynamic Type, VoiceOver descriptions, Reduce Motion, and Reduce Transparency are part of the design.

## Product

- Workshop: primitives, transmissions, road vehicles, rail, flight, and energy machines, each with its own model, interactive parameters, live measurements, an equation, a practical challenge, and stated assumptions.
- Room: airflow around moveable bodies plus a room environmental-control experiment. Real-time Metal rendering of a simplified 2D incompressible flow field and a separate lumped HVAC, humidity, and CO2 model.
- Notebook: save parameter snapshots and measured results, restore experiments, compare runs, and share a plain-text record.

## Interaction

Touch scrubs or drives the machine. Motion is opt-in, reports hardware availability, and maps calibrated phone tilt to a named simulation input. Manual controls always work. Haptics mark intentional control changes and mechanical events; optional sound conveys motion speed. Pause, reset, speed, and snapshot are accessible. Sensors stop outside the active experiment and when backgrounded. No sensor is presented as measuring airflow, forces, or room air quality.

## Numerical truth

Use equations with explicit units and bounds, conserve ideal power where applicable, handle zero drive, and show stall and physical limits. Teaching models are not engineering design tools. Animated cutaways are slowed for inspection independently of their numerical RPM. Test boundary behavior and directional relationships. Build, observed simulator interactions, signed device build, installation, and physical sensor/audio/haptic tests are separate evidence.
# Chrome / hologram instruments

Version 1.0 build 3 extends the midnight workbench with machined chrome, restrained spectral edges and a gravity-driven optical housing. The gear bench uses procedural depth-rendered Metal geometry and a sampled refractive cover; phone movement changes view and light independently from physical inputs. The original cutaways and Room retain clear forces, vectors and readings beneath their new chrome housing. Native Liquid Glass remains the control and navigation layer. Twelve gear setups, a drag-operated drive crown, orbit, separated assemblies, shaft arrows, live ratios and explicit model assumptions make every visible affordance causal.

