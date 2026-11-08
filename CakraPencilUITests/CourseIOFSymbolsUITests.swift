import XCTest

/// Course page: IOF course symbols (702, 707–715) from the Objects tab — a point symbol by tapping, an out-of-bounds
/// area by dragging.
final class CourseIOFSymbolsUITests: XCTestCase {
    func testPlaceFirstAidAndOutOfBoundsArea() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let open = app.buttons["Open Course Planner"]
        guard open.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: open)
        wait(for: [ready], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        open.tap()
        if !app.staticTexts["Course Planner"].waitForExistence(timeout: 4) { open.tap() }
        XCTAssertTrue(app.staticTexts["Course Planner"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        func map(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: 0.2 + dx, dy: 0.4 + dy)) }

        app.segmentedControls.buttons["Objects"].tap()
        let before = app.buttons.matching(NSPredicate(format: "label CONTAINS '712 First aid post'")).count

        // 712 First aid post: tap.
        let menu = app.buttons["courseIOFSymbols"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["712 First aid post"].tap()
        map(0, 0).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'First aid post added'")).firstMatch.waitForExistence(timeout: 5)
                      || app.buttons.matching(NSPredicate(format: "label CONTAINS '712 First aid post'")).count > before, "First aid post placed")

        // 709 Out-of-bounds area: drag a rectangle.
        menu.tap()
        app.buttons["709 Out-of-bounds area"].tap()
        map(0.05, 0.08).press(forDuration: 0.1, thenDragTo: map(0.18, 0.16))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '709 Out-of-bounds area'")).firstMatch.waitForExistence(timeout: 5),
                      "Out-of-bounds area listed")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "course-iof-symbols"; shot.lifetime = .keepAlways; add(shot)
    }
}
