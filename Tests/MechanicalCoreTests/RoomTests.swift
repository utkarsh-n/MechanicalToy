import XCTest
@testable import MechanicalCore

final class RoomTests: XCTestCase {
    func testWindRemainsCoherentForFortySecondsAtDefaultAndMaximumInletSpeed() {
        for speed in [5.0, 14.0] {
            var inputs = RoomFlowInputs()
            inputs.speed = speed
            var flow = RoomAirflow()
            flow.reset(inputs: inputs)
            var wallTime = 0.0
            var frameNumber = 0
            while wallTime < 40 {
                // Uneven render cadence previously produced tiny remainder substeps
                // and amplified the stale pressure correction across the entire room.
                let dt = min(40 - wallTime, [0.0354, 0.0378, 0.0491, 0.0347][frameNumber % 4])
                flow.step(seconds: dt, inputs: inputs)
                wallTime += dt
                frameNumber += 1
                if frameNumber % 50 == 0 || wallTime >= 40 {
                    let frame = flow.frame()
                    XCTAssertTrue(frame.pixels.allSatisfy(\.isFinite))
                    XCTAssertGreaterThan(frame.meanSpeed, speed * 0.6)
                    XCTAssertLessThan(frame.meanSpeed, speed * 1.3)
                    XCTAssertLessThan(frame.peakSpeed, speed * 1.8)
                    XCTAssertLessThan(frame.divergence, speed * 0.05)
                    var fluidCount = 0, strongReversals = 0
                    for cell in 0..<(frame.width * frame.height) where frame.pixels[cell * 4 + 3] < 0.5 {
                        fluidCount += 1
                        if frame.pixels[cell * 4] < -Float(speed) * 0.5 { strongReversals += 1 }
                    }
                    XCTAssertLessThan(Double(strongReversals) / Double(fluidCount), 0.03)
                }
            }
            XCTAssertEqual(flow.time, 40, accuracy: 0.0001)
        }
    }

    func testFixedSimulationStepIsIndependentOfRenderCadence() {
        let inputs = RoomFlowInputs()
        var regular = RoomAirflow(), uneven = RoomAirflow()
        regular.reset(inputs: inputs)
        uneven.reset(inputs: inputs)
        for _ in 0..<90 { regular.step(seconds: 1 / 30, inputs: inputs) }
        var wallTime = 0.0, number = 0
        while wallTime < 3 {
            let dt = min(3 - wallTime, [0.009, 0.043, 0.017, 0.061][number % 4])
            uneven.step(seconds: dt, inputs: inputs)
            wallTime += dt
            number += 1
        }
        XCTAssertEqual(regular.time, uneven.time, accuracy: 0.00001)
        let regularFrame = regular.frame(), unevenFrame = uneven.frame()
        XCTAssertEqual(regularFrame.meanSpeed, unevenFrame.meanSpeed, accuracy: 0.00001)
        XCTAssertEqual(regularFrame.peakSpeed, unevenFrame.peakSpeed, accuracy: 0.00001)
        XCTAssertEqual(regularFrame.divergence, unevenFrame.divergence, accuracy: 0.00001)
        XCTAssertEqual(regularFrame.pixels, unevenFrame.pixels)
    }

    func testStillAirStaysStillAndTracersRemainBounded() {
        var inputs = RoomFlowInputs()
        inputs.speed = 0
        var flow = RoomAirflow(width: 36, height: 24)
        flow.reset(inputs: inputs)
        for _ in 0..<30 { flow.step(seconds: 1 / 30, inputs: inputs) }
        let frame = flow.frame()
        XCTAssertEqual(frame.peakSpeed, 0, accuracy: 0.00001)
        XCTAssertEqual(frame.divergence, 0, accuracy: 0.00001)
        for cell in 0..<(frame.width * frame.height) {
            XCTAssertTrue(frame.pixels[cell * 4 + 2].isFinite)
            XCTAssertTrue((0...1).contains(frame.pixels[cell * 4 + 2]))
            if frame.pixels[cell * 4 + 3] > 0.5 {
                XCTAssertEqual(frame.pixels[cell * 4 + 2], 0)
            }
        }
    }

