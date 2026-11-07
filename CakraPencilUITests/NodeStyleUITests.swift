import XCTest

/// Node Tool: active point → Convert to Sharp / Smooth / Smart.
final class NodeStyleUITests: XCTestCase {
    func testConvertActiveNode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-use-symbol", "505000"]
        app.launch()
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let map = { (x: CGFloat, y: CGFloat) in app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        let x: CGFloat = 0.15, y: CGFloat = 0.28
        let lines = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Line · 3 points'"))
        let n0 = lines.count

        pen.tap()
        map(x, y).tap()
        map(x + 0.08, y + 0.04).tap()
        map(x + 0.16, y).doubleTap()
        let deadline = Date().addingTimeInterval(5)
        while lines.count != n0 + 1, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertEqual(lines.count, n0 + 1, "3-point line")

        // Node Tool: select the line, then tap the middle point → three point-type buttons appear.
        app.buttons["Node Tool"].tap()
        map(x + 0.04, y + 0.02).tap()
        Thread.sleep(forTimeInterval: 0.4)
        map(x + 0.08, y + 0.04).tap()
        let sharp = app.buttons["Convert to Sharp"], smooth = app.buttons["Convert to Smooth"], smart = app.buttons["Convert to Smart"]
        XCTAssertTrue(sharp.waitForExistence(timeout: 3), "Point-type buttons appear for the active point")
        XCTAssertTrue(sharp.isSelected, "Pen tool point without handles = sharp")

        smart.tap()
        XCTAssertTrue(smart.waitForSelected(), "Convert to Smart")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "smart-point"
        shot.lifetime = .keepAlways
        add(shot)
        smooth.tap()
        XCTAssertTrue(smooth.waitForSelected(), "Convert to Smooth")
        sharp.tap()
        XCTAssertTrue(sharp.waitForSelected(), "Convert to Sharp")

        // Drag the middle of the first segment up → the segment curves, the line still has 3 points (not moved).
        map(x + 0.04, y + 0.02).press(forDuration: 0.2, thenDragTo: map(x + 0.03, y - 0.03))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(lines.count, n0 + 1, "Still a 3-point line")
        let bent = XCTAttachment(screenshot: app.screenshot())
        bent.name = "segment-dragged"
        bent.lifetime = .keepAlways
        add(bent)

        // The Move Tool does not show the point buttons.
        app.buttons["Move Tool"].tap()
        XCTAssertFalse(sharp.waitForExistence(timeout: 1))

        // Clean up: 3 conversions + segment drag + line.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<5 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(lines.count, n0)
    }
}

private extension XCUIElement {
    func waitForSelected(timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isSelected, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return isSelected
    }
}
