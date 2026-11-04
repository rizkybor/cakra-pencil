import XCTest

/// Perilaku menggambar mirip OCAD/OOM: gambar bebas dengan simbol garis, pen tool selesai dengan ketuk dua kali,
/// dan "Ganti simbol" pada objek terpilih. Butuh proyek terbaru yang areanya sudah dikunci (simulator uji).
final class OcadLikeDrawingUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Layer", "-cp-use-symbol", "505000"]
        app.launch()
    }

    private func count(_ prefix: String) -> Int {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).count
    }

    /// Tunggu sampai jumlah baris layer berawalan `prefix` = `n` (daftar diperbarui setelah gestur selesai).
    private func waitCount(_ prefix: String, _ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while count(prefix) != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return count(prefix)
    }

    private func waitCount(_ q: XCUIElementQuery, _ n: Int, timeout: TimeInterval = 5) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while q.count != n, Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return q.count
    }

    private func map(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    func testFreehandPenDoubleTapAndSwitchSymbol() throws {
        let freehand = app.buttons["Gambar bebas"]
        guard freehand.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        let before = count("505.0")

        // 1. Gambar bebas dengan simbol garis 505.0.
        freehand.tap()
        // Posisi acak: ujung goresan yang jatuh di ujung garis 505.0 sisa putaran sebelumnya akan digabung otomatis.
        let fy = CGFloat.random(in: 0.46...0.53), fx = CGFloat.random(in: 0.14...0.22)
        map(fx, fy).press(forDuration: 0.2, thenDragTo: map(fx + 0.32, fy + 0.01))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '505.0'")).element(boundBy: before).waitForExistence(timeout: 5),
                      "Gambar bebas membuat objek 505.0")

        // 2. Pen tool: dua ketukan + ketuk dua kali = selesai, garis 3 titik (titik ketukan ganda ikut).
        //    Posisi acak agar tidak jatuh di ujung garis dari putaran tes sebelumnya (itu memicu "lanjutkan garis").
        let x = CGFloat.random(in: 0.12...0.22), y = CGFloat.random(in: 0.56...0.63) // di atas hint pen tool (2 baris di portrait, mulai ±0,68)
        let threeNodes = app.staticTexts.matching(NSPredicate(format: "label == 'Garis · 3 titik · 0,45 mm'"))
        let fourNodes = app.staticTexts.matching(NSPredicate(format: "label == 'Garis · 4 titik · 0,45 mm'"))
        let three0 = threeNodes.count, four0 = fourNodes.count
        app.buttons["Pen tool (bezier)"].tap()
        Thread.sleep(forTimeInterval: 0.6) // ketukan selama pergantian alat bisa hilang
        map(x, y).tap()
        map(x + 0.12, y + 0.03).tap()
        map(x + 0.25, y).doubleTap()
        let afterPen = waitCount("505.0", before + 2)
        XCTAssertEqual(afterPen, before + 2, "Ketuk dua kali menyelesaikan garis baru")
        XCTAssertEqual(waitCount(threeNodes, three0 + 1), three0 + 1, "Garis pen tool punya 3 titik (titik ketukan ganda jadi titik akhir)")

        // 3. Lanjutkan garis (OCAD/OOM): mulai tepat di ujung garis tadi → garis itu disambung, bukan objek baru.
        map(x + 0.25, y).tap()
        map(x + 0.32, y + 0.04).doubleTap()
        XCTAssertEqual(waitCount(fourNodes, four0 + 1), four0 + 1, "Garis yang dilanjutkan bertambah jadi 4 titik")
        XCTAssertEqual(count("505.0"), afterPen, "Melanjutkan garis tidak membuat objek baru")
        XCTAssertEqual(threeNodes.count, three0, "Garis 3 titik tadi kini 4 titik")

        // 4. Pilih garis gambar bebas, pilih simbol 506.0 di panel, Ganti simbol.
        app.buttons["Pilih & edit titik"].tap()
        map(fx + 0.16, fy + 0.005).tap()
        app.buttons["Simbol"].tap()
        let search = app.textFields["Cari kode atau nama"]
        if !search.waitForExistence(timeout: 3) { app.buttons["Simbol"].tap() } // ketukan tab kadang jatuh saat panel beranimasi
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("506")
        let small = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '506.0'")).firstMatch
        XCTAssertTrue(small.waitForExistence(timeout: 5), "Simbol 506.0 ditemukan")
        small.tap()
        let switchButton = app.buttons["Ganti simbol → 506.0"]
        XCTAssertTrue(switchButton.waitForExistence(timeout: 5), "Tombol Ganti simbol muncul untuk objek terpilih")
        switchButton.tap()

        app.buttons["Layer"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '506.0'")).firstMatch.waitForExistence(timeout: 5),
                      "Objek berganti simbol ke 506.0")

        // Rapikan agar proyek uji tidak menumpuk objek: undo ganti simbol, lanjutkan garis, pen tool, gambar bebas.
        let undo = app.buttons["Undo"].firstMatch
        for _ in 0..<4 { undo.tap() }
        // (Jangan hitung "505.0": teks itu juga tampil di kontrol simbol aktif, yang kini 506.0.)
        XCTAssertEqual(waitCount(fourNodes, four0), four0, "Undo menghapus garis pen tool uji")
        XCTAssertEqual(threeNodes.count, three0)
    }
}
