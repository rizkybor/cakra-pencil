import XCTest

/// Panel Lintasan: ganti nama lintasan langsung, nama penyelenggara; tab Deskripsi: deskripsi bergambar IOF (kolom C–H).
final class CourseRenameAndSymbolsUITests: XCTestCase {
    func testRenameCourseAndSymbolDescriptions() throws {
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

        app.segmentedControls.buttons["Lintasan"].tap()
        app.buttons["Lintasan baru"].tap()

        // Ganti nama langsung di kartu detail lintasan.
        let name = app.textFields["courseName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Kolom nama lintasan")
        name.tap()
        name.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        else if app.menuItems["Pilih Semua"].waitForExistence(timeout: 1) { app.menuItems["Pilih Semua"].tap() }
        let newName = "Elite \(Int.random(in: 100...999))"
        name.typeText(newName + "\n")
        XCTAssertTrue(app.staticTexts["Lintasan \(newName)"].waitForExistence(timeout: 5), "Judul kartu memakai nama baru")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", newName)).firstMatch.exists
                      || app.staticTexts[newName].exists, "Nama baru di daftar lintasan")

        // Penyelenggara: tampil di bawah nama acara pada deskripsi.
        let org = app.textFields["organizer"]
        XCTAssertTrue(org.waitForExistence(timeout: 3), "Kolom penyelenggara")
        org.tap()
        if let v = org.value as? String, !v.isEmpty, v != org.placeholderValue {
            org.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count))
        }
        let orgName = "Makopala \(Int.random(in: 100...999))"
        org.typeText(orgName + "\n")

        // Deskripsi bergambar: pilih gaya Simbol IOF; tabel tampil (baris finish navigasi).
        app.segmentedControls.buttons["Deskripsi"].tap()
        XCTAssertTrue(app.staticTexts[orgName].waitForExistence(timeout: 5), "Penyelenggara di lembar deskripsi")
        let style = app.segmentedControls["descriptionStyle"]
        var swipes = 0
        while !(style.exists && style.isHittable), swipes < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45)))
            swipes += 1
        }
        XCTAssertTrue(style.exists, "Pilihan gaya deskripsi")
        style.buttons["Simbol IOF"].tap()
        XCTAssertTrue(style.buttons["Simbol IOF"].isSelected)
        let color = app.segmentedControls["descriptionColor"]
        XCTAssertTrue(color.exists, "Pilihan warna deskripsi")
        color.buttons["Ungu (seperti kontrol)"].tap()
        XCTAssertTrue(color.buttons["Ungu (seperti kontrol)"].isSelected)
        // Gulir kembali ke atas agar tabel deskripsi terlihat di screenshot.
        for _ in 0..<4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.3)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.85)))
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "deskripsi-simbol-ungu"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

