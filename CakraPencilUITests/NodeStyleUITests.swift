import XCTest

/// Node Tool: titik aktif → Convert to Sharp / Smooth / Smart.
final class NodeStyleUITests: XCTestCase {
    func testConvertActiveNode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layer", "-cp-use-symbol", "505000"]
        app.launch()
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        let map = { (x: CGFloat, y: CGFloat) in app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }
        let x: CGFloat = 0.15, y: CGFloat = 0.28
        let lines = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Garis · 3 titik'"))
        let n0 = lines.count

        pen.tap()
        map(x, y).tap()
        map(x + 0.08, y + 0.04).tap()
        map(x + 0.16, y).doubleTap()
        let deadline = Date().addingTimeInterval(5)
        while lines.count != n0 + 1, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertEqual(lines.count, n0 + 1, "Garis 3 titik")

        // Node Tool: pilih garis, lalu ketuk titik tengah → tiga tombol jenis titik muncul.
        app.buttons["Node Tool"].tap()
        map(x + 0.04, y + 0.02).tap()
        Thread.sleep(forTimeInterval: 0.4)
        map(x + 0.08, y + 0.04).tap()
        let sharp = app.buttons["Convert to Sharp"], smooth = app.buttons["Convert to Smooth"], smart = app.buttons["Convert to Smart"]
        XCTAssertTrue(sharp.waitForExistence(timeout: 3), "Tombol jenis titik muncul untuk titik aktif")
        XCTAssertTrue(sharp.isSelected, "Titik pen tool tanpa handle = sharp")

        smart.tap()
        XCTAssertTrue(smart.waitForSelected(), "Convert to Smart")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "titik-smart"
        shot.lifetime = .keepAlways
        add(shot)
        smooth.tap()
        XCTAssertTrue(smooth.waitForSelected(), "Convert to Smooth")
        sharp.tap()
        XCTAssertTrue(sharp.waitForSelected(), "Convert to Sharp")

        // Tarik tengah segmen pertama ke atas → segmen jadi lengkung, garis tetap 3 titik (tidak berpindah).
        map(x + 0.04, y + 0.02).press(forDuration: 0.2, thenDragTo: map(x + 0.03, y - 0.03))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(lines.count, n0 + 1, "Masih garis 3 titik")
        let bent = XCTAttachment(screenshot: app.screenshot())
        bent.name = "segmen-ditarik"
        bent.lifetime = .keepAlways
        add(bent)

        // Move Tool tidak menampilkan tombol titik.
        app.buttons["Move Tool"].tap()
        XCTAssertFalse(sharp.waitForExistence(timeout: 1))

        // Rapikan: 3 konversi + tarik segmen + garis.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<5 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(lines.count, n0)
    }
}

private extension XCUIElement {
    func waitForSelected(timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isSelected, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return isSelected
    }
}
