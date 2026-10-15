import XCTest
@testable import MechanicalCore

final class GuidedLabTests: XCTestCase {
    func testCatalogHasEightCompleteLabsAndUniqueStepIdentities() {
        XCTAssertEqual(Set(GuidedLabDefinition.catalog.map(\.id)), Set(GuidedLabID.allCases))
        XCTAssertEqual(GuidedLabDefinition.catalog.count, 8)
        for lab in GuidedLabDefinition.catalog {
            XCTAssertEqual(lab.id.id, lab.id.rawValue)
            XCTAssertEqual(GuidedLabDefinition.find(lab.id).id, lab.id)
            XCTAssertFalse(lab.title.isEmpty)
            XCTAssertFalse(lab.subtitle.isEmpty)
            XCTAssertFalse(lab.steps.isEmpty)
            XCTAssertEqual(Set(lab.steps.map(\.id)).count, lab.steps.count)
            for step in lab.steps {
                XCTAssertFalse(step.title.isEmpty)
                XCTAssertFalse(step.instructions.isEmpty)
                XCTAssertFalse(step.expected.isEmpty)
                if step.action == .none { XCTAssertNil(step.actionTitle) }
                else { XCTAssertFalse(step.actionTitle?.isEmpty ?? true) }
            }
        }
        XCTAssertEqual(GuidedLabDefinition.find(.tiltGears).steps.map(\.action), [.calibrateTilt, .none, .none, .pauseGear, .resumeGear])
        XCTAssertEqual(GuidedLabDefinition.find(.airflow).steps.map(\.action), [.runAirflow, .doubleAirflow, .angleWing, .blockAirflow, .pauseAirflow, .stepAirflow])
        XCTAssertEqual(GuidedLabDefinition.find(.climateFreshAir).steps.map(\.action), [.advanceClosedClimate, .ventilateClimate, .none])
        XCTAssertEqual(GuidedLabDefinition.find(.climateThermostat).steps.map(\.action), [.advanceClosedClimate, .enableAutoHeat, .advanceHeatedClimate, .none])
    }

    func testGearLabSetupsRestoreNormalizedCompleteModelsAndPlaybackIntent() throws {
        let expected: [(GuidedLabID, GearKind, Double, Double, Bool)] = [
            (.gearOptics, .spur, 20, 60, true),
            (.gearSpurDrive, .spur, 20, 60, false),
            (.gearWormReduction, .worm, 20, 120, false),
            (.gearRackTravel, .rackAndPinion, 16, 60, false)
        ]
        for (id, kind, teeth, rpm, paused) in expected {
            let lab = GuidedLabDefinition.find(id)
            let setup = try XCTUnwrap(lab.gearBenchSetup)
            XCTAssertEqual(lab.destination, .gearBench)
            XCTAssertEqual(setup.kind, kind)
            XCTAssertEqual(setup.inputs, GearTransmission.normalizedInputs(kind: kind, inputs: setup.inputs))
            XCTAssertEqual(setup.inputs.driverTeeth, teeth)
            XCTAssertEqual(setup.inputs.drivenTeeth, 40)
            XCTAssertEqual(setup.inputs.inputRPM, rpm)
            XCTAssertEqual(setup.inputs.inputTorque, 5)
            XCTAssertEqual(setup.inputs.efficiency, 0.95)
            XCTAssertEqual(setup.inputs.moduleMM, 3)
            XCTAssertEqual(setup.inputs.wormStarts, 1)
            XCTAssertEqual(setup.startsPaused, paused)
        }
        for id in [GuidedLabID.tiltGears, .airflow, .climateFreshAir, .climateThermostat] {
            XCTAssertNil(GuidedLabDefinition.find(id).gearBenchSetup)
        }
    }

