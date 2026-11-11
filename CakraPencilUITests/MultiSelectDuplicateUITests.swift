import XCTest

/// Multi-selection (⌘A, marquee) and duplicating objects; map controls are in the tools panel.
final class MultiSelectDuplicateUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layers"]
        app.launchArguments += ["-cp-no-splash", "-cp-restore-fixtures"]; app.launch()
    }

    private func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// Number of objects from the layer panel header ("14 objects · 0 strokes").
    private func featureCount() -> Int {
        let label = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' objects · '")).firstMatch.label
        return Int(label.split(separator: " ").first ?? "") ?? -1
    }

    private func waitFeatureCount(_ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while featureCount() != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return featureCount()
    }

    private var selectionCount: Int {
        let label = app.staticTexts["selectionCount"].label
        return Int(label.split(separator: " ").first ?? "") ?? -1
    }

    func testSelectAllDuplicateMarqueeAndRail() throws {
        let select = app.buttons["Move Tool"]
        guard select.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }

        // Map controls sit in the toolbar band at the top (like the Mac): on screen, above the map, in one row.
        let screen = app.windows.firstMatch.frame
        let row = app.buttons["Zoom in"].frame
        let mapTop = app.otherElements["scaleBar"].frame.minY
        for label in ["Zoom in", "Zoom out", "View whole map", "Zoom to frame", "Show my location"] {
            let b = app.buttons[label]
            XCTAssertTrue(b.exists, label)
            XCTAssertTrue(screen.contains(b.frame), "\(label) on screen")
            XCTAssertEqual(b.frame.midY, row.midY, accuracy: 2, "\(label) in the map controls row")
            XCTAssertLessThan(b.frame.maxY, mapTop, "\(label) in the band above the map")
        }

        select.tap()
        let n0 = featureCount()
        XCTAssertGreaterThan(n0, 1, "Test project has several objects")

        // 1. Select all → all objects selected; Duplicate → the number of (unlocked) objects doubles.
        // No Multi-select / Select all / Auto-merge buttons; select all via ⌘A.
        for id in ["multiSelect", "autoMerge"] { XCTAssertFalse(app.descendants(matching: .any)[id].exists, id) }
        XCTAssertFalse(app.buttons["Select all"].exists)
        // Give the map keyboard focus first (tap empty space above the frame); key focus right after launch can still be
        // elsewhere when tests run back to back, so retry ⌘A once.
        map(0.35, 0.2).tap()
        app.typeKey("a", modifierFlags: .command)
        if !app.staticTexts["selectionCount"].waitForExistence(timeout: 2) { app.typeKey("a", modifierFlags: .command) }
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3), "Multi-selection bar appears")
        let picked = selectionCount
        XCTAssertGreaterThan(picked, 1)
        app.buttons["Duplicate"].firstMatch.tap()
        XCTAssertEqual(waitFeatureCount(n0 + picked), n0 + picked, "All selected objects duplicated")
        XCTAssertEqual(selectionCount, picked, "The copies become the new selection")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "duplicate-many"
        shot.lifetime = .keepAlways
        add(shot)

        // Undo = one step.
        app.buttons["Undo"].tap()
        XCTAssertEqual(waitFeatureCount(n0), n0, "Undo removes all copies at once")
        // Copies gone → the selection is cleared too.
        XCTAssertFalse(app.staticTexts["selectionCount"].exists, "Selection of the copies released after undo")

        // 2. Click then drag on empty space = marquee (no Multi-select mode needed).
        map(0.10, 0.29).press(forDuration: 0.3, thenDragTo: map(0.52, 0.72))
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3), "Marquee selects several objects")
        let boxed = selectionCount
        XCTAssertGreaterThan(boxed, 1)
        let box = XCTAttachment(screenshot: app.screenshot())
        box.name = "marquee"
        box.lifetime = .keepAlways
        add(box)

        // Duplicate then delete the copies (Delete N objects) → back to the original count.
        app.buttons["Duplicate"].firstMatch.tap()
        XCTAssertEqual(waitFeatureCount(n0 + boxed), n0 + boxed)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete '")).firstMatch.tap()
        XCTAssertEqual(waitFeatureCount(n0), n0, "Selected copies deleted at once")

        // Marquee again with a quick drag without pause (mouse/finger click-drag), then tap empty space.
        map(0.10, 0.29).press(forDuration: 0.01, thenDragTo: map(0.52, 0.72), withVelocity: .fast, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3))
        map(0.56, 0.80).tap()
        XCTAssertFalse(app.staticTexts["selectionCount"].waitForExistence(timeout: 1), "Tapping empty space releases the selection")
    }

    /// Multi-selection → Change symbol → pick a symbol: every selected object changes in one undo step.
    func testChangeSymbolOfSelection() throws {
        let select = app.buttons["Move Tool"]
        guard select.waitForExistence(timeout: 15) else { throw XCTSkip("Latest project's area is not locked yet") }
        select.tap()
        Thread.sleep(forTimeInterval: 1.0)
        map(0.35, 0.85).tap()   // empty map below the frame (the toolbar band is at the top)
        app.typeKey("a", modifierFlags: .command)
        if !app.staticTexts["selectionCount"].waitForExistence(timeout: 2) { app.typeKey("a", modifierFlags: .command) }
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3), "Multi-selection bar appears")
        let picked = selectionCount

        let change = app.buttons["changeSelectionSymbol"]
        XCTAssertTrue(change.exists, "Change symbol in the multi-selection bar")
        change.tap()
        XCTAssertTrue(app.staticTexts["\(picked) objects"].waitForExistence(timeout: 3)
                      || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "\(picked) objects")).firstMatch.exists,
                      "Picker says how many objects change")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "change-symbol-many"
        shot.lifetime = .keepAlways
        add(shot)
        // First symbol in the list ("<code> <name>, <kind>").
        let row = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]{3}(\\.[0-9])? .*")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Symbols listed")
        let code = String(row.label.split(separator: " ").first ?? "")
        row.tap()
        let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "changed to \(code)")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 3), "Notice: objects changed to \(code)")
        let done = XCTAttachment(screenshot: app.screenshot())
        done.name = "change-symbol-many-done"
        done.lifetime = .keepAlways
        add(done)
        XCTAssertTrue(app.staticTexts["selectionCount"].exists, "Selection kept after the change")
    }
}
