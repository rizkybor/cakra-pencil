import XCTest

/// Credits: the project list footer and the ⓘ button open About, which shows the developer and the supporting
/// company with its logo.
final class AboutCreditsUITests: XCTestCase {
    func testAboutShowsCreditsFromButtonAndFooter() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let footer = app.buttons["creditFooter"]
        XCTAssertTrue(footer.waitForExistence(timeout: 10), "Credit footer on the project list")
        XCTAssertTrue(footer.label.contains("PT. Jendela Cakra Digital"))
        XCTAssertTrue(footer.label.contains("Indonesia"), "Country in the credit")

        app.buttons["aboutButton"].tap()
        XCTAssertTrue(app.navigationBars["About OCCA"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rizky Ajie Kurniawan"].exists || app.otherElements.containing(NSPredicate(format: "label CONTAINS 'Rizky Ajie Kurniawan'")).count > 0)
        XCTAssertTrue(app.images["aboutSupporterLogo"].exists, "Supporter logo shown")
        XCTAssertTrue(app.staticTexts["Indonesia"].exists, "Country in About")
        XCTAssertTrue(app.staticTexts["PT. Jendela Cakra Digital"].exists)
        app.navigationBars["About OCCA"].buttons["Done"].tap()
        XCTAssertFalse(app.navigationBars["About OCCA"].waitForExistence(timeout: 2))

        footer.tap()
        XCTAssertTrue(app.navigationBars["About OCCA"].waitForExistence(timeout: 5), "Footer opens About too")
    }
}
