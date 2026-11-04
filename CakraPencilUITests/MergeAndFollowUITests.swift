import XCTest

/// Gabung otomatis dan panduan objek (OCAD Follow) dengan pen tool, simbol garis 505.0.
final class MergeAndFollowUITests: XCTestCase {
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

    func testAutoMergeAndFollowExistingLine() throws {
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        pen.tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(app.descendants(matching: .any)["autoMerge"].exists, "Sakelar gabung otomatis di bar pen tool")
        XCTAssertTrue(app.descendants(matching: .any)["followGuides"].exists, "Sakelar ikuti objek di bar pen tool")

        let x = CGFloat.random(in: 0.12...0.18), y = CGFloat.random(in: 0.56...0.60)
        let five0 = lines(5).count, four0 = lines(4).count, three0 = lines(3).count

        // Garis A: 3 titik, berakhir di E.
        map(x, y).tap()
        map(x + 0.12, y + 0.04).tap()
        map(x + 0.24, y).doubleTap()
        XCTAssertEqual(waitCount(lines(3), three0 + 1), three0 + 1, "Garis A")

        // Garis B: dari tempat lain, berakhir tepat di E → ujungnya menempel dan langsung digabung jadi 5 titik.
        map(x + 0.34, y + 0.05).tap()
        map(x + 0.30, y + 0.02).tap()
        map(x + 0.24, y).doubleTap()
        XCTAssertEqual(waitCount(lines(5), five0 + 1), five0 + 1, "A + B digabung jadi satu garis 5 titik")
        XCTAssertEqual(lines(3).count, three0, "Garis A tidak lagi berdiri sendiri")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "gabung-otomatis"
        shot.lifetime = .keepAlways
        add(shot)

        // Garis C mengikuti A: ketuk di tengah segmen 1 lalu tengah segmen 2 (di garis, bukan di titik) →
        // titik sudut A di antaranya ikut disalin; lalu ketuk dua kali di luar = 4 titik.
        map(x + 0.06, y + 0.02).tap()
        map(x + 0.18, y + 0.02).tap()
        map(x + 0.18, y - 0.06).doubleTap()
        XCTAssertEqual(waitCount(lines(4), four0 + 1), four0 + 1, "Garis C mengikuti bentuk A (4 titik)")

        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "ikuti-objek"
        shot2.lifetime = .keepAlways
        add(shot2)

        // Isi area (OCAD Fill): pilih garis gabungan A+B, isi dengan simbol area; garisnya tetap ada.
        let areas = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Area · 5 titik'"))
        let areas0 = areas.count
        app.buttons["Pilih & edit titik"].tap()
        map(x + 0.30, y + 0.02).tap()   // segmen garis B
        let fill = app.buttons["fillArea"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5), "Tombol Isi area untuk garis terpilih")
        fill.tap()
        let search = app.textFields["Cari kode atau nama (mis. 506 atau path)"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("406")
        let veg = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '406.0'")).firstMatch
        XCTAssertTrue(veg.waitForExistence(timeout: 5), "Hanya simbol area")
        veg.tap()
        XCTAssertEqual(waitCount(areas, areas0 + 1), areas0 + 1, "Area baru dari bentuk garis")
        XCTAssertEqual(lines(5).count, five0 + 1, "Garisnya tidak hilang")
        let shot3 = XCTAttachment(screenshot: app.screenshot())
        shot3.name = "isi-area"
        shot3.lifetime = .keepAlways
        add(shot3)

        // Rapikan: undo isi area, C, gabungan B, dan A.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<4 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(areas.count, areas0)
        XCTAssertEqual(waitCount(lines(5), five0), five0)
        XCTAssertEqual(lines(4).count, four0)
        XCTAssertEqual(lines(3).count, three0)
    }
}
