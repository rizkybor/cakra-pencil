import XCTest

/// Ready-for-the-field check and field mode on iPad (fake GPS inside the Uji Vektor frame).
final class FieldModeUITests: XCTestCase {
    func testReadyCheckAndFieldMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field", "-cp-fake-gps", "-6.8945,107.6085"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let ready = app.buttons["fieldReadyCheck"]
        guard ready.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }

        // Ready check: summary + offline checklist.
        ready.tap()
        XCTAssertTrue(app.descendants(matching: .any)["readySummary"].waitForExistence(timeout: 5), "Ready check summary")
        XCTAssertTrue(app.staticTexts["Map area locked"].exists)
        XCTAssertTrue(app.staticTexts["HD image — Satellite"].exists)
        XCTAssertTrue(app.staticTexts["Symbol sets"].exists)
        XCTAssertTrue(app.staticTexts["Free storage"].exists)
        app.navigationBars["Ready for the field"].buttons["Done"].tap()

        // Field mode: normal tools hidden, big buttons, exit.
        app.buttons["fieldModeEnter"].tap()
        let exit = app.buttons["fieldModeExit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5), "Field mode on")
        XCTAssertFalse(app.buttons["Pen tool (bezier)"].exists, "Drawing tools hidden in field mode")

        // Record from the big button, then stop.
        app.buttons["fieldModeRecord"].tap()
        let stop = app.buttons["fieldModeStop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "Recording")
        Thread.sleep(forTimeInterval: 1.5)
        // Pause / resume: the same track continues with a new segment.
        app.buttons["fieldModePause"].tap()
        let resume = app.buttons["fieldModeResume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3), "Paused")
        Thread.sleep(forTimeInterval: 1)
        resume.tap()
        XCTAssertTrue(app.buttons["fieldModePause"].waitForExistence(timeout: 3), "Resumed")
        Thread.sleep(forTimeInterval: 1.5)
        stop.tap()
        XCTAssertTrue(app.buttons["fieldModeRecord"].waitForExistence(timeout: 5), "Stopped")

        // Touch lock: buttons gone until the unlock button is held for 1 s.
        app.buttons["fieldModeLock"].tap()
        let unlock = app.descendants(matching: .any)["fieldModeUnlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3), "Locked")
        XCTAssertFalse(app.buttons["fieldModeRecord"].exists, "Buttons hidden while locked")
        unlock.press(forDuration: 0.3)
        XCTAssertFalse(app.buttons["fieldModeRecord"].waitForExistence(timeout: 1), "A short press does not unlock")
        unlock.press(forDuration: 1.6)
        XCTAssertTrue(app.buttons["fieldModeRecord"].waitForExistence(timeout: 3), "Unlocked after holding")

        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "field-mode"; shot.lifetime = .keepAlways; add(shot)
        exit.tap()
        XCTAssertTrue(app.buttons["Pen tool (bezier)"].waitForExistence(timeout: 5), "Normal workspace back")
        XCTAssertTrue(app.staticTexts["fieldSummary"].label.hasPrefix("1 track"), "The track recorded in field mode is kept")
    }
}
