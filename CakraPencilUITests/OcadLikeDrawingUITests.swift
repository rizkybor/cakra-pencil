import XCTest

/// OCAD/OOM-like drawing behavior: freehand drawing with a line symbol, the pen tool finishes with a double tap,
/// and "Change symbol" on the selected object. Needs a latest project whose area is already locked (test simulator).
final class OcadLikeDrawingUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-use-symbol", "505000"]
        app.launch()
    }

    private func count(_ prefix: String) -> Int {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).count
    }

    /// Waits until the number of layer rows starting with `prefix` = `n` (the list updates after the gesture ends).
    private func waitCount(_ prefix: String, _ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while count(prefix) != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return count(prefix)
    }

    private func waitCount(_ q: XCUIElementQuery, _ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return q.count
    }

    private func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    func testFreehandPenDoubleTapAndSwitchSymbol() throws {
        let freehand = app.buttons["Freehand"]
        guard freehand.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let before = count("505.0")

        // 1. Freehand drawing with line symbol 505.0.
        freehand.tap()
        // Random position: a stroke end landing on the end of a 505.0 line left over from a previous run would be auto-merged.
        let fy = CGFloat.random(in: 0.46...0.53), fx = CGFloat.random(in: 0.14...0.22)
        map(fx, fy).press(forDuration: 0.2, thenDragTo: map(fx + 0.32, fy + 0.01))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '505.0'")).element(boundBy: before).waitForExistence(timeout: 5),
                      "Freehand drawing creates a 505.0 object")

        // 2. Pen tool: two taps + double tap = done, 3-point line (the double-tap point is included).
        //    Random position so it does not land on the end of a line from a previous test run (that triggers "continue line").
        let x = CGFloat.random(in: 0.12...0.22), y = CGFloat.random(in: 0.56...0.63) // above the pen tool hint (2 rows in portrait, starting at ±0.68)
        let threeNodes = app.staticTexts.matching(NSPredicate(format: "label == 'Line · 3 points · 0.45 mm'"))
        let fourNodes = app.staticTexts.matching(NSPredicate(format: "label == 'Line · 4 points · 0.45 mm'"))
        let three0 = threeNodes.count, four0 = fourNodes.count
        app.buttons["Pen tool (bezier)"].tap()
        Thread.sleep(forTimeInterval: 0.6) // taps during the tool switch can get lost
        map(x, y).tap()
        map(x + 0.12, y + 0.03).tap()
        map(x + 0.25, y).doubleTap()
        let afterPen = waitCount("505.0", before + 2)
        XCTAssertEqual(afterPen, before + 2, "Double tap finishes the new line")
        XCTAssertEqual(waitCount(threeNodes, three0 + 1), three0 + 1, "Pen tool line has 3 points (the double-tap point becomes the end point)")

        // 3. Continue line (OCAD/OOM): start exactly at the end of that line → that line is extended, not a new object.
        map(x + 0.25, y).tap()
        map(x + 0.32, y + 0.04).doubleTap()
        XCTAssertEqual(waitCount(fourNodes, four0 + 1), four0 + 1, "The continued line grows to 4 points")
        XCTAssertEqual(count("505.0"), afterPen, "Continuing a line does not create a new object")
        XCTAssertEqual(threeNodes.count, three0, "The 3-point line now has 4 points")

        // 4. Select the freehand line, pick symbol 506.0 in the panel, Change symbol.
        app.buttons["Node Tool"].tap()
        map(fx + 0.16, fy + 0.005).tap()
        app.buttons["Symbols"].tap()
        let search = app.textFields["Search code or name"]
        if !search.waitForExistence(timeout: 3) { app.buttons["Symbols"].tap() } // the tab tap sometimes lands while the panel animates
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("506")
        let small = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '506.0'")).firstMatch
        XCTAssertTrue(small.waitForExistence(timeout: 5), "Symbol 506.0 found")
        small.tap()
        let switchButton = app.buttons["Change symbol → 506.0"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 5), "Change symbol button appears for the selected object")
        switchButton.tap()

        app.buttons["Layers"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '506.0'")).firstMatch.waitForExistence(timeout: 5),
                      "Object switched to symbol 506.0")

        // Clean up so the test project does not pile up objects: undo symbol change, continued line, pen tool, freehand.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<4 { undo.tap() }
        // (Don't count "505.0": that text is also shown in the active symbol control, which is now 506.0.)
        XCTAssertEqual(waitCount(fourNodes, four0), four0, "Undo removes the test pen tool line")
        XCTAssertEqual(threeNodes.count, three0)
    }
}
