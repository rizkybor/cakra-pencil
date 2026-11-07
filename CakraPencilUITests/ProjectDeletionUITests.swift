import XCTest

/// Delete-project flow from the home screen, exactly like a user: create a project, go back, ••• → Delete project → confirm.
/// Then the app is relaunched to make sure the project is also gone from disk, not just from the view.
final class ProjectDeletionUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
    }

    func testCreateThenDeleteProject() {
        let name = "Delete Test \(Int.random(in: 1000...9999))"
        let menu = createProject(named: name)

        let alert = openDeleteConfirmation(menu)
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists,
                      "Project name mentioned in the confirmation")
        alert.buttons["Delete"].tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5), "Card gone after deleting")

        // Relaunch: the project does not come back (the .cakra package is really deleted from disk).
        app.terminate()
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
        XCTAssertTrue(app.buttons["New project"].firstMatch.waitForExistence(timeout: 10) || app.buttons["Create first project"].exists,
                      "Home screen shown after relaunch")
        XCTAssertFalse(app.buttons["Project menu \(name)"].waitForExistence(timeout: 3), "Project does not reappear after relaunching the app")
    }

    func testCancelKeepsProject() {
        let name = "Cancel Delete \(Int.random(in: 1000...9999))"
        let menu = createProject(named: name)

        let alert = openDeleteConfirmation(menu)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), "Confirmation closed after Cancel")
        XCTAssertTrue(menu.exists, "Cancel: project is kept")

        // Clean up this test project.
        openDeleteConfirmation(menu).buttons["Delete"].tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5), "Test project deleted")
    }

    // MARK: Shared steps

    /// Creates a project via the New project sheet, waits for the workspace to be ready, goes back to the list. Returns the card's ••• button.
    @discardableResult
    private func createProject(named name: String) -> XCUIElement {
        // The button can be registered before the launch screen finishes: wait until it is actually tappable.
        let newButton = app.buttons["New project"].firstMatch
        let firstButton = app.buttons["Create first project"]
        let button = newButton.waitForExistence(timeout: 10) ? newButton : firstButton
        XCTAssertTrue(waitUntilHittable(button), "Home screen ready")
        button.tap()

        let field = app.textFields["Project name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "New project sheet open")
        field.tap()
        field.typeText(name)
        let create = app.navigationBars["New project"].buttons["Create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), "Create button present")
        create.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), "New project sheet closed after Create")

        // iOS ignores touches during the presentation animation: wait until the workspace is fully shown.
        let back = app.buttons["Back to project list"]
        XCTAssertTrue(back.waitForExistence(timeout: 15), "New project's workspace open")
        XCTAssertTrue(app.buttons["Lock area"].waitForExistence(timeout: 15), "Workspace ready (Select Area mode)")
        Thread.sleep(forTimeInterval: 1.0)
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 10), "Workspace closed after Back")

        let menu = app.buttons["Project menu \(name)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "New project's card is in the list")
        return menu
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        let done = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [done], timeout: timeout) == .completed
    }

    /// ••• → Delete project → confirmation alert shown.
    private func openDeleteConfirmation(_ menu: XCUIElement) -> XCUIElement {
        menu.tap()
        let deleteItem = app.buttons["Delete project"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 5), "Card menu contains Delete project")
        deleteItem.tap()
        let alert = app.alerts["Delete project?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Confirmation dialog appears")
        return alert
    }
}
