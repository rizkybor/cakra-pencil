import XCTest

/// Ganti simbol objek yang sudah dibuat (OCAD Change symbol / OOM Switch symbol):
/// area → area lain, lalu area → garis, dari tombol "Ganti simbol" di bar objek terpilih.
final class SymbolSwitchUITests: XCTestCase {
    func testSwitchSymbolOfExistingObject() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Simbol", "-cp-use-symbol", "401000"]
        app.launch()

        // Gambar area 401.0 sendiri lalu pilih: tes tidak bergantung pada data lama.
        let rectangle = app.buttons["Rectangle"]
        guard rectangle.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        rectangle.tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: CGFloat.random(in: 0.15...0.25), dy: CGFloat.random(in: 0.30...0.40)))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 90, dy: 50)))
        app.buttons["Node Tool"].tap()

        let switchButton = app.buttons["Ganti simbol objek"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 5), "Tombol Ganti simbol muncul untuk objek terpilih")
        XCTAssertEqual(switchButton.value as? String, "401.0", "Objek dibuat dengan simbol 401.0")

        // Area → area lain.
        try pick("406.0", query: "406", app: app, from: switchButton)
        XCTAssertEqual(switchButton.value as? String, "406.0", "Simbol objek berganti ke 406.0")

        // Area → garis (seperti OOM: garis dan area bisa saling ditukar).
        try pick("506.0", query: "506", app: app, from: switchButton)
        XCTAssertEqual(switchButton.value as? String, "506.0", "Area berganti jadi garis 506.0")

        // Undo mengembalikan simbol sebelumnya.
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(waitForValue(switchButton, "406.0"), "Undo: kembali ke 406.0")

        app.buttons["Hapus objek"].tap()
        XCTAssertFalse(switchButton.waitForExistence(timeout: 2), "Objek uji terhapus")
    }

    private func pick(_ code: String, query: String, app: XCUIApplication, from button: XCUIElement) throws {
        button.tap()
        let search = app.textFields["Cari kode atau nama (mis. 506 atau path)"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Pemilih simbol terbuka")
        search.tap()
        search.typeText(query)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(code) ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Simbol \(code) ada di daftar")
        row.tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 5), "Pemilih tertutup setelah memilih")
        XCTAssertTrue(waitForValue(button, code), "Simbol objek jadi \(code)")
    }

    private func waitForValue(_ e: XCUIElement, _ v: String) -> Bool {
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", v), object: e)
        return XCTWaiter.wait(for: [done], timeout: 5) == .completed
    }
}
