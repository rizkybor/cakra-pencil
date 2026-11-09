import XCTest

/// Move Tool: round scale handles on the selected object's box. Corner = proportional, edge = one direction.
final class ScaleHandlesUITests: XCTestCase {
    private func box(_ overlay: XCUIElement) -> (w: Int, h: Int)? {
        guard let v = overlay.value as? String, v.hasPrefix("box ") else { return nil }
        let parts = v.dropFirst(4).split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    func testCornerAndEdgeHandlesScaleTheObject() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        let rectangle = app.buttons["Rectangle"]
        guard rectangle.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }

        // A 120 × 80 pt rectangle, then select it with the Move Tool.
        rectangle.tap()
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let topLeft = origin.withOffset(CGVector(dx: 220, dy: 420))   // clear of the tool palette and the inspector
        topLeft.press(forDuration: 0.2, thenDragTo: topLeft.withOffset(CGVector(dx: 120, dy: 80)))
        app.buttons["Move Tool"].tap()
        topLeft.withOffset(CGVector(dx: 60, dy: 40)).tap()

        let overlay = app.descendants(matching: .any)["vectorEditOverlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        guard let b0 = box(overlay) else { return XCTFail("No scale box: \(String(describing: overlay.value))") }
        XCTAssertEqual(Double(b0.w), 120, accuracy: 6)
        XCTAssertEqual(Double(b0.h), 80, accuracy: 6)

        // Bottom-right corner (box is 6 pt outside the shape) dragged out by 60 pt along x: proportional → 150%.
        let corner = topLeft.withOffset(CGVector(dx: 126, dy: 86))
        corner.press(forDuration: 0.3, thenDragTo: corner.withOffset(CGVector(dx: 63, dy: 43)))
        Thread.sleep(forTimeInterval: 0.5)
        guard let b1 = box(overlay) else { return XCTFail("No scale box after corner drag") }
        XCTAssertEqual(Double(b1.w) / Double(b0.w), 1.5, accuracy: 0.08, "Corner scales width")
        XCTAssertEqual(Double(b1.h) / Double(b0.h), 1.5, accuracy: 0.08, "…and height in proportion")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scaled-corner"
        shot.lifetime = .keepAlways
        add(shot)

        // Right edge handle (middle of the right side) pulled in: only the width changes.
        let right = topLeft.withOffset(CGVector(dx: CGFloat(b1.w) + 6, dy: CGFloat(b1.h) / 2))
        right.press(forDuration: 0.3, thenDragTo: right.withOffset(CGVector(dx: -60, dy: 0)))
        Thread.sleep(forTimeInterval: 0.5)
        guard let b2 = box(overlay) else { return XCTFail("No scale box after edge drag") }
        XCTAssertEqual(Double(b2.w), Double(b1.w) - 60, accuracy: 8, "Edge changes the width")
        XCTAssertEqual(Double(b2.h), Double(b1.h), accuracy: 3, "…not the height")

        // Undo both scale steps, then remove the test object.
        let undo = app.buttons["Undo"].firstMatch
        undo.tap(); undo.tap()
        Thread.sleep(forTimeInterval: 0.5)
        if let b3 = box(overlay) {
            XCTAssertEqual(Double(b3.w), Double(b0.w), accuracy: 3, "Undo restores the size")
        }
        app.buttons["Delete object"].firstMatch.tap()
    }
}
