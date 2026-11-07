import XCTest

/// Quick show/hide of the north lines (vertical grid) from the map controls; mirrored in Layers → Grid.
final class NorthLinesUITests: XCTestCase {
    func testToggleNorthLinesFromMapControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Layers", "-cp-no-imagery"]
        app.launch()

        let toggle = app.buttons["northLinesToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let wasShown = toggle.label == "Hide north lines"
        toggle.tap()
        XCTAssertEqual(toggle.label, wasShown ? "Show north lines" : "Hide north lines")
        // The Grid row sits at the end of the Layers list.
        let row = app.staticTexts["North lines"]
        for _ in 0..<6 where !row.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(row.exists, "Grid row in the Layers panel")
        toggle.tap()
        XCTAssertEqual(toggle.label, wasShown ? "Hide north lines" : "Show north lines", "Back to the original state")
    }
}
