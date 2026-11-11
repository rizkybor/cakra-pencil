import XCTest

/// Course Settings rail: Move Tool (select/move only, nothing placed) and Cut leg (gap in the course line).
final class CourseMoveAndCutLegUITests: XCTestCase {
    func testMoveToolPlacesNothingAndCutLegHint() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-open-course", "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()
        let move = app.buttons["Move Tool"]
        guard move.waitForExistence(timeout: 15) else { throw XCTSkip("Course page not open") }
        let all = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'controls on the map'")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        let before = all.label

        // Move Tool: tapping empty map space places no control.
        move.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Move Tool:'")).firstMatch.waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.40)).tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(all.label, before, "No new control with the Move Tool")

        // Cut leg tool: active, with its hint for the open course.
        app.buttons["Cut leg"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Cut leg'")).firstMatch.waitForExistence(timeout: 3))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.40)).tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(all.label, before, "Cut leg places no control either")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "course-tools"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Cut leg: drag along a leg = gap of that length; tap inside the gap = remove it.
    func testDragAlongLegCutsAGap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-project", "Uji Vektor", "-cp-open-course", "-cp-no-splash", "-cp-no-imagery", "-cp-restore-fixtures"]
        app.launch()
        let cut = app.buttons["Cut leg"]
        guard cut.waitForExistence(timeout: 15) else { throw XCTSkip("Course page not open") }
        // The Course page's map overlay (the workspace has one too): its value counts the open course's gaps.
        // (the hidden workspace overlay may still show an older value, so take the highest count).
        func gaps() -> String? {
            let counts = app.descendants(matching: .any).matching(identifier: "vectorEditOverlay").allElementsBoundByIndex
                .compactMap { $0.value as? String }.filter { $0.hasPrefix("legGaps ") }
                .compactMap { Int($0.dropFirst("legGaps ".count)) }
            return counts.max().map { "legGaps \($0)" }
        }

        // Own course: start → control, a straight leg left to right.
        app.buttons["New course"].tap()
        let x: CGFloat = 0.18, y: CGFloat = 0.50   // inside the map frame, left of the panel
        let map = { (dx: CGFloat, dy: CGFloat) in app.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y + dy)) }
        app.buttons["Place Start"].tap()
        Thread.sleep(forTimeInterval: 1.0)   // the band's status row changes height; let the map settle
        map(0, 0).tap()
        map(0.20, 0).tap()
        Thread.sleep(forTimeInterval: 0.5)

        cut.tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(gaps(), "legGaps 0")
        map(0.06, 0).press(forDuration: 0.2, thenDragTo: map(0.13, 0))
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(gaps(), "legGaps 1", "Drag along the leg cuts a gap")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "leg-gap-drag"
        shot.lifetime = .keepAlways
        add(shot)

        map(0.095, 0).tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(gaps(), "legGaps 0", "Tap in the gap closes it")
    }
}
