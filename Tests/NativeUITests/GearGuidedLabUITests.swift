import XCTest

/// Checks navigation, configured operating points, and guide lifecycle.
/// Phone optics and crown haptics remain observations made on the physical iPhone.
final class GearGuidedLabUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testOpticalLabStartsPausedAndManualObservationsCanFinish() throws {
        let app = launchApp()
        try startLab("gearOptics", in: app)
        try assertStep("Choose a comfortable neutral position", in: app)
        try assertReading("Input speed", equals: 60, unit: "rpm", in: app)
        try assertReading("Output speed", equals: -30, unit: "rpm", in: app)
        try assertReading("Output torque", equals: 9.5, unit: "N·m", in: app)
        let animation = try readingText("Animation", in: app)
        XCTAssertTrue(animation.contains("Paused") || animation.contains("Step only"))
        try assertReadingText("Holo", contains: "On", in: app)

        let next = try reveal("guided.next", in: app)
        XCTAssertFalse(next.isEnabled, "Recenter is an explicit setup action before the first observation.")
        try applyStep(in: app)
        try nextStep(in: app)
        try assertStep("Move the phone; watch the surfaces", in: app)
        XCTAssertFalse(element("guided.action", in: app).exists)
        XCTAssertTrue(element("guided.expected", in: app).exists)
        try assertReading("Output speed", equals: -30, unit: "rpm", in: app)

        // Next records that the user explored the instruction; it does not certify a sensor pass.
        try nextStep(in: app)
        try assertStep("Compare Holo and another viewing angle", in: app)
        XCTAssertFalse(element("guided.action", in: app).exists)
        try nextStep(in: app)
        XCTAssertTrue(element("guided.finished", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("guided.step.title", in: app).exists)
        try endGuideAndConfirmWorkingBench(in: app, expectedGear: "Spur gear")
    }

    @MainActor
    func testSpurCheckpointsApplyAndRestartRestoresTwoToOneSetup() throws {
        let app = launchApp()
        try startLab("gearSpurDrive", in: app)
        try assertStep("Feel the drive crown at 60 rpm", in: app)
        try assertReading("Input speed", equals: 60, unit: "rpm", in: app)
        try assertReading("Output speed", equals: -30, unit: "rpm", in: app)
        XCTAssertTrue(try reveal("guided.next", in: app).isEnabled,
                      "Manual crown changes can continue without applying the exact checkpoint.")
        try applyStep(in: app)

        try nextStep(in: app)
        try assertStep("Double the speed with the crown", in: app)
        try applyStep(in: app)
        try assertReading("Input speed", equals: 120, unit: "rpm", in: app)
        try assertReading("Output speed", equals: -60, unit: "rpm", in: app)
        try assertReading("Output torque", equals: 9.5, unit: "N·m", in: app)

        try nextStep(in: app)
        try assertStep("Bring the drive to zero", in: app)
        try applyStep(in: app)
        try assertReading("Input speed", equals: 0, unit: "rpm", in: app)
        try assertReading("Output speed", equals: 0, unit: "rpm", in: app)

        try nextStep(in: app)
        try assertStep("Make the output gear larger", in: app)
        try applyStep(in: app)
        try assertReading("Input speed", equals: 60, unit: "rpm", in: app)
        try assertReading("Output speed", equals: -20, unit: "rpm", in: app)
        try assertReading("Speed reduction", equals: 3, unit: ":1", in: app)
        try assertReading("Output torque", equals: 14.25, unit: "N·m", in: app)

        try reveal("guided.restart", in: app).tap()
        try assertStep("Feel the drive crown at 60 rpm", in: app)
        try assertReading("Output speed", equals: -30, unit: "rpm", in: app)
        try assertReading("Speed reduction", equals: 2, unit: ":1", in: app)
        try assertReading("Output torque", equals: 9.5, unit: "N·m", in: app)
        XCTAssertTrue(try reveal("guided.next", in: app).isEnabled)
        try endGuideAndConfirmWorkingBench(in: app, expectedGear: "Spur gear")
    }

