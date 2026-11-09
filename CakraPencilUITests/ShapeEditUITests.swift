import XCTest

/// OCAD-like edit tools: add point (double tap on the line), cut, parallel, scale, reverse direction.
final class ShapeEditUITests: XCTestCase {
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

    private func lines(_ n: Int) -> XCUIElementQuery {
        app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label == %@", "Line · \(n) points · 0.45 mm"))
    }

    private func waitCount(_ q: XCUIElementQuery, _ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return q.count
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testReshapeCutParallelScale() throws {
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        pen.tap()
        Thread.sleep(forTimeInterval: 0.6)
        let x = CGFloat.random(in: 0.12...0.18), y = CGFloat.random(in: 0.30...0.36)
        let two0 = lines(2).count, three0 = lines(3).count, four0 = lines(4).count

        map(x, y).tap()
        map(x + 0.12, y + 0.04).tap()
        map(x + 0.24, y).doubleTap()
        XCTAssertEqual(waitCount(lines(3), three0 + 1), three0 + 1, "3-point line")

        // Reshape: select the line, double-tap on the second segment = add a point.
        app.buttons["Node Tool"].tap()
        map(x + 0.06, y + 0.02).tap()
        Thread.sleep(forTimeInterval: 0.5)
        map(x + 0.18, y + 0.02).doubleTap()
        XCTAssertEqual(waitCount(lines(4), four0 + 1), four0 + 1, "Point added (4 points)")
        XCTAssertEqual(lines(3).count, three0)

        // Cut the line on the first segment → 2 points + 4 points.
        openShapeTool(app, "Cut line")
        XCTAssertTrue(app.staticTexts["Cut: tap a point on the line to cut it in two"].waitForExistence(timeout: 3))
        map(x + 0.06, y + 0.02).tap()
        XCTAssertEqual(waitCount(lines(2), two0 + 1), two0 + 1, "Part 1 (2 points)")
        XCTAssertEqual(lines(4).count, four0 + 1, "Part 2 (4 points)")
        shot("cut")

        // Parallel: copy part 1 (selected) to the left.
        openShapeTool(app, "Parallel…")
        let copy = app.buttons["parallelCopy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertEqual(waitCount(lines(2), two0 + 2), two0 + 2, "Parallel copy")
        shot("parallel")

        // Scale 200% and reverse direction on the selected object.
        openShapeTool(app, "Scale…")
        let k200 = app.buttons["200%"]
        XCTAssertTrue(k200.waitForExistence(timeout: 5))
        k200.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()   // close the popover
        openShapeTool(app, "Reverse line direction")
        XCTAssertEqual(lines(2).count, two0 + 2)
        shot("scale-reverse")

        // Clean up: undo reverse, scale, parallel, cut, add point, line.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<6 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(waitCount(lines(2), two0), two0)
        XCTAssertEqual(lines(3).count, three0)
        XCTAssertEqual(lines(4).count, four0)
    }
}

/// Shape tools: separate buttons in a wide bar; in a narrow bar (iPad portrait) inside the scissors menu.
private func openShapeTool(_ app: XCUIApplication, _ label: String) {
    let menu = app.buttons["shapeTools"]
    if menu.exists && menu.isHittable { menu.tap() }
    let item = app.buttons[label].firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 3), label)
    item.tap()
}
