import XCTest

/// Field capture on iPad with fake GPS inside the Uji Vektor frame: record a track, add a note, average a position.
final class FieldCaptureUITests: XCTestCase {
    func testRecordTrackAddNoteAndAveragePosition() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field", "-cp-fake-gps", "-6.8945,107.6085"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let summary = app.staticTexts["fieldSummary"]
        guard summary.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        func waitSummary(_ text: String, _ timeout: TimeInterval = 8) -> Bool {
            XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == %@", text), evaluatedWith: summary)], timeout: timeout) == .completed
        }
        XCTAssertTrue(waitSummary("0 tracks · 0 notes"))

        // 1. Record a track for a few seconds (fake GPS walks north-east), REC badge on the map, then stop.
        app.buttons["fieldRecord"].tap()
        let badge = app.buttons["recordingBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "REC badge on the map")
        Thread.sleep(forTimeInterval: 3)
        let stats = app.staticTexts["fieldRecordingStats"]
        XCTAssertTrue(stats.exists)
        XCTAssertFalse(stats.label.hasSuffix(" 0 points"), "GPS points recorded: \(stats.label)")
        app.buttons["fieldStop"].tap()
        XCTAssertTrue(badge.waitForNonExistence(timeout: 5), "Badge gone after stop")
        XCTAssertTrue(waitSummary("1 track · 0 notes"), "Track saved: \(summary.label)")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Track 1'")).firstMatch.exists)

        // 2. Add a note (category + text) at the GPS position.
        app.buttons["fieldAddNote"].tap()
        let text = app.descendants(matching: .any).matching(identifier: "noteText").firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        app.buttons["Boulder / rock"].tap()
        text.tap()
        text.typeText("Test boulder 2 m")
        // The on-screen keyboard may slide in and move the sheet while tapping: retry until the sheet is gone.
        tapUntilGone(app.buttons["noteSave"], gone: text)
        XCTAssertTrue(waitSummary("1 track · 1 note"), "Note saved: \(summary.label)")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Test boulder 2 m' AND label CONTAINS 'GPS'")).firstMatch.exists,
                      "Note at the GPS position (accuracy shown)")

        // 3. Average a position for 10 s and save it.
        app.buttons["fieldAverage"].tap()
        let start = app.buttons["averageStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        app.buttons["10 s"].tap()
        start.tap()
        XCTAssertTrue(app.staticTexts["averageResult"].waitForExistence(timeout: 20), "Averaging finished")
        tapUntilGone(app.buttons["averageSave"], gone: app.buttons["averageSave"])
        XCTAssertTrue(waitSummary("1 track · 2 notes"), "Averaged position saved: \(summary.label)")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'averaged ±'")).firstMatch.exists,
                      "Averaged accuracy listed")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "field-capture"; shot.lifetime = .keepAlways; add(shot)
    }

    private func tapUntilGone(_ button: XCUIElement, gone: XCUIElement, attempts: Int = 3) {
        for _ in 0..<attempts {
            guard button.waitForExistence(timeout: 3) else { return }
            Thread.sleep(forTimeInterval: 0.6)
            button.tap()
            if gone.waitForNonExistence(timeout: 3) { return }
        }
    }
}
