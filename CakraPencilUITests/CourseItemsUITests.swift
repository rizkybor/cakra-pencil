import XCTest

/// Halaman Course: teks + bentuk di peta (tab Objek), batas baris dan posisi deskripsi, pratinjau tanpa
/// panah utara / kotak judul.
final class CourseItemsUITests: XCTestCase {
    func testTextShapesAndDescriptionLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launch()

        let open = app.buttons["Buka Course Planner"]
        guard open.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: open)
        wait(for: [ready], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        open.tap()
        if !app.staticTexts["Course Planner"].waitForExistence(timeout: 4) { open.tap() }
        XCTAssertTrue(app.staticTexts["Course Planner"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)

        let x = CGFloat.random(in: 0.16...0.22), y = CGFloat.random(in: 0.30...0.36)
        func map(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y + dy)) }

        // Objek sisa run lain (bila ada) tidak boleh mengacaukan hitungan.
        app.segmentedControls.buttons["Objek"].tap()
        let parkirBefore = app.buttons.matching(NSPredicate(format: "label == 'Teks Parkir'")).count
        app.segmentedControls.buttons["Lintasan"].tap()

        // Lintasan kecil untuk tab Deskripsi.
        app.buttons["Lintasan baru"].tap()
        app.buttons["Tempatkan Start"].tap()
        map(0, 0.25).tap()
        map(0.1, 0.27).tap()
        map(0.2, 0.25).tap()
        app.buttons["Tempatkan Finish"].tap()
        map(0.25, 0.3).tap()

        // Teks: ketuk peta → tab Objek terbuka dengan editor teks.
        app.buttons["Alat Teks"].tap()
        map(0.05, 0.03).tap()   // di dalam batas kertas (posisi y acak bisa jatuh di tepi atas)
        let field = app.textFields["courseItemText"].exists ? app.textFields["courseItemText"] : app.textViews["courseItemText"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Editor teks di tab Objek")
        field.typeText("Parkir")   // teks baru: kolom kosong dan langsung fokus
        // Gaya huruf: tebal + miring (teks tersimpan saat fokus pindah).
        let weight = app.segmentedControls["courseTextWeight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 3), "Pilihan ketebalan huruf")
        weight.buttons["Tebal"].tap()
        XCTAssertTrue(weight.buttons["Tebal"].isSelected)
        let italic = app.descendants(matching: .any)["courseTextItalic"]
        XCTAssertTrue(italic.exists, "Tombol miring")
        italic.tap()
        XCTAssertTrue(app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'Ukuran huruf'")).firstMatch.exists)

        // Persegi: tarik di peta.
        app.buttons["Alat Persegi"].tap()
        map(0.02, 0.06).press(forDuration: 0.2, thenDragTo: map(0.16, 0.14))
        XCTAssertTrue(app.buttons["Persegi Persegi"].waitForExistence(timeout: 5), "Persegi ditambahkan")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Teks Parkir'")).count, parkirBefore + 1,
                       "Teks tersimpan saat pindah ke objek lain")
        let fill = app.switches["Isi transparan (mis. area terlarang)"]
        XCTAssertTrue(fill.waitForExistence(timeout: 3))
        fill.tap()
        // Garis.
        app.buttons["Alat Garis"].tap()
        map(0.02, 0.18).press(forDuration: 0.2, thenDragTo: map(0.2, 0.2))
        XCTAssertTrue(app.buttons["Garis Garis"].waitForExistence(timeout: 5), "Garis ditambahkan")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "objek-lintasan"
        shot.lifetime = .keepAlways
        add(shot)

        // Deskripsi: batas baris 3 → 2 kolom, pojok kiri bawah.
        app.segmentedControls.buttons["Deskripsi"].tap()
        let limit = app.switches["Batasi baris per kolom"]
        XCTAssertTrue(limit.waitForExistence(timeout: 5))
        // Mulai dari 8 baris: matikan dulu bila sudah aktif.
        if (limit.value as? String) == "1" { limit.tap() }
        limit.tap()
        let stepper = app.steppers.matching(NSPredicate(format: "label BEGINSWITH 'Maksimal baris'")).firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 3))
        for _ in 0..<5 { stepper.buttons.element(boundBy: 0).tap() }   // 8 → 3
        let twoCols = app.steppers.matching(NSPredicate(format: "label CONTAINS '3 baris · 2 kolom'")).firstMatch
        XCTAssertTrue(twoCols.waitForExistence(timeout: 3), "Baris berlebih pindah ke kolom kedua")
        let corner = app.buttons["Kiri bawah"]
        // Tombol pojok di bawah miniatur: gulir panel sampai terlihat.
        var swipes = 0
        while !corner.isHittable, swipes < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45)))
            swipes += 1
        }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "tata-letak-deskripsi"
        before.lifetime = .keepAlways
        add(before)
        corner.tap()
        let position = app.staticTexts["descriptionPosition"]
        XCTAssertTrue(position.waitForExistence(timeout: 3))
        let deadline = Date().addingTimeInterval(3)
        while position.label != "Kiri bawah", Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertEqual(position.label, "Kiri bawah", "Pojok deskripsi berganti")
        app.buttons["Pratinjau deskripsi kontrol"].firstMatch.tap()
        let preview = app.otherElements["Pratinjau peta lomba"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "pratinjau-objek-deskripsi"
        shot2.lifetime = .keepAlways
        add(shot2)
        app.navigationBars.buttons["Tutup"].firstMatch.tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))

        // Rapikan: undo semua langkah tes.
        let undo = app.buttons["courseUndo"]
        var taps = 0
        while undo.isEnabled, taps < 25 {
            undo.tap()
            taps += 1
            Thread.sleep(forTimeInterval: 0.25)
        }
        app.segmentedControls.buttons["Objek"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Teks Parkir'")).count, parkirBefore, "Undo menghapus objek tes")
        app.buttons["Kembali ke peta kerja"].tap()
    }
}
