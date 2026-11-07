import XCTest

/// Alur hapus proyek dari halaman utama, persis seperti user: buat proyek, kembali, ••• → Hapus proyek → konfirmasi.
/// Lalu app dibuka ulang untuk memastikan proyek juga hilang dari disk, bukan hanya dari tampilan.
final class ProjectDeletionUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testCreateThenDeleteProject() {
        let name = "Hapus Uji \(Int.random(in: 1000...9999))"
        let menu = createProject(named: name)

        let alert = openDeleteConfirmation(menu)
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists,
                      "Nama proyek disebut di konfirmasi")
        alert.buttons["Hapus"].tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5), "Kartu hilang setelah dihapus")

        // Buka ulang: proyek tidak kembali (paket .cakra benar-benar terhapus dari disk).
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Proyek baru"].firstMatch.waitForExistence(timeout: 10) || app.buttons["Buat proyek pertama"].exists,
                      "Halaman utama tampil setelah buka ulang")
        XCTAssertFalse(app.buttons["Menu proyek \(name)"].waitForExistence(timeout: 3), "Proyek tidak muncul lagi setelah app dibuka ulang")
    }

    func testCancelKeepsProject() {
        let name = "Batal Hapus \(Int.random(in: 1000...9999))"
        let menu = createProject(named: name)

        let alert = openDeleteConfirmation(menu)
        alert.buttons["Batal"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), "Konfirmasi tertutup setelah Batal")
        XCTAssertTrue(menu.exists, "Batal: proyek tetap ada")

        // Bersihkan proyek uji ini.
        openDeleteConfirmation(menu).buttons["Hapus"].tap()
        XCTAssertTrue(menu.waitForNonExistence(timeout: 5), "Proyek uji terhapus")
    }

    // MARK: Langkah bersama

    /// Buat proyek lewat lembar Proyek baru, tunggu workspace siap, kembali ke daftar. Kembalikan tombol ••• kartunya.
    @discardableResult
    private func createProject(named name: String) -> XCUIElement {
        // Tombol bisa terdaftar sebelum layar peluncuran selesai: tunggu sampai benar-benar bisa diketuk.
        let newButton = app.buttons["Proyek baru"].firstMatch
        let firstButton = app.buttons["Buat proyek pertama"]
        let button = newButton.waitForExistence(timeout: 10) ? newButton : firstButton
        XCTAssertTrue(waitUntilHittable(button), "Halaman utama siap")
        button.tap()

        let field = app.textFields["Nama proyek"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Lembar Proyek baru terbuka")
        field.tap()
        field.typeText(name)
        let create = app.navigationBars["Proyek baru"].buttons["Buat"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), "Tombol Buat ada")
        create.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), "Lembar Proyek baru tertutup setelah Buat")

        // iOS mengabaikan sentuhan selama animasi presentasi: tunggu workspace selesai tampil.
        let back = app.buttons["Kembali ke daftar proyek"]
        XCTAssertTrue(back.waitForExistence(timeout: 15), "Workspace proyek baru terbuka")
        XCTAssertTrue(app.buttons["Kunci area"].waitForExistence(timeout: 15), "Workspace siap (mode Pilih Area)")
        Thread.sleep(forTimeInterval: 1.0)
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 10), "Workspace tertutup setelah Kembali")

        let menu = app.buttons["Menu proyek \(name)"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Kartu proyek baru ada di daftar")
        return menu
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
        let done = expectation(for: NSPredicate(format: "exists == true AND hittable == true"), evaluatedWith: element)
        return XCTWaiter.wait(for: [done], timeout: timeout) == .completed
    }

    /// ••• → Hapus proyek → alert konfirmasi tampil.
    private func openDeleteConfirmation(_ menu: XCUIElement) -> XCUIElement {
        menu.tap()
        let deleteItem = app.buttons["Hapus proyek"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 5), "Menu kartu berisi Hapus proyek")
        deleteItem.tap()
        let alert = app.alerts["Hapus proyek?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Dialog konfirmasi muncul")
        return alert
    }
}
