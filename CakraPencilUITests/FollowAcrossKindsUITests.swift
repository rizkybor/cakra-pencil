import XCTest

/// Ikuti objek lintas jenis: simbol area mengikuti garis, dan simbol garis mengikuti area
/// (ketuk pertama lalu ketuk kedua di objek yang sama).
final class FollowAcrossKindsUITests: XCTestCase {
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

    private func rows(_ prefix: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
    }

    private func waitCount(_ q: XCUIElementQuery, _ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return q.count
    }

    /// Pilih simbol dari panel Simbol (kode diketik di kolom cari), lalu kembali ke panel Layer.
    private func useSymbol(_ code: String) {
        app.buttons["Simbol"].tap()
        let search = app.textFields["Cari kode atau nama"]
        if !search.waitForExistence(timeout: 3) { app.buttons["Simbol"].tap() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        if let old = search.value as? String, !old.isEmpty, old != "Cari kode atau nama" {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        search.typeText(code)
        let symbol = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "\(code).0")).firstMatch
        XCTAssertTrue(symbol.waitForExistence(timeout: 5), "Simbol \(code).0")
        symbol.tap()
        app.buttons["Layer"].tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testAreaFollowsLineAndLineFollowsArea() throws {
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        pen.tap()
        // Bagian kosong di atas frame peta proyek uji (tanpa objek lain yang bisa ikut ditempeli).
        let x: CGFloat = 0.15, y: CGFloat = 0.28
        let line3 = rows("Garis · 3 titik"), line4 = rows("Garis · 4 titik"), area4 = rows("Area · 4 titik")
        let l3 = line3.count, l4 = line4.count, a4 = area4.count

        // Garis A (505.0): 3 titik dengan sudut di tengah.
        map(x, y).tap()
        map(x + 0.08, y + 0.03).tap()
        map(x + 0.16, y).doubleTap()
        XCTAssertEqual(waitCount(line3, l3 + 1), l3 + 1, "Garis A")

        // Area (406.0) mengikuti garis A: ketuk tengah segmen 1 lalu tengah segmen 2 → sudut A ikut disalin,
        // lalu satu titik di bawah dan ketuk titik pertama untuk menutup = area 4 titik.
        useSymbol("406")
        map(x + 0.04, y + 0.015).tap()
        map(x + 0.12, y + 0.015).tap()
        map(x + 0.08, y + 0.08).tap()
        map(x + 0.04, y + 0.015).tap()
        XCTAssertEqual(waitCount(area4, a4 + 1), a4 + 1, "Area mengikuti bentuk garis (4 titik)")

        // Garis (505.0) mengikuti area tadi: ketuk di sisi kanan lalu sisi kiri bawah → sudut bawah area ikut
        // disalin, lalu ketuk dua kali di luar = garis 4 titik.
        useSymbol("505")
        map(x + 0.10, y + 0.0475).tap()
        map(x + 0.06, y + 0.0475).tap()
        map(x + 0.06, y + 0.12).doubleTap()
        XCTAssertEqual(waitCount(line4, l4 + 1), l4 + 1, "Garis mengikuti bentuk area (4 titik)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ikuti-lintas-jenis"
        shot.lifetime = .keepAlways
        add(shot)

        // Rapikan: garis, area, garis A.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<3 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(waitCount(line3, l3), l3)
        XCTAssertEqual(area4.count, a4)
        XCTAssertEqual(line4.count, l4)
    }
}
