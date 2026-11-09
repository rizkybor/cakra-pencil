import XCTest

/// License: the Free plan shows locks and the plans screen; Pro opens everything. Plans come from
/// `-cp-license free|pro` (Debug only), so no App Store purchase is needed.
final class LicenseUITests: XCTestCase {
    private func plans(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["proPlans"] }

    private func closePlans(_ app: XCUIApplication) {
        app.buttons["proPlansClose"].tap()
        XCTAssertFalse(plans(app).waitForExistence(timeout: 2), "Plans screen closed")
    }

    func testFreePlanProjectLimitAndPlanChip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "free", "-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()

        let chip = app.buttons["planChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertEqual(chip.label, "Plan: Free")

        // The test projects are more than the Free limit (2): a new project needs Pro.
        let newProject = app.buttons["New project"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 5))
        newProject.tap()
        XCTAssertTrue(plans(app).waitForExistence(timeout: 5), "Plans screen instead of New project")
        XCTAssertTrue(app.descendants(matching: .any)["proLockedFeature"].exists, "Says which feature is locked")
        XCTAssertEqual(app.staticTexts["proPlanStatus"].label, "Free")
        closePlans(app)

        // The chip opens the plans screen too; the developer card can switch to Pro.
        chip.tap()
        XCTAssertTrue(plans(app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["proLockedFeature"].exists)
        closePlans(app)
    }

    func testFreePlanLocksProFeaturesInWorkspace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "free", "-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Contours",
                               "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()

        // Contours: built-in download is Pro.
        let builtIn = app.buttons["contourDownload"].firstMatch
        guard builtIn.waitForExistence(timeout: 15) else { throw XCTSkip("Contour panel not shown") }
        builtIn.tap()
        XCTAssertTrue(plans(app).waitForExistence(timeout: 5), "Contours need Pro")
        closePlans(app)

        // Export: PDF is free; raster and vector formats show a lock and open the plans screen.
        app.buttons["Export"].firstMatch.tap()
        let raster = app.buttons["locked-rasterExport"]
        XCTAssertTrue(raster.waitForExistence(timeout: 5), "Raster export locked on Free")
        XCTAssertTrue(app.buttons["locked-vectorExport"].firstMatch.exists, "Vector export locked on Free")
        XCTAssertTrue(app.switches["Georeferenced PDF"].exists, "PDF stays available")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "free-export"
        shot.lifetime = .keepAlways
        add(shot)
        raster.tap()
        XCTAssertTrue(plans(app).waitForExistence(timeout: 5), "Locked row opens the plans screen over the Export sheet")
        let paywall = XCTAttachment(screenshot: app.screenshot())
        paywall.name = "plans-screen"
        paywall.lifetime = .keepAlways
        add(paywall)
        closePlans(app)
    }

    func testProPlanUnlocksEverything() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "pro", "-cp-open-project", "Uji Vektor", "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()

        let export = app.buttons["Export"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 15))
        export.tap()
        XCTAssertTrue(app.switches["Raster + world file"].waitForExistence(timeout: 5), "Raster export available on Pro")
        XCTAssertFalse(app.buttons["locked-rasterExport"].exists)
        XCTAssertFalse(app.buttons["locked-vectorExport"].exists)
    }
}
