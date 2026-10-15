import XCTest
@testable import MechanicalCore

final class GearTransmissionTests: XCTestCase {
    func testExternalGearReductionAndInternalGearDirection() {
        let external = GearTransmission.solve(kind: .spur, inputs: .init())
        let internalMesh = GearTransmission.solve(kind: .internalGear, inputs: .init())
        XCTAssertEqual(external.ratio, 2)
        XCTAssertEqual(external.outputRPM, -30)
        XCTAssertEqual(internalMesh.outputRPM, 30)
        XCTAssertEqual(external.outputTorque, 9.5, accuracy: 1e-12)
        XCTAssertEqual(internalMesh.outputTorque, external.outputTorque)
        XCTAssertEqual(internalMesh.ratio, external.ratio)
    }

    func testRotaryTransmissionPowerAndReversalAcrossAllGeometries() {
        for kind in GearKind.allCases where !kind.isRack {
            for rpm in [-240.0, 0, 240] {
                let inputs = GearTransmissionInputs(driverTeeth: 18, drivenTeeth: 54,
                                                    inputRPM: rpm, inputTorque: 7,
                                                    efficiency: 0.8, wormStarts: 2)
                let result = GearTransmission.solve(kind: kind, inputs: inputs)
                let inputPower = inputs.inputTorque * abs(rpm) * 2 * .pi / 60
                let outputPower = result.outputTorque * abs(result.outputRPM) * 2 * .pi / 60
                XCTAssertEqual(outputPower, inputPower * inputs.efficiency, accuracy: 1e-9, kind.rawValue)
                XCTAssertEqual(abs(result.outputRPM) * result.ratio, abs(rpm), accuracy: 1e-9)
            }
        }
    }

    func testWormStartsControlReductionRatherThanDriverToothCount() {
        var inputs = GearTransmissionInputs()
        let singleStart = GearTransmission.solve(kind: .worm, inputs: inputs)
        XCTAssertEqual(singleStart.ratio, 40)
        XCTAssertEqual(singleStart.outputRPM, -1.5)
        XCTAssertEqual(singleStart.outputTorque, 190, accuracy: 1e-12)
        inputs.wormStarts = 2
        inputs.driverTeeth = 100
        let doubleStart = GearTransmission.solve(kind: .worm, inputs: inputs)
        XCTAssertEqual(doubleStart.ratio, 20)
        XCTAssertEqual(doubleStart.outputRPM, singleStart.outputRPM * 2)
        XCTAssertEqual(doubleStart.outputTorque, singleStart.outputTorque / 2)
    }

    func testMitreKeepsEqualCountsAndSpeedUnderChangingControls() {
        for teeth in [10.0, 28, 70] {
            let inputs = GearTransmissionInputs(driverTeeth: teeth, drivenTeeth: 120,
                                                inputRPM: 90, inputTorque: 8, efficiency: 0.75)
            let normalized = GearTransmission.normalizedInputs(kind: .mitre, inputs: inputs)
            XCTAssertEqual(normalized.drivenTeeth, teeth)
            let result = GearTransmission.solve(kind: .mitre, inputs: inputs)
            XCTAssertEqual(result.ratio, 1)
            XCTAssertEqual(abs(result.outputRPM), 90)
            XCTAssertEqual(result.outputTorque, 6)
        }
    }

    func testRackKnownSpeedForceAndPowerInSIUnits() {
        let result = GearTransmission.solve(kind: .rackAndPinion, inputs: .init())
        // A 60 mm pitch diameter advances 60π mm for each revolution.
        XCTAssertEqual(result.rackSpeedMMPerSecond, 60 * .pi, accuracy: 1e-9)
        XCTAssertEqual(result.rackForceNewtons, 158.3333333333333, accuracy: 1e-9)
        let outputPower = result.rackForceNewtons * result.rackSpeedMMPerSecond / 1000
        XCTAssertEqual(outputPower, 5 * 2 * .pi * 0.95, accuracy: 1e-9)
        XCTAssertEqual(result.outputRPM, 0)
        XCTAssertEqual(result.outputTorque, 0)
    }

    func testLargerRackPinionTradesForceForTravelAndReverses() {
        let small = GearTransmission.solve(kind: .rackAndPinion, inputs: .init())
        let large = GearTransmission.solve(kind: .rackAndPinion,
                                           inputs: .init(driverTeeth: 40, inputRPM: -60))
        XCTAssertEqual(large.rackSpeedMMPerSecond, -2 * small.rackSpeedMMPerSecond, accuracy: 1e-9)
        XCTAssertEqual(large.rackForceNewtons, small.rackForceNewtons / 2, accuracy: 1e-9)
        let widerModule = GearTransmission.solve(kind: .rackAndPinion, inputs: .init(moduleMM: 6))
        XCTAssertEqual(widerModule.rackSpeedMMPerSecond, 2 * small.rackSpeedMMPerSecond, accuracy: 1e-9)
        XCTAssertEqual(widerModule.rackForceNewtons, small.rackForceNewtons / 2, accuracy: 1e-9)
    }

