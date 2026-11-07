import XCTest

/// Measure Tool: drag on the map → distance (m), length on paper, azimuth; Esc clears the measurement.
/// Move Tool and Node Tool are in the tools panel.
final class MeasureToolUITests: XCTestCase {
    func testMeasureDistance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers"]
        app.launch()
        let measure = app.buttons["Measure Tool"]
        guard measure.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        XCTAssertTrue(app.buttons["Move Tool"].exists)
        XCTAssertTrue(app.buttons["Node Tool"].exists)

        measure.tap()
        let map = { (x: CGFloat, y: CGFloat) in app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        map(0.15, 0.28).press(forDuration: 0.2, thenDragTo: map(0.35, 0.28))
        let distance = app.staticTexts["measureDistance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 3), "Measurement result appears")
        // English number format: "1,050 m" or "45.3 m" (comma thousands separator, decimal point).
        let meters = Double(distance.label.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " m", with: "")) ?? 0
        XCTAssertGreaterThan(meters, 0, distance.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Azimuth '")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "measure"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Clear measurement"].tap()
        XCTAssertFalse(distance.waitForExistence(timeout: 1), "Measurement cleared")
    }
}
