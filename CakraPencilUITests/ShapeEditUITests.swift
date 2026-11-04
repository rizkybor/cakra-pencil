import XCTest

/// Alat edit seperti OCAD: tambah titik (ketuk dua kali di garis), potong, paralel, skala, balik arah.
final class ShapeEditUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layer", "-cp-use-symbol", "505000"]
        app.launch()
    }

    private func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func lines(_ n: Int) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Garis · \(n) titik · 0,45 mm"))
    }

    private func waitCount(_ q: XCUIElementQuery, _ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return q.count
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testReshapeCutParallelScale() throws {
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        // Sambung/ikuti objek dimatikan di tes ini agar objek sisa tes lain tidak ikut tergabung.
        pen.tap()
        Thread.sleep(forTimeInterval: 0.6)
        for id in ["autoMerge", "followGuides"] {
            let t = app.descendants(matching: .any)[id]
            if t.exists, (t.value as? String) == "1" { t.tap() }
        }
        let x = CGFloat.random(in: 0.12...0.18), y = CGFloat.random(in: 0.30...0.36)
        let two0 = lines(2).count, three0 = lines(3).count, four0 = lines(4).count

        map(x, y).tap()
        map(x + 0.12, y + 0.04).tap()
        map(x + 0.24, y).doubleTap()
        XCTAssertEqual(waitCount(lines(3), three0 + 1), three0 + 1, "Garis 3 titik")

        // Reshape: pilih garis, ketuk dua kali di segmen kedua = tambah titik.
        app.buttons["Pilih & edit titik"].tap()
        map(x + 0.06, y + 0.02).tap()
        Thread.sleep(forTimeInterval: 0.5)
        map(x + 0.18, y + 0.02).doubleTap()
        XCTAssertEqual(waitCount(lines(4), four0 + 1), four0 + 1, "Titik bertambah (4 titik)")
        XCTAssertEqual(lines(3).count, three0)

        // Potong garis di segmen pertama → 2 titik + 4 titik.
        app.buttons["shapeEdit"].tap()
        app.buttons["Potong garis"].tap()
        XCTAssertTrue(app.staticTexts["Potong: ketuk titik di garis untuk memotongnya jadi dua"].waitForExistence(timeout: 3))
        map(x + 0.06, y + 0.02).tap()
        XCTAssertEqual(waitCount(lines(2), two0 + 1), two0 + 1, "Bagian 1 (2 titik)")
        XCTAssertEqual(lines(4).count, four0 + 1, "Bagian 2 (4 titik)")
        shot("potong")

        // Paralel: salin bagian 1 (terpilih) ke kiri.
        app.buttons["shapeEdit"].tap()
        app.buttons["Paralel…"].tap()
        let copy = app.buttons["parallelCopy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertEqual(waitCount(lines(2), two0 + 2), two0 + 2, "Salinan paralel")
        shot("paralel")

        // Skala 200% dan balik arah pada objek terpilih.
        app.buttons["shapeEdit"].tap()
        app.buttons["Skala…"].tap()
        let k200 = app.buttons["200%"]
        XCTAssertTrue(k200.waitForExistence(timeout: 5))
        k200.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()   // tutup popover
        app.buttons["shapeEdit"].tap()
        app.buttons["Balik arah garis"].tap()
        XCTAssertEqual(lines(2).count, two0 + 2)
        shot("skala-balik")

        // Rapikan: undo balik, skala, paralel, potong, tambah titik, garis.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<6 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(waitCount(lines(2), two0), two0)
        XCTAssertEqual(lines(3).count, three0)
        XCTAssertEqual(lines(4).count, four0)
        for id in ["autoMerge", "followGuides"] {
            app.buttons["Pen tool (bezier)"].tap()
            let t = app.descendants(matching: .any)[id]
            if t.waitForExistence(timeout: 2), (t.value as? String) == "0" { t.tap() }
        }
    }
}
