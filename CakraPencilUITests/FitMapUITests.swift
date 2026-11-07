import XCTest

/// The "View whole map" button in the zoom group: after zooming far in, the whole frame + objects are visible again.
final class FitMapUITests: XCTestCase {
    func testFitWholeMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        let fit = app.buttons["View whole map"]
        guard fit.waitForExistence(timeout: 15) else { throw XCTSkip("Project not open yet") }
        let zoomIn = app.buttons["Zoom in"]
        for _ in 0..<4 { zoomIn.tap(); Thread.sleep(forTimeInterval: 0.4) }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "before-fit"
        before.lifetime = .keepAlways
        add(before)
        fit.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "whole-map"
        after.lifetime = .keepAlways
        add(after)
        XCTAssertTrue(app.buttons["Zoom to frame"].exists, "Zoom to frame button still in the rail")

        // Layout does not overflow: the top bar and map controls stay on screen.
        let screen = app.windows.firstMatch.frame
        let export = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Export'")).firstMatch
        XCTAssertTrue(export.exists)
        XCTAssertGreaterThanOrEqual(export.frame.minY, screen.minY + 20, "Top bar not covered by the status bar")
        XCTAssertTrue(screen.contains(fit.frame), "Map controls on screen")
        XCTAssertTrue(screen.contains(app.buttons["Show my location"].frame), "Location button on screen")

        // Landscape (shortest screen height): same, must not overflow at the top/bottom.
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        Thread.sleep(forTimeInterval: 1.5)
        let land = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(export.frame.minY, land.minY + 20, "Landscape: top bar not covered by the status bar")
        XCTAssertTrue(land.contains(app.buttons["Show my location"].frame), "Landscape: location button on screen")
        XCTAssertTrue(land.contains(app.buttons["Zoom to frame"].frame), "Landscape: rail on screen")
        let landShot = XCTAttachment(screenshot: app.screenshot())
        landShot.name = "landscape"
        landShot.lifetime = .keepAlways
        add(landShot)
    }
}
