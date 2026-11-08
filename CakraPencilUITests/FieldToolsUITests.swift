import XCTest

/// Fieldwork stage 2 (iPad capture, panel on iPad and Mac): quick vegetation classes, bearing/distance offset,
/// track → line objects, survey coverage, field report PDF. Uses Uji Vektor and Documents/Field-Sample.gpx.
final class FieldToolsUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field"] + extra
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        return app
    }

    private func label(_ app: XCUIApplication, beginsWith s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", s)).firstMatch
    }

    func testVegetationAndOffsetNote() throws {
        let app = launch()
        guard app.buttons["fieldVegetation"].waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }

        // Vegetation: two classes in a row at the map center.
        app.buttons["fieldVegetation"].tap()
        let center = app.buttons["Map center"].firstMatch
        XCTAssertTrue(center.waitForExistence(timeout: 5))
        center.tap()
        app.buttons["veg-408"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vegetationSaved"].waitForExistence(timeout: 3), "Class noted")
        app.buttons["veg-401"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "vegetation"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars["Vegetation"].buttons["Done"].tap()
        XCTAssertTrue(label(app, beginsWith: "408 Walk").waitForExistence(timeout: 5), "Vegetation note listed")
        XCTAssertTrue(label(app, beginsWith: "401 Open land").exists)

        // Offset: 50 m east of the map center.
        app.buttons["fieldAddNote"].tap()
        let center2 = app.buttons["Map center"].firstMatch
        XCTAssertTrue(center2.waitForExistence(timeout: 5))
        center2.tap()
        let toggle = app.switches["noteOffset"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if toggle.value as? String != "1" { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }
        let bearing = app.textFields["offsetBearing"]
        XCTAssertTrue(bearing.waitForExistence(timeout: 3), "Offset fields shown")
        bearing.tap(); bearing.typeText("90")
        let distance = app.textFields["offsetDistance"]
        distance.tap(); distance.typeText("50")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '50 m at 90° E'")).firstMatch.waitForExistence(timeout: 3),
                      "Target described")
        let text = app.descendants(matching: .any).matching(identifier: "noteText").firstMatch
        text.tap(); text.typeText("Boulder across the stream")
        tapUntilGone(app.buttons["noteSave"])
        let note = label(app, beginsWith: "Boulder across the stream")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Offset 50 m at 90° E'")).firstMatch
            .waitForExistence(timeout: 5), "Offset kept with the note")
    }

    func testTrackToLineAndCoverage() throws {
        let app = launch(["-cp-import-gpx", "Field-Sample.gpx"])
        let track = label(app, beginsWith: "Survey walk")
        guard track.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor or Documents/Field-Sample.gpx not available") }

        // Coverage on: a percentage of the frame.
        app.buttons["coverageToggle"].tap()
        let percent = app.staticTexts["coveragePercent"]
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "label CONTAINS '% of the map area walked'"), evaluatedWith: percent)],
                                     timeout: 10) == .completed, "Coverage measured (\(percent.label))")

        // Track → line: the editor with a path symbol, then objects.
        track.press(forDuration: 1.0)
        let make = app.buttons["Make line object…"]
        XCTAssertTrue(make.waitForExistence(timeout: 5))
        make.tap()
        let result = app.staticTexts["trackLineResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Track → line editor")
        XCTAssertTrue(result.label.hasPrefix("1 line"), result.label)
        XCTAssertTrue(app.buttons["trackLineSymbol"].label.contains("50"), "A path symbol is chosen (\(app.buttons["trackLineSymbol"].label))")
        app.sliders["trackLineStart"].adjust(toNormalizedSliderPosition: 0.3)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "track-line"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["trackMakeObjects"].tap()
        XCTAssertTrue(track.waitForExistence(timeout: 5), "Back to the list")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'from Survey walk'")).firstMatch.waitForExistence(timeout: 5),
                      "Objects made")
        let done = XCTAttachment(screenshot: app.screenshot()); done.name = "track-line-done"; done.lifetime = .keepAlways; add(done)
    }

    /// The report is written to Documents/Field-Report-Test.pdf for a visual check.
    func testFieldReportPDF() throws {
        let app = launch(["-cp-import-gpx", "Field-Sample.gpx", "-cp-sample-photo-note", "-cp-field-report", "Field-Report-Test.pdf"])
        guard label(app, beginsWith: "Survey walk").waitForExistence(timeout: 15) else { throw XCTSkip("Sample data not available") }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Field report saved'")).firstMatch.waitForExistence(timeout: 30))
    }

    /// The simulator keyboard can shift the sheet while a tap is on its way; tap again until the button is gone.
    private func tapUntilGone(_ button: XCUIElement, tries: Int = 4) {
        for _ in 0..<tries where button.exists {
            button.tap()
            _ = button.waitForNonExistence(timeout: 2)
        }
    }
}
