import XCTest

/// Appearance button in the project list header: each tap switches Light → Dark → System → Light; the choice is kept.
final class AppearanceUITests: XCTestCase {
    func testSwitchAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        let button = app.buttons["appearanceButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))

        // Start from System (default, or left from an earlier run): tap until System shows.
        for _ in 0..<3 where !app.buttons["Appearance: System"].exists { button.tap() }
        XCTAssertTrue(app.buttons["Appearance: System"].waitForExistence(timeout: 5), "System")

        app.buttons["appearanceButton"].tap()
        XCTAssertTrue(app.buttons["Appearance: Light"].waitForExistence(timeout: 5), "System → Light")
        let light = XCTAttachment(screenshot: app.screenshot()); light.name = "light"; light.lifetime = .keepAlways; add(light)

        app.buttons["appearanceButton"].tap()
        XCTAssertTrue(app.buttons["Appearance: Dark"].waitForExistence(timeout: 5), "Light → Dark")
        let dark = XCTAttachment(screenshot: app.screenshot()); dark.name = "dark"; dark.lifetime = .keepAlways; add(dark)

        // Kept after relaunch, then on to System (default).
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Appearance: Dark"].waitForExistence(timeout: 10), "Choice kept")
        app.buttons["appearanceButton"].tap()
        XCTAssertTrue(app.buttons["Appearance: System"].waitForExistence(timeout: 5), "Dark → System")
    }
}