    func testOpticalRecenterDoesNotChangeGearInputsOrSupplyAnAutomaticSensorPass() throws {
        let lab = GuidedLabDefinition.find(.gearOptics)
        XCTAssertEqual(lab.steps.map(\.action), [.recenterGearOptics, .none, .none])
        XCTAssertNil(GuidedLabAction.recenterGearOptics.gearBenchSetup)
        let setup = try XCTUnwrap(lab.gearBenchSetup)
        let result = GearTransmission.solve(kind: setup.kind, inputs: setup.inputs)
        XCTAssertTrue(setup.startsPaused)
        XCTAssertEqual(result.outputRPM, -30, accuracy: 1e-9)
        XCTAssertEqual(result.ratio, 2, accuracy: 1e-9)
        XCTAssertEqual(result.outputTorque, 9.5, accuracy: 1e-9)
    }

    func testSpurCrownCheckpointsMatchSpeedTorqueAndPowerTradeoff() throws {
        let sixty = try XCTUnwrap(GuidedLabAction.driveSpur60.gearBenchSetup)
        let doubled = try XCTUnwrap(GuidedLabAction.driveSpur120.gearBenchSetup)
        let stopped = try XCTUnwrap(GuidedLabAction.stopSpurDrive.gearBenchSetup)
        let larger = try XCTUnwrap(GuidedLabAction.reduceSpurThreeToOne.gearBenchSetup)
        for setup in [sixty, doubled, stopped, larger] {
            XCTAssertEqual(setup.kind, .spur)
            XCTAssertEqual(setup.inputs.inputTorque, 5)
            XCTAssertEqual(setup.inputs.efficiency, 0.95)
            XCTAssertFalse(setup.startsPaused)
        }
        let baseResult = GearTransmission.solve(kind: sixty.kind, inputs: sixty.inputs)
        let doubleResult = GearTransmission.solve(kind: doubled.kind, inputs: doubled.inputs)
        let stoppedResult = GearTransmission.solve(kind: stopped.kind, inputs: stopped.inputs)
        let largerResult = GearTransmission.solve(kind: larger.kind, inputs: larger.inputs)
        XCTAssertEqual(baseResult.outputRPM, -30, accuracy: 1e-9)
        XCTAssertEqual(doubleResult.outputRPM, -60, accuracy: 1e-9)
        XCTAssertEqual(doubleResult.outputTorque, baseResult.outputTorque, accuracy: 1e-9)
        XCTAssertEqual(stopped.inputs.inputRPM, 0)
        XCTAssertEqual(stoppedResult.outputRPM, 0)
        XCTAssertEqual(stoppedResult.outputTorque, 9.5, accuracy: 1e-9)
        XCTAssertEqual(rotaryOutputPower(stoppedResult), 0)
        XCTAssertEqual(larger.inputs.inputRPM, 60)
        XCTAssertEqual(larger.inputs.driverTeeth, 20)
        XCTAssertEqual(larger.inputs.drivenTeeth, 60)
        XCTAssertEqual(largerResult.ratio, 3, accuracy: 1e-9)
        XCTAssertEqual(largerResult.outputRPM, -20, accuracy: 1e-9)
        XCTAssertEqual(largerResult.outputTorque, 14.25, accuracy: 1e-9)
        XCTAssertEqual(rotaryOutputPower(largerResult), rotaryOutputPower(baseResult), accuracy: 1e-9)
        XCTAssertEqual(rotaryOutputPower(doubleResult), rotaryOutputPower(baseResult) * 2, accuracy: 1e-9)
    }

