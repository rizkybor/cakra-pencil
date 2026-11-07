import XCTest

/// Auto-merge and object guides (OCAD Follow) with the pen tool, line symbol 505.0.
final class MergeAndFollowUITests: XCTestCase {
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

    func testAutoMergeAndFollowExistingLine() throws {
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        pen.tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertFalse(app.descendants(matching: .any)["autoMerge"].exists, "Auto-merge has no button (always on)")
        XCTAssertFalse(app.descendants(matching: .any)["followGuides"].exists, "Follow objects has no button (always on via taps)")

        // Empty part above the test project's map frame (the fixture is restored on launch, so no leftovers there).
        let x: CGFloat = 0.22, y: CGFloat = 0.22  // right of the tool rail (two columns while the pen hint shows)
        let five0 = lines(5).count, four0 = lines(4).count, three0 = lines(3).count

        // Line A: 3 points, ending at E.
        map(x, y).tap()
        map(x + 0.12, y + 0.04).tap()
        map(x + 0.24, y).doubleTap()
        XCTAssertEqual(waitCount(lines(3), three0 + 1), three0 + 1, "Line A")

        // Line B: from somewhere else, ending exactly at E → its end snaps and is merged right away into 5 points.
        map(x + 0.34, y + 0.05).tap()
        map(x + 0.30, y + 0.02).tap()
        map(x + 0.24, y).doubleTap()
        XCTAssertEqual(waitCount(lines(5), five0 + 1), five0 + 1, "A + B merged into one 5-point line")
        XCTAssertEqual(lines(3).count, three0, "Line A no longer stands alone")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "auto-merge"
        shot.lifetime = .keepAlways
        add(shot)
        // The dock with an active symbol must not push the screen sideways (Export button stays on screen).
        let screen = app.windows.firstMatch.frame
        let export = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Export'")).firstMatch
        XCTAssertLessThanOrEqual(export.frame.maxX, screen.maxX, "Top bar not pushed off screen")

        // Line C follows A: tap the middle of segment 1 then the middle of segment 2 (on the line, not on a point) →
        // A's corner point in between is copied; then double-tap outside = 4 points.
        map(x + 0.06, y + 0.02).tap()
        map(x + 0.18, y + 0.02).tap()
        map(x + 0.18, y - 0.06).doubleTap()
        XCTAssertEqual(waitCount(lines(4), four0 + 1), four0 + 1, "Line C follows A's shape (4 points)")

        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "follow-object"
        shot2.lifetime = .keepAlways
        add(shot2)

        // Fill area (OCAD Fill): select the merged line A+B, fill it with an area symbol; the line stays.
        let areas = app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label BEGINSWITH 'Area · 5 points'"))
        let areas0 = areas.count
        app.buttons["Node Tool"].tap()
        map(x + 0.30, y + 0.02).tap()   // segment of line B
        let fill = app.buttons["fillArea"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5), "Fill area button for the selected line")
        fill.tap()
        let search = app.textFields["Search code or name (e.g. 506 or path)"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("406")
        let veg = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '406.0'")).firstMatch
        XCTAssertTrue(veg.waitForExistence(timeout: 5), "Area symbols only")
        veg.tap()
        XCTAssertEqual(waitCount(areas, areas0 + 1), areas0 + 1, "New area from the line's shape")
        XCTAssertEqual(lines(5).count, five0 + 1, "The line does not disappear")
        let shot3 = XCTAttachment(screenshot: app.screenshot())
        shot3.name = "fill-area"
        shot3.lifetime = .keepAlways
        add(shot3)

        // Line D follows A+B from the middle of the second segment to A's start: its shape is followed (3 points) and
        // it is not merged into A+B even though the ends meet (the lines overlap).
        app.buttons["Pen tool (bezier)"].tap()
        let three1 = lines(3).count
        map(x + 0.15, y + 0.03).tap()
        map(x, y).doubleTap()
        XCTAssertEqual(waitCount(lines(3), three1 + 1), three1 + 1, "Line D follows the curve to the end (3 points)")
        XCTAssertEqual(lines(5).count, five0 + 1, "A+B not merged with the overlapping line")

        // Line symbol: returning to the start point = closed line, not an area.
        let anyArea = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Area · '"))
        let areaCount = anyArea.count, four1 = lines(4).count
        map(x, y + 0.10).tap()
        map(x + 0.1, y + 0.10).tap()
        map(x + 0.05, y + 0.16).tap()
        map(x, y + 0.10).tap()
        XCTAssertEqual(waitCount(lines(4), four1 + 1), four1 + 1, "Closed 4-point line (end point = start point)")
        XCTAssertEqual(anyArea.count, areaCount, "Does not turn into an area")
        let shot4 = XCTAttachment(screenshot: app.screenshot())
        shot4.name = "follow-to-end-and-closed-line"
        shot4.lifetime = .keepAlways
        add(shot4)

        // Clean up: undo closed line, D, fill area, C, merged B, and A.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<6 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(areas.count, areas0)
        XCTAssertEqual(waitCount(lines(5), five0), five0)
        XCTAssertEqual(lines(4).count, four0)
        XCTAssertEqual(lines(3).count, three0)
    }
}
