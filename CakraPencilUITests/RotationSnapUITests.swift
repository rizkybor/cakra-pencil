import XCTest

/// Move Tool: pegangan rotasi di atas objek terpilih. Shift + putar = sisi lurus menempel sejajar dengan
/// garis lurus objek lain di dekatnya.
final class RotationSnapUITests: XCTestCase {
    func testShiftRotateAlignsLineWithNeighbour() throws {
        let app = XCUIApplication()
        // XCUITest tidak bisa menahan Shift selama gestur sentuh di iOS → `-cp-force-shift` (DEBUG) = Shift ditahan.
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layer", "-cp-use-symbol", "505000", "-cp-force-shift"]
        app.launch()
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        let size = app.windows.firstMatch.frame.size
        func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        let lines = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Garis · 2 titik · 0,45'"))
        let l0 = lines.count

        // Garis A mendatar dan garis B sedikit miring (±12° dari A), berjauhan agar tidak tergabung.
        // (Shift dipaksa: pen tool tidak memakai Shift, Move Tool baru dipakai setelah kedua garis jadi.)
        pen.tap()
        map(0.15, 0.29).tap()
        map(0.35, 0.29).doubleTap()
        let b0 = CGPoint(x: 0.15, y: 0.37), b1 = CGPoint(x: 0.35, y: 0.37 - 35 / size.height)
        map(b0.x, b0.y).tap()
        map(b1.x, b1.y).doubleTap()
        let deadline = Date().addingTimeInterval(5)
        while lines.count != l0 + 2, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertEqual(lines.count, l0 + 2)

        // Move Tool: pilih B → pegangan rotasi di atas kotaknya (tengah atas − 28 pt).
        app.buttons["Move Tool"].tap()
        map(0.56, 0.80).tap()
        map((b0.x + b1.x) / 2, (b0.y + b1.y) / 2).tap()
        let rotation = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rotasi objek'")).firstMatch
        XCTAssertTrue(rotation.waitForExistence(timeout: 3))
        XCTAssertEqual(rotation.label, "Rotasi objek, 0 derajat")

        // Titik (pt) layar.
        let p0 = CGPoint(x: b0.x * size.width, y: b0.y * size.height), p1 = CGPoint(x: b1.x * size.width, y: b1.y * size.height)
        let pivot = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let handle = CGPoint(x: pivot.x, y: min(p0.y, p1.y) - 28)
        // Putar ±10° searah jarum jam (sisi A ada di +12°): Shift → menempel tepat sejajar.
        let a = 10 * Double.pi / 180, dx = Double(handle.x - pivot.x), dy = Double(handle.y - pivot.y)
        let target = CGPoint(x: pivot.x + CGFloat(dx * cos(a) - dy * sin(a)), y: pivot.y + CGFloat(dx * sin(a) + dy * cos(a)))
        func pt(_ p: CGPoint) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x, dy: p.y))
        }
        pt(handle).press(forDuration: 0.3, thenDragTo: pt(target), withVelocity: .slow, thenHoldForDuration: 0.3)
        let snapped = rotation.label
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "rotasi-presisi"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(snapped, "Rotasi objek, 12 derajat", "Sejajar dengan garis A (bukan 10° atau 15°)")

        // Rapikan: rotasi, B, A.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<3 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(lines.count, l0)
    }
}
