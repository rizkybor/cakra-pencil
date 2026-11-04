import XCTest

/// Halaman Course Planner (seperti Purple Pen): buka dari tombol Course di workspace, buat lintasan,
/// tempatkan start → 2 kontrol → finish lewat rail, isi deskripsi IOF, cek tab Deskripsi dan Laporan,
/// export IOF XML + PDF, lalu undo semua langkah dan kembali ke peta kerja.
final class CoursePlannerUITests: XCTestCase {
    func testPlanCourseInDedicatedPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launch()

        let open = app.buttons["Buka Course Planner"]
        guard open.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        // Tunggu animasi workspace selesai (ketukan selama presentasi diabaikan iOS), lalu buka; ulang sekali bila perlu.
        XCTAssertTrue(app.buttons["Kunci area"].waitForExistence(timeout: 2) == false)
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: open)
        wait(for: [ready], timeout: 10)
        Thread.sleep(forTimeInterval: 1.5)
        open.tap()
        if !app.staticTexts["Course Planner"].waitForExistence(timeout: 4) { open.tap() }
        XCTAssertTrue(app.staticTexts["Course Planner"].waitForExistence(timeout: 5), "Halaman Course terbuka")
        XCTAssertTrue(app.buttons["Tempatkan Kontrol"].exists, "Rail alat Course")
        XCTAssertFalse(app.buttons["Pen tool (bezier)"].isHittable, "Alat gambar peta tidak ada di halaman Course")
        Thread.sleep(forTimeInterval: 1)
        let countLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Lintasan ('")).firstMatch
        XCTAssertTrue(countLabel.waitForExistence(timeout: 5))
        let coursesBefore = countLabel.label

        app.buttons["Lintasan baru"].tap()
        let x = CGFloat.random(in: 0.18...0.24), y = CGFloat.random(in: 0.34...0.40)
        func map(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y + dy)) }
        app.buttons["Tempatkan Start"].tap()
        map(0, 0).tap()
        map(0.14, 0.02).tap()   // otomatis lanjut ke Kontrol
        map(0.2, 0.12).tap()
        app.buttons["Tempatkan Finish"].tap()
        map(0.04, 0.16).tap()

        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start S'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Start di urutan kontrol")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS ', nomor 1'")).firstMatch
        XCTAssertTrue(first.exists, "Kontrol nomor 1")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS ', nomor 2'")).firstMatch.exists, "Kontrol nomor 2")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Finish F'")).firstMatch.exists, "Finish")

        // Deskripsi IOF kolom D.
        first.tap()
        let feature = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'D · Fitur'")).firstMatch
        XCTAssertTrue(feature.waitForExistence(timeout: 5), "Editor kontrol terbuka")
        feature.tap()
        let rock = app.buttons["2.4  Batu besar"]
        XCTAssertTrue(rock.waitForExistence(timeout: 5))
        rock.tap()
        app.navigationBars["Kontrol"].buttons["Selesai"].tap()
        XCTAssertTrue(app.staticTexts["Batu besar"].waitForExistence(timeout: 5), "Deskripsi di urutan kontrol")

        // Ukuran objek kontrol terpilih: default 100% (standar IOF), +10%.
        XCTAssertTrue(app.buttons["Ukuran kontrol 100 persen, ketuk untuk standar IOF"].waitForExistence(timeout: 5), "Default standar IOF")
        app.buttons["Perbesar kontrol"].tap()
        XCTAssertTrue(app.buttons["Ukuran kontrol 110 persen, ketuk untuk standar IOF"].waitForExistence(timeout: 3), "Kontrol diperbesar")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "course-lintasan"
        shot.lifetime = .keepAlways
        add(shot)

        // Tab Deskripsi: lembar deskripsi; tab Laporan: ringkasan; tab Kontrol: penomoran.
        app.segmentedControls.buttons["Deskripsi"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Batu besar'")).firstMatch.waitForExistence(timeout: 5),
                      "Baris deskripsi kontrol 1")
        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "course-deskripsi"
        shot2.lifetime = .keepAlways
        add(shot2)
        // Pratinjau PDF sebelum export: halaman deskripsi kontrol.
        app.buttons["Pratinjau PDF deskripsi"].tap()
        let preview = app.otherElements["Pratinjau peta lomba"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "Pratinjau peta lomba (satu halaman) tampil")
        Thread.sleep(forTimeInterval: 1)
        let shot3 = XCTAttachment(screenshot: app.screenshot())
        shot3.name = "course-pratinjau"
        shot3.lifetime = .keepAlways
        add(shot3)
        app.navigationBars.buttons["Tutup"].firstMatch.tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        app.segmentedControls.buttons["Laporan"].tap()
        XCTAssertTrue(app.staticTexts["Ringkasan lintasan"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Kontrol"].tap()
        XCTAssertTrue(app.buttons["Nomori ulang semua kode"].waitForExistence(timeout: 5))

        // Export dari top bar halaman Course.
        app.buttons["courseExport"].tap()
        XCTAssertTrue(app.switches["IOF XML 3.0 (CourseData)"].waitForExistence(timeout: 5), "Export langsung di mode Lintasan")
        app.navigationBars["Export"].buttons["Export"].tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15) || app.collectionViews.cells.count > 0, "Share Sheet muncul")
        XCTAssertFalse(app.alerts["Export gagal"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        let close = app.navigationBars["Export"].buttons["Tutup"]
        if close.waitForExistence(timeout: 5) { close.tap() }

        // Rapikan: riwayat undo sesi ini hanya berisi langkah tes, jadi undo sampai habis; lalu kembali ke peta kerja.
        XCTAssertTrue(app.navigationBars["Export"].waitForNonExistence(timeout: 5), "Export sheet tertutup")
        let undo = app.buttons["courseUndo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        var taps = 0
        while undo.isEnabled, taps < 12 {
            undo.tap()
            taps += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertGreaterThanOrEqual(taps, 7, "Lintasan, 4 titik, deskripsi, dan ukuran tercatat sebagai langkah undo")
        app.segmentedControls.buttons["Lintasan"].tap()
        XCTAssertTrue(app.staticTexts[coursesBefore].waitForExistence(timeout: 3), "Undo mengembalikan jumlah lintasan semula")
        app.buttons["Kembali ke peta kerja"].tap()
        XCTAssertTrue(app.buttons["Pen tool (bezier)"].waitForExistence(timeout: 5), "Kembali ke workspace pemetaan")
    }
}