    @MainActor
    func testWormSetupAndSecondStartChangeReductionAndTorque() throws {
        let app = launchApp()
        try startLab("gearWormReduction", in: app)
        XCTAssertTrue(element("gears.stage", in: app).label.contains("Worm gear"))
        try assertStep("Watch a single-start worm", in: app)
        XCTAssertFalse(element("guided.action", in: app).exists)
        try assertReading("Input speed", equals: 120, unit: "rpm", in: app)
        try assertReading("Output speed", equals: -3, unit: "rpm", in: app)
        try assertReading("Speed reduction", equals: 40, unit: ":1", in: app)
        try assertReading("Output torque", equals: 190, unit: "N·m", in: app)

        try nextStep(in: app)
        try assertStep("Give the worm a second start", in: app)
        try applyStep(in: app)
        try assertReading("Output speed", equals: -6, unit: "rpm", in: app)
        try assertReading("Speed reduction", equals: 20, unit: ":1", in: app)
        try assertReading("Output torque", equals: 95, unit: "N·m", in: app)

        try nextStep(in: app)
        try assertStep("Inspect the skew shafts", in: app)
        XCTAssertFalse(element("guided.action", in: app).exists)
        try nextStep(in: app)
        XCTAssertTrue(element("guided.finished", in: app).waitForExistence(timeout: 5))
        try endGuideAndConfirmWorkingBench(in: app, expectedGear: "Worm gear")
    }

