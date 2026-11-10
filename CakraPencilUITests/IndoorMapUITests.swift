import XCTest

/// "Indoor map (ISInOM)": a new indoor project at 1:700 uses the OCCA ISInOM set and ISInOM course sizes, lists the
/// indoor description features first; switching the option off in the Map tab returns to ISSprOM.
final class IndoorMapUITests: XCTestCase {
    private var app: XCUIApplication!

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        let done = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [done], timeout: timeout) == .completed
    }

    private func text(containing s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    private func turn(_ toggle: XCUIElement, on: Bool) {
        for _ in 0..<3 where (toggle.value as? String == "1") != on {
            // Tap the switch itself (right edge of a Form row).
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertEqual(toggle.value as? String == "1", on, toggle.identifier)
    }

    /// Inspector tab strip: tap (again) until the tab's content shows.
    private func openTab(_ name: String, showing element: XCUIElement) {
        for _ in 0..<4 where !element.waitForExistence(timeout: 0.5) {
            Thread.sleep(forTimeInterval: 0.8)
            app.buttons[name].firstMatch.tap()
            _ = element.waitForExistence(timeout: 3)
        }
    }

    func testIndoorProjectUsesISInOM() throws {
        app = XCUIApplication()
        app.launchArguments = ["-cp-license", "pro", "-cp-no-license-prompt", "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()

        // New project sheet: Indoor map on → 1:700.
        let newButton = app.buttons["New project"].firstMatch
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilHittable(newButton))
        newButton.tap()
        let field = app.textFields["Project name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "New project sheet open")
        field.tap()
        field.typeText("Indoor test")
        let indoor = app.switches["newProjectIndoor"]
        XCTAssertTrue(indoor.waitForExistence(timeout: 5), "Indoor map toggle")
        turn(indoor, on: true)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '1:700' OR value CONTAINS '1:700'")).firstMatch
            .waitForExistence(timeout: 3), "Indoor scale 1:700 chosen")
        XCTAssertTrue(text(containing: "ISInOM 6.7.3").exists, "Footer explains the indoor standard")
        shot("indoor-new-project")
        let create = app.navigationBars["New project"].buttons["Create"]
        create.tap()
        if field.waitForNonExistence(timeout: 5) == false { create.tap() }
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), "Sheet closed")

        // Workspace: lock the area.
        let lock = app.buttons["lockArea"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20), "Select Area mode")
        XCTAssertTrue(waitUntilHittable(lock))
        Thread.sleep(forTimeInterval: 1)
        lock.tap()
        XCTAssertTrue(lock.waitForNonExistence(timeout: 10), "Area locked")

        // Symbols panel: OCCA ISInOM set, at 100 % (no "sized" note at its own scale).
        let isinomSet = app.staticTexts["ISInOM 6.7.3 · OCCA"]
        XCTAssertTrue(isinomSet.waitForExistence(timeout: 10), "Symbols panel shows the ISInOM set on an indoor map")
        XCTAssertTrue(text(containing: "1:700 ·").exists)
        XCTAssertFalse(text(containing: "sized").exists, "ISInOM set not resized at 1:700")
        shot("indoor-symbols")

        // Draw a few ISInOM objects inside the frame: outer wall, table, fence (shared code 516), pillar.
        func useSymbol(_ code: String) {
            openTab("Symbols", showing: app.textFields["Search code or name"])
            let search = app.textFields["Search code or name"]
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            if let old = search.value as? String, !old.isEmpty, old != "Search code or name" {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            search.typeText(code)
            let symbol = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(code).0")).firstMatch
            XCTAssertTrue(symbol.waitForExistence(timeout: 5), "Symbol \(code).0")
            symbol.tap()
            app.buttons["Layers"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        useSymbol("1102")
        app.buttons["Rectangle"].tap()
        pt(0.18, 0.38).press(forDuration: 0.2, thenDragTo: pt(0.50, 0.62))
        useSymbol("1401")
        app.buttons["Rectangle"].tap()
        pt(0.24, 0.44).press(forDuration: 0.2, thenDragTo: pt(0.34, 0.50))
        useSymbol("516")
        app.buttons["Pen tool (bezier)"].tap()
        pt(0.20, 0.67).tap()
        pt(0.48, 0.67).doubleTap()
        useSymbol("1108")
        pt(0.42, 0.55).tap()
        Thread.sleep(forTimeInterval: 0.5)
        shot("indoor-objects")

        // Course page: place a start and a control; ISInOM sizes (circle 6.0 mm at 1:700).
        let open = app.buttons["Open Course Settings"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilHittable(open))
        Thread.sleep(forTimeInterval: 1)
        open.tap()
        if !app.staticTexts["Course Settings"].waitForExistence(timeout: 4) { open.tap() }
        XCTAssertTrue(app.staticTexts["Course Settings"].waitForExistence(timeout: 5))
        app.buttons["New course"].tap()
        func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        app.buttons["Place Start"].tap()
        map(0.30, 0.45).tap()
        map(0.42, 0.40).tap()          // continues with Control
        map(0.38, 0.58).tap()
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS ', number 1'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Control 1 placed")
        shot("indoor-course")

        app.segmentedControls.buttons["Controls"].tap()
        let footer = text(containing: "100% = ISInOM 6.7.3 standard: circle 6")
        for _ in 0..<4 where !footer.exists { app.swipeUp() }
        XCTAssertTrue(footer.waitForExistence(timeout: 5), "Course symbols at ISInOM 1:700 size (ø6.0 mm, not ISSprOM × 5.7)")

        // Description picker: indoor features first.
        app.segmentedControls.buttons["Courses"].tap()
        let control = app.buttons.matching(NSPredicate(format: "label CONTAINS ', number 1'")).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.tap()
        let feature = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'D · Feature'")).firstMatch
        XCTAssertTrue(feature.waitForExistence(timeout: 5), "Control editor open")
        feature.tap()
        let pillar = app.buttons["7.119  Pillar"]
        XCTAssertTrue(pillar.waitForExistence(timeout: 5), "Indoor group in the description picker")
        XCTAssertTrue(app.buttons["7.143  Couch / sofa"].exists)
        shot("indoor-description-picker")
        app.buttons["7.141  Table or bench"].tap()
        app.buttons["controlEditorDone"].tap()
        XCTAssertTrue(app.staticTexts["Table"].waitForExistence(timeout: 5), "Indoor description (short text name) in the control order")
        app.buttons["Back to map workspace"].tap()
        XCTAssertTrue(app.buttons["Pen tool (bezier)"].waitForExistence(timeout: 5))

        // Map tab: switch Indoor off → ISSprOM (1:700 enlarged), on again → ISInOM.
        let mapTab = app.buttons["Map"].firstMatch
        XCTAssertTrue(mapTab.waitForExistence(timeout: 5))
        mapTab.tap()
        let toggle = app.switches["mapIndoor"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Indoor toggle in the Map tab")
        XCTAssertEqual(toggle.value as? String, "1")
        turn(toggle, on: false)
        openTab("Symbols", showing: app.staticTexts["ISSprOM 2019-2 · OCCA"])
        XCTAssertTrue(app.staticTexts["ISSprOM 2019-2 · OCCA"].exists, "Back to ISSprOM")
        XCTAssertTrue(text(containing: "sized 571% for 1:700").exists, "ISSprOM enlarged for 1:700 (automatic standard)")
        shot("indoor-off-issprom")
        openTab("Map", showing: app.switches["mapIndoor"])
        turn(app.switches["mapIndoor"], on: true)
        openTab("Symbols", showing: app.staticTexts["ISInOM 6.7.3 · OCCA"])
        XCTAssertTrue(app.staticTexts["ISInOM 6.7.3 · OCCA"].exists, "ISInOM again")
        shot("indoor-map")
    }
}
