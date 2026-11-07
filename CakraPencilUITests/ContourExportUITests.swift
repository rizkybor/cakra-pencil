import XCTest

/// Export contours only from the Contours panel. Needs a latest project that already has contour (DEM) data in the test simulator.
final class ContourExportUITests: XCTestCase {
    func testExportContoursOnlyFromPanel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Contours"]
        app.launch()

        let exportButton = app.buttons["Export contours only (SHP, KML, KMZ)…"]
        guard exportButton.waitForExistence(timeout: 15), exportButton.isEnabled else {
            throw XCTSkip("Latest project has no contour data yet")
        }
        exportButton.tap()

        let mode = app.segmentedControls.buttons["Contours only"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "Export sheet open")
        XCTAssertTrue(mode.isSelected, "Opens directly in Contours only mode")
        XCTAssertTrue(app.staticTexts["Lines"].exists, "Number of contour lines shown")
        XCTAssertTrue(app.switches["Shapefile (.shp)"].exists)
        XCTAssertTrue(app.switches["KML (.kml)"].exists)
        XCTAssertTrue(app.switches["KMZ (.kmz)"].exists)

        app.navigationBars["Export"].buttons["Export"].tap()
        // The Share Sheet appearing means the files were written without error.
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15) || app.collectionViews.cells.count > 0, "Share Sheet appears")
        XCTAssertFalse(app.alerts["Export failed"].exists)
    }
}
