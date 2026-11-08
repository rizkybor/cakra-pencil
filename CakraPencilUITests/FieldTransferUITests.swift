import XCTest

/// Field data between devices (`.occafield`, iPad and Mac alike): export from one copy of the project, import into a
/// fresh copy — tracks, notes and photos arrive, the menu offers both directions. Uses Uji Vektor and
/// Documents/Field-Sample.gpx; writes Documents/Field-Transfer-Test.occafield.
final class FieldTransferUITests: XCTestCase {
    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field"] + extra
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        return app
    }

    private func waitLabel(_ app: XCUIApplication, contains s: String, timeout: TimeInterval = 15) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch.waitForExistence(timeout: timeout)
    }

    func testExportThenImportIntoFreshProject() throws {
        // "iPad": survey data, exported.
        var app = launch(["-cp-import-gpx", "Field-Sample.gpx", "-cp-sample-photo-note", "-cp-export-field", "Field-Transfer-Test.occafield"])
        guard app.staticTexts["fieldSummary"].waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        guard waitLabel(app, contains: "Field data saved") else {
            throw XCTSkip("Documents/Field-Sample.gpx not in the test simulator")
        }

        // The Data menu: field data both ways, then GPX.
        app.buttons["fieldMenu"].tap()
        XCTAssertTrue(app.buttons["Import field data…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Export field data…"].exists)
        XCTAssertTrue(app.buttons["Import GPX…"].exists)
        app.buttons["Export field data…"].tap()
        XCTAssertTrue(app.buttons["All field data"].waitForExistence(timeout: 3), "Export choice")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New since'")).firstMatch.exists, "Offered after the first export")
        let dialog = XCTAttachment(screenshot: app.screenshot()); dialog.name = "export-choice"; dialog.lifetime = .keepAlways; add(dialog)
        app.terminate()

        // "Mac": the same project without field data (fixtures restored), import the file.
        app = launch(["-cp-import-field", "Field-Transfer-Test.occafield"])
        let summary = app.staticTexts["fieldSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertTrue(waitLabel(app, contains: "1 new track, 3 new notes"), "Import summary")
        XCTAssertEqual(summary.label, "1 track · 3 notes")
        // The photo came along.
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Boulder with photo'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        XCTAssertTrue(app.buttons["notePhoto"].firstMatch.waitForExistence(timeout: 5), "Photo imported")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "imported"; shot.lifetime = .keepAlways; add(shot)
    }
}
