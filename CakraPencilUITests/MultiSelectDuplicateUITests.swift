import XCTest

/// Pilih banyak (⌘A, kotak pilih) dan duplikat objek; kontrol peta ada di panel tools.
final class MultiSelectDuplicateUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layer"]
        app.launch()
    }

    private func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    /// Jumlah objek dari judul panel layer ("14 objek · 0 stroke").
    private func featureCount() -> Int {
        let label = app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' objek · '")).firstMatch.label
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
        guard select.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }

        // Kontrol peta menyatu di panel tools (satu panel): zoom, seluruh peta, kompas, lokasi.
        let rail = app.buttons["Navigasi"].frame
        for label in ["Zoom in", "Zoom out", "Lihat seluruh peta", "Zoom ke frame", "Tampilkan posisi saya"] {
            let b = app.buttons[label]
            XCTAssertTrue(b.exists, label)
            XCTAssertEqual(b.frame.midX, rail.midX, accuracy: 2, "\(label) segaris di panel tools")
        }

        select.tap()
        let n0 = featureCount()
        XCTAssertGreaterThan(n0, 1, "Proyek uji punya beberapa objek")

        // 1. Pilih semua → semua objek terpilih; Duplikat → jumlah objek dua kali lipat (yang tidak terkunci).
        // Tanpa tombol Pilih banyak / Pilih semua / Gabung otomatis; pilih semua lewat ⌘A.
        for id in ["multiSelect", "autoMerge"] { XCTAssertFalse(app.descendants(matching: .any)[id].exists, id) }
        XCTAssertFalse(app.buttons["Pilih semua"].exists)
        app.typeKey("a", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3), "Bar pilih banyak muncul")
        let picked = selectionCount
        XCTAssertGreaterThan(picked, 1)
        app.buttons["Duplikat"].firstMatch.tap()
        XCTAssertEqual(waitFeatureCount(n0 + picked), n0 + picked, "Semua objek terpilih diduplikat")
        XCTAssertEqual(selectionCount, picked, "Salinan jadi pilihan baru")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "duplikat-banyak"
        shot.lifetime = .keepAlways
        add(shot)

        // Undo = satu langkah.
        app.buttons["Undo"].tap()
        XCTAssertEqual(waitFeatureCount(n0), n0, "Undo menghapus semua salinan sekaligus")
        // Salinan hilang → pilihan ikut kosong.
        XCTAssertFalse(app.staticTexts["selectionCount"].exists, "Pilihan salinan dilepas setelah undo")

        // 2. Klik lalu tarik di tempat kosong = kotak pilih (tanpa perlu mode Pilih banyak).
        map(0.10, 0.29).press(forDuration: 0.3, thenDragTo: map(0.52, 0.72))
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3), "Kotak pilih memilih beberapa objek")
        let boxed = selectionCount
        XCTAssertGreaterThan(boxed, 1)
        let box = XCTAttachment(screenshot: app.screenshot())
        box.name = "kotak-pilih"
        box.lifetime = .keepAlways
        add(box)

        // Duplikat lalu hapus salinan (Hapus N objek) → kembali ke jumlah awal.
        app.buttons["Duplikat"].firstMatch.tap()
        XCTAssertEqual(waitFeatureCount(n0 + boxed), n0 + boxed)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hapus '")).firstMatch.tap()
        XCTAssertEqual(waitFeatureCount(n0), n0, "Salinan terpilih dihapus sekaligus")

        // Kotak pilih lagi dengan tarikan cepat tanpa jeda (klik-tarik mouse/jari), lalu ketuk tempat kosong.
        map(0.10, 0.29).press(forDuration: 0.01, thenDragTo: map(0.52, 0.72), withVelocity: .fast, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.staticTexts["selectionCount"].waitForExistence(timeout: 3))
        map(0.56, 0.80).tap()
        XCTAssertFalse(app.staticTexts["selectionCount"].waitForExistence(timeout: 1), "Ketuk tempat kosong melepas pilihan")
    }
}
