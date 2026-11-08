import XCTest

/// Guide for new users: opens by itself on first launch (forced with `-cp-show-guide`; other test launches skip it),
/// six pages, reopened from the Guide button, device note on a Wi-Fi-only iPad.
final class GuideUITests: XCTestCase {
    func testGuidePagesAndReopen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-show-guide", "-cp-no-splash"]
        app.launch()

        let next = app.buttons["guideNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 8), "Guide opens by itself")
        XCTAssertTrue(app.staticTexts["Welcome to OCCA"].exists)
        XCTAssertTrue(app.images["guideImage"].firstMatch.exists, "Screenshot on the page")
        let titles = ["Start a project", "Draw the map", "Fieldwork on iPad", "iPad ⇄ Mac", "Process and share"]
        for t in titles {
            next.tap()
            XCTAssertTrue(app.staticTexts[t].waitForExistence(timeout: 3), t)
            if t == "iPad ⇄ Mac" {
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "guide-ipad-mac"; shot.lifetime = .keepAlways; add(shot)
            }
        }
        XCTAssertFalse(next.exists, "Last page")
        app.buttons["guideDone"].tap()
        XCTAssertTrue(app.buttons["guideDone"].waitForNonExistence(timeout: 3), "Closed")

        // Reopen from the project list; Skip closes it.
        app.buttons["guideButton"].tap()
        XCTAssertTrue(app.buttons["guideSkip"].waitForExistence(timeout: 3), "Reopened")
        app.buttons["guideSkip"].tap()
        XCTAssertTrue(app.buttons["guideSkip"].waitForNonExistence(timeout: 3))
    }

    func testWifiOnlyIPadNote() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-show-guide", "-cp-no-splash", "-cp-wifi-only"]
        app.launch()
        let next = app.buttons["guideNext"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        for _ in 0..<3 { next.tap() }
        XCTAssertTrue(app.staticTexts["Fieldwork on iPad"].waitForExistence(timeout: 3))
        let note = app.descendants(matching: .any)["guideDeviceNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "Device note")
        XCTAssertTrue(note.label.contains("no GPS chip"), note.label)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "guide-wifi"; shot.lifetime = .keepAlways; add(shot)
    }
}
