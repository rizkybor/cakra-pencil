import XCTest

/// Two lines with the same symbol that meet (after one of them is moved) → the merge button appears,
/// both when one object is selected and when both are selected together.
final class MergeButtonUITests: XCTestCase {
    func testMergeButtonWhenSameSymbolObjectsMeet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-use-symbol", "505000"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let map = { (x: CGFloat, y: CGFloat) in app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        let two = app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label BEGINSWITH 'Line · 2 points · 0.45'"))
        let three = app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label BEGINSWITH 'Line · 3 points · 0.45'"))
        func wait(_ q: XCUIElementQuery, _ n: Int) -> Int {
            let deadline = Date().addingTimeInterval(5)
            while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            return q.count
        }
        let two0 = two.count, three0 = three.count

        // Lines A and B (505.0), separate.
        pen.tap()
        Thread.sleep(forTimeInterval: 1.0)   // the contextual bar row appears in the band; let the map settle
        map(0.15, 0.28).tap()
        map(0.25, 0.28).doubleTap()
        map(0.15, 0.36).tap()
        map(0.25, 0.36).doubleTap()
        XCTAssertEqual(wait(two, two0 + 2), two0 + 2, "Two separate lines")

        // Move Tool: move B until its left end meets A's right end → the Join button appears.
        app.buttons["Move Tool"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        map(0.20, 0.36).press(forDuration: 0.2, thenDragTo: map(0.30, 0.28))
        let mergeOne = app.buttons["mergeSelected"]
        XCTAssertTrue(mergeOne.waitForExistence(timeout: 3), "Merge button for the selected object")
        XCTAssertTrue(mergeOne.isHittable, "Merge button visible (not pushed out of the bar)")
        XCTAssertEqual(mergeOne.label, "Join", "Line = Join")

        // Select both (marquee) → the merge button in the multi-selection bar.
        map(0.56, 0.80).tap()
        map(0.12, 0.25).press(forDuration: 0.2, thenDragTo: map(0.40, 0.33))
        let mergeMany = app.buttons["mergeSelection"]
        XCTAssertTrue(mergeMany.waitForExistence(timeout: 3), "Merge button for a multi-selection")
        XCTAssertEqual(mergeMany.label, "Join", "Two lines = Join")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "merge-button"
        shot.lifetime = .keepAlways
        add(shot)
        mergeMany.tap()
        XCTAssertEqual(wait(three, three0 + 1), three0 + 1, "A + B become one 3-point line")
        XCTAssertEqual(two.count, two0)

        // Clean up: merge, move, B, A.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<4 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(wait(two, two0), two0)
        XCTAssertEqual(three.count, three0)
    }
}
