import XCTest

/// Corner Tool [C]: a new project (no fixtures needed), a rectangle, then select it, select one corner with a box,
/// drag its round handle to round it, and type a radius in the contextual bar. The project is deleted at the end.
final class CornerToolUITests: XCTestCase {
    private var app: XCUIApplication!
    private let projectName = "Corner test"

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        // `CP_SHOT_DIR` (test runner environment): also write the image there, for review outside Xcode.
        if let dir = ProcessInfo.processInfo.environment["CP_SHOT_DIR"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        let done = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [done], timeout: timeout) == .completed
    }

    /// Debug value of the vector overlay: "corners N radius R nodes M".
    private func overlayValue(_ overlay: XCUIElement) -> String { overlay.value as? String ?? "" }

    private func waitForOverlay(_ overlay: XCUIElement, containing s: String, timeout: TimeInterval = 5) -> Bool {
        let done = expectation(for: NSPredicate(format: "value CONTAINS %@", s), evaluatedWith: overlay)
        return XCTWaiter.wait(for: [done], timeout: timeout) == .completed
    }

    func testRoundOneCornerOfARectangle() throws {
        app = XCUIApplication()
        app.launchArguments = ["-cp-license", "pro", "-cp-no-license-prompt", "-cp-no-splash", "-cp-no-imagery"]
        app.launch()
        deleteProject(named: projectName)   // left over by an earlier failed run

        let newButton = app.buttons["New project"].firstMatch
        XCTAssertTrue(newButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilHittable(newButton))
        newButton.tap()
        let field = app.textFields["Project name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "New project sheet open")
        field.tap()
        field.typeText(projectName)
        let create = app.navigationBars["New project"].buttons["Create"]
        create.tap()
        if field.waitForNonExistence(timeout: 5) == false { create.tap() }
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), "Sheet closed")

        let lock = app.buttons["lockArea"]
        XCTAssertTrue(lock.waitForExistence(timeout: 20), "Select Area mode")
        XCTAssertTrue(waitUntilHittable(lock))
        Thread.sleep(forTimeInterval: 1)
        lock.tap()
        XCTAssertTrue(lock.waitForNonExistence(timeout: 10), "Area locked")

        func pt(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        // A rectangle inside the frame.
        app.buttons["Rectangle"].tap()
        pt(0.36, 0.42).press(forDuration: 0.2, thenDragTo: pt(0.54, 0.62))
        Thread.sleep(forTimeInterval: 0.5)

        // Corner Tool: nothing selected yet → "Select corners".
        let cornerTool = app.buttons["Corner Tool"]
        XCTAssertTrue(cornerTool.waitForExistence(timeout: 5), "Corner Tool in the tool band")
        cornerTool.tap()
        XCTAssertTrue(app.descendants(matching: .any)["cornerHint"].waitForExistence(timeout: 5), "Select corners hint")
        let overlay = app.descendants(matching: .any)["vectorEditOverlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))

        // Click the object: it and all its 4 corners are selected.
        pt(0.45, 0.52).tap()
        XCTAssertTrue(waitForOverlay(overlay, containing: "corners 4 radius 0.00 nodes 4"), overlayValue(overlay))

        // Box over the top-right corner only: one corner.
        pt(0.60, 0.36).press(forDuration: 0.1, thenDragTo: pt(0.49, 0.47))
        XCTAssertTrue(waitForOverlay(overlay, containing: "corners 1 radius 0.00"), overlayValue(overlay))

        // Drag its round handle inward: the corner is rounded (5 nodes), one radius > 0.
        pt(0.54, 0.42).press(forDuration: 0.2, thenDragTo: pt(0.50, 0.46))
        XCTAssertTrue(waitForOverlay(overlay, containing: "nodes 5"), overlayValue(overlay))
        XCTAssertFalse(overlayValue(overlay).contains("radius 0.00"), overlayValue(overlay))
        XCTAssertTrue(app.descendants(matching: .any)["cornerCount"].exists, "Contextual bar with the radius")
        shot("corner-tool-ipad")

        // Type a radius of 0 → the corner is sharp again (4 nodes).
        let radius = app.textFields["cornerRadiusField"]
        XCTAssertTrue(radius.waitForExistence(timeout: 5))
        radius.tap()
        radius.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        radius.typeText(XCUIKeyboardKey.delete.rawValue + "0")
        app.buttons["cornerApply"].firstMatch.tap()
        XCTAssertTrue(waitForOverlay(overlay, containing: "radius 0.00 nodes 4"), overlayValue(overlay))

        // Clean up.
        let back = app.buttons["Back to project list"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 10), "Back on the project list")
        deleteProject(named: projectName)
        XCTAssertFalse(app.buttons["Project menu \(projectName)"].exists, "Test project deleted")
    }

    private func deleteProject(named name: String) {
        let menu = app.buttons["Project menu \(name)"]
        guard menu.waitForExistence(timeout: 5) else { return }
        Thread.sleep(forTimeInterval: 1.0)
        menu.tap()
        let delete = app.buttons["Delete project"]
        guard delete.waitForExistence(timeout: 5) else { return }
        delete.tap()
        let alert = app.alerts["Delete project?"]
        guard alert.waitForExistence(timeout: 5) else { return }
        alert.buttons["Delete"].tap()
        _ = menu.waitForNonExistence(timeout: 10)
    }
}
