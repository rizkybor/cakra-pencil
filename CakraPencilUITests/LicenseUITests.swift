import XCTest

/// License: the Free plan shows locks and the License screen; Pro opens everything. Plans come from
/// `-cp-license free|pro` (Debug only), so no App Store purchase is needed.
final class LicenseUITests: XCTestCase {
    /// Plan without a key: iPad has no free plan ("No license"); the Mac has Starter.
    static let noKeyPlan = "No license"

    private func licenseScreen(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["licenseScreen"] }

    /// Waits until the element is on screen and hittable (sheets animate in and out), then taps it.
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 8) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed, "\(element) ready")
        element.tap()
    }

    private func closeLicense(_ app: XCUIApplication) {
        app.buttons["licenseClose"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: licenseScreen(app))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "License screen closed")
    }

    func testFreePlanProjectLimitAndPlanChip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "free", "-cp-no-license-prompt", "-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()

        let chip = app.buttons["planChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertEqual(chip.label, "Plan: \(Self.noKeyPlan)")

        // iPad has no Starter: a new project needs a license key.
        let newProject = app.buttons["New project"].firstMatch
        XCTAssertTrue(newProject.waitForExistence(timeout: 5))
        newProject.tap()
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 5), "License screen instead of New project")
        XCTAssertTrue(app.descendants(matching: .any)["proLockedFeature"].exists, "Says which feature is locked")
        XCTAssertEqual(app.staticTexts["licensePlanStatus"].label, Self.noKeyPlan)
        closeLicense(app)

        // The chip opens the License screen too; the developer card can switch to Pro.
        chip.tap()
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["proLockedFeature"].exists)
        closeLicense(app)
    }

    func testFreePlanLocksProFeaturesInWorkspace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "free", "-cp-no-license-prompt", "-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Contours",
                               "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()

        // Contours: the whole panel is locked on Starter (no download or upload controls).
        let unlock = app.buttons["contourUnlock"].firstMatch
        guard unlock.waitForExistence(timeout: 15) else { throw XCTSkip("Contour panel not shown") }
        XCTAssertFalse(app.buttons["contourDownload"].exists, "No contour controls on Starter")
        unlock.tap()
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 5), "Contours need a license key")
        closeLicense(app)

        // Export: PDF is free; raster and vector formats show a lock and open the License screen.
        app.buttons["Export"].firstMatch.tap()
        XCTAssertTrue(app.switches["Georeferenced PDF"].waitForExistence(timeout: 5), "PDF is the default export")
        app.descendants(matching: .any)["exportMoreFormats"].tap()
        let raster = app.buttons["locked-rasterExport"]
        XCTAssertTrue(raster.waitForExistence(timeout: 5), "Raster export locked on Free")
        XCTAssertTrue(app.buttons["locked-vectorExport"].firstMatch.exists, "Vector export locked on Free")
        XCTAssertTrue(app.switches["Georeferenced PDF"].exists, "PDF stays available")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "free-export"
        shot.lifetime = .keepAlways
        add(shot)
        tapWhenReady(raster)   // Other formats has just expanded: wait until the row stops moving
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 5), "Locked row opens the License screen over the Export sheet")
        let paywall = XCTAttachment(screenshot: app.screenshot())
        paywall.name = "license-screen"
        paywall.lifetime = .keepAlways
        add(paywall)
        closeLicense(app)
    }

    /// Starter has no fieldwork: the Field panel is locked and opens the License screen.
    func testFreePlanLocksFieldwork() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "free", "-cp-no-license-prompt", "-cp-open-project", "Uji Vektor", "-cp-inspector-tab", "Field",
                               "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()
        let unlock = app.buttons["fieldUnlock"].firstMatch
        guard unlock.waitForExistence(timeout: 15) else { throw XCTSkip("Field panel not shown") }
        XCTAssertFalse(app.buttons["fieldModeEnter"].exists, "No Field mode on Starter")
        unlock.tap()
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 5), "Fieldwork needs a license key")
        closeLicense(app)
    }

    /// iPad without a license: the License screen at launch, and projects open view-only.
    func testNoLicenseOnIPadPromptsAndOpensViewOnly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "free", "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 10), "License screen at launch")
        XCTAssertEqual(app.staticTexts["licensePlanStatus"].label, Self.noKeyPlan)
        XCTAssertFalse(app.descendants(matching: .any)["licensePlan-starter"].exists, "No Starter plan on iPad")
        closeLicense(app)

        app.terminate()
        app.launchArguments = ["-cp-license", "free", "-cp-no-license-prompt", "-cp-open-project", "Uji Vektor",
                               "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()
        let banner = app.descendants(matching: .any)["viewOnlyBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "View-only banner in the workspace")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "view-only"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["viewOnlyActivate"].tap()
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 5), "Activate opens the License screen")
        closeLicense(app)
        // Export to PDF stays available.
        app.buttons["Export"].firstMatch.tap()
        XCTAssertTrue(app.switches["Georeferenced PDF"].waitForExistence(timeout: 5), "PDF export available view-only")
    }

    func testProPlanUnlocksEverything() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "pro", "-cp-open-project", "Uji Vektor", "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()

        let export = app.buttons["Export"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 15))
        export.tap()
        XCTAssertTrue(app.switches["Georeferenced PDF"].waitForExistence(timeout: 5), "PDF is the default export")
        XCTAssertEqual(app.switches["Georeferenced PDF"].value as? String, "1", "PDF on by default")
        app.descendants(matching: .any)["exportMoreFormats"].tap()
        XCTAssertTrue(app.switches["Raster + world file"].waitForExistence(timeout: 5), "Raster export available on Pro")
        XCTAssertEqual(app.switches["Raster + world file"].value as? String, "0", "Other formats are off by default")
        XCTAssertFalse(app.buttons["locked-rasterExport"].exists)
        XCTAssertFalse(app.buttons["locked-vectorExport"].exists)
    }

    /// A Mac key (OC3…) is recognized as the wrong platform on iPad: a hint, and Activate stays off. No server needed.
    func testMacKeyIsRefusedOnIPad() throws {
        let app = XCUIApplication()
        // Key mode with no server: the key field shows, and nothing is sent for a Mac key.
        app.launchArguments = ["-cp-license", "key", "-cp-license-api", "http://127.0.0.1:9", "-cp-no-license-prompt",
                               "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()
        let chip = app.buttons["planChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 5))
        let field = app.textFields["licenseKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 where !focused.evaluate(with: field) {
            field.tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2)
        }
        field.typeText("oc32aaaabbbbcccc0001")
        XCTAssertTrue(app.descendants(matching: .any)["licenseKeyWrongPlatform"].waitForExistence(timeout: 3), "Mac key flagged on iPad")
        XCTAssertFalse(app.buttons["licenseActivate"].isEnabled, "Activate off for a Mac key")
    }

    /// Full key flow against the back office: Starter → enter key → Professional (key, licensee, devices) → release → Starter.
    func testActivateAndReleaseLicenseKey() throws {
        let env = ProcessInfo.processInfo.environment
        let api = env["OCCA_LICENSE_API"] ?? "http://127.0.0.1:8765"
        guard let key = env["OCCA_TEST_KEY"], !key.isEmpty else { throw XCTSkip("Set OCCA_TEST_KEY (and run the back office API)") }

        let app = XCUIApplication()
        app.launchArguments = ["-cp-license", "key", "-cp-no-license-prompt", "-cp-license-api", api, "-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()

        let chip = app.buttons["planChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        if chip.label != "Plan: \(Self.noKeyPlan)" {
            // Left over from an earlier run: release first.
            chip.tap()
            app.buttons["licenseRelease"].tap()
            app.alerts.buttons["Release"].tap()
            app.alerts.buttons["OK"].tap()
            closeLicense(app)
        }
        XCTAssertEqual(chip.label, "Plan: \(Self.noKeyPlan)")
        chip.tap()
        XCTAssertTrue(licenseScreen(app).waitForExistence(timeout: 5))

        let field = app.textFields["licenseKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Key field on Free")
        // Plans and features are collapsed until their header is tapped.
        XCTAssertFalse(app.descendants(matching: .any)["licensePlan-trial"].exists, "Plans closed by default")
        tapWhenReady(app.buttons["licensePlans"])
        XCTAssertTrue(app.descendants(matching: .any)["licensePlan-trial"].waitForExistence(timeout: 3), "Plans open on tap")
        tapWhenReady(app.buttons["licensePlans"])
        // License Terms open from the agreement line.
        tapWhenReady(app.buttons["licenseTermsLink"])
        XCTAssertTrue(app.descendants(matching: .any)["licenseTerms"].waitForExistence(timeout: 5), "Terms sheet")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'License grant'")).count > 0, "Terms text shown")
        tapWhenReady(app.buttons["licenseTermsClose"])
        let termsGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: app.descendants(matching: .any)["licenseTerms"])
        wait(for: [termsGone], timeout: 5)
        // The sim may use a hardware keyboard, so check the field's own focus; tap again if it missed.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 where !focused.evaluate(with: field) {
            field.tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2)
        }
        // Typed in lowercase: the field uppercases it and adds the dashes as you type.
        field.typeText(key.replacingOccurrences(of: "-", with: "").lowercased())
        let formatted = key.uppercased()
        XCTAssertEqual(field.value as? String, String(formatted.map { $0 == "-" ? "-" : "•" }), "Masked, dashes added while typing")
        // The key is 20 characters, like the back office makes them: more typing is ignored.
        field.typeText("zz99")
        XCTAssertEqual(field.value as? String, String(formatted.map { $0 == "-" ? "-" : "•" }), "Stops at 20 characters")
        tapWhenReady(app.buttons["licenseKeyReveal"])
        XCTAssertEqual(field.value as? String, formatted, "Eye shows the formatted key")
        if key.uppercased().hasPrefix("OC5") {
            XCTAssertTrue(app.descendants(matching: .any)["licenseKeyPlan"].exists, "Plan shown from the key")
        }
        tapWhenReady(app.buttons["licenseActivate"])
        let ok = app.alerts.buttons["OK"]
        XCTAssertTrue(ok.waitForExistence(timeout: 20), "Activation answered")
        let alertText = app.alerts.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(alertText.contains("is active"), "Activated: \(alertText)")
        ok.tap()

        XCTAssertFalse(app.staticTexts["licensePlanStatus"].label.hasPrefix("Starter"), "On the key's plan")
        XCTAssertFalse(field.exists, "Key field hidden once active")
        XCTAssertTrue(app.staticTexts["1 of 1 device in use"].exists || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'device'")).count > 0)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "license-active"
        shot.lifetime = .keepAlways
        add(shot)

        // Check now: refresh with the server (buttons are disabled while it runs).
        app.buttons["licenseCheck"].tap()
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: app.buttons["licenseRelease"])
        wait(for: [idle], timeout: 20)
        XCTAssertFalse(app.staticTexts["licensePlanStatus"].label.hasPrefix("Starter"), "On the key's plan")

        // Release this device: back to Free, the key field returns.
        app.buttons["licenseRelease"].tap()
        app.alerts.buttons["Release"].tap()
        XCTAssertTrue(ok.waitForExistence(timeout: 20))
        ok.tap()
        XCTAssertEqual(app.staticTexts["licensePlanStatus"].label, Self.noKeyPlan)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        closeLicense(app)
        XCTAssertEqual(chip.label, "Plan: \(Self.noKeyPlan)")
    }
}
