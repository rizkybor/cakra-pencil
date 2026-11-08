import XCTest

/// Stage 1d (iPad and Mac): open a field note, view its photo full screen, make a map object from it (the note is
/// marked done and linked to the object), filter notes still to do. Uses `-cp-sample-photo-note` on Uji Vektor.
final class FieldNoteUITests: XCTestCase {
    func testOpenNoteViewPhotoAndMakeMapObject() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field", "-cp-sample-photo-note"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Boulder with photo'")).firstMatch
        guard note.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        note.tap()

        // Detail: photo, text, category, actions.
        let photo = app.buttons["notePhoto"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "Note detail with its photo")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Camera facing 45° NE'")).firstMatch.exists,
                      "Camera direction shown")

        // Full-screen photo viewer.
        photo.tap()
        let close = app.buttons["photoViewerClose"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Photo viewer open")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Facing 45° NE'")).firstMatch.exists)
        let viewer = XCTAttachment(screenshot: app.screenshot()); viewer.name = "photo-viewer"; viewer.lifetime = .keepAlways; add(viewer)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), "Viewer closed")

        // Make a map object: boulder suggested first.
        app.buttons["noteMakeObject"].tap()
        let boulder = app.buttons.matching(NSPredicate(format: "identifier IN %@", ["noteSymbol-204", "noteSymbol-204.0"])).firstMatch
        XCTAssertTrue(boulder.waitForExistence(timeout: 5), "204 Boulder suggested")
        boulder.tap()
        XCTAssertTrue(app.buttons["noteShowObject"].waitForExistence(timeout: 5), "Note linked to the new object")
        XCTAssertTrue(app.descendants(matching: .any)["noteDoneBadge"].exists, "Note marked done")
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "note-detail"; detail.lifetime = .keepAlways; add(detail)

        // Back to the list; the "To do" filter hides it.
        app.buttons["noteBack"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        let todo = app.buttons["To do"].firstMatch
        if todo.waitForExistence(timeout: 3) {
            todo.tap()
            XCTAssertTrue(note.waitForNonExistence(timeout: 3), "Processed note not in To do")
        }
    }

    /// Photos on an existing note: add (Upload photo on Mac, camera / library on iPad) and remove.
    func testAddAndRemoveNotePhoto() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field", "-cp-sample-photo-note"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Boulder with photo'")).firstMatch
        guard note.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        note.tap()
        let photo = app.buttons["notePhoto"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["noteAddPhoto"].exists, "More photos can be added (1 of 4)")

        photo.press(forDuration: 1.0)
        let remove = app.buttons["Remove photo"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(photo.waitForNonExistence(timeout: 5), "Photo removed")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Camera facing'")).firstMatch.exists,
                       "No camera direction without photos")
        XCTAssertTrue(app.descendants(matching: .any)["noteAddPhoto"].exists)
    }

    /// Markup on a photo (Apple Pencil / finger / mouse): draw, save; the photo shows the drawing and a markup badge.
    func testMarkupPhoto() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field", "-cp-sample-photo-note"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Boulder with photo'")).firstMatch
        guard note.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor not available") }
        note.tap()
        let photo = app.buttons["notePhoto"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["Has markup"].exists)
        photo.tap()
        let markup = app.buttons["photoMarkup"]
        XCTAssertTrue(markup.waitForExistence(timeout: 5), "Markup button in the viewer")
        markup.tap()
        let canvas = app.descendants(matching: .any)["markupCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "Markup canvas")
        // A circle-ish stroke around the "boulder".
        let a = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
        a.press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6)))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "markup-editor"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["markupDone"].tap()
        XCTAssertTrue(canvas.waitForNonExistence(timeout: 5), "Editor closed")
        let viewer = XCTAttachment(screenshot: app.screenshot()); viewer.name = "markup-viewer"; viewer.lifetime = .keepAlways; add(viewer)
        app.buttons["photoViewerClose"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Has markup"].waitForExistence(timeout: 5), "Markup badge on the photo")
    }
}
