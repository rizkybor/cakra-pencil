import XCTest

/// Color Hierarchy: a yellow area (401.0) drawn AFTER a footpath line (505.0) still stays below it,
/// because yellow is lower in the ISSprOM color table. Tapping on the line = the line is selected.
final class ColorHierarchyUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-use-symbol", "505000"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
    }

    private func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func useSymbol(_ code: String) {
        app.buttons["Symbols"].tap()
        let search = app.textFields["Search code or name"]
        if !search.waitForExistence(timeout: 3) { app.buttons["Symbols"].tap() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        if let old = search.value as? String, !old.isEmpty, old != "Search code or name" {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        search.typeText(code)
        let symbol = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(code).0")).firstMatch
        XCTAssertTrue(symbol.waitForExistence(timeout: 5), "Symbol \(code).0")
        symbol.tap()
        app.buttons["Layers"].tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testYellowAreaStaysBelowFootpath() throws {
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let lines = app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label BEGINSWITH 'Line · 2 points · 0.45'"))
        let areas = app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label BEGINSWITH 'Area · 4 points'"))
        let l0 = lines.count, a0 = areas.count
        func wait(_ q: XCUIElementQuery, _ n: Int) -> Int {
            let deadline = Date().addingTimeInterval(5)
            while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            return q.count
        }

        // 1. Line 505.0 first.
        pen.tap()
        map(0.15, 0.32).tap()
        map(0.35, 0.32).doubleTap()
        XCTAssertEqual(wait(lines, l0 + 1), l0 + 1, "Line 505.0")

        // 2. Yellow area 401.0 (Rectangle) covering that line, drawn after it.
        useSymbol("401")
        app.buttons["Rectangle"].tap()
        map(0.12, 0.27).press(forDuration: 0.2, thenDragTo: map(0.38, 0.38))
        XCTAssertEqual(wait(areas, a0 + 1), a0 + 1, "Area 401.0")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "yellow-below-path"
        shot.lifetime = .keepAlways
        add(shot)

        // 3. Tap on the line (inside the yellow area) with the Move Tool → the line is selected (drawn on top).
        app.buttons["Move Tool"].tap()
        map(0.56, 0.80).tap()
        map(0.25, 0.32).tap()
        let lineKind = app.buttons["Line"]
        XCTAssertTrue(lineKind.waitForExistence(timeout: 3))
        XCTAssertTrue(lineKind.isSelected, "The line (above the yellow area) is selected")
        // Tap the yellow area away from the line → the area is selected.
        map(0.25, 0.36).tap()
        XCTAssertTrue(app.buttons["Area"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(app.buttons["Area"].isSelected, "Yellow area selected when tapped away from the line")

        // Clean up.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<2 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(wait(lines, l0), l0)
        XCTAssertEqual(areas.count, a0)
    }
}