    func testWormStartsCheckpointDoublesSpeedAndHalvesTorqueAtSamePower() throws {
        let single = try XCTUnwrap(GuidedLabDefinition.find(.gearWormReduction).gearBenchSetup)
        let double = try XCTUnwrap(GuidedLabAction.doubleWormStarts.gearBenchSetup)
        XCTAssertEqual(single.kind, .worm)
        XCTAssertEqual(double.kind, .worm)
        XCTAssertEqual(single.inputs.inputRPM, 120)
        XCTAssertEqual(double.inputs.inputRPM, 120)
        XCTAssertEqual(double.inputs.drivenTeeth, 40)
        XCTAssertEqual(double.inputs.wormStarts, 2)
        let singleResult = GearTransmission.solve(kind: single.kind, inputs: single.inputs)
        let doubleResult = GearTransmission.solve(kind: double.kind, inputs: double.inputs)
        XCTAssertEqual(singleResult.ratio, 40, accuracy: 1e-9)
        XCTAssertEqual(singleResult.outputRPM, -3, accuracy: 1e-9)
        XCTAssertEqual(singleResult.outputTorque, 190, accuracy: 1e-9)
        XCTAssertEqual(doubleResult.ratio, 20, accuracy: 1e-9)
        XCTAssertEqual(doubleResult.outputRPM, -6, accuracy: 1e-9)
        XCTAssertEqual(doubleResult.outputTorque, 95, accuracy: 1e-9)
        XCTAssertEqual(rotaryOutputPower(singleResult), rotaryOutputPower(doubleResult), accuracy: 1e-9)
        // The visual inspection clock runs at 1/8 of physical speed.
        XCTAssertEqual(60 / (abs(singleResult.outputRPM) / 8), 160, accuracy: 1e-9)
        XCTAssertEqual(60 / (abs(doubleResult.outputRPM) / 8), 80, accuracy: 1e-9)
    }

    func testRackCheckpointsMatchTravelAndForceAtConstantTorque() throws {
        let baseline = try XCTUnwrap(GuidedLabDefinition.find(.gearRackTravel).gearBenchSetup)
        let doubled = try XCTUnwrap(GuidedLabAction.doubleRackSpeed.gearBenchSetup)
        let enlarged = try XCTUnwrap(GuidedLabAction.enlargeRackPinion.gearBenchSetup)
        for setup in [baseline, doubled, enlarged] {
            XCTAssertEqual(setup.kind, .rackAndPinion)
            XCTAssertEqual(setup.inputs.moduleMM, 3)
            XCTAssertEqual(setup.inputs.inputTorque, 5)
            XCTAssertEqual(setup.inputs.efficiency, 0.95)
            XCTAssertFalse(setup.startsPaused)
        }
        let baseResult = GearTransmission.solve(kind: baseline.kind, inputs: baseline.inputs)
        let doubleResult = GearTransmission.solve(kind: doubled.kind, inputs: doubled.inputs)
        let enlargedResult = GearTransmission.solve(kind: enlarged.kind, inputs: enlarged.inputs)
        XCTAssertEqual(baseline.inputs.driverTeeth * baseline.inputs.moduleMM, 48)
        XCTAssertEqual(enlarged.inputs.driverTeeth * enlarged.inputs.moduleMM, 72)
        XCTAssertEqual(baseResult.rackSpeedMMPerSecond, 150.7964473723, accuracy: 1e-6)
        XCTAssertEqual(baseResult.rackForceNewtons, 197.9166666667, accuracy: 1e-6)
        XCTAssertEqual(doubleResult.rackSpeedMMPerSecond, 301.5928947446, accuracy: 1e-6)
        XCTAssertEqual(doubleResult.rackForceNewtons, baseResult.rackForceNewtons, accuracy: 1e-9)
        XCTAssertEqual(enlarged.inputs.inputRPM, 60)
        XCTAssertEqual(enlargedResult.rackSpeedMMPerSecond, 226.1946710585, accuracy: 1e-6)
        XCTAssertEqual(enlargedResult.rackForceNewtons, 131.9444444444, accuracy: 1e-6)
        let basePower = baseResult.rackForceNewtons * baseResult.rackSpeedMMPerSecond / 1000
        let enlargedPower = enlargedResult.rackForceNewtons * enlargedResult.rackSpeedMMPerSecond / 1000
        let doublePower = doubleResult.rackForceNewtons * doubleResult.rackSpeedMMPerSecond / 1000
        XCTAssertEqual(basePower, baseline.inputs.inputTorque * 2 * .pi * baseline.inputs.inputRPM / 60 * baseline.inputs.efficiency, accuracy: 1e-9)
        XCTAssertEqual(enlargedPower, basePower, accuracy: 1e-9)
        XCTAssertEqual(doublePower, 2 * basePower, accuracy: 1e-9)
    }

