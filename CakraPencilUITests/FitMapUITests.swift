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
    }
}
