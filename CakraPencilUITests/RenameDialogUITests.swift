import XCTest

/// Rename dialog (OCCA style, not the system alert): rename a project from its card menu, then rename it back.
final class RenameDialogUITests: XCTestCase {
    private func rename(_ app: XCUIApplication, from old: String, to new: String) {
        let menu = app.buttons["Project menu \(old)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Card menu for \(old)")
        menu.tap()
        let item = app.buttons["Rename"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let field = app.textFields["renameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Rename dialog open")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 4) + new)
        app.buttons["renameSave"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "cardEffect").firstMatch.waitForExistence(timeout: 3),
                      "Card shows the success effect")
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Dialog closed")
        XCTAssertTrue(app.buttons["Project menu \(new)"].waitForExistence(timeout: 5), "Card shows the new name")
    }

    func testRenameProjectWithDialog() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        rename(app, from: "Uji Vektor", to: "Uji Vektor R")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "renamed"; shot.lifetime = .keepAlways; add(shot)
        rename(app, from: "Uji Vektor R", to: "Uji Vektor")

        // Cancel keeps the name.
        app.buttons["Project menu Uji Vektor"].tap()
        app.buttons["Rename"].firstMatch.tap()
        XCTAssertTrue(app.textFields["renameField"].waitForExistence(timeout: 5))
        app.buttons["renameCancel"].tap()
        XCTAssertTrue(app.buttons["Project menu Uji Vektor"].waitForExistence(timeout: 5))
    }

    /// Duplicate highlights the copy; deleting it shrinks the card away and shows a short message.
    func testDuplicateAndDeleteEffects() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-no-splash", "-cp-restore-fixtures"]
        app.launch()
        let menu = app.buttons["Project menu Uji Vektor"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        app.buttons["Duplicate"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Duplicated"].waitForExistence(timeout: 5), "Copy highlighted with “Duplicated”")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "duplicated"; shot.lifetime = .keepAlways; add(shot)

        let copyMenu = app.buttons["Project menu Uji Vektor (copy)"].firstMatch
        XCTAssertTrue(copyMenu.waitForExistence(timeout: 5))
        copyMenu.tap()
        app.buttons["Delete project"].firstMatch.tap()
        let alert = app.alerts["Delete project?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["projectToast"].waitForExistence(timeout: 5), "Deleted message")
        XCTAssertTrue(copyMenu.waitForNonExistence(timeout: 5), "Copy removed")
    }
}
