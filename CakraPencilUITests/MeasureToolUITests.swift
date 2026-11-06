import XCTest

/// Measure Tool: tarik di peta → jarak (m), panjang di kertas, azimut; Esc menghapus ukuran.
/// Move Tool dan Node Tool ada di panel tools.
final class MeasureToolUITests: XCTestCase {
    func testMeasureDistance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layer"]
        app.launch()
        let measure = app.buttons["Measure Tool"]
        guard measure.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        XCTAssertTrue(app.buttons["Move Tool"].exists)
        XCTAssertTrue(app.buttons["Node Tool"].exists)

        measure.tap()
        let map = { (x: CGFloat, y: CGFloat) in app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        map(0.15, 0.28).press(forDuration: 0.2, thenDragTo: map(0.35, 0.28))
        let distance = app.staticTexts["measureDistance"]
        XCTAssertTrue(distance.waitForExistence(timeout: 3), "Hasil ukur muncul")
        let meters = Double(distance.label.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " m", with: "")) ?? 0
        XCTAssertGreaterThan(meters, 0, distance.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Azimut '")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ukur"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["Hapus ukuran"].tap()
        XCTAssertFalse(distance.waitForExistence(timeout: 1), "Ukuran dihapus")
    }
}
