import XCTest

/// Project list → Open file with an OCAD (.ocd) or OOM (.omap) map → "New project from map" → project with its area
/// locked on the map, objects (and OCAD courses) included. Needs Documents/Sample.ocd and Documents/Sample.omap in the
/// test simulator (`-cp-open-map-file` runs the same path as Open file without the system file picker).
final class MapFileProjectUITests: XCTestCase {
    private func run(file: String, name: String, zoneFixed: Bool, expectedObjects: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-map-file", file, "-cp-inspector-tab", "Layers"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()

        let field = app.textFields["mapImportName"]
        guard field.waitForExistence(timeout: 15) else { throw XCTSkip("Documents/\(file) not in the test simulator") }
        XCTAssertTrue(app.navigationBars["New project from map"].exists)
        XCTAssertEqual(app.steppers["mapImportZone"].exists, !zoneFixed, zoneFixed ? "OOM: zone from the file" : "OCAD: zone chosen by the user")
        if !zoneFixed {
            // Make the zone explicit (48 South) and check the map center follows it (Jakarta area).
            app.segmentedControls["mapImportHemisphere"].buttons["South"].tap()
        }
        let center = app.descendants(matching: .any)["mapImportCenter"]
        XCTAssertTrue(center.exists, "Map center preview")
        XCTAssertEqual(field.value as? String, "Sample", "Name taken from the file name")
        // Unique name so the clean-up below finds exactly this card.
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + name)
        app.buttons["mapImportCreate"].tap()

        let back = app.buttons["Back to project list"]
        XCTAssertTrue(back.waitForExistence(timeout: 15), "New project opens right away")
        XCTAssertFalse(app.buttons["Lock area"].exists, "Area already locked on the map")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", expectedObjects)).firstMatch.waitForExistence(timeout: 5),
                      "Objects imported (\(expectedObjects))")
        Thread.sleep(forTimeInterval: 1.0)
        back.tap()

        // Clean up the test project.
        let menu = app.buttons["Project menu \(name)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Project card in the list")
        Thread.sleep(forTimeInterval: 1.0)
        menu.tap()
        let delete = app.buttons["Delete project"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let alert = app.alerts["Delete project?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 10), "Test project deleted")
    }

    func testOcadMapBecomesProject() throws {
        try run(file: "Sample.ocd", name: "Map Import OCD \(Int.random(in: 1000...9999))", zoneFixed: false, expectedObjects: "1 objects")
    }

    func testOomMapBecomesProject() throws {
        try run(file: "Sample.omap", name: "Map Import OMAP \(Int.random(in: 1000...9999))", zoneFixed: true, expectedObjects: "5 objects")
    }

    /// OCAD zone validation: the place name shows for a zone on land; a zone that puts the map in the sea shows a
    /// warning, and Create asks for confirmation. Needs Apple's geocoder (network).
    func testOcadZoneValidationWarnsWhenMapLandsInTheSea() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-map-file", "Sample.ocd"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        guard app.textFields["mapImportName"].waitForExistence(timeout: 15) else { throw XCTSkip("Documents/Sample.ocd not in the test simulator") }

        // Sample.ocd lies near Jakarta: 48 South is on land.
        app.segmentedControls["mapImportHemisphere"].buttons["South"].tap()
        let place = app.descendants(matching: .any).matching(identifier: "mapImportPlace").firstMatch
        guard place.waitForExistence(timeout: 20) else { throw XCTSkip("Geocoder unavailable (offline?)") }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Indonesia'")).firstMatch.waitForExistence(timeout: 5),
                      "Place name shown")

        // North hemisphere puts the same coordinates in the Arctic sea → warning, Create asks first.
        app.segmentedControls["mapImportHemisphere"].buttons["North"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "mapImportWarning").firstMatch.waitForExistence(timeout: 20), "Sea warning")
        app.buttons["mapImportCreate"].tap()
        let alert = app.alerts["Map center is in the sea"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Create asks for confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.textFields["mapImportName"].exists, "Still in the import sheet")
        app.navigationBars["New project from map"].buttons["Cancel"].tap()
    }
}
