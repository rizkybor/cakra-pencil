import XCTest

/// Course page: text + shapes on the map (Objects tab), row limit and description position, preview without
/// north arrow / title box.
final class CourseItemsUITests: XCTestCase {
    func testTextShapesAndDescriptionLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let open = app.buttons["Open Course Settings"]
        guard open.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: open)
        wait(for: [ready], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        open.tap()
        if !app.staticTexts["Course Settings"].waitForExistence(timeout: 4) { open.tap() }
        XCTAssertTrue(app.staticTexts["Course Settings"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)

        let x = CGFloat.random(in: 0.16...0.22), y = CGFloat.random(in: 0.30...0.36)
        func map(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y + dy)) }

        // Objects left over from other runs (if any) must not throw off the counts.
        app.segmentedControls.buttons["Objects"].tap()
        let parkirBefore = app.buttons.matching(NSPredicate(format: "label == 'Text Parkir'")).count
        app.segmentedControls.buttons["Courses"].tap()

        // A small course for the Descriptions tab.
        app.buttons["New course"].tap()
        app.buttons["Place Start"].tap()
        map(0, 0.25).tap()
        map(0.1, 0.27).tap()
        map(0.2, 0.25).tap()
        app.buttons["Place Finish"].tap()
        map(0.25, 0.3).tap()

        // Text: tap the map → the Objects tab opens with the text editor.
        app.buttons["Text tool"].tap()
        map(0.05, 0.03).tap()   // inside the paper bounds (the random y position may land on the top edge)
        let field = app.textFields["courseItemText"].exists ? app.textFields["courseItemText"] : app.textViews["courseItemText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Text editor in the Objects tab")
        field.typeText("Parkir")   // new text: the field is empty and focused right away
        // Font style: bold + italic (the text is saved when focus moves).
        let weight = app.segmentedControls["courseTextWeight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 3), "Font weight picker")
        weight.buttons["Bold"].tap()
        XCTAssertTrue(weight.buttons["Bold"].isSelected)
        let italic = app.descendants(matching: .any)["courseTextItalic"]
        XCTAssertTrue(italic.exists, "Italic button")
        italic.tap()
        XCTAssertTrue(app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'Font size'")).firstMatch.exists)

        // Rectangle: drag on the map.
        app.buttons["Rectangle tool"].tap()
        map(0.02, 0.06).press(forDuration: 0.2, thenDragTo: map(0.16, 0.14))
        XCTAssertTrue(app.buttons["Rectangle Rectangle"].waitForExistence(timeout: 5), "Rectangle added")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Text Parkir'")).count, parkirBefore + 1,
                       "Text saved when moving to another object")
        let fill = app.switches["Transparent fill (e.g. out-of-bounds area)"]
        XCTAssertTrue(fill.waitForExistence(timeout: 3))
        fill.tap()
        // Line.
        app.buttons["Line tool"].tap()
        map(0.02, 0.18).press(forDuration: 0.2, thenDragTo: map(0.2, 0.2))
        XCTAssertTrue(app.buttons["Line Line"].waitForExistence(timeout: 5), "Line added")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "course-objects"
        shot.lifetime = .keepAlways
        add(shot)

        // Descriptions: row limit 3 → 2 columns, bottom-left corner.
        app.segmentedControls.buttons["Descriptions"].tap()
        let limit = app.switches["Limit rows per column"]
        XCTAssertTrue(limit.waitForExistence(timeout: 5))
        // Start from 8 rows: turn it off first if it is already on.
        if (limit.value as? String) == "1" { limit.tap() }
        limit.tap()
        let stepper = app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'Max rows'")).firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 3))
        for _ in 0..<5 { stepper.buttons.element(boundBy: 0).tap() }   // 8 → 3
        let twoCols = app.steppers.matching(NSPredicate(format: "label CONTAINS '3 rows · 2 columns'")).firstMatch
        XCTAssertTrue(twoCols.waitForExistence(timeout: 3), "Overflow rows move to the second column")
        let corner = app.buttons["Bottom left"]
        // The corner buttons are below the thumbnail: scroll the panel until they are visible.
        var swipes = 0
        // Scroll until the buttons are clear of the panel's bottom edge (a tap on a half-hidden button can miss).
        let bottom = app.windows.firstMatch.frame.maxY - 200
        while !corner.isHittable || corner.frame.maxY > bottom, swipes < 8 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45)))
            swipes += 1
        }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "description-layout"
        before.lifetime = .keepAlways
        add(before)
        corner.tap()
        let position = app.staticTexts["descriptionPosition"]
        XCTAssertTrue(position.waitForExistence(timeout: 3))
        let deadline = Date().addingTimeInterval(3)
        while position.label != "Bottom left", Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertEqual(position.label, "Bottom left", "Description corner changes")
        app.buttons["Preview control descriptions"].firstMatch.tap()
        let preview = app.otherElements["Preview competition map"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "preview-objects-descriptions"
        shot2.lifetime = .keepAlways
        add(shot2)
        app.navigationBars.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))

        // Clean up: undo every step of the test.
        let undo = app.buttons["courseUndo"]
        var taps = 0
        while undo.isEnabled, taps < 25 {
            undo.tap()
            taps += 1
            Thread.sleep(forTimeInterval: 0.25)
        }
        app.segmentedControls.buttons["Objects"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Text Parkir'")).count, parkirBefore, "Undo removes the test objects")
        app.buttons["Back to map workspace"].tap()
    }
}
