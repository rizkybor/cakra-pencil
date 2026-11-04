import XCTest

/// Course planner (seperti Purple Pen): buat lintasan, tempatkan start → 2 kontrol → finish, isi deskripsi IOF,
/// jumlah peserta, lalu export IOF XML + PDF. Di akhir semua langkah di-undo agar proyek uji bersih.
final class CoursePlannerUITests: XCTestCase {
    func testPlanCourseDescribeAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first", "-cp-inspector-tab", "Course"]
        app.launch()

        let newCourse = app.buttons["Lintasan baru"]
        guard newCourse.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek terbaru belum dikunci areanya") }
        Thread.sleep(forTimeInterval: 1)
        newCourse.tap()
        XCTAssertTrue(app.buttons["Kontrol lintasan"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.6)

        // Start → kontrol → kontrol (placement pindah otomatis ke Kontrol setelah start).
        let x = CGFloat.random(in: 0.14...0.2), y = CGFloat.random(in: 0.36...0.42)
        func map(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y + dy)) }
        map(0, 0).tap()
        map(0.14, 0.02).tap()
        map(0.2, 0.12).tap()
        app.segmentedControls.buttons["Finish"].tap()
        map(0.04, 0.16).tap()

        let start = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start S'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Start ada di daftar lintasan")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS ', nomor 1'")).firstMatch
        XCTAssertTrue(first.exists, "Kontrol nomor 1")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS ', nomor 2'")).firstMatch.exists, "Kontrol nomor 2")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Finish F'")).firstMatch.exists, "Finish ada")
        XCTAssertFalse(app.staticTexts["• A: belum ada finish."].exists)

        // Deskripsi IOF kolom D untuk kontrol 1.
        first.tap()
        let feature = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'D · Fitur'")).firstMatch
        XCTAssertTrue(feature.waitForExistence(timeout: 5), "Editor kontrol terbuka")
        feature.tap()
        let rock = app.buttons["2.4  Batu besar"]
        XCTAssertTrue(rock.waitForExistence(timeout: 5), "Simbol IOF 2.4 ada di menu")
        rock.tap()
        app.navigationBars["Kontrol"].buttons["Selesai"].tap()
        XCTAssertTrue(app.staticTexts["Batu besar"].waitForExistence(timeout: 5), "Deskripsi teks tampil di daftar")

        // Peserta → beban kontrol.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "lintasan"
        shot.lifetime = .keepAlways
        add(shot)
        let competitors = app.steppers.firstMatch
        XCTAssertTrue(competitors.waitForExistence(timeout: 5), "Stepper peserta ada")
        competitors.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["5 peserta"].firstMatch.waitForExistence(timeout: 3), "Beban kontrol dihitung")

        // Export: IOF XML + PDF per lintasan.
        app.buttons["Export lintasan…"].tap()
        let mode = app.segmentedControls.buttons["Lintasan"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "Export sheet terbuka")
        XCTAssertTrue(mode.isSelected, "Langsung di mode Lintasan")
        XCTAssertTrue(app.switches["IOF XML 3.0 (CourseData)"].exists)
        app.navigationBars["Export"].buttons["Export"].tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15) || app.collectionViews.cells.count > 0, "Share Sheet muncul")
        XCTAssertFalse(app.alerts["Export gagal"].exists)

        // Rapikan: tutup share sheet + export, undo semua langkah (lintasan, 4 titik, deskripsi, peserta).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        let close = app.navigationBars["Export"].buttons["Tutup"]
        if close.waitForExistence(timeout: 5) { close.tap() }
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        for _ in 0..<7 { undo.tap() }
        XCTAssertFalse(start.waitForExistence(timeout: 2), "Undo membersihkan lintasan uji")
    }
}
