import XCTest

/// "Semua kontrol" (master): deskripsi + pratinjau PDF; objek lintasan: warna bebas dan beberapa lintasan.
final class MasterAndItemColorUITests: XCTestCase {
    func testAllControlsPreviewAndItemColor() throws {
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

        // Pastikan ada minimal satu lintasan (untuk pilihan "beberapa lintasan").
        app.segmentedControls.buttons["Lintasan"].tap()
        app.buttons["Lintasan baru"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        // Tab Deskripsi: pilih "Semua kontrol" → lembar master, lalu pratinjau.
        app.segmentedControls.buttons["Deskripsi"].tap()
        let all = app.segmentedControls.buttons["Semua kontrol"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "Pilihan Semua kontrol di tab Deskripsi")
        all.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Semua kontrol (master)'")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["Pratinjau deskripsi kontrol"].tap()   // tombol Pratinjau di bar atas
        XCTAssertTrue(app.navigationBars["Pratinjau Semua kontrol"].waitForExistence(timeout: 10), "Pratinjau master")
        XCTAssertTrue(app.buttons["Export PDF"].waitForExistence(timeout: 15))
        let pv = XCTAttachment(screenshot: app.screenshot())
        pv.name = "pratinjau-semua-kontrol"
        pv.lifetime = .keepAlways
        add(pv)
        app.buttons["Tutup"].tap()

        // Objek: persegi biru, hanya di lintasan tertentu.
        let x = CGFloat.random(in: 0.16...0.22), y = CGFloat.random(in: 0.30...0.36)
        func map(_ dx: CGFloat, _ dy: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x + dx, dy: y + dy)) }
        app.buttons["Alat Persegi"].tap()
        map(0.02, 0.06).press(forDuration: 0.2, thenDragTo: map(0.16, 0.14))
        let blue = app.buttons["Warna #0072CE"]
        XCTAssertTrue(blue.waitForExistence(timeout: 5), "Warna cepat di editor objek")
        blue.tap()
        XCTAssertTrue(app.descendants(matching: .any)["courseItemColor"].exists, "Pemilih warna bebas")
        let allCourses = app.switches["courseItemAllCourses"]
        XCTAssertTrue(allCourses.waitForExistence(timeout: 3))
        if (allCourses.value as? String) == "1" { allCourses.tap() }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tampil di lintasan'")).firstMatch.waitForExistence(timeout: 3),
                      "Daftar centang lintasan")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "objek-warna-lintasan"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