    func testGearNeutralAndSignedTenDegreeTiltPredictions() {
        let lab = GuidedLabDefinition.find(.tiltGears)
        XCTAssertEqual(lab.destination, .gears)
        XCTAssertEqual(lab.gearValues, MechanicalSolver.normalizedValues(for: .gears, values: lab.gearValues))
        let neutral = measurements(lab.gearValues)
        XCTAssertEqual(neutral["outputRPM"]!, -300, accuracy: 1e-9)
        XCTAssertEqual(neutral["outputTorque"]!, 9.5, accuracy: 1e-9)
        let rpmRange = ExperimentDefinition.find(.gears).parameters.first { $0.id == "inputRPM" }!.range
        for roll in [-10.0, 10.0] {
            var values = lab.gearValues
            // The app maps ±45° to ±half the input range; this verifies the guide's numbers.
            values["inputRPM"]! += (roll / 90) * (rpmRange.upperBound - rpmRange.lowerBound)
            let metrics = measurements(values)
            XCTAssertEqual(values["inputRPM"]!, roll < 0 ? 466.6666666667 : 733.3333333333, accuracy: 1e-6)
            XCTAssertEqual(metrics["outputRPM"]!, roll < 0 ? -233.3333333333 : -366.6666666667, accuracy: 1e-6)
            XCTAssertEqual(metrics["outputTorque"]!, neutral["outputTorque"]!, accuracy: 1e-9)
            XCTAssertEqual(metrics["outputPower"]!, metrics["inputPower"]! * 0.95, accuracy: 1e-9)
        }
    }

    func testFreshAirGuideCheckpointsAndSourceSinkEquilibrium() {
        let lab = GuidedLabDefinition.find(.climateFreshAir)
        XCTAssertEqual(lab.destination, .climate)
        var inputs = lab.climateSetup
        var room = RoomEnvironment()
        XCTAssertEqual(inputs.mode, .off)
        XCTAssertEqual(inputs.airChangesPerHour, 0)
        XCTAssertEqual(inputs.occupants, 4)
        XCTAssertEqual(inputs.outdoorTemperature, 22)
        room.step(seconds: 600, inputs: inputs)
        XCTAssertEqual(room.co2PPM, 850, accuracy: 1e-7)
        XCTAssertEqual(room.elapsed, 600, accuracy: 1e-9)
        XCTAssertGreaterThan(room.temperature, 22)
        XCTAssertEqual(room.hvacPower, 0)

        inputs.ventilationACH = 3
        room.step(seconds: 600, inputs: inputs)
        XCTAssertEqual(room.co2PPM, 798.8489857626, accuracy: 1e-6)
        XCTAssertEqual(room.elapsed, 1200, accuracy: 1e-9)
        for _ in 0..<8 { room.step(seconds: 3600, inputs: inputs) }
        XCTAssertEqual(room.co2PPM, 720, accuracy: 1e-6)
        XCTAssertGreaterThan(room.co2PPM, RoomEnvironment.outdoorCO2)
    }

