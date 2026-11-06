import XCTest

/// Color Hierarchy: area kuning (401.0) yang digambar SETELAH garis jalan setapak (505.0) tetap berada di
/// bawahnya, karena kuning lebih bawah di tabel warna ISSprOM. Ketuk di garis = garis yang terpilih.
final class ColorHierarchyUITests: XCTestCase {
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

    func testYellowAreaStaysBelowFootpath() throws {
        let pen = app.buttons["Pen tool (bezier)"]
        guard pen.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        let lines = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Garis · 2 titik · 0,45'"))
        let areas = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Area · 4 titik'"))
        let l0 = lines.count, a0 = areas.count
        func wait(_ q: XCUIElementQuery, _ n: Int) -> Int {
            let deadline = Date().addingTimeInterval(5)
            while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            return q.count
        }

        // 1. Garis 505.0 dulu.
        pen.tap()
        map(0.15, 0.32).tap()
        map(0.35, 0.32).doubleTap()
        XCTAssertEqual(wait(lines, l0 + 1), l0 + 1, "Garis 505.0")

        // 2. Area kuning 401.0 (Rectangle) menutupi garis itu, digambar sesudahnya.
        useSymbol("401")
        app.buttons["Rectangle"].tap()
        map(0.12, 0.27).press(forDuration: 0.2, thenDragTo: map(0.38, 0.38))
        XCTAssertEqual(wait(areas, a0 + 1), a0 + 1, "Area 401.0")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "kuning-di-bawah-jalan"
        shot.lifetime = .keepAlways
        add(shot)

        // 3. Ketuk di garis (di dalam area kuning) dengan Move Tool → garis yang terpilih (terlihat paling atas).
        app.buttons["Move Tool"].tap()
        map(0.56, 0.80).tap()
        map(0.25, 0.32).tap()
        let lineKind = app.buttons["Garis"]
        XCTAssertTrue(lineKind.waitForExistence(timeout: 3))
        XCTAssertTrue(lineKind.isSelected, "Garis (di atas area kuning) yang terpilih")
        // Ketuk di area kuning di luar garis → area yang terpilih.
        map(0.25, 0.36).tap()
        XCTAssertTrue(app.buttons["Area"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(app.buttons["Area"].isSelected, "Area kuning terpilih saat diketuk di luar garis")

        // Rapikan.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<2 { undo.tap(); Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertEqual(wait(lines, l0), l0)
        XCTAssertEqual(areas.count, a0)
    }
}
