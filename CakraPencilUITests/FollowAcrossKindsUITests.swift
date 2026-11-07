import XCTest

/// Follow objects across kinds: an area symbol follows a line, and a line symbol follows an area
/// (first tap then second tap on the same object).
final class FollowAcrossKindsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers", "-cp-use-symbol", "505000"]
        app.launch()
    }

    private func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func rows(_ prefix: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
    }

    private func waitCount(_ q: XCUIElementQuery, _ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return q.count
    }

    /// Picks a symbol from the Symbols panel (code typed into the search field), then returns to the Layers panel.
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

    func testAreaFollowsLineAndLineFollowsArea() throws {
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        pen.tap()
        // Empty part above the test project's map frame (no other objects to snap to).
        let x: CGFloat = 0.15, y: CGFloat = 0.28
        let line3 = rows("Line · 3 points"), line4 = rows("Line · 4 points"), area4 = rows("Area · 4 points")
        let l3 = line3.count, l4 = line4.count, a4 = area4.count

        // Line A (505.0): 3 points with a corner in the middle.
        map(x, y).tap()
        map(x + 0.08, y + 0.03).tap()
        map(x + 0.16, y).doubleTap()
        XCTAssertEqual(waitCount(line3, l3 + 1), l3 + 1, "Line A")

        // Area (406.0) follows line A: tap the middle of segment 1 then the middle of segment 2 → A's corner is copied,
        // then one point below and tap the first point to close = 4-point area.
        useSymbol("406")
        map(x + 0.04, y + 0.015).tap()
        map(x + 0.12, y + 0.015).tap()
        map(x + 0.08, y + 0.08).tap()
        map(x + 0.04, y + 0.015).tap()
        XCTAssertEqual(waitCount(area4, a4 + 1), a4 + 1, "Area follows the line's shape (4 points)")

        // Line (505.0) follows that area: tap on the right side then the lower-left side → the area's bottom corner is
        // copied, then double-tap outside = 4-point line.
        useSymbol("505")
        map(x + 0.10, y + 0.0475).tap()
        map(x + 0.06, y + 0.0475).tap()
        map(x + 0.06, y + 0.12).doubleTap()
        XCTAssertEqual(waitCount(line4, l4 + 1), l4 + 1, "Line follows the area's shape (4 points)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "follow-across-kinds"
        shot.lifetime = .keepAlways
        add(shot)

        // Clean up: line, area, line A.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<3 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(waitCount(line3, l3), l3)
        XCTAssertEqual(area4.count, a4)
        XCTAssertEqual(line4.count, l4)
    }
}
