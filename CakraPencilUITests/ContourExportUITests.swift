import XCTest

/// Export kontur saja dari panel Kontur. Butuh proyek terbaru yang sudah punya data kontur (DEM) di simulator uji.
final class ContourExportUITests: XCTestCase {
    func testExportContoursOnlyFromPanel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Kontur"]
        app.launch()

        let exportButton = app.buttons["Export kontur saja (SHP, KML, KMZ)…"]
        guard exportButton.waitForExistence(timeout: 15), exportButton.isEnabled else {
            throw XCTSkip("Proyek terbaru belum punya data kontur")
        }
        exportButton.tap()

        let mode = app.segmentedControls.buttons["Kontur saja"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "Export sheet terbuka")
        XCTAssertTrue(mode.isSelected, "Langsung di mode Kontur saja")
        XCTAssertTrue(app.staticTexts["Garis"].exists, "Jumlah garis kontur ditampilkan")
        XCTAssertTrue(app.switches["Shapefile (.shp)"].exists)
        XCTAssertTrue(app.switches["KML (.kml)"].exists)
        XCTAssertTrue(app.switches["KMZ (.kmz)"].exists)

        app.navigationBars["Export"].buttons["Export"].tap()
        // Share Sheet muncul berarti file berhasil ditulis tanpa error.
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15) || app.collectionViews.cells.count > 0, "Share Sheet muncul")
        XCTAssertFalse(app.alerts["Export gagal"].exists)
    }
}
