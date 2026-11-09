import XCTest

/// "All controls" (master): descriptions + PDF preview; course objects: free color and multiple courses.
final class MasterAndItemColorUITests: XCTestCase {
    func testAllControlsPreviewAndItemColor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let open = app.buttons["Open Course Settings"]
        guard open.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: open)
        wait(for: [ready], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        open.tap()
        if !app.staticTexts["Course Settings"].waitForExistence(timeout: 4) { open.tap() }
        XCTAssertTrue(app.staticTexts["Course Settings"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)

        // Make sure there is at least one course (for the "multiple courses" option).
        app.segmentedControls.buttons["Courses"].tap()
        app.buttons["New course"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Descriptions tab: choose "All controls" → master sheet, then preview.
        app.segmentedControls.buttons["Descriptions"].tap()
        let all = app.segmentedControls.buttons["All controls"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "All controls option in the Descriptions tab")
        all.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'All controls (master)'")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Preview control descriptions"].tap()   // Preview button in the top bar
        XCTAssertTrue(app.navigationBars["Preview All controls"].waitForExistence(timeout: 10), "Master preview")
        XCTAssertTrue(app.buttons["Export PDF"].waitForExistence(timeout: 15))
        let pv = XCTAttachment(screenshot: app.screenshot())
        pv.name = "preview-all-controls"
        pv.lifetime = .keepAlways
        add(pv)
        app.buttons["Close"].tap()

        // Object: blue rectangle, only on specific courses.
        let x = CGFloat.random(in: 0.16...0.22), y = CGFloat.random(in: 0.30...0.36)
        func map(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y + dy)) }
        app.buttons["Rectangle tool"].tap()
        map(0.02, 0.06).press(forDuration: 0.2, thenDragTo: map(0.16, 0.14))
        let blue = app.buttons["Color #0072CE"]
        XCTAssertTrue(blue.waitForExistence(timeout: 5), "Quick colors in the object editor")
        blue.tap()
        XCTAssertTrue(app.descendants(matching: .any)["courseItemColor"].exists, "Free color picker")
        let allCourses = app.switches["courseItemAllCourses"]
        XCTAssertTrue(allCourses.waitForExistence(timeout: 3))
        if (allCourses.value as? String) == "1" { allCourses.tap() }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show on course'")).firstMatch.waitForExistence(timeout: 3),
                      "Course checklist")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "object-color-courses"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
