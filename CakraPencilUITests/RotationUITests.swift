import XCTest

/// Manual object rotation 0–360°: select an object from the Layers panel, change the angle with the ± buttons and presets.
final class RotationUITests: XCTestCase {
    func testRotateSelectedObject() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers"]
        app.launch()

        // Create our own object (rectangle), then select it with the Select tool: the test does not depend on old data.
        let rectangle = app.buttons["Rectangle"]
        guard rectangle.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        rectangle.tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: CGFloat.random(in: 0.15...0.25), dy: CGFloat.random(in: 0.30...0.40)))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 90, dy: 50)))
        app.buttons["Node Tool"].tap()

        let rotate = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rotate object'")).firstMatch
        XCTAssertTrue(rotate.waitForExistence(timeout: 5), "Rotation button appears for the selected object")
        rotate.tap()

        let zero = app.buttons["0°"]
        XCTAssertTrue(zero.waitForExistence(timeout: 5), "Rotation panel open")
        zero.tap()
        app.buttons["+15°"].tap()
        app.buttons["+15°"].tap()
        XCTAssertTrue(app.staticTexts["30°"].waitForExistence(timeout: 3), "0° + 15° + 15° = 30°")
        app.buttons["-1°"].tap()
        XCTAssertTrue(app.staticTexts["29°"].waitForExistence(timeout: 3), "1° step")
        app.buttons["90°"].tap()
        XCTAssertTrue(app.staticTexts["90°"].waitForExistence(timeout: 3), "Preset 90°")

        // Close the panel: the button label contains the new angle.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15)).tap()
        XCTAssertTrue(app.buttons["Rotate object, 90 degrees"].waitForExistence(timeout: 5), "Angle saved on the object")

        // Clean up: delete the test object.
        app.buttons["Delete object"].tap()
        XCTAssertFalse(app.buttons["Rotate object, 90 degrees"].waitForExistence(timeout: 2), "Test object deleted")
    }
}
