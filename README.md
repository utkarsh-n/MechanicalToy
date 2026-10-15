# Mechanical Toy

A native iPhone playground for touching, tilting, observing, and measuring mechanics. Requires iOS 27. Built with SwiftUI, Canvas, Metal, Core Motion, and AVFoundation. No server or account.

## Workshop

25 distinct experiments cover levers, pulleys, inclined planes, pendulums, springs, gears, slider cranks, hydraulics, flywheels, bicycles, differentials, suspension, gasoline and diesel engines, electric motors, steam engines, locomotives, high-speed trains, propellers, wings, helicopters, turbofans, rockets, wind turbines, and heat pumps. Each has an annotated cutaway, bounded physical inputs, live calculated results, a challenge, an equation, and model assumptions.

Drag the drawing to scrub time, use run/pause/step, adjust sliders or tap values for numeric input. Cutaway rotations are slowed independently from numerical RPM. Opt-in calibrated roll drives a selected parameter. Motion, acceleration, gyro, and optional barometric pressure report actual available hardware; simulator uses touch and says so. Sound is optional and respects silent mode. Haptic control detents are optional.

## Chrome / hologram gear bench

Open the new **Gear bench** card in Workshop. Twelve working setups explore spur, helical, double helical, bevel, screw (crossed helical), spiral bevel, worm, mitre, internal, rack and pinion, herringbone, and hypoid gears. Drag to orbit actual procedural 3D Metal geometry, separate the assembly, toggle its axes, and change tooth counts, rpm, torque, module, helix angle, and worm starts. Live values show direction, speed ratio, torque, rack speed/force, and ideal helical axial thrust. Motion is shown at one eighth speed. Gear teeth illustrate geometry rather than manufactured contact profiles.

Move the phone to shift studio reflections, viewing angle, spectral edges, and a refractive optical cover that actually samples the rendered image. A shared chrome housing and motion-sensitive highlights also dress the original cutaways and Room. **Guide & settings → Motion-reactive surfaces** turns optical motion off; **Recenter reflections** uses your current comfortable position. Optical motion does not change physical inputs. Core Motion runs only in the foreground; Reduce Motion disables automatic optics and rotation, while Step and drag remain available. Reduce Transparency bypasses refractive cover and spectral caustics. The rendered environment uses no camera or network.

## Room

Airflow uses a modest CPU-solved 2D incompressible grid, semi-Lagrangian advection, pressure projection, walls and a moveable solid body. Metal renders dye, speed, or vorticity. This low-resolution model teaches flow routing and wakes, not certified lift/drag or turbulent CFD. The environment model independently balances heat, ventilation, water vapor and CO₂, including occupants, thermostat, insulation, windows and outdoor conditions. Room quantities are simulated, not measured by the phone.

## Guided labs

Open **Workshop → Guided labs**, or use **Guided labs** inside the Gear bench, for eight experiments with one-tap setup and 31 guided steps. The four new gear guides are **Move the light, freeze the gears**, **Drive a spur pair**, **Many worm turns, one slow wheel**, and **Turn rotation into travel**. Each opens the live 3D bench with the relevant geometry, controls, playback, and expected readings. Optical tilt leaves mechanical inputs unchanged. Numerical checkpoint buttons restore a complete operating point; you can also use the crown and steppers yourself before continuing. **Restart guide** restores the initial setup. Completion records that the guide was explored, without claiming a physical sensor test passed.

The original **Tilt a gear pair**, **Shape an airstream**, **People and fresh air**, and **A thermostat meets an open window** remain available. The original tilt lab uses **Calibrate & run** to control speed with your phone, while the new optics lab keeps gear inputs fixed. Climate buttons advance exact simulated intervals while paused. See [gear-lab verification](Documentation/GearGuidedLabsVerification.md).

Fresh-air checkpoints are 850 then approximately 799 ppm. The cold-room guide shows about 18.0°C after cooling, then 18.4°C after ten minutes of heating at 3 kW, with an eventual proportional-controller equilibrium near 19.2°C. See [guided-lab verification](Documentation/GuidedLabsVerification.md).

## Notebook

Save inputs, simulation time, results, and notes. Restore any saved experiment paused at its captured state, compare the last two runs of a mechanism, and share a text record. Atomic local JSON persistence preserves unreadable archives without overwriting them. Generic city, touring, sports, and supercar presets illustrate differences in petrol engines, with additional diesel and electric-drive archetypes.

## Build

```sh
cd '/path/to/developer/Documents/AI Stuff/MechanicalToy'
xcodegen generate
swift test -Xswiftc -O
xcodebuild -project MechanicalToy.xcodeproj -scheme MechanicalToy -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/MechanicalToyDerivedData CODE_SIGNING_ALLOWED=NO build
```

The generated Xcode app targets iPhone only (device family 1, no Catalyst, Mac or XR designed-for-iPhone compatibility). A Foundation-only `MechanicalCore` Swift package supports fast numerical tests. See [the design](Documentation/Direction.md) and [verification](Documentation/Verification.md).

## References

- [Apple Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials): native navigation and control materials.
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): grouped native glass controls.
- [NASA: Lift equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/lift-equation/): dynamic pressure and lift coefficient.
- [NASA: Ideal rocket equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/ideal-rocket-equation/): exhaust velocity and mass ratio.
- [US DOE: Heat pump systems](https://www.energy.gov/energysaver/heat-pump-systems): moving heat between environments.

All models state simplifications inside the app. Observed simulator behavior, automated model tests, signed builds, and hands-on sensor/audio/haptic behavior are reported separately.


## Public snapshot

See [PUBLICATION.md](PUBLICATION.md) for publication exclusions and setup requirements.