    func testColdRoomGuideCheckpointsAndHeatingCapacity() {
        let lab = GuidedLabDefinition.find(.climateThermostat)
        var inputs = lab.climateSetup
        var room = RoomEnvironment()
        XCTAssertEqual(inputs.mode, .off)
        XCTAssertEqual(inputs.occupants, 0)
        XCTAssertEqual(inputs.airChangesPerHour, 6)
        XCTAssertEqual(inputs.targetTemperature, 21)
        XCTAssertEqual(inputs.conductance, 85)
        room.step(seconds: 900, inputs: inputs)
        XCTAssertEqual(room.temperature, 17.9518099317, accuracy: 1e-7)
        XCTAssertEqual(room.hvacPower, 0)
        inputs.mode = .auto
        room.step(seconds: 0.01, inputs: inputs)
        XCTAssertEqual(room.hvacPower, 3000)
        room.step(seconds: 600, inputs: inputs)
        // Includes the guide's 0.01-second refresh after enabling Auto.
        XCTAssertEqual(room.temperature, 18.4033441368, accuracy: 1e-6)
        XCTAssertEqual(room.hvacPower, 3000)
        XCTAssertEqual(room.elapsed, 1500.01, accuracy: 1e-7)
        XCTAssertLessThan(room.temperature, inputs.targetTemperature)
    }

    func testProportionalThermostatReachesStatedBelowTargetEquilibrium() {
        var inputs = GuidedLabDefinition.find(.climateThermostat).climateSetup
        var room = RoomEnvironment()
        room.step(seconds: 900, inputs: inputs)
        inputs.mode = .auto
        for _ in 0..<12 { room.step(seconds: 3600, inputs: inputs) }
        XCTAssertEqual(room.temperature, 19.16520968, accuracy: 1e-6)
        XCTAssertEqual(room.hvacPower, 2752.18548, accuracy: 0.01)
        XCTAssertLessThan(room.temperature, 21)
        XCTAssertLessThan(room.hvacPower, 3000)
        XCTAssertGreaterThan(room.hvacPower, 0)
        let windowOpenPower = room.hvacPower
        inputs.windowOpening = 0
        for _ in 0..<12 { room.step(seconds: 3600, inputs: inputs) }
        XCTAssertGreaterThan(room.temperature, 19.16520968)
        XCTAssertLessThan(room.hvacPower, windowOpenPower)
    }

    func testFlowGuideSpeedAndGeometryActionsProduceValidFields() {
        let lab = GuidedLabDefinition.find(.airflow)
        XCTAssertEqual(lab.destination, .airflow)
        var inputs = lab.flowSetup
        XCTAssertEqual(inputs.body, .wing)
        XCTAssertEqual(inputs.speed, 5)
        XCTAssertEqual(inputs.angle, 0)
        XCTAssertEqual(inputs.bodyX, 0.47)
        XCTAssertEqual(inputs.bodyY, 0.5)

        var flow = RoomAirflow(width: 40, height: 28)
        flow.reset(inputs: inputs)
        flow.step(seconds: 1, inputs: inputs)
        let slower = flow.frame()
        inputs.speed = 10
        flow.reset(inputs: inputs)
        flow.step(seconds: 1, inputs: inputs)
        let faster = flow.frame()
        XCTAssertGreaterThan(faster.meanSpeed, slower.meanSpeed)
        XCTAssertGreaterThan(faster.peakSpeed, slower.peakSpeed)

        inputs.speed = 5
        inputs.angle = 15
        inputs.bodyY = 0.75
        flow.reset(inputs: inputs)
        flow.step(seconds: 1, inputs: inputs)
        let wing = flow.frame()
        inputs.body = .block
        flow.step(seconds: 1, inputs: inputs)
        let block = flow.frame()
        XCTAssertTrue(block.pixels.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(block.meanSpeed, 0)
        XCTAssertNotEqual(wing.pixels, block.pixels)
        let beforeStep = block.time
        flow.step(seconds: 0.1, inputs: inputs)
        XCTAssertEqual(flow.frame().time, beforeStep + 0.1, accuracy: 1e-8)
    }

    private func measurements(_ values: [String: Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: MechanicalSolver.metrics(for: .gears, values: values, time: 0).map { ($0.id, $0.value) })
    }

    private func rotaryOutputPower(_ result: GearTransmissionResult) -> Double {
        abs(result.outputRPM) * 2 * .pi / 60 * result.outputTorque
    }
}
