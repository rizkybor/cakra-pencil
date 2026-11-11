import XCTest

/// Cutting with shapes: Split area + a rectangle / pen path drawn across the area, and Cut line + a dragged box.
/// Everything is drawn below the map frame, where the fixture project is empty (the coordinates below are the ones
/// measured above the frame in the earlier layout, shifted down by `drawShift`: the toolbar band now sits there).
final class ShapeCutUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(symbol: String) {
        app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-use-symbol", symbol]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
    }

    private let drawShift: CGFloat = 0.62

    private func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y + drawShift))
    }

    private func rows(_ prefix: String) -> XCUIElementQuery {
        app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
    }

    private func featureCount() -> Int {
        let label = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' objects · '")).firstMatch.label
        return Int(label.split(separator: " ").first ?? "") ?? -1
    }

    private func waitFor(_ n: Int, timeout: TimeInterval = 5, _ value: () -> Int) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while value() != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return value()
    }

    private var selectionCount: Int {
        let label = app.staticTexts["selectionCount"].label
        return Int(label.split(separator: " ").first ?? "") ?? -1
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Draw a 401.0 rectangle area and select it with the Move Tool; returns the number of 4-point areas before.
    private func drawArea(from a: (CGFloat, CGFloat) = (0.26, 0.215), to b: (CGFloat, CGFloat) = (0.56, 0.265)) throws -> (objects: Int, areas4: Int) {
        let rectangle = app.buttons["Rectangle"]
        guard rectangle.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        Thread.sleep(forTimeInterval: 0.6)
        let n0 = featureCount(), a0 = rows("Area · 4 points").count
        rectangle.tap()
        map(a.0, a.1).press(forDuration: 0.2, thenDragTo: map(b.0, b.1))
        XCTAssertEqual(waitFor(n0 + 1, featureCount), n0 + 1, "Area drawn")
        app.buttons["Move Tool"].tap()
        return (n0, a0)
    }

    func testSplitAreaWithRectangleAndPath() throws {
        launch(symbol: "401000")
        let (n0, a0) = try drawArea()
        XCTAssertEqual(rows("Area · 4 points").count, a0 + 1)

        // Split area → the prompt offers the cutting tools.
        openShapeTool(app, "Split area")
        let prompt = app.staticTexts["cutPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertEqual(prompt.label, "Split area: tap two points on the edge, or draw a rectangle, ellipse or path across it")
        for id in ["points", "rectangle", "ellipse", "bezier", "freehand"] {
            XCTAssertTrue(app.buttons["cutTool-\(id)"].exists, "Cut tool \(id)")
        }

        // 1. A rectangle drawn completely inside the area punches a hole: still one object (undone again below).
        app.buttons["cutTool-rectangle"].tap()
        XCTAssertTrue(prompt.label.hasPrefix("Cut area: drag a rectangle"))
        map(0.30, 0.23).press(forDuration: 0.2, thenDragTo: map(0.33, 0.25))
        XCTAssertTrue(app.staticTexts["Hole cut in the area."].waitForExistence(timeout: 3))
        XCTAssertEqual(featureCount(), n0 + 1)
        XCTAssertEqual(rows("Area · 4 points · 1 hole").count, 1)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(waitFor(0, { rows("Area · 4 points · 1 hole").count }), 0, "Undo: hole gone")
        map(0.30, 0.24).tap()
        openShapeTool(app, "Split area")
        app.buttons["cutTool-rectangle"].tap()

        // 2. A strip across the area: cut into two pieces, both selected, one undo step.
        shot("area-before")
        map(0.40, 0.20).press(forDuration: 0.2, thenDragTo: map(0.44, 0.28), withVelocity: .slow, thenHoldForDuration: 3)
        XCTAssertEqual(waitFor(n0 + 2, featureCount), n0 + 2, "Area cut into two pieces")
        XCTAssertEqual(rows("Area · 4 points").count, a0 + 2, "Two rectangles left")
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3), "Both pieces selected")
        XCTAssertEqual(selectionCount, 2)
        XCTAssertFalse(app.staticTexts["cutPrompt"].exists, "Cut mode ends after the cut")
        shot("area-rectangle-cut")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(waitFor(n0 + 1, featureCount), n0 + 1, "Undo: one step")

        // 3. Pen path across the area (restored by undo; select it again).
        map(0.30, 0.24).tap()
        openShapeTool(app, "Split area")
        app.buttons["cutTool-bezier"].tap()
        map(0.34, 0.20).tap()
        map(0.40, 0.245).tap()
        map(0.47, 0.285).doubleTap()
        XCTAssertEqual(waitFor(n0 + 2, featureCount), n0 + 2, "Area split along the path")
        XCTAssertEqual(selectionCount, 2)
        shot("area-path-split")

        // Clean up: undo the split, the area (the hole of step 1 was undone already).
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(waitFor(n0 + 1, featureCount), n0 + 1)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(waitFor(n0, featureCount), n0)
    }

    /// An ellipse inside an area makes a hole (one object); a tap in the hole misses the area; a rectangle across the
    /// edge into the hole opens it up.
    func testHoleInsideAreaThenCutAcrossEdgeAndHole() throws {
        launch(symbol: "401000")
        let (n0, _) = try drawArea(from: (0.26, 0.17), to: (0.56, 0.29))
        let holed = { self.rows("Area · 4 points · 1 hole").count }
        let deleteObject = app.buttons["Delete object"].firstMatch

        openShapeTool(app, "Split area")
        app.buttons["cutTool-ellipse"].tap()
        map(0.32, 0.19).press(forDuration: 0.2, thenDragTo: map(0.40, 0.27), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.staticTexts["Hole cut in the area."].waitForExistence(timeout: 3))
        XCTAssertEqual(featureCount(), n0 + 1, "Still one object")
        XCTAssertEqual(waitFor(1, holed), 1, "The area has a hole")
        XCTAssertTrue(deleteObject.waitForExistence(timeout: 3), "The area stays selected")
        shot("hole-ellipse")

        // A tap in the hole hits nothing (deselects); a tap on the filled part selects the area again.
        map(0.36, 0.23).tap()
        XCTAssertFalse(deleteObject.waitForExistence(timeout: 1.5), "Tap inside the hole doesn't select the area")
        map(0.28, 0.23).tap()
        XCTAssertTrue(deleteObject.waitForExistence(timeout: 3), "Tap on the filled part selects it")

        // A rectangle from outside the top edge into the hole: the hole opens into a notch, still one piece.
        openShapeTool(app, "Split area")
        app.buttons["cutTool-rectangle"].tap()
        map(0.355, 0.15).press(forDuration: 0.2, thenDragTo: map(0.365, 0.23), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.staticTexts["Shape cut out of the area."].waitForExistence(timeout: 3))
        XCTAssertEqual(featureCount(), n0 + 1)
        XCTAssertEqual(waitFor(0, holed), 0, "The hole merged into the outer edge")
        shot("hole-opened")

        for k in [1, 0] {
            app.buttons["Undo"].firstMatch.tap()
            XCTAssertEqual(waitFor(k, holed), k)
        }
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(waitFor(n0, featureCount), n0)
    }

    /// A pattern area (marsh) with an ellipse hole; a hole point edited in the Node Tool; Remove hole.
    func testPatternAreaHoleInNodeTool() throws {
        launch(symbol: "308000")
        let (n0, _) = try drawArea(from: (0.26, 0.17), to: (0.56, 0.29))
        let holed = { self.rows("Area · 4 points · 1 hole").count }
        openShapeTool(app, "Split area")
        app.buttons["cutTool-ellipse"].tap()
        map(0.32, 0.19).press(forDuration: 0.2, thenDragTo: map(0.40, 0.27), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertEqual(waitFor(1, holed), 1)
        shot("hole-pattern")

        // Node Tool: the hole's points are editable; its right point is dragged outward.
        app.buttons["Node Tool"].tap()
        map(0.40, 0.23).tap()
        let remove = app.buttons["removeHole"]
        XCTAssertTrue(remove.waitForExistence(timeout: 3), "A hole point is active")
        map(0.40, 0.23).press(forDuration: 0.2, thenDragTo: map(0.45, 0.235), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertEqual(holed(), 1)
        shot("hole-node-edit")
        map(0.45, 0.235).tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.tap()
        XCTAssertEqual(waitFor(0, holed), 0, "Hole removed")
        XCTAssertEqual(featureCount(), n0 + 1)

        for _ in 0..<4 { app.buttons["Undo"].firstMatch.tap() }
        XCTAssertEqual(waitFor(n0, featureCount), n0)
    }

    func testCutLineWithBox() throws {
        launch(symbol: "505000")
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        Thread.sleep(forTimeInterval: 0.6)
        let n0 = featureCount(), two0 = rows("Line · 2 points").count
        pen.tap()
        map(0.28, 0.24).tap()
        map(0.40, 0.235).tap()
        map(0.52, 0.24).doubleTap()
        XCTAssertEqual(waitFor(n0 + 1, featureCount), n0 + 1, "Line drawn")
        app.buttons["Move Tool"].tap()

        openShapeTool(app, "Cut line")
        let prompt = app.staticTexts["cutPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        XCTAssertEqual(prompt.label, "Cut: tap a point on the line to cut it in two, or drag a box to cut out a part")

        // A box beside the line: nothing to cut.
        map(0.30, 0.20).press(forDuration: 0.2, thenDragTo: map(0.34, 0.215))
        XCTAssertTrue(app.staticTexts["The box doesn't cover any part of the line."].waitForExistence(timeout: 3))

        // A box over the middle point: two pieces of 2 points each, both selected.
        shot("line-before")
        map(0.36, 0.21).press(forDuration: 0.2, thenDragTo: map(0.44, 0.27), withVelocity: .slow, thenHoldForDuration: 3)
        XCTAssertEqual(waitFor(n0 + 2, featureCount), n0 + 2, "Line cut into two pieces")
        XCTAssertEqual(rows("Line · 2 points").count, two0 + 2)
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3))
        XCTAssertEqual(selectionCount, 2)
        XCTAssertFalse(prompt.exists, "Cut mode ends after the cut")
        shot("line-box-cut")

        // Undo = one step back to the whole line, then remove the line.
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(waitFor(n0 + 1, featureCount), n0 + 1)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(waitFor(n0, featureCount), n0)
    }
}

/// Shape tools: separate buttons in a wide bar; in a narrow bar (iPad portrait) inside the scissors menu.
private func openShapeTool(_ app: XCUIApplication, _ label: String) {
    let menu = app.buttons["shapeTools"]
    if menu.exists, !app.buttons[label].firstMatch.exists { menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    let item = app.buttons[label].firstMatch
    XCTAssertTrue(item.waitForExistence(timeout: 3), label)
    item.tap()
}
