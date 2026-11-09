import XCTest

/// Appearance: System (default) / Light / Dark from the project list header; the choice is kept.
final class AppearanceUITests: XCTestCase {
    func testSwitchAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        let button = app.buttons["appearanceButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))

        button.tap()
        app.buttons["appearance-dark"].tap()
        XCTAssertTrue(app.buttons["Appearance: Dark"].waitForExistence(timeout: 5), "Dark chosen")
        let dark = XCTAttachment(screenshot: app.screenshot()); dark.name = "dark"; dark.lifetime = .keepAlways; add(dark)

        app.buttons["appearanceButton"].tap()
        app.buttons["appearance-light"].tap()
        XCTAssertTrue(app.buttons["Appearance: Light"].waitForExistence(timeout: 5), "Light chosen")
        let light = XCTAttachment(screenshot: app.screenshot()); light.name = "light"; light.lifetime = .keepAlways; add(light)

        // Kept after relaunch, then back to System (default).
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Appearance: Light"].waitForExistence(timeout: 10), "Choice kept")
        app.buttons["appearanceButton"].tap()
        app.buttons["appearance-system"].tap()
        XCTAssertTrue(app.buttons["Appearance: System"].waitForExistence(timeout: 5))
    }
}
