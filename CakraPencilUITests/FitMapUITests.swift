import XCTest

/// Tombol "Lihat seluruh peta" di grup zoom: setelah zoom in jauh, seluruh frame + objek kembali terlihat.
final class FitMapUITests: XCTestCase {
    func testFitWholeMap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-cp-open-first"]
        app.launch()
        let fit = app.buttons["Lihat seluruh peta"]
        guard fit.waitForExistence(timeout: 15) else { throw XCTSkip("Proyek belum terbuka") }
        let zoomIn = app.buttons["Zoom in"]
        for _ in 0..<4 { zoomIn.tap(); Thread.sleep(forTimeInterval: 0.4) }
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "sebelum-fit"
        before.lifetime = .keepAlways
        add(before)
        fit.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "seluruh-peta"
        after.lifetime = .keepAlways
        add(after)
        XCTAssertTrue(app.buttons["Zoom ke frame"].exists, "Tombol zoom ke frame tetap ada di rail")

        // Tata letak tidak meluber: bar atas dan kontrol peta tetap di dalam layar.
        let screen = app.windows.firstMatch.frame
        let export = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Export'")).firstMatch
        XCTAssertTrue(export.exists)
        XCTAssertGreaterThanOrEqual(export.frame.minY, screen.minY + 20, "Bar atas tidak tertutup status bar")
        XCTAssertTrue(screen.contains(fit.frame), "Kontrol peta di dalam layar")
        XCTAssertTrue(screen.contains(app.buttons["Tampilkan posisi saya"].frame), "Tombol lokasi di dalam layar")

        // Landscape (tinggi layar paling sempit): sama, tidak boleh meluber atas/bawah.
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        Thread.sleep(forTimeInterval: 1.5)
        let land = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(export.frame.minY, land.minY + 20, "Landscape: bar atas tidak tertutup status bar")
        XCTAssertTrue(land.contains(app.buttons["Tampilkan posisi saya"].frame), "Landscape: tombol lokasi di dalam layar")
        XCTAssertTrue(land.contains(app.buttons["Zoom ke frame"].frame), "Landscape: rail di dalam layar")
        let landShot = XCTAttachment(screenshot: app.screenshot())
        landShot.name = "landscape"
        landShot.lifetime = .keepAlways
        add(landShot)
    }
}
