import XCTest

/// Export the map sheet with the HD basemap image underneath. Needs the "Uji Vektor" test project (locked area) and
/// network access to Apple Maps for the HD image download.
final class ExportBasemapUITests: XCTestCase {
    func testExportMapSheetWithBasemap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Map"]
        app.launch()

        // Wait until the HD image of the current basemap type is ready (the size row appears).
        let size = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'm/px'")).firstMatch
        guard size.waitForExistence(timeout: 60) else { throw XCTSkip("HD image not downloaded (offline?)") }

        app.buttons["Export"].firstMatch.tap()
        let toggle = app.switches["exportIncludeBasemap"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Include basemap option shown")
        XCTAssertTrue(toggle.isEnabled, "Enabled once the HD image exists")
        XCTAssertEqual(toggle.value as? String, "0", "Off by default")
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")

        app.navigationBars["Export"].buttons["Export"].tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 60) || app.collectionViews.cells.count > 0, "Share Sheet appears")
        XCTAssertFalse(app.alerts["Export failed"].exists)
    }

    /// HD image and Live are separate basemap modes in the Map tab; the mode shows in Map data info.
    func testSwitchBetweenHDImageAndLiveMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Map"]
        app.launch()
        let size = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'm/px'")).firstMatch
        guard size.waitForExistence(timeout: 60) else { throw XCTSkip("HD image not downloaded (offline?)") }

        let mode = app.segmentedControls["basemapMode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        let info = app.descendants(matching: .any)["mapDataInfo"]
        mode.buttons["Live"].tap()
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        XCTAssertTrue(info.label.contains("(live)"), "Live mode shows the live map: \(info.label)")
        mode.buttons["HD image"].tap()
        XCTAssertTrue(info.label.contains("(HD image)"), "Back to the HD image: \(info.label)")
    }
}
