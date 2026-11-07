import XCTest

/// Course page → Import course. Uses Documents/Sample.ocd (OCAD 10 course setting: courses A and B) in the test
/// simulator; `-cp-import-course` runs the same path as the Import course button without the system file picker.
final class CourseImportUITests: XCTestCase {
    func testImportCourseButtonAndOcadCourses() throws {
        let name = "Course Import \(Int.random(in: 1000...9999))"
        let app = XCUIApplication()
        // 1. New project from the OCAD file (its courses come along), then open the Course page.
        app.launchArguments = ["-cp-open-map-file", "Sample.ocd"]
        app.launch()
        let field = app.textFields["mapImportName"]
        guard field.waitForExistence(timeout: 15) else { throw XCTSkip("Documents/Sample.ocd not in the test simulator") }
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + name)
        app.segmentedControls["mapImportHemisphere"].buttons["South"].tap()
        app.buttons["mapImportCreate"].tap()
        if app.alerts["Map center is in the sea"].waitForExistence(timeout: 2) { app.alerts.buttons["Create anyway"].tap() }
        XCTAssertTrue(app.buttons["Back to project list"].waitForExistence(timeout: 15))
        app.terminate()

        // 2. Course page: Import course button + row; importing the same file again adds "(imported)" copies.
        app.launchArguments = ["-cp-open-project", name, "-cp-open-course", "-cp-import-course", "Sample.ocd"]
        app.launch()
        XCTAssertTrue(app.buttons["importCourse"].waitForExistence(timeout: 15), "Import course button in the Course top bar")
        XCTAssertTrue(app.buttons["importCourseRow"].exists, "Import course… in the Courses list")
        let imported = app.staticTexts["A (imported)"]
        XCTAssertTrue(imported.waitForExistence(timeout: 10), "Imported course listed")
        XCTAssertTrue(app.staticTexts["A"].exists && app.staticTexts["B (imported)"].exists)
        app.terminate()

        // 3. Clean up.
        app.launchArguments = []
        app.launch()
        let menu = app.buttons["Project menu \(name)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)
        menu.tap()
        let delete = app.buttons["Delete project"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let alert = app.alerts["Delete project?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 10), "Test project deleted")
    }
}
