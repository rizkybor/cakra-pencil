import XCTest

/// The splash screen shows every time OCCA opens (logo, name, tagline, version, credit), then fades to the project list.
final class SplashUITests: XCTestCase {
    /// Content check with the splash held on screen (`-cp-splash-hold`, DEBUG only).
    func testSplashShowsVersion() {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-splash-hold"]
        app.launch()
        let splash = app.descendants(matching: .any)["splashScreen"]
        XCTAssertTrue(splash.waitForExistence(timeout: 5), "Splash on launch")
        XCTAssertTrue(splash.label.contains("Version "), "Version in the splash: \(splash.label)")
        XCTAssertTrue(splash.label.contains("Jendela Cakra Digital"), "Supporter credit in the splash")
    }

    /// The real launch: the splash appears, then fades to the project list by itself.
    func testSplashFadesToProjectList() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["splashScreen"].waitForExistence(timeout: 5), "Splash on launch")
        XCTAssertTrue(app.descendants(matching: .any)["splashScreen"].waitForNonExistence(timeout: 9), "Splash fades out")
        XCTAssertTrue(app.buttons["New project"].firstMatch.waitForExistence(timeout: 5) || app.buttons["Create first project"].exists,
                      "Project list after the splash")
    }
}