    func testFlowRemainsFiniteAtHighSpeedWithMovingObstacles() {
        var inputs = RoomFlowInputs()
        inputs.speed = 14
        var flow = RoomAirflow(width: 40, height: 28)
        flow.reset(inputs: inputs)
        for shape in RoomBody.allCases {
            inputs.body = shape
            inputs.angle = 35
            inputs.bodyY = 0.3
            for _ in 0..<40 { flow.step(seconds: 1 / 30, inputs: inputs) }
            let frame = flow.frame()
            XCTAssertTrue(frame.pixels.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(frame.peakSpeed, 5)
            XCTAssertLessThan(frame.peakSpeed, 40)
            XCTAssertLessThan(frame.divergence, 12)
        }
    }

    func testPressureProjectionReducesInitialDivergence() {
        var flow = RoomAirflow()
        var inputs = RoomFlowInputs()
        inputs.body = .block
        inputs.speed = 6
        flow.reset(inputs: inputs)
        XCTAssertLessThan(flow.projectionDivergenceAfter, flow.projectionDivergenceBefore)
        for _ in 0..<90 { flow.step(seconds: 1 / 30, inputs: inputs) }
        let final = flow.frame()
        // Compare before/after the same projection; continued advection creates new divergence.
        XCTAssertLessThan(flow.projectionDivergenceAfter, flow.projectionDivergenceBefore)
        XCTAssertLessThan(final.divergence, 0.25)
        XCTAssertGreaterThan(final.meanSpeed, 2)
    }

    func testRoomWithoutSourcesEquilibratesToOutdoors() {
        var inputs = RoomEnvironmentInputs()
        inputs.mode = .off
        inputs.occupants = 0
        inputs.outdoorTemperature = 12
        inputs.outdoorHumidity = 50
        inputs.ventilationACH = 6
        var room = RoomEnvironment(temperature: 25, relativeHumidity: 75, co2PPM: 2_000)
        for _ in 0..<48 { room.step(seconds: 3_600, inputs: inputs) }
        XCTAssertEqual(room.temperature, 12, accuracy: 0.001)
        XCTAssertEqual(room.co2PPM, RoomEnvironment.outdoorCO2, accuracy: 0.001)
        XCTAssertEqual(room.relativeHumidity, 50, accuracy: 0.01)
    }

    func testClosedRoomConservesCO2SourceAndWaterMass() {
        var inputs = RoomEnvironmentInputs()
        inputs.mode = .off
        inputs.occupants = 2
        inputs.ventilationACH = 0
        inputs.windowOpening = 0
        inputs.outdoorTemperature = 22
        var room = RoomEnvironment(temperature: 22, relativeHumidity: 30, co2PPM: 420)
        let startWater = room.humidityRatio
        room.step(seconds: 600, inputs: inputs)
        XCTAssertEqual(room.co2PPM, 420 + 2 * 0.000005 / 80 * 1_000_000 * 600, accuracy: 0.001)
        XCTAssertEqual(room.humidityRatio - startWater, 2 * 0.000015 * 600 / (1.204 * 80), accuracy: 0.000001)
        XCTAssertGreaterThan(room.temperature, 22)
    }

    func testFreshAirRemovesCO2AndCostsHeatInWinter() {
        var closedInputs = RoomEnvironmentInputs()
        closedInputs.mode = .off
        closedInputs.occupants = 3
        closedInputs.ventilationACH = 0
        var openInputs = closedInputs
        openInputs.windowOpening = 1
        var closed = RoomEnvironment(co2PPM: 1_500)
        var open = closed
        closed.step(seconds: 3_600, inputs: closedInputs)
        open.step(seconds: 3_600, inputs: openInputs)
        XCTAssertLessThan(open.co2PPM, closed.co2PPM)
        XCTAssertLessThan(open.temperature, closed.temperature)
        XCTAssertLessThan(open.ventilationPower, 0)
    }

    func testThermostatHeatAndCoolDirectionAndCapacity() {
        var inputs = RoomEnvironmentInputs()
        inputs.mode = .heat
        inputs.targetTemperature = 25
        var heated = RoomEnvironment(temperature: 17)
        heated.step(seconds: 600, inputs: inputs)
        XCTAssertGreaterThan(heated.temperature, 17)
        XCTAssertGreaterThan(heated.hvacPower, 0)
        XCTAssertLessThanOrEqual(heated.hvacPower, 3_000)
        inputs.mode = .cool
        inputs.targetTemperature = 18
        inputs.outdoorTemperature = 30
        var cooled = RoomEnvironment(temperature: 29, relativeHumidity: 75)
        let startingWater = cooled.humidityRatio
        cooled.step(seconds: 600, inputs: inputs)
        XCTAssertLessThan(cooled.temperature, 29)
        XCTAssertLessThan(cooled.hvacPower, 0)
        XCTAssertGreaterThanOrEqual(cooled.hvacPower, -3_000)
        XCTAssertLessThan(cooled.humidityRatio, startingWater)
    }

    func testExtremeInputsStayFiniteAndHumidityCondenses() {
        var inputs = RoomEnvironmentInputs()
        inputs.occupants = 100
        inputs.ventilationACH = -.infinity
        inputs.outdoorTemperature = .nan
        inputs.outdoorHumidity = 200
        inputs.windowOpening = -2
        inputs.mode = .off
        var room = RoomEnvironment(temperature: 20, relativeHumidity: 100)
        for _ in 0..<12 { room.step(seconds: 3_600, inputs: inputs) }
        XCTAssertTrue(room.temperature.isFinite)
        XCTAssertTrue(room.co2PPM.isFinite)
        XCTAssertTrue((0...100).contains(room.relativeHumidity))
        XCTAssertGreaterThan(room.condensedWater, 0)
        let elapsed = room.elapsed
        room.step(seconds: .nan, inputs: inputs)
        XCTAssertEqual(room.elapsed, elapsed)
    }
}
