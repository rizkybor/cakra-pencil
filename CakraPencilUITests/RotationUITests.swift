import XCTest

/// Rotasi manual objek 0–360°: pilih objek dari panel Layer, ubah sudut lewat tombol ± dan preset.
final class RotationUITests: XCTestCase {
    func testRotateSelectedObject() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layer"]
        app.launch()

        // Buat objek sendiri (rectangle), lalu pilih dengan alat Pilih: tes tidak bergantung pada data lama.
        let rectangle = app.buttons["Rectangle"]
        guard rectangle.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        rectangle.tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: CGFloat.random(in: 0.15...0.25), dy: CGFloat.random(in: 0.30...0.40)))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 90, dy: 50)))
        app.buttons["Node Tool"].tap()

        let rotate = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rotasi objek'")).firstMatch
        XCTAssertTrue(rotate.waitForExistence(timeout: 5), "Tombol rotasi muncul untuk objek terpilih")
        rotate.tap()

        let zero = app.buttons["0°"]
        XCTAssertTrue(zero.waitForExistence(timeout: 5), "Panel rotasi terbuka")
        zero.tap()
        app.buttons["+15°"].tap()
        app.buttons["+15°"].tap()
        XCTAssertTrue(app.staticTexts["30°"].waitForExistence(timeout: 3), "0° + 15° + 15° = 30°")
        app.buttons["-1°"].tap()
        XCTAssertTrue(app.staticTexts["29°"].waitForExistence(timeout: 3), "Langkah 1°")
        app.buttons["90°"].tap()
        XCTAssertTrue(app.staticTexts["90°"].waitForExistence(timeout: 3), "Preset 90°")

        // Tutup panel: label tombol memuat sudut baru.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15)).tap()
        XCTAssertTrue(app.buttons["Rotasi objek, 90 derajat"].waitForExistence(timeout: 5), "Sudut tersimpan di objek")

        // Rapikan: hapus objek uji.
        app.buttons["Hapus objek"].tap()
        XCTAssertFalse(app.buttons["Rotasi objek, 90 derajat"].waitForExistence(timeout: 2), "Objek uji terhapus")
    }
}
