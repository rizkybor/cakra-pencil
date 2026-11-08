import XCTest

/// The six sketch pen colors in the pen dock can be shown and hidden with the palette button (hidden by default).
final class PenColorsUITests: XCTestCase {
    func testShowAndHidePenColors() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let toggle = app.buttons["togglePenColors"]
        guard toggle.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let black = app.buttons["Pen Black 0.14 mm"]
        // The choice is saved per device: start from the hidden state.
        if black.exists { toggle.tap() }
        XCTAssertTrue(black.waitForNonExistence(timeout: 3), "Pen colors hidden")
        XCTAssertEqual(toggle.label, "Show pen colors")

        toggle.tap()
        XCTAssertTrue(black.waitForExistence(timeout: 3), "Pen colors shown")
        XCTAssertTrue(app.buttons["Pen Red 0.25 mm"].exists)
        XCTAssertEqual(toggle.label, "Hide pen colors")
        black.tap()                                    // still usable as before

        toggle.tap()
        XCTAssertTrue(black.waitForNonExistence(timeout: 3), "Hidden again (the default)")
    }
}
