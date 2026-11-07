import XCTest

/// Symbol guide (ISOM / ISSprOM omapwiki) next to the map: opened from the active symbol bar, the Symbols panel, and
/// the selected object's bar; scrolls to the symbol code; follows the active symbol. Needs network for the page.
final class SymbolGuideUITests: XCTestCase {
    private func waitForMatch(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let status = app.staticTexts["guideStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), file: file, line: line)
        let found = NSPredicate(format: "label CONTAINS ' of ' OR label CONTAINS 'Not found'")
        let ok = XCTWaiter.wait(for: [expectation(for: found, evaluatedWith: status)], timeout: 30) == .completed
        if !ok || app.staticTexts["The symbol guide needs an internet connection."].exists { throw XCTSkip("omapwiki not reachable") }
        return status.label
    }

    func testGuideFromActiveSymbolPanelAndSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Symbols", "-cp-use-symbol", "505000", "-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()

        // A. Active symbol bar.
        let fromActive = app.buttons["guideActiveSymbol"]
        XCTAssertTrue(fromActive.waitForExistence(timeout: 15), "Guide button next to the active symbol")
        let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: fromActive)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed, "Guide button visible on screen")
        Thread.sleep(forTimeInterval: 1.0)
        fromActive.tap()
        let after = XCTAttachment(screenshot: app.screenshot()); after.name = "after-tap"; after.lifetime = .keepAlways; add(after)
        XCTAssertTrue(app.descendants(matching: .any)["symbolGuidePanel"].waitForExistence(timeout: 5), "Guide panel next to the map")
        XCTAssertEqual(app.staticTexts["guideCode"].label, "505.0")
        let status = try waitForMatch(app)
        XCTAssertTrue(status.contains(" of "), "505.0 found on the page: \(status)")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "guide-505"; shot.lifetime = .keepAlways; add(shot)

        // Search for another symbol, then close.
        let search = app.textFields["guideSearch"]
        search.tap(); search.typeText("520\n")
        XCTAssertTrue(app.staticTexts["guideCode"].waitForExistence(timeout: 5))
        _ = try waitForMatch(app)
        XCTAssertTrue(app.staticTexts["guideCode"].label.hasPrefix("520"), "Search moves to 520: \(app.staticTexts["guideCode"].label)")
        app.buttons["Close symbol guide"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["symbolGuidePanel"].waitForNonExistence(timeout: 5))

        // B. Symbols panel row.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Symbol guide '")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Guide button in the Symbols panel rows")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["symbolGuidePanel"].waitForExistence(timeout: 5))
        app.buttons["Close symbol guide"].firstMatch.tap()
    }

    func testGuideFromSelectedObject() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-select-first", "-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        let fromObject = app.buttons["guideSelectedObject"]
        guard fromObject.waitForExistence(timeout: 15) else { throw XCTSkip("First object has no symbol") }
        fromObject.tap()
        XCTAssertTrue(app.descendants(matching: .any)["symbolGuidePanel"].waitForExistence(timeout: 5), "Guide for the selected object")
        XCTAssertFalse(app.staticTexts["guideCode"].label.isEmpty)
    }
}
