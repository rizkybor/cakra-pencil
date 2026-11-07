import XCTest

/// Built-in symbol sets: OCCA's own ISOM 2017-2 / ISSprOM 2019-2 sets (.occasym) are the default per map scale;
/// the OpenOrienteering Mapper sets (ISOM 2017-2 1:10000, ISSprOM 2019 1:4000, Course design) can be picked in the
/// Symbols panel and drawn with; credits and the GPL-3.0 text in About; sets can be exported as .occasym.
final class OpenOrienteeringSymbolSetsUITests: XCTestCase {
    private func search(_ app: XCUIApplication, _ query: String) {
        let field = app.textFields["Search code or name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if let old = field.value as? String, !old.isEmpty, old != "Search code or name" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(query)
    }

    /// 1:10000 forest map: OCCA's ISOM set is the default (sized 150 %); its 505 Footpath draws a 0.375 mm line.
    func testISOMSetIsDefaultOnForestMapAndDraws() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "BSD CRT", "-cp-inspector-tab", "Symbols"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let header = app.buttons.matching(NSPredicate(format: "label CONTAINS 'ISOM 2017-2 · OCCA'")).firstMatch
        guard header.waitForExistence(timeout: 15) else {
            if app.buttons["Pen tool (bezier)"].exists { return XCTFail("ISOM set is not the default on a 1:10000 map") }
            throw XCTSkip("BSD CRT project not available")
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'sized 150% for 1:10000'")).firstMatch.exists,
                      "Header notes the enlargement of the 1:15000 set")
        search(app, "505")
        let footpath = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '505.0 Footpath' OR label BEGINSWITH '505.0, Footpath'")).firstMatch
        let anyFootpath = app.staticTexts["Footpath"]
        XCTAssertTrue(footpath.waitForExistence(timeout: 5) || anyFootpath.exists, "ISOM 505 Footpath listed")
        (footpath.exists ? footpath : anyFootpath).tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Footpath'")).firstMatch.waitForExistence(timeout: 5),
                      "Active symbol is the ISOM footpath")

        // Draw a 2-point line above the frame and check the Layers panel.
        app.buttons["Pen tool (bezier)"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.22)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.22)).doubleTap()
        app.buttons["Layers"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '505.0 Footpath'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Line drawn with the ISOM footpath symbol")
        let width = app.staticTexts.matching(identifier: "layerRowMirror").matching(NSPredicate(format: "label CONTAINS '0.38 mm' OR label CONTAINS '0.375 mm'")).firstMatch
        XCTAssertTrue(width.exists, "ISOM 505 at 1:10000 = 0.375 mm (0.25 × 150%)")
    }

    /// The set menu offers Export (.occasym) for the current set and opens the save dialog.
    func testExportSetAsOccasym() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Symbols"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let current = app.buttons.matching(NSPredicate(format: "label CONTAINS 'ISSprOM 2019-2 · OCCA'")).firstMatch
        guard current.waitForExistence(timeout: 15) else { return XCTFail("OCCA ISSprOM set is the default on a 1:4000 map") }
        current.tap()
        let export = app.buttons["exportSymbolSet"]
        XCTAssertTrue(export.waitForExistence(timeout: 5), "Export menu item")
        XCTAssertTrue(export.label.contains(".occasym"))
        export.tap()
        // The system save dialog appears (Files on iPad); cancel it.
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Save dialog for the .occasym file")
        cancel.tap()
    }

    /// 1:4000 sprint map: the OpenOrienteering ISSprOM set can be picked from the set menu.
    func testPickISSprOMSetOnSprintMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Symbols"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let current = app.buttons.matching(NSPredicate(format: "label CONTAINS 'ISSprOM 2019-2 · OCCA'")).firstMatch
        guard current.waitForExistence(timeout: 15) else { throw XCTSkip("Uji Vektor project not available") }
        current.tap()
        XCTAssertTrue(app.buttons["ISSprOM 2019-2 (built-in)"].waitForExistence(timeout: 5), "BOF set still available")
        let item = app.buttons["ISSprOM 2019-2 · OpenOrienteering"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "OpenOrienteering ISSprOM set in the set menu")
        XCTAssertTrue(app.buttons["ISOM 2017-2 · OpenOrienteering"].exists)
        XCTAssertTrue(app.buttons["Course design 1:4000 · OpenOrienteering"].exists)
        item.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'ISSprOM 2019-2 · OpenOrienteering'")).firstMatch.waitForExistence(timeout: 5))
        search(app, "521")
        let building = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Building'")).firstMatch
        XCTAssertTrue(building.waitForExistence(timeout: 5), "ISSprOM 521 Building listed")
    }

    /// About: symbol set credits and the GPL-3.0 text.
    func testAboutShowsSymbolSetLicense() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-show-about"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        XCTAssertTrue(app.navigationBars["About OCCA"].waitForExistence(timeout: 10))
        let credits = app.descendants(matching: .any)["aboutSymbolSets"]
        let link = app.buttons["aboutGPLLicense"]
        var swipes = 0
        while !(link.exists && link.isHittable), swipes < 8 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(credits.exists || link.exists, "Symbol set credits")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'OpenOrienteering Mapper contributors'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'GPL-3.0'")).firstMatch.exists)
        // Size and storage: app size and data.
        let size = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' MB'")).firstMatch
        XCTAssertTrue(app.staticTexts["App size"].exists || size.exists, "App size shown")
        link.tap()
        let text = app.staticTexts["licenseText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("GNU GENERAL PUBLIC LICENSE"), "Full GPL-3.0 text")
    }
}
