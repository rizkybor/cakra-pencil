import XCTest

/// Descriptions tab (IOF 2024): course sheet fields (classes, distance to start triangle, route to finish), a special
/// instruction row, and the column G direction picker in the control editor.
final class CourseDescriptions2024UITests: XCTestCase {
    func testSpecialInstructionFinishRouteAndDirection() throws {
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

        // Fixture course "A": start, 33, 34, finish.
        app.buttons["courseTab-Descriptions"].tap()
        let courseA = app.segmentedControls.buttons["A"]
        guard courseA.waitForExistence(timeout: 5) else { throw XCTSkip("Fixture course A missing") }
        courseA.tap()

        // Control 33 (first control row): feature, bend, and a directional flag location.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Row 1 33'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Description row for control 33")
        row.tap()
        func choose(_ column: String, _ item: String) {
            let menu = app.buttons[column]
            XCTAssertTrue(menu.waitForExistence(timeout: 5), column)
            menu.tap()
            let entry = app.buttons[item].firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5), item)
            entry.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        choose("D · Feature", "5.24  Railway")
        choose("F · Combination / bend", "11.1  bend")
        choose("G · Flag location", "12.4  corner (inside)")
        let ne = app.buttons["direction-NE"]
        XCTAssertTrue(ne.waitForExistence(timeout: 5), "Direction picker for 12.4")
        ne.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'north east corner (inside)'")).firstMatch
            .waitForExistence(timeout: 5), "Text description with the direction")
        let editor = XCTAttachment(screenshot: app.screenshot()); editor.name = "control-editor-2024"; editor.lifetime = .keepAlways; add(editor)
        app.buttons["controlEditorDone"].tap()

        // Course sheet: classes, distance to the start triangle, taped finish, special instructions.
        let classes = app.textFields["courseClasses"]
        var swipes = 0
        while !classes.isHittable, swipes < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
            swipes += 1
        }
        XCTAssertTrue(classes.waitForExistence(timeout: 5), "Classes field")
        classes.tap()
        classes.typeText("M45 W21\n")
        let start = app.steppers["startDistance"]
        XCTAssertTrue(start.exists)
        for _ in 0..<15 { start.buttons.element(boundBy: 1).tap() }   // 150 m
        app.segmentedControls["finishRoute"].buttons["Taped"].tap()
        XCTAssertTrue(app.segmentedControls["finishRoute"].buttons["Taped"].isSelected)

        for kind in ["15.1", "15.6"] {
            app.buttons["addSpecialInstruction"].tap()
            let entry = app.buttons["addSpecial-\(kind)"]
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "Menu entry \(kind)")
            entry.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(app.buttons["Remove Taped route away from control"].waitForExistence(timeout: 5), "15.1 added")
        XCTAssertTrue(app.buttons["Remove Map flip"].exists, "15.6 added")
        // 15.1 after control 1 (new instructions go after the last control).
        let position = app.steppers["specialPosition-0"]
        XCTAssertTrue(position.exists)
        position.buttons.element(boundBy: 0).tap()
        let panel = XCTAttachment(screenshot: app.screenshot()); panel.name = "descriptions-panel-2024"; panel.lifetime = .keepAlways; add(panel)

        // Back to the sheet: the special rows are drawn in the description table.
        swipes = 0
        while !courseA.isHittable, swipes < 8 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.85)))
            swipes += 1
        }
        func sheetRow(_ text: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Row \(text)")).firstMatch
        }
        XCTAssertTrue(sheetRow("Follow taped route 50 m away from control").waitForExistence(timeout: 5), "15.1 row on the sheet")
        XCTAssertTrue(sheetRow("Map flip (turn the map over)").exists, "15.6 row on the sheet")
        XCTAssertTrue(sheetRow("Distance to start triangle: 150 m").exists, "14.1 row on the sheet")
        XCTAssertTrue(app.staticTexts["M45 W21"].exists, "Classes line")
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "descriptions-sheet-2024"; sheet.lifetime = .keepAlways; add(sheet)

        app.buttons["Preview description PDF"].tap()
        XCTAssertTrue(app.otherElements["Preview competition map"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        let pdf = XCTAttachment(screenshot: app.screenshot()); pdf.name = "descriptions-preview-2024"; pdf.lifetime = .keepAlways; add(pdf)
        app.navigationBars.buttons["Close"].firstMatch.tap()
    }
}
