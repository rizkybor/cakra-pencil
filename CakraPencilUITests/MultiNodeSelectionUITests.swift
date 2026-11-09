import XCTest

/// Node Tool: select several points with a selection box (Shift/⌘-click on Mac and with a keyboard does the same),
/// then delete them together.
final class MultiNodeSelectionUITests: XCTestCase {
    func testSelectionBoxSelectsAndDeletesSeveralPoints() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-use-symbol", "505000"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let map = { (x: CGFloat, y: CGFloat) in app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        let x: CGFloat = 0.30, y: CGFloat = 0.28   // right of the tool palette, so the selection box starts on the map
        let rows = { (n: Int) in
            app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label BEGINSWITH 'Line · \(n) points'"))
        }
        let four0 = rows(4).count, two0 = rows(2).count

        // 4-point zigzag line.
        pen.tap()
        map(x, y).tap()
        map(x + 0.08, y + 0.05).tap()
        map(x + 0.16, y).tap()
        map(x + 0.24, y + 0.05).doubleTap()
        XCTAssertTrue(rows(4).waitForCount(four0 + 1), "4-point line")

        // Node Tool: select the line, then box-select the first two points.
        app.buttons["Node Tool"].tap()
        map(x + 0.12, y + 0.025).tap()
        Thread.sleep(forTimeInterval: 0.4)
        map(x - 0.03, y - 0.04).press(forDuration: 0.15, thenDragTo: map(x + 0.11, y + 0.08))
        let deleteTwo = app.buttons["Delete 2 points"]
        XCTAssertTrue(deleteTwo.waitForExistence(timeout: 3), "Two points selected by the box")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "two-points-selected"
        shot.lifetime = .keepAlways
        add(shot)

        deleteTwo.tap()
        XCTAssertTrue(rows(2).waitForCount(two0 + 1), "Line now has 2 points")
        XCTAssertTrue(rows(4).waitForCount(four0))

        // Clean up: point deletion + line.
        let undo = app.buttons["Undo"].firstMatch
        undo.tap()
        XCTAssertTrue(rows(4).waitForCount(four0 + 1), "Undo restores both points")
        undo.tap()
        XCTAssertTrue(rows(4).waitForCount(four0))
    }
}

private extension XCUIElementQuery {
    func waitForCount(_ n: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return count == n
    }
}
