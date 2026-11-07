import XCTest

/// Change the symbol of an existing object (OCAD Change symbol / OOM Switch symbol):
/// area → another area, then area → line, from the "Change symbol" button in the selected-object bar.
final class SymbolSwitchUITests: XCTestCase {
    func testSwitchSymbolOfExistingObject() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Symbols", "-cp-use-symbol", "401000"]
        app.launch()

        // Draw our own 401.0 area and select it: the test does not depend on old data.
        let rectangle = app.buttons["Rectangle"]
        guard rectangle.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        rectangle.tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: CGFloat.random(in: 0.15...0.25), dy: CGFloat.random(in: 0.30...0.40)))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 90, dy: 50)))
        app.buttons["Node Tool"].tap()

        let switchButton = app.buttons["Change object symbol"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 5), "Change symbol button appears for the selected object")
        XCTAssertEqual(switchButton.value as? String, "401.0", "Object created with symbol 401.0")

        // Area → another area.
        try pick("406.0", query: "406", app: app, from: switchButton)
        XCTAssertEqual(switchButton.value as? String, "406.0", "Object symbol changed to 406.0")

        // Area → line (like OOM: lines and areas can be swapped).
        try pick("506.0", query: "506", app: app, from: switchButton)
        XCTAssertEqual(switchButton.value as? String, "506.0", "Area changed into line 506.0")

        // Undo restores the previous symbol.
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(waitForValue(switchButton, "406.0"), "Undo: back to 406.0")

        app.buttons["Delete object"].tap()
        XCTAssertFalse(switchButton.waitForExistence(timeout: 2), "Test object deleted")
    }

    private func pick(_ code: String, query: String, app: XCUIApplication, from button: XCUIElement) throws {
        button.tap()
        let search = app.textFields["Search code or name (e.g. 506 or path)"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Symbol picker open")
        search.tap()
        search.typeText(query)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(code) ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Symbol \(code) is in the list")
        row.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5), "Picker closed after choosing")
        XCTAssertTrue(waitForValue(button, code), "Object symbol becomes \(code)")
    }

    private func waitForValue(_ e: XCUIElement, _ v: String) -> Bool {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", v), object: e)
        return XCTWaiter.wait(for: [done], timeout: 5) == .completed
    }
}
