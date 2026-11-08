import XCTest

final class ProbeFlowTests: XCTestCase {
    @MainActor
    func testMediaTrialReportAndCleanup() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Jabra Button Probe"].waitForExistence(timeout: 10))
        let start = app.buttons["Start media test"]
        scrollTo(start, in: app)
        start.tap()
        XCTAssertTrue(app.staticTexts["Test tone playing"].waitForExistence(timeout: 5))
        let trial = app.buttons["Test: Idle baseline"]
        scrollTo(trial, in: app)
        trial.tap()
        XCTAssertTrue(app.staticTexts["Complete"].waitForExistence(timeout: 18))
        XCTAssertTrue(app.staticTexts["BLE: 0 · Media: 0"].exists)

        app.buttons["Report"].tap()
        XCTAssertTrue(app.navigationBars["Diagnostic report"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share diagnostic report"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "candidates, not proof")).firstMatch.exists)
        app.buttons["Done"].tap()

        let stop = app.buttons["Stop all tests"]
        scrollTo(stop, in: app)
        stop.tap()
        app.swipeDown()
        app.swipeDown()
        let restarted = app.buttons["Start media test"]
        scrollTo(restarted, in: app)
        XCTAssertTrue(restarted.exists)
        app.terminate()
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
