import XCTest
@testable import MechanicalCore

final class MechanicalSolverTests: XCTestCase {
    private func readings(_ kind: ExperimentKind, _ overrides: [String: Double] = [:], time: Double = 0) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: MechanicalSolver.metrics(for: kind, values: overrides, time: time).map { ($0.id, $0.value) })
    }

    private func reading(_ kind: ExperimentKind, _ id: String, _ overrides: [String: Double] = [:], time: Double = 0) -> Double {
        readings(kind, overrides, time: time)[id]!
    }

    func testCatalogIsCompleteUniqueAndInputsAreValid() {
        XCTAssertEqual(ExperimentDefinition.catalog.count, ExperimentKind.allCases.count)
        XCTAssertEqual(Set(ExperimentDefinition.catalog.map(\.id)), Set(ExperimentKind.allCases))
        for entry in ExperimentDefinition.catalog {
            XCTAssertFalse(entry.title.isEmpty)
            XCTAssertFalse(entry.equation.isEmpty)
            XCTAssertFalse(entry.challenge.isEmpty)
            XCTAssertFalse(entry.limitations.isEmpty)
            XCTAssertEqual(Set(entry.parameters.map(\.id)).count, entry.parameters.count)
            for parameter in entry.parameters {
                XCTAssertTrue(parameter.range.contains(parameter.defaultValue), "\(entry.id): \(parameter.id)")
            }
        }
    }

    func testAllModelsAreFiniteAtDefaultsBoundsAndInvalidInputs() {
        for kind in ExperimentKind.allCases {
            let parameters = ExperimentDefinition.find(kind).parameters
            let lower = Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.range.lowerBound) })
            let upper = Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.range.upperBound) })
            let invalid = Dictionary(uniqueKeysWithValues: parameters.enumerated().map { ($0.element.id, $0.offset.isMultiple(of: 2) ? Double.nan : Double.infinity) })
            for values in [[:], lower, upper, invalid] {
                for time in [0.0, 1.0, 300.0, 1e12, .nan, -.infinity] {
                    let metrics = MechanicalSolver.metrics(for: kind, values: values, time: time)
                    XCTAssertGreaterThan(metrics.count, 3)
                    XCTAssertEqual(Set(metrics.map(\.id)).count, metrics.count)
                    for metric in metrics { XCTAssertTrue(metric.value.isFinite, "\(kind): \(metric.id)") }
                }
            }
        }
    }

    func testClampRestoredInputsAndGeometricConstraints() {
        let rocket = MechanicalSolver.normalizedValues(for: .rocket, values: ["initialMass": 100, "propellant": 400000])
        XCTAssertEqual(rocket["propellant"], 95)
        let crank = MechanicalSolver.normalizedValues(for: .crank, values: ["radius": 0.2, "rodLength": 0.08])
        XCTAssertGreaterThan(crank["rodLength"]!, crank["radius"]!)
        let gears = MechanicalSolver.normalizedValues(for: .gears, values: ["driverTeeth": 19.8, "drivenTeeth": 10000, "inputRPM": -1])
        XCTAssertEqual(gears["driverTeeth"], 20)
        XCTAssertEqual(gears["drivenTeeth"], 80)
        XCTAssertEqual(gears["inputRPM"], 0)
        XCTAssertEqual(MechanicalSolver.normalizedValues(for: .spring, values: ["mass": .nan])["mass"], 2)
    }

    func testLeverBalancesTorquesAndTradeoff() {
        let input = MechanicalSolver.gravity * 20 / 3
        let metrics = readings(.lever, ["effort": input, "effortArm": 1.5, "loadArm": 0.5, "load": 20])
        XCTAssertEqual(metrics["netTorque"]!, 0, accuracy: 1e-10)
        XCTAssertEqual(metrics["outputForce"]!, 20 * MechanicalSolver.gravity, accuracy: 1e-10)
        XCTAssertEqual(reading(.lever, "requiredEffort", ["effortArm": 2]), reading(.lever, "requiredEffort", ["effortArm": 1]) / 2, accuracy: 1e-10)
    }

    func testPulleyPowerBalanceAndDistanceTradeoff() {
        let metrics = readings(.pulley, ["efficiency": 80, "strands": 4, "pullSpeed": 0.8])
        XCTAssertEqual(metrics["outputPower"]!, metrics["inputPower"]! * 0.8, accuracy: 1e-10)
        XCTAssertEqual(metrics["inputPower"]!, metrics["outputPower"]! + metrics["loss"]!, accuracy: 1e-10)
        XCTAssertEqual(metrics["loadSpeed"]!, 0.2, accuracy: 1e-10)
        // More supporting strands need proportionally more rope speed for the same lift speed.
        XCTAssertEqual(reading(.pulley, "inputPower", ["strands": 8, "pullSpeed": 0.8]), reading(.pulley, "inputPower", ["strands": 4, "pullSpeed": 0.4]), accuracy: 1e-10)
    }

    func testInclineStaticFrictionAndDirection() {
        XCTAssertEqual(reading(.incline, "acceleration", ["angle": 10, "friction": 0.3, "push": 0]), 0, accuracy: 1e-10)
        XCTAssertLessThan(reading(.incline, "acceleration", ["angle": 45, "friction": 0.1, "push": 0]), 0)
        let force = reading(.incline, "requiredPush", ["angle": 20, "friction": 0.25])
        XCTAssertEqual(reading(.incline, "acceleration", ["angle": 20, "friction": 0.25, "push": force]), 0, accuracy: 1e-10)
        XCTAssertGreaterThan(reading(.incline, "acceleration", ["angle": 20, "friction": 0.25, "push": force + 10]), 0)
    }

    func testNonlinearPendulumPeriodMassIndependenceAndEnergy() {
        let period = reading(.pendulum, "period", ["length": 1, "amplitude": 60])
        XCTAssertGreaterThan(period, 2 * .pi * sqrt(1 / MechanicalSolver.gravity))
        XCTAssertEqual(reading(.pendulum, "period", ["mass": 10]), reading(.pendulum, "period", ["mass": 1]), accuracy: 1e-10)
        XCTAssertEqual(reading(.pendulum, "period", ["length": 2.4]), sqrt(2) * reading(.pendulum, "period", ["length": 1.2]), accuracy: 1e-10)
        let initial = reading(.pendulum, "energy", ["length": 1, "amplitude": 60])
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            XCTAssertEqual(reading(.pendulum, "energy", ["length": 1, "amplitude": 60], time: period * fraction), initial, accuracy: 1e-10)
        }
        XCTAssertEqual(reading(.pendulum, "angle", ["length": 1, "amplitude": 60], time: period / 4), 0, accuracy: 1e-6)
        XCTAssertEqual(reading(.pendulum, "angle", ["length": 1, "amplitude": 60], time: period / 2), -60, accuracy: 1e-6)
    }

    func testPendulumVelocityAgreesWithAngleDerivative() {
        let length = 1.2, amplitude = Double.pi / 3.0, time = 0.37, epsilon = 1e-5
        let before = MechanicalSolver.pendulumState(length: length, amplitude: amplitude, time: time - epsilon)
        let after = MechanicalSolver.pendulumState(length: length, amplitude: amplitude, time: time + epsilon)
        let state = MechanicalSolver.pendulumState(length: length, amplitude: amplitude, time: time)
        XCTAssertEqual(state.speed, length * (after.angle - before.angle) / (2 * epsilon), accuracy: 1e-5)
    }

    func testSpringUndampedEnergyAndQuarterCycle() {
        let values = ["mass": 2.0, "stiffness": 80.0, "amplitude": 0.25, "damping": 0.0]
        let period = 1 / reading(.spring, "frequency", values)
        let initial = reading(.spring, "energy", values)
        for step in 0...20 {
            XCTAssertEqual(reading(.spring, "energy", values, time: period * Double(step) / 20), initial, accuracy: 1e-10)
        }
        XCTAssertEqual(reading(.spring, "displacement", values, time: period / 4), 0, accuracy: 1e-10)
        XCTAssertEqual(reading(.spring, "displacement", values, time: period / 2), -0.25, accuracy: 1e-10)
    }

    func testDampingDissipatesEnergyInAllThreeRegimes() {
        for damping in [2.0, 2 * sqrt(2 * 80), 80.0] {
            let values = ["mass": 2.0, "stiffness": 80.0, "amplitude": 0.25, "damping": damping]
            var previous = reading(.spring, "energy", values)
            for step in 1...100 {
                let metrics = readings(.spring, values, time: Double(step) * 0.03)
                XCTAssertLessThanOrEqual(metrics["energy"]!, previous + 1e-9)
                XCTAssertEqual(metrics["energy"]! + metrics["dissipated"]!, 2.5, accuracy: 1e-9)
                previous = metrics["energy"]!
            }
            let release = MechanicalSolver.dampedRelease(mass: 2, stiffness: 80, damping: damping, displacement: 0.25, time: 0)
            XCTAssertEqual(release.position, 0.25, accuracy: 1e-10)
            XCTAssertEqual(release.velocity, 0, accuracy: 1e-10)
        }
    }

    func testGearsConserveIdealPowerAndReverseDirection() {
        let ideal = readings(.gears, ["driverTeeth": 20, "drivenTeeth": 60, "inputRPM": 120, "inputTorque": 5, "efficiency": 100])
        XCTAssertEqual(ideal["outputRPM"], -40)
        XCTAssertEqual(ideal["outputTorque"], 15)
        XCTAssertEqual(ideal["inputPower"]!, ideal["outputPower"]!, accuracy: 1e-10)
        let loss = readings(.gears, ["efficiency": 75])
        XCTAssertEqual(loss["outputPower"]!, loss["inputPower"]! * 0.75, accuracy: 1e-10)
        XCTAssertEqual(loss["outputPower"]! + loss["loss"]!, loss["inputPower"]!, accuracy: 1e-10)
    }

    func testCrankBoundsCycleAndVelocityDerivative() {
        let values = ["radius": 0.06, "rodLength": 0.22, "rpm": 60.0]
        XCTAssertEqual(reading(.crank, "pistonTravel", values), 0, accuracy: 1e-10)
        XCTAssertEqual(reading(.crank, "pistonTravel", values, time: 0.5), 0.12, accuracy: 1e-10)
        XCTAssertEqual(reading(.crank, "pistonTravel", values, time: 1), 0, accuracy: 1e-10)
        let epsilon = 1e-6, time = 0.17
        let travelDerivative = (reading(.crank, "pistonTravel", values, time: time + epsilon) - reading(.crank, "pistonTravel", values, time: time - epsilon)) / (2 * epsilon)
        XCTAssertEqual(reading(.crank, "pistonVelocity", values, time: time), -travelDerivative, accuracy: 1e-6)
        for step in 0...100 {
            let travel = reading(.crank, "pistonTravel", values, time: Double(step) / 100)
            XCTAssertGreaterThanOrEqual(travel, -1e-10)
            XCTAssertLessThanOrEqual(travel, 0.12 + 1e-10)
        }
    }

    func testHydraulicWorkAndVolumeConservation() {
        let values = ["force": 100.0, "inputRadius": 1.0, "outputRadius": 4.0, "travel": 16.0, "efficiency": 100.0]
        let metrics = readings(.hydraulics, values)
        XCTAssertEqual(metrics["outputForce"]!, 1600, accuracy: 1e-9)
        XCTAssertEqual(metrics["outputTravel"]!, 1, accuracy: 1e-10)
        XCTAssertEqual(metrics["inputWork"]!, metrics["outputWork"]!, accuracy: 1e-10)
        let lossy = readings(.hydraulics, ["efficiency": 70])
        XCTAssertEqual(lossy["outputWork"]!, lossy["inputWork"]! * 0.7, accuracy: 1e-10)
    }

    func testFlywheelSquareLawsAndStopsWithoutReversing() {
        XCTAssertEqual(reading(.flywheel, "energy", ["rpm": 1200]), 4 * reading(.flywheel, "energy", ["rpm": 600]), accuracy: 1e-8)
        XCTAssertEqual(reading(.flywheel, "energy", ["radius": 0.6]), 4 * reading(.flywheel, "energy", ["radius": 0.3]), accuracy: 1e-8)
        let values = ["brakeTorque": 10.0]
        let stop = reading(.flywheel, "stopTime", values)
        XCTAssertEqual(reading(.flywheel, "currentRPM", values, time: stop * 2), 0)
        let half = readings(.flywheel, values, time: stop / 2)
        XCTAssertEqual(half["currentRPM"]!, 300, accuracy: 1e-8)
        XCTAssertEqual(half["energy"]! + half["dissipated"]!, reading(.flywheel, "energy", values), accuracy: 1e-8)
    }

    func testBicycleSpeedForceTradeoffAndNoDrive() {
        let low = readings(.bicycle, ["rearTeeth": 40])
        let high = readings(.bicycle, ["rearTeeth": 20])
        XCTAssertEqual(high["speed"]!, 2 * low["speed"]!, accuracy: 1e-10)
        XCTAssertEqual(low["driveForce"]!, 2 * high["driveForce"]!, accuracy: 1e-10)
        XCTAssertEqual(high["driveForce"]! * high["speed"]! / 3.6, high["wheelPower"]!, accuracy: 1e-10)
        XCTAssertEqual(reading(.bicycle, "wheelPower", ["cadence": 0]), 0)
        XCTAssertEqual(reading(.bicycle, "driveForce", ["cadence": 0]), 0)
    }

    func testDifferentialAverageAndPowerConservation() {
        for radius in [0.0, 0.2, 5, 30] {
            let metrics = readings(.differential, ["turnRadius": radius, "carrierRPM": 250])
            XCTAssertEqual(metrics["averageRPM"]!, 250, accuracy: 1e-10)
            XCTAssertEqual(metrics["inputPower"]!, metrics["outputPower"]!, accuracy: 1e-10)
            XCTAssertGreaterThanOrEqual(metrics["innerRPM"]!, 0)
        }
        XCTAssertEqual(reading(.differential, "innerRPM", ["turnRadius": 0]), reading(.differential, "outerRPM", ["turnRadius": 0]), accuracy: 1e-10)
    }

    func testSuspensionResonanceDampingAndStaticTracking() {
        XCTAssertEqual(reading(.suspension, "transmissibility", ["roadFrequency": 0]), 1, accuracy: 1e-10)
        let natural = reading(.suspension, "naturalFrequency")
        let lowDamping = reading(.suspension, "transmissibility", ["roadFrequency": natural, "damping": 100])
        let highDamping = reading(.suspension, "transmissibility", ["roadFrequency": natural, "damping": 3000])
        XCTAssertGreaterThan(lowDamping, highDamping)
        XCTAssertEqual(reading(.suspension, "resonanceLimit", ["roadFrequency": natural, "damping": 0]), 1)
        XCTAssertEqual(reading(.suspension, "transmissibility", ["roadFrequency": natural, "damping": 0]), 50, accuracy: 1e-10)
        XCTAssertLessThan(reading(.suspension, "transmissibility", ["roadFrequency": 8]), 1)
    }

    func testPetrolEnginePowerTorqueFiringRateAndStoppedBoundary() {
        let low = readings(.combustion, ["rpm": 2000])
        let high = readings(.combustion, ["rpm": 4000])
        XCTAssertEqual(high["torque"]!, low["torque"]!, accuracy: 1e-10)
        XCTAssertEqual(high["power"]!, low["power"]! * 2, accuracy: 1e-10)
        XCTAssertEqual(reading(.combustion, "power", ["throttle": 0]), 0)
        XCTAssertEqual(reading(.combustion, "power", ["rpm": 0]), 0)
        XCTAssertGreaterThan(reading(.combustion, "idealEfficiency", ["compression": 14]), reading(.combustion, "idealEfficiency", ["compression": 6]))
        XCTAssertEqual(reading(.combustion, "firingRate", ["rpm": 2400, "cylinders": 4]), 80)
        XCTAssertEqual(reading(.combustion, "firingRate", ["rpm": 0]), 0)
    }

    func testDieselBoostAndPowerScaling() {
        let unboosted = reading(.diesel, "torque", ["boost": 0])
        XCTAssertEqual(reading(.diesel, "torque", ["boost": 1]), unboosted * 2, accuracy: 1e-9)
        XCTAssertEqual(reading(.diesel, "power", ["displacement": 6]), 2 * reading(.diesel, "power", ["displacement": 3]), accuracy: 1e-9)
        XCTAssertGreaterThan(reading(.diesel, "idealEfficiency", ["compression": 24]), reading(.diesel, "idealEfficiency", ["compression": 12]))
        XCTAssertEqual(reading(.diesel, "torque", ["throttle": 0]), 0)
    }

    func testElectricMotorPowerBalanceStallAndBackEMF() {
        let stall = readings(.electricMotor, ["rpm": 0])
        XCTAssertGreaterThan(stall["torque"]!, 0)
        XCTAssertEqual(stall["mechanicalPower"], 0)
        XCTAssertEqual(stall["copperLoss"]!, stall["inputPower"]!, accuracy: 1e-10)
        let spinning = readings(.electricMotor, ["rpm": 2000])
        XCTAssertEqual(spinning["inputPower"]!, spinning["mechanicalPower"]! + spinning["copperLoss"]!, accuracy: 1e-10)
        let noLoadRPM = spinning["noLoadRPM"]!
        XCTAssertEqual(reading(.electricMotor, "torque", ["rpm": noLoadRPM]), 0, accuracy: 1e-10)
        XCTAssertEqual(reading(.electricMotor, "current", ["rpm": noLoadRPM * 1.1]), 0)
        XCTAssertEqual(reading(.electricMotor, "torque", ["voltage": 0, "rpm": 0]), 0)
        XCTAssertLessThanOrEqual(spinning["current"]!, 80)
        XCTAssertLessThanOrEqual(spinning["efficiency"]!, 100)
    }

    func testSteamCutoffAndPressureBoundaries() {
        XCTAssertEqual(reading(.steam, "power", ["pressure": 0]), 0)
        XCTAssertEqual(reading(.steam, "power", ["rpm": 0]), 0)
        XCTAssertGreaterThan(reading(.steam, "power", ["cutoff": 100]), reading(.steam, "power", ["cutoff": 50]))
        XCTAssertEqual(reading(.steam, "steamVolume", ["cutoff": 100]), 2 * reading(.steam, "steamVolume", ["cutoff": 50]), accuracy: 1e-10)
        let metrics = readings(.steam)
        XCTAssertEqual(metrics["power"]! / 0.85, metrics["power"]! + metrics["mechanicalLoss"]!, accuracy: 1e-10)
    }

    func testLocomotiveAdhesionPowerAndGradeLimits() {
        let slow = readings(.locomotive, ["speed": 1, "adhesion": 0.1])
        XCTAssertEqual(slow["tractiveForce"]!, slow["adhesionLimit"]!, accuracy: 1e-10)
        let fast = readings(.locomotive, ["speed": 100, "power": 1000])
        XCTAssertEqual(fast["deliveredPower"]!, 1000, accuracy: 1e-10)
        XCTAssertLessThan(reading(.locomotive, "acceleration", ["grade": 3]), reading(.locomotive, "acceleration", ["grade": 0]))
        XCTAssertEqual(reading(.locomotive, "tractiveForce", ["power": 0]), 0)
    }

    func testTrainAerodynamicSquareAndCubicLaws() {
        let slower = readings(.highSpeedTrain, ["speed": 150])
        let faster = readings(.highSpeedTrain, ["speed": 300])
        XCTAssertEqual(faster["drag"]!, 4 * slower["drag"]!, accuracy: 1e-10)
        let slowAeroPower = slower["drag"]! * 150 / 3.6
        let fastAeroPower = faster["drag"]! * 300 / 3.6
        XCTAssertEqual(fastAeroPower, slowAeroPower * 8, accuracy: 1e-8)
        XCTAssertEqual(reading(.highSpeedTrain, "requiredPower", ["speed": 0]), 0)
    }

    func testActuatorDiscMomentumAndPowerBalance() {
        for speed in [0.0, 20.0, 80.0] {
            let induced = MechanicalSolver.actuatorInducedVelocity(power: 80000, area: 3, density: 1.225, airspeed: speed)
            let thrust = 2 * 1.225 * 3 * induced * (speed + induced)
            XCTAssertEqual(thrust * (speed + induced), 80000, accuracy: 1e-6)
        }
        XCTAssertEqual(MechanicalSolver.actuatorInducedVelocity(power: 0, area: 3, density: 1.225, airspeed: 0), 0)
        XCTAssertGreaterThan(reading(.propeller, "thrust", ["diameter": 3]), reading(.propeller, "thrust", ["diameter": 1]))
        XCTAssertEqual(reading(.propeller, "thrust", ["rpm": 0]), 0)
        XCTAssertEqual(reading(.propeller, "thrust", ["power": 0]), 0)
    }

    func testWingVelocitySquaredAndStall() {
        let low = readings(.wing, ["speed": 30, "angle": 6])
        let high = readings(.wing, ["speed": 60, "angle": 6])
        XCTAssertEqual(high["lift"]!, low["lift"]! * 4, accuracy: 1e-9)
        XCTAssertEqual(high["drag"]!, low["drag"]! * 4, accuracy: 1e-9)
        XCTAssertLessThan(reading(.wing, "lift", ["angle": 30]), reading(.wing, "lift", ["angle": 15]))
        XCTAssertGreaterThan(reading(.wing, "drag", ["angle": 30]), reading(.wing, "drag", ["angle": 15]))
        XCTAssertEqual(reading(.wing, "stalled", ["angle": 16]), 1)
        XCTAssertLessThan(reading(.wing, "lift", ["angle": -6]), 0)
        XCTAssertEqual(reading(.wing, "lift", ["speed": 0]), 0)
    }

    func testHelicopterHoverBalanceAndAreaBenefit() {
        let metrics = readings(.helicopter)
        let required = metrics["hoverPower"]!
        XCTAssertEqual(reading(.helicopter, "thrustWeight", ["power": required]), 1, accuracy: 1e-9)
        XCTAssertLessThan(reading(.helicopter, "hoverPower", ["diameter": 12]), reading(.helicopter, "hoverPower", ["diameter": 6]))
        XCTAssertEqual(reading(.helicopter, "availableThrust", ["power": 0]), 0)
    }

    func testTurbofanMomentumAccountingAndNoFlow() {
        let metrics = readings(.turbofan)
        XCTAssertEqual(metrics["thrust"]!, metrics["coreThrust"]! + metrics["fanThrust"]!, accuracy: 1e-10)
        XCTAssertEqual(reading(.turbofan, "fanThrust", ["bypass": 0]), 0)
        XCTAssertEqual(reading(.turbofan, "thrust", ["coreFlow": 0]), 0)
        XCTAssertGreaterThan(reading(.turbofan, "thrust", ["bypass": 10]), reading(.turbofan, "thrust", ["bypass": 1]))
        XCTAssertEqual(reading(.turbofan, "thrust", ["airSpeed": 300, "jetSpeed": 300, "fanSpeed": 300]), 0)
    }

    func testRocketBurnMassPressureAndLogDeltaV() {
        let values = ["initialMass": 30000.0, "propellant": 20000.0, "massFlow": 100.0, "exhaustSpeed": 3000.0, "exitPressure": 0.0, "ambientPressure": 0.0]
        let initial = readings(.rocket, values)
        let middle = readings(.rocket, values, time: 100)
        let burnout = readings(.rocket, values, time: 200)
        XCTAssertEqual(initial["thrust"]!, 300, accuracy: 1e-10)
        XCTAssertEqual(middle["mass"]!, 20000, accuracy: 1e-10)
        XCTAssertEqual(middle["idealDeltaV"]!, 3000 * log(1.5), accuracy: 1e-9)
        XCTAssertGreaterThan(middle["acceleration"]!, initial["acceleration"]!)
        XCTAssertEqual(burnout["thrust"], 0)
        XCTAssertEqual(burnout["mass"], 10000)
        XCTAssertEqual(burnout["propellantRemaining"], 0)
        XCTAssertEqual(reading(.rocket, "mass", values, time: 10000), 10000)
        XCTAssertEqual(reading(.rocket, "thrust", ["massFlow": 0]), 0)
        XCTAssertEqual(reading(.rocket, "thrust", ["propellant": 0]), 0)
        XCTAssertGreaterThan(reading(.rocket, "thrust", ["ambientPressure": 0]), reading(.rocket, "thrust", ["ambientPressure": 101.325]))
    }

    func testWindCubicRadiusSquareAndBetzLimit() {
        XCTAssertEqual(reading(.windTurbine, "electricPower", ["wind": 16]), 8 * reading(.windTurbine, "electricPower", ["wind": 8]), accuracy: 1e-8)
        XCTAssertEqual(reading(.windTurbine, "electricPower", ["radius": 40]), 4 * reading(.windTurbine, "electricPower", ["radius": 20]), accuracy: 1e-8)
        let metrics = readings(.windTurbine, ["coefficient": 1, "efficiency": 100])
        XCTAssertEqual(metrics["rotorPower"]!, metrics["betzLimit"]!, accuracy: 1e-8)
        XCTAssertLessThanOrEqual(metrics["electricPower"]!, metrics["windPower"]!)
        XCTAssertEqual(reading(.windTurbine, "electricPower", ["wind": 0]), 0)
    }

    func testHeatPumpEnergyBalanceCOPAndColdWeather() {
        let mild = readings(.heatPump, ["outdoor": 10, "indoor": 21])
        let cold = readings(.heatPump, ["outdoor": -20, "indoor": 21])
        XCTAssertGreaterThan(mild["cop"]!, cold["cop"]!)
        for metrics in [mild, cold, readings(.heatPump, ["outdoor": 21, "indoor": 21]), readings(.heatPump, ["outdoor": 35, "indoor": 10])] {
            XCTAssertEqual(metrics["heatDelivered"]!, metrics["heatExtracted"]! + metrics["electricalInput"]!, accuracy: 1e-10)
            XCTAssertGreaterThanOrEqual(metrics["cop"]!, 1)
            XCTAssertLessThanOrEqual(metrics["cop"]!, metrics["carnotCOP"]!)
        }
        XCTAssertEqual(reading(.heatPump, "heatDelivered", ["power": 0]), 0)
    }
}
