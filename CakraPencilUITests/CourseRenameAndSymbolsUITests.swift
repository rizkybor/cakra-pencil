import XCTest

/// Courses panel: rename a course inline, organizer name; Descriptions tab: IOF pictorial descriptions (columns C–H).
final class CourseRenameAndSymbolsUITests: XCTestCase {
    func testRenameCourseAndSymbolDescriptions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launch()

        let open = app.buttons["Open Course Planner"]
        guard open.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: open)
        wait(for: [ready], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        open.tap()
        if !app.staticTexts["Course Planner"].waitForExistence(timeout: 4) { open.tap() }
        XCTAssertTrue(app.staticTexts["Course Planner"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)

        app.segmentedControls.buttons["Courses"].tap()
        app.buttons["New course"].tap()

        // Rename directly in the course detail card.
        let name = app.textFields["courseName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Course name field")
        name.tap()
        name.press(forDuration: 1.2)
        // The edit menu follows the simulator's system language: English first, Indonesian as a fallback.
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        else if app.menuItems["Pilih Semua"].waitForExistence(timeout: 1) { app.menuItems["Pilih Semua"].tap() }
        let newName = "Elite \(Int.random(in: 100...999))"
        name.typeText(newName + "\n")
        XCTAssertTrue(app.staticTexts["Course \(newName)"].waitForExistence(timeout: 5), "Card title uses the new name")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", newName)).firstMatch.exists
                      || app.staticTexts[newName].exists, "New name in the course list")

        // Organizer: shown below the event name on the descriptions.
        let org = app.textFields["organizer"]
        XCTAssertTrue(org.waitForExistence(timeout: 3), "Organizer field")
        org.tap()
        if let v = org.value as? String, !v.isEmpty, v != org.placeholderValue {
            org.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count))
        }
        let orgName = "Makopala \(Int.random(in: 100...999))"
        org.typeText(orgName + "\n")

        // Pictorial descriptions: choose the IOF symbols style; the table is shown (navigation-to-finish row).
        app.segmentedControls.buttons["Descriptions"].tap()
        XCTAssertTrue(app.staticTexts[orgName].waitForExistence(timeout: 5), "Organizer on the description sheet")
        let style = app.segmentedControls["descriptionStyle"]
        var swipes = 0
        while !(style.exists && style.isHittable), swipes < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45)))
            swipes += 1
        }
        XCTAssertTrue(style.exists, "Description style picker")
        style.buttons["IOF symbols"].tap()
        XCTAssertTrue(style.buttons["IOF symbols"].isSelected)
        let color = app.segmentedControls["descriptionColor"]
        XCTAssertTrue(color.exists, "Description color picker")
        color.buttons["Purple (like controls)"].tap()
        XCTAssertTrue(color.buttons["Purple (like controls)"].isSelected)
        // Scroll back to the top so the description table is visible in the screenshot.
        for _ in 0..<4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.85)))
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "descriptions-symbols-purple"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

