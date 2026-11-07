import XCTest

/// Move Tool: rotation handle above the selected object. Shift + rotate = a straight side snaps parallel to
/// a straight line of another nearby object.
final class RotationSnapUITests: XCTestCase {
    func testShiftRotateAlignsLineWithNeighbour() throws {
        let app = XCUIApplication()
        // XCUITest cannot hold Shift during a touch gesture on iOS → `-cp-force-shift` (DEBUG) = Shift held.
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-use-symbol", "505000", "-cp-force-shift"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let size = app.windows.firstMatch.frame.size
        func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        let lines = app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label BEGINSWITH 'Line · 2 points · 0.45'"))
        let l0 = lines.count

        // Line A horizontal and line B slightly tilted (±12° from A), far apart so they are not merged.
        // (Shift forced: the pen tool does not use Shift, the Move Tool is only used once both lines are done.)
        pen.tap()
        map(0.15, 0.29).tap()
        map(0.35, 0.29).doubleTap()
        let b0 = CGPoint(x: 0.15, y: 0.37), b1 = CGPoint(x: 0.35, y: 0.37 - 35 / size.height)
        map(b0.x, b0.y).tap()
        map(b1.x, b1.y).doubleTap()
        let deadline = Date().addingTimeInterval(5)
        while lines.count != l0 + 2, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertEqual(lines.count, l0 + 2)

        // Move Tool: select B → rotation handle above its box (top center − 28 pt).
        app.buttons["Move Tool"].tap()
        map(0.56, 0.80).tap()
        map((b0.x + b1.x) / 2, (b0.y + b1.y) / 2).tap()
        let rotation = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rotate object'")).firstMatch
        XCTAssertTrue(rotation.waitForExistence(timeout: 3))
        XCTAssertEqual(rotation.label, "Rotate object, 0 degrees")

        // Screen points (pt).
        let p0 = CGPoint(x: b0.x * size.width, y: b0.y * size.height), p1 = CGPoint(x: b1.x * size.width, y: b1.y * size.height)
        let pivot = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let handle = CGPoint(x: pivot.x, y: min(p0.y, p1.y) - 28)
        // Rotate ±10° clockwise (A's side is at +12°): Shift → snaps exactly parallel.
        let a = 10 * Double.pi / 180, dx = Double(handle.x - pivot.x), dy = Double(handle.y - pivot.y)
        let target = CGPoint(x: pivot.x + CGFloat(dx * cos(a) - dy * sin(a)), y: pivot.y + CGFloat(dx * sin(a) + dy * cos(a)))
        func pt(_ p: CGPoint) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
        }
        pt(handle).press(forDuration: 0.3, thenDragTo: pt(target), withVelocity: .slow, thenHoldForDuration: 0.3)
        let snapped = rotation.label
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "precise-rotation"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(snapped, "Rotate object, 12 degrees", "Parallel to line A (not 10° or 15°)")

        // Clean up: rotation, B, A.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<3 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(lines.count, l0)
    }
}
