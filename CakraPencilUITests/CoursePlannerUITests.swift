import XCTest

/// Course Planner page (like Purple Pen): open it from the Course button in the workspace, create a course,
/// place start → 2 controls → finish via the rail, fill in an IOF description, check the Descriptions and Report tabs,
/// export IOF XML + PDF, then undo every step and go back to the map workspace.
final class CoursePlannerUITests: XCTestCase {
    func testPlanCourseInDedicatedPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let open = app.buttons["Open Course Settings"]
        guard open.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        // Wait for the workspace animation to finish (iOS ignores taps during presentation), then open; retry once if needed.
        XCTAssertTrue(app.buttons["lockArea"].waitForExistence(timeout: 2) == false)
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: open)
        wait(for: [ready], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        open.tap()
        if !app.staticTexts["Course Settings"].waitForExistence(timeout: 4) { open.tap() }
        XCTAssertTrue(app.staticTexts["Course Settings"].waitForExistence(timeout: 5), "Course page open")
        XCTAssertTrue(app.buttons["Place Control"].exists, "Course tool rail")
        XCTAssertFalse(app.buttons["Pen tool (bezier)"].isHittable, "Map drawing tools are not on the Course page")
        Thread.sleep(forTimeInterval: 1)
        let countLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Courses ('")).firstMatch
        XCTAssertTrue(countLabel.waitForExistence(timeout: 5))
        let coursesBefore = countLabel.label

        app.buttons["New course"].tap()
        let x = CGFloat.random(in: 0.18...0.24), y = CGFloat.random(in: 0.34...0.40)
        func map(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y + dy)) }
        app.buttons["Place Start"].tap()
        map(0, 0).tap()
        map(0.14, 0.02).tap()   // automatically continues with Control
        map(0.2, 0.12).tap()
        app.buttons["Place Finish"].tap()
        map(0.04, 0.16).tap()

        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start S'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Start in the control order")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS ', number 1'")).firstMatch
        XCTAssertTrue(first.exists, "Control number 1")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS ', number 2'")).firstMatch.exists, "Control number 2")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Finish F'")).firstMatch.exists, "Finish")

        // IOF description, column D.
        first.tap()
        let feature = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'D · Feature'")).firstMatch
        XCTAssertTrue(feature.waitForExistence(timeout: 5), "Control editor open")
        feature.tap()
        let rock = app.buttons["2.4  Boulder"]
        XCTAssertTrue(rock.waitForExistence(timeout: 5))
        rock.tap()
        app.buttons["controlEditorDone"].tap()
        XCTAssertTrue(app.staticTexts["Boulder"].waitForExistence(timeout: 5), "Description in the control order")

        // Size of the selected control object: default 100% (IOF standard), +10%.
        XCTAssertTrue(app.buttons["Control size 100 percent, tap for IOF standard"].waitForExistence(timeout: 5), "Default IOF standard")
        app.buttons["Enlarge control"].tap()
        XCTAssertTrue(app.buttons["Control size 110 percent, tap for IOF standard"].waitForExistence(timeout: 3), "Control enlarged")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "course-course"
        shot.lifetime = .keepAlways
        add(shot)

        // Descriptions tab: description sheet; Report tab: summary; Controls tab: numbering.
        app.segmentedControls.buttons["Descriptions"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Boulder'")).firstMatch.waitForExistence(timeout: 5),
                      "Description row for control 1")
        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "course-descriptions"
        shot2.lifetime = .keepAlways
        add(shot2)
        // PDF preview before export: control description page.
        app.buttons["Preview description PDF"].tap()
        let preview = app.otherElements["Preview competition map"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Competition map preview (one page) shown")
        Thread.sleep(forTimeInterval: 1)
        let shot3 = XCTAttachment(screenshot: app.screenshot())
        shot3.name = "course-preview"
        shot3.lifetime = .keepAlways
        add(shot3)
        app.navigationBars.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        app.segmentedControls.buttons["Report"].tap()
        XCTAssertTrue(app.staticTexts["Course summary"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Controls"].tap()
        XCTAssertTrue(app.buttons["Renumber all codes"].waitForExistence(timeout: 5))

        // Export from the Course page top bar.
        app.buttons["courseExport"].tap()
        XCTAssertTrue(app.switches["Race map PDF"].waitForExistence(timeout: 5), "Export opens directly in Courses mode, PDF first")
        app.descendants(matching: .any)["exportMoreFormats"].tap()
        XCTAssertTrue(app.switches["IOF XML 3.0 (CourseData)"].waitForExistence(timeout: 5), "IOF XML under Other formats")
        app.navigationBars["Export"].buttons["Export"].tap()
        let saved = app.descendants(matching: .any)["exportSaved"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "Files saved to Documents › OCCA › Exports")
        XCTAssertFalse(app.alerts["Export failed"].exists)
        app.navigationBars["Saved"].buttons["Done"].tap()

        // Clean up: this session's undo history only holds the test steps, so undo until empty; then back to the map workspace.
        XCTAssertTrue(app.navigationBars["Export"].waitForNonExistence(timeout: 5), "Export sheet closed")
        let undo = app.buttons["courseUndo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        var taps = 0
        while undo.isEnabled, taps < 12 {
            undo.tap()
            taps += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertGreaterThanOrEqual(taps, 7, "Course, 4 points, description, and size are recorded as undo steps")
        app.segmentedControls.buttons["Courses"].tap()
        XCTAssertTrue(app.staticTexts[coursesBefore].waitForExistence(timeout: 3), "Undo restores the original number of courses")
        app.buttons["Back to map workspace"].tap()
        XCTAssertTrue(app.buttons["Pen tool (bezier)"].waitForExistence(timeout: 5), "Back in the mapping workspace")
    }
}