    func testSingleHelixThrustAndBalancedDoubleHelices() {
        let inputs = GearTransmissionInputs(inputTorque: 3, moduleMM: 3, helixAngleDegrees: 45)
        let helical = GearTransmission.solve(kind: .helical, inputs: inputs)
        let screw = GearTransmission.solve(kind: .screw, inputs: inputs)
        // Input pitch radius 0.03 m, giving Ft = 100 N and tan(45°) = 1.
        XCTAssertEqual(helical.axialForceNewtons, 100, accuracy: 1e-9)
        XCTAssertEqual(screw.axialForceNewtons, 100, accuracy: 1e-9)
        for kind in [GearKind.doubleHelical, .herringbone] {
            let balanced = GearTransmission.solve(kind: kind, inputs: inputs)
            XCTAssertEqual(balanced.axialForceNewtons, 0)
            XCTAssertEqual(balanced.outputRPM, helical.outputRPM)
            XCTAssertEqual(balanced.outputTorque, helical.outputTorque)
        }
        XCTAssertEqual(GearTransmission.solve(kind: .helical, inputs: .init(helixAngleDegrees: 0)).axialForceNewtons, 0)
        let steeper = GearTransmission.solve(kind: .helical, inputs: .init(helixAngleDegrees: 40))
        let shallow = GearTransmission.solve(kind: .helical, inputs: .init(helixAngleDegrees: 10))
        XCTAssertGreaterThan(steeper.axialForceNewtons, shallow.axialForceNewtons)
        XCTAssertEqual(steeper.outputRPM, shallow.outputRPM)
    }

    func testEfficiencyChangesDeliveredForceAndTorqueWithoutChangingSpeed() {
        for kind in GearKind.allCases {
            let ideal = GearTransmission.solve(kind: kind, inputs: .init(efficiency: 1))
            let lossy = GearTransmission.solve(kind: kind, inputs: .init(efficiency: 0.6))
            let disconnected = GearTransmission.solve(kind: kind, inputs: .init(efficiency: 0))
            XCTAssertEqual(lossy.outputRPM, ideal.outputRPM)
            XCTAssertEqual(lossy.rackSpeedMMPerSecond, ideal.rackSpeedMMPerSecond)
            XCTAssertEqual(lossy.outputTorque, ideal.outputTorque * 0.6, accuracy: 1e-9)
            XCTAssertEqual(lossy.rackForceNewtons, ideal.rackForceNewtons * 0.6, accuracy: 1e-9)
            XCTAssertEqual(disconnected.outputTorque, 0)
            XCTAssertEqual(disconnected.rackForceNewtons, 0)
        }
    }

    func testInvalidInputsProduceFiniteBoundedCompatibleGeometry() {
        for kind in GearKind.allCases {
            for invalid in [Double.nan, .infinity, -.infinity, -1e300, 1e300, 0, 7.6] {
                let inputs = GearTransmissionInputs(driverTeeth: invalid, drivenTeeth: invalid,
                                                    inputRPM: invalid, inputTorque: invalid,
                                                    efficiency: invalid, moduleMM: invalid,
                                                    helixAngleDegrees: invalid, wormStarts: invalid)
                let values = GearTransmission.normalizedInputs(kind: kind, inputs: inputs)
                let result = GearTransmission.solve(kind: kind, inputs: inputs)
                for scalar in [result.ratio, result.outputRPM, result.outputTorque,
                               result.rackSpeedMMPerSecond, result.rackForceNewtons, result.axialForceNewtons] {
                    XCTAssertTrue(scalar.isFinite, "\(kind.rawValue): \(invalid)")
                }
                XCTAssertEqual(values.driverTeeth, values.driverTeeth.rounded())
                XCTAssertEqual(values.drivenTeeth, values.drivenTeeth.rounded())
                XCTAssertEqual(values.wormStarts, values.wormStarts.rounded())
                XCTAssertTrue((0...1).contains(values.efficiency))
                XCTAssertGreaterThan(values.moduleMM, 0)
                XCTAssertGreaterThan(result.ratio, 0)
                if kind == .internalGear { XCTAssertGreaterThanOrEqual(values.drivenTeeth - values.driverTeeth, 4) }
                if kind == .mitre { XCTAssertEqual(values.drivenTeeth, values.driverTeeth) }
                XCTAssertEqual(GearTransmission.normalizedInputs(kind: kind, inputs: values), values)
            }
        }
    }

    func testReferenceConceptsAreCompleteAndPreserveDistinctGeometries() throws {
        XCTAssertEqual(GearKind.allCases.count, 12)
        XCTAssertEqual(GearKind.allCases.map(\.index), Array(0..<12))
        XCTAssertEqual(GearKind.allCases.filter(\.isRack), [.rackAndPinion])
        XCTAssertEqual(GearKind.allCases.filter(\.showsAxialForceEstimate), [.helical, .doubleHelical, .screw, .herringbone])
        for kind in GearKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.explanation.isEmpty)
            XCTAssertFalse(kind.caution.isEmpty)
            let encoded = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(GearKind.self, from: encoded), kind)
        }
        XCTAssertNotEqual(GearKind.doubleHelical.explanation, GearKind.herringbone.explanation)
        XCTAssertNotEqual(GearKind.screw.explanation, GearKind.worm.explanation)
        XCTAssertNotEqual(GearKind.spiralBevel.axesDescription, GearKind.hypoid.axesDescription)
    }
}
