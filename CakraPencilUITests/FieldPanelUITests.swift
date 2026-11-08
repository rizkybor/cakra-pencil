import XCTest

/// Field panel (iPad and Mac): GPX import shows tracks and notes in the panel and on the map; show/hide, mark a note
/// done, delete. Needs Documents/Field-Sample.gpx (a track and two waypoints inside the Uji Vektor frame).
final class FieldPanelUITests: XCTestCase {
    func testImportGPXAndManageFieldData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field", "-cp-import-gpx", "Field-Sample.gpx"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let summary = app.staticTexts["fieldSummary"]
        guard summary.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        let imported = NSPredicate(format: "label == '1 track · 2 notes'")
        guard XCTWaiter.wait(for: [expectation(for: imported, evaluatedWith: summary)], timeout: 10) == .completed else {
            throw XCTSkip("Documents/Field-Sample.gpx not in the test simulator (\(summary.label))")
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Survey walk'")).firstMatch.exists,
                      "Track listed with its name")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'GPX'")).firstMatch.exists,
                      "Imported track marked GPX")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Big boulder 2 m'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["2 to do"].exists, "Both notes still to do")

        // Hide and show all notes.
        app.buttons["Hide notes"].tap()
        XCTAssertTrue(app.buttons["Show notes"].waitForExistence(timeout: 3))
        app.buttons["Show notes"].tap()

        // Mark a note done (context menu), then delete the other one.
        let check = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Check vegetation'")).firstMatch
        check.press(forDuration: 1.0)
        let done = app.buttons["Mark as done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.staticTexts["1 to do"].waitForExistence(timeout: 5), "One note done")
        let boulder = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Big boulder 2 m'")).firstMatch
        boulder.press(forDuration: 1.0)
        let delete = app.buttons["Delete note"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label == '1 track · 1 note'"), evaluatedWith: summary)], timeout: 5) == .completed,
                      "Note deleted")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "field-panel"; shot.lifetime = .keepAlways; add(shot)
    }
}
