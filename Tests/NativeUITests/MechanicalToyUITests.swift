import XCTest

final class MechanicalToyUITests: XCTestCase {
    @MainActor
    func testSaveRestoreAndRoomNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        let experiment = app.buttons["experiment.lever"]
        for _ in 0..<4 where !experiment.isHittable { app.swipeUp() }
        XCTAssertTrue(experiment.waitForExistence(timeout: 8))
        experiment.tap()
        XCTAssertTrue(app.buttons["save.experiment"].waitForExistence(timeout: 5))
        app.buttons["save.experiment"].tap()
        app.buttons["save.confirm"].tap()
        app.tabBars.buttons["Notebook"].tap()
        let record = app.buttons["notebook.run.lever"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        let restore = app.buttons["notebook.restore"]
        for _ in 0..<4 where !restore.isHittable { app.swipeUp() }
        restore.tap()
        XCTAssertTrue(app.buttons["transport.play"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Room"].tap()
        XCTAssertTrue(app.staticTexts["Room"].firstMatch.waitForExistence(timeout: 5))
    }
}
