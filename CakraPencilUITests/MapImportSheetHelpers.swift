import XCTest

extension XCUIApplication {
    /// Taps "Create" in the New project from map sheet. The name field may have brought up the on-screen keyboard, which
    /// moves the sheet while it animates and makes the tap miss: close the keyboard first and retry once if the sheet is
    /// still there.
    func tapMapImportCreate() {
        let field = textFields["mapImportName"]
        if keyboards.firstMatch.exists, field.exists { field.typeText("\n") }
        let create = buttons["mapImportCreate"]
        _ = create.waitForExistence(timeout: 3)
        Thread.sleep(forTimeInterval: 0.6)
        create.tap()
        if field.waitForNonExistence(timeout: 3) == false, create.exists, create.isHittable {
            create.tap()
        }
    }
}
