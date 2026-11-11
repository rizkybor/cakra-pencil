import XCTest

/// Sketch notes (iPad and Mac): draw on the map, save the drawing with a note, process it into a map object; and
/// show / hide field items per row, per section and several at once (Select). Uses Uji Vektor.
final class FieldSketchUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field"] + extra
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        return app
    }

    private func wait(_ element: XCUIElement, _ format: String, _ args: CVarArg..., timeout: TimeInterval = 8) -> Bool {
        let p = NSPredicate(format: format, argumentArray: args)
        return XCTWaiter.wait(for: [expectation(for: p, evaluatedWith: element)], timeout: timeout) == .completed
    }

    private func any(_ app: XCUIApplication, _ format: String, _ args: CVarArg...) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: format, argumentArray: args)).firstMatch
    }

    /// One finger stroke on the map (left part of the window, clear of the side panel).
    private func stroke(_ app: XCUIApplication, from a: CGVector, to b: CGVector) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: a).press(forDuration: 0.15, thenDragTo: window.coordinate(withNormalizedOffset: b))
    }

    private func tapUntilGone(_ button: XCUIElement, gone: XCUIElement, attempts: Int = 3) {
        for _ in 0..<attempts {
            guard button.waitForExistence(timeout: 3) else { return }
            Thread.sleep(forTimeInterval: 0.6)
            button.tap()
            if gone.waitForNonExistence(timeout: 3) { return }
        }
    }

    /// Tap Draw until the sketch bar shows (the panel can still be settling right after launch).
    private func startDrawing(_ app: XCUIApplication) {
        for _ in 0..<3 {
            app.buttons["fieldDraw"].tap()
            if app.buttons["sketchCancel"].waitForExistence(timeout: 3) { return }
        }
    }

    func testDrawSketchNoteAndMakeLine() throws {
        let app = launch(["-cp-fake-gps", "-6.8945,107.6085"])
        let summary = app.staticTexts["fieldSummary"]
        guard summary.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        XCTAssertTrue(wait(summary, "label == '0 tracks · 0 notes'"))

        // Draw: the bar appears, Done waits for a stroke.
        startDrawing(app)
        let done = app.buttons["sketchDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Sketch bar shown")
        XCTAssertFalse(done.isEnabled, "Nothing drawn yet")
        let count = app.staticTexts["sketchStrokeCount"]

        // Two strokes, undo one, draw it again.
        stroke(app, from: CGVector(dx: 0.25, dy: 0.45), to: CGVector(dx: 0.42, dy: 0.52))
        XCTAssertTrue(wait(count, "label == '1 stroke'"), "First stroke: \(count.label)")
        stroke(app, from: CGVector(dx: 0.42, dy: 0.52), to: CGVector(dx: 0.50, dy: 0.66))
        XCTAssertTrue(wait(count, "label == '2 strokes'"))
        XCTAssertTrue(app.buttons["sketchUndo"].isEnabled)
        app.buttons["sketchUndo"].tap()
        XCTAssertTrue(wait(count, "label == '1 stroke'"), "Undo stroke")
        stroke(app, from: CGVector(dx: 0.42, dy: 0.52), to: CGVector(dx: 0.52, dy: 0.62))
        XCTAssertTrue(wait(count, "label == '2 strokes'"))
        let drawing = XCTAttachment(screenshot: app.screenshot()); drawing.name = "sketch-drawing"; drawing.lifetime = .keepAlways; add(drawing)

        // Done → the note editor with the sketch preview; save as a path note.
        done.tap()
        XCTAssertTrue(any(app, "identifier == 'noteSketchPreview'").waitForExistence(timeout: 5), "Editor shows the sketch")
        app.buttons["Path / road"].tap()
        let text = app.descendants(matching: .any).matching(identifier: "noteText").firstMatch
        text.tap()
        text.typeText("Small path to the pit")
        tapUntilGone(app.buttons["noteSave"], gone: text)
        XCTAssertTrue(wait(summary, "label == '0 tracks · 1 note'"), "Note saved: \(summary.label)")
        XCTAssertTrue(done.waitForNonExistence(timeout: 3), "Back to the map, bar gone")
        let row = any(app, "label BEGINSWITH 'Small path to the pit' AND label CONTAINS 'with sketch'")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Listed with the sketch indicator")
        let onMap = XCTAttachment(screenshot: app.screenshot()); onMap.name = "sketch-on-map"; onMap.lifetime = .keepAlways; add(onMap)

        // Detail: the sketch is shown; Make map object suggests path lines first.
        row.tap()
        XCTAssertTrue(app.staticTexts["noteSketchInfo"].waitForExistence(timeout: 5), "Detail shows the sketch")
        XCTAssertTrue(app.staticTexts["noteSketchInfo"].label.contains("2 strokes"))
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "sketch-note-detail"; detail.lifetime = .keepAlways; add(detail)
        app.buttons["noteMakeObject"].tap()
        let path = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["noteSymbol-506", "noteSymbol-506.0", "noteSymbol-505", "noteSymbol-505.0"])).firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5), "Path symbol suggested")
        path.tap()
        XCTAssertTrue(app.buttons["noteShowObject"].waitForExistence(timeout: 5), "Note linked to the new line object")
        XCTAssertTrue(app.descendants(matching: .any)["noteDoneBadge"].exists, "Note marked done")
    }

    func testCancelDiscardsTheSketch() throws {
        let app = launch()
        let summary = app.staticTexts["fieldSummary"]
        guard summary.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        startDrawing(app)
        XCTAssertTrue(app.buttons["sketchCancel"].waitForExistence(timeout: 5))
        stroke(app, from: CGVector(dx: 0.25, dy: 0.45), to: CGVector(dx: 0.45, dy: 0.55))
        XCTAssertTrue(wait(app.staticTexts["sketchStrokeCount"], "label == '1 stroke'"))
        app.buttons["sketchClear"].tap()
        XCTAssertTrue(wait(app.staticTexts["sketchStrokeCount"], "NOT (label CONTAINS 'stroke')"), "Cleared")
        app.buttons["sketchCancel"].tap()
        XCTAssertTrue(app.buttons["sketchCancel"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(wait(summary, "label == '0 tracks · 0 notes'"), "Nothing saved")
    }

    func testShowHideFieldItems() throws {
        let app = launch(["-cp-sample-sketch-note", "-cp-sample-photo-note"])
        let summary = app.staticTexts["fieldSummary"]
        guard summary.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        XCTAssertTrue(wait(summary, "label == '0 tracks · 2 notes'"))
        let notesEye = app.buttons["fieldEye-notes"]
        XCTAssertEqual(notesEye.value as? String, "All shown")

        // Per row: hide the sketch note.
        app.buttons["Hide Thicket, fight"].tap()
        XCTAssertTrue(any(app, "label BEGINSWITH 'Thicket, fight' AND label CONTAINS 'hidden'").waitForExistence(timeout: 3))
        XCTAssertTrue(wait(notesEye, "value == 'Some hidden'"), "Section eye shows the mixed state")

        // Per section: shows everything again.
        notesEye.tap()
        XCTAssertTrue(wait(notesEye, "value == 'All shown'"))
        XCTAssertTrue(any(app, "label BEGINSWITH 'Thicket, fight' AND NOT (label CONTAINS 'hidden')").exists)

        // Several at once: Select, tick both, Hide.
        app.buttons["fieldSelect"].tap()
        any(app, "label BEGINSWITH 'Thicket, fight'").tap()
        any(app, "label BEGINSWITH 'Boulder with photo'").tap()
        XCTAssertTrue(wait(app.staticTexts["fieldSelectionCount"], "label == '2 selected'"))
        app.buttons["fieldHideSelected"].tap()
        XCTAssertTrue(wait(notesEye, "value == 'All hidden'"), "Both hidden")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "field-visibility"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["fieldShowSelected"].tap()
        XCTAssertTrue(wait(notesEye, "value == 'All shown'"))
        app.buttons["fieldSelect"].tap()
        XCTAssertFalse(app.staticTexts["fieldSelectionCount"].exists, "Select mode closed")
    }

    /// A second sketch drawn next to a saved sketch note: both on the map (the saved one in its note colour).
    func testDrawNextToSavedSketchNote() throws {
        let app = launch(["-cp-sample-sketch-note"])
        let summary = app.staticTexts["fieldSummary"]
        guard summary.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        XCTAssertTrue(wait(summary, "label == '0 tracks · 1 note'"))
        XCTAssertTrue(any(app, "label BEGINSWITH 'Thicket, fight' AND label CONTAINS 'with sketch'").exists)
        startDrawing(app)
        stroke(app, from: CGVector(dx: 0.20, dy: 0.40), to: CGVector(dx: 0.33, dy: 0.47))
        stroke(app, from: CGVector(dx: 0.33, dy: 0.47), to: CGVector(dx: 0.30, dy: 0.60))
        XCTAssertTrue(wait(app.staticTexts["sketchStrokeCount"], "label == '2 strokes'"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "sketch-drawing-and-note"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["sketchCancel"].tap()
        XCTAssertTrue(wait(summary, "label == '0 tracks · 1 note'"), "Cancel saves nothing")
    }
}