    @MainActor
    func testRackCheckpointsTradePinionSizeForSpeedAndForce() throws {
        let app = launchApp()
        try startLab("gearRackTravel", in: app)
        XCTAssertTrue(element("gears.stage", in: app).label.contains("Rack and pinion"))
        try assertStep("Follow a moving rack", in: app)
        XCTAssertFalse(element("guided.action", in: app).exists)
        try assertReading("Input speed", equals: 60, unit: "rpm", in: app)
        try assertReading("Rack speed", equals: 150.8, unit: "mm/s", accuracy: 0.05, in: app)
        try assertReading("Rack force", equals: 197.9, unit: "N", accuracy: 0.05, in: app)
        try assertReading("Pitch diameter", equals: 48, unit: "mm", in: app)

        try nextStep(in: app)
        try assertStep("Double the crown speed", in: app)
        try applyStep(in: app)
        try assertReading("Input speed", equals: 120, unit: "rpm", in: app)
        try assertReading("Rack speed", equals: 301.6, unit: "mm/s", accuracy: 0.05, in: app)
        try assertReading("Rack force", equals: 197.9, unit: "N", accuracy: 0.05, in: app)
        try assertReading("Pitch diameter", equals: 48, unit: "mm", in: app)

        try nextStep(in: app)
        try assertStep("Enlarge the pinion at the original speed", in: app)
        try applyStep(in: app)
        try assertReading("Input speed", equals: 60, unit: "rpm", in: app)
        try assertReading("Rack speed", equals: 226.2, unit: "mm/s", accuracy: 0.05, in: app)
        try assertReading("Rack force", equals: 131.9, unit: "N", accuracy: 0.05, in: app)
        try assertReading("Pitch diameter", equals: 72, unit: "mm", in: app)
        try nextStep(in: app)
        XCTAssertTrue(element("guided.finished", in: app).waitForExistence(timeout: 5))
        try endGuideAndConfirmWorkingBench(in: app, expectedGear: "Rack and pinion")
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    private func startLab(_ id: String, in app: XCUIApplication) throws {
        try reveal("guided.open", in: app).tap()
        XCTAssertTrue(element("guided.catalog", in: app).waitForExistence(timeout: 5))
        try reveal("guided.start.\(id)", in: app).tap()
        XCTAssertTrue(element("gears.stage", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("guided.step.title", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertStep(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        let step = try reveal("guided.step.title", in: app)
        XCTAssertEqual(step.label, title, file: file, line: line)
        XCTAssertTrue(element("guided.expected", in: app).exists, file: file, line: line)
    }

    @MainActor
    private func applyStep(in app: XCUIApplication) throws {
        let action = try reveal("guided.action", in: app)
        XCTAssertTrue(action.isEnabled)
        action.tap()
        let applied = NSPredicate(format: "enabled == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: applied, object: element("guided.action", in: app))], timeout: 5), .completed)
        XCTAssertTrue(element("guided.next", in: app).isEnabled)
    }

    @MainActor
    private func nextStep(in app: XCUIApplication) throws {
        let next = try reveal("guided.next", in: app)
        XCTAssertTrue(next.isEnabled)
        next.tap()
    }

    @MainActor
    private func endGuideAndConfirmWorkingBench(in app: XCUIApplication, expectedGear: String) throws {
        try reveal("guided.end", in: app).tap()
        XCTAssertFalse(element("guided.step.title", in: app).exists)
        XCTAssertFalse(element("guided.finished", in: app).exists)
        let stage = try reveal("gears.stage", in: app)
        XCTAssertTrue(stage.label.contains(expectedGear))
        let step = try reveal("gears.step", in: app)
        XCTAssertTrue(step.isEnabled)
        step.tap()
        XCTAssertEqual(element("gears.play", in: app).label, "Run")
        XCTAssertTrue(element("gears.readings", in: app).exists)
    }

    @MainActor
    private func assertReading(_ label: String, equals expected: Double, unit: String, accuracy: Double = 0.01, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        let text = try readingText(label, in: app)
        XCTAssertTrue(text.contains(unit), "Missing unit in live reading: \(text)", file: file, line: line)
        let numberText = text.replacingOccurrences(of: label, with: "")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: "")
        let expression = try NSRegularExpression(pattern: #"[-+]?(?:\d+(?:\.\d*)?|\.\d+)"#)
        guard let match = expression.firstMatch(in: numberText, range: NSRange(numberText.startIndex..., in: numberText)),
              let range = Range(match.range, in: numberText), let number = Double(numberText[range]) else {
            XCTFail("No numeric value in live reading: \(text)", file: file, line: line)
            throw LabTestError.missingReading(label)
        }
        XCTAssertEqual(number, expected, accuracy: accuracy, "Live \(label): \(text)", file: file, line: line)
    }

    @MainActor
    private func assertReadingText(_ label: String, contains expected: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(try readingText(label, in: app).contains(expected), file: file, line: line)
    }

    @MainActor
    private func readingText(_ label: String, in app: XCUIApplication) throws -> String {
        _ = try reveal("guided.readings", in: app)
        let row = element("guided.reading.\(label)", in: app)
        guard row.waitForExistence(timeout: 3) else {
            XCTFail("No live reading row for \(label).")
            throw LabTestError.missingReading(label)
        }
        return [row.label, row.value as? String ?? ""].joined(separator: " ")
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// ToyScreen has 20 pt content padding. Drag in that margin so the Metal
    /// orbit gesture, crown, and horizontal gear selector cannot capture scrolling.
    /// Read-only accessibility elements need visible geometry rather than a touch target.
    @MainActor
    private func reveal(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let readOnly = ["guided.step.title", "guided.readings", "gears.stage"].contains(identifier)
        for _ in 0..<8 {
            let target = element(identifier, in: app)
            let window = app.frame
            if target.exists && !readOnly && target.isHittable { return target }
            let candidates = app.scrollViews.allElementsBoundByIndex.compactMap { scroll -> (CGRect, Bool, Bool)? in
                guard scroll.exists else { return nil }
                let frame = scroll.frame.intersection(window)
                guard frame.width > 100, frame.height > 250, frame.height > frame.width * 0.6 else { return nil }
                let containsTarget = scroll.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
                return (frame, containsTarget, scroll.isHittable)
            }
            // Select the target's vertical container ahead of any underlying sheet content.
            guard let (scrollFrame, _, _) = candidates.max(by: { left, right in
                if left.1 != right.1 { return !left.1 && right.1 }
                if left.2 != right.2 { return !left.2 && right.2 }
                return left.0.height < right.0.height
            }) else { break }
            // Keep read-only text clear of navigation and tab bars as well.
            let viewport = scrollFrame.insetBy(dx: 0, dy: 70)
            let targetFrame = target.exists ? target.frame : .zero
            let visiblePart = targetFrame.intersection(viewport)
            if target.exists {
                if readOnly && !visiblePart.isNull && visiblePart.width > 20
                    && visiblePart.height >= min(32, targetFrame.height) { return target }
            }

            let moveUp = !target.exists || targetFrame.midY >= viewport.midY
            let distance = min(viewport.height * 0.55,
                               max(140, abs(targetFrame.midY - viewport.midY)))
            let x = scrollFrame.minX + min(8, scrollFrame.width * 0.02)
            let low = viewport.midY + distance / 2
            let high = viewport.midY - distance / 2
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x - window.minX, dy: (moveUp ? low : high) - window.minY))
            let end = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x - window.minX, dy: (moveUp ? high : low) - window.minY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Could not reveal \(identifier) after bounded scrolling.")
        throw LabTestError.missingElement(identifier)
    }

    private enum LabTestError: Error {
        case missingElement(String)
        case missingReading(String)
    }
}
