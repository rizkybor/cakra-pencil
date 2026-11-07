import XCTest
@testable import CakraCore

/// Basemap GeoTIFF: georeferensi dibaca dari tag, posisi pojok tepat di UTM proyek.
final class BasemapImageTests: XCTestCase {
    /// GeoTIFF minimal (tanpa piksel) dengan tag georeferensi sama seperti timo.tif: 8192 × 5574, EPSG:32748,
    /// piksel 0,23123 m, tiepoint (0,0) → (702395.672409, 9315992.579392).
    static func timoLikeGeoTIFF() -> Data {
        var d = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        func u16(_ v: Int) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func u32(_ v: Int) { d.append(contentsOf: (0..<4).map { UInt8(v >> (8 * $0) & 0xFF) }) }
        func f64(_ v: Double) { d.append(contentsOf: (0..<8).map { UInt8(v.bitPattern >> (8 * UInt64($0)) & 0xFF) }) }
        let scale = [0.2312297475472178, 0.23122974754731193, 0]
        let tie = [0, 0, 0, 702_395.672409, 9_315_992.579392, 0]
        let keys = [1, 1, 0, 3, 1024, 0, 1, 1, 2048, 0, 1, 4326, 3072, 0, 1, 32748]
        let entries = 5, ifdSize = 2 + entries * 12 + 4
        let scaleOff = 8 + ifdSize, tieOff = scaleOff + 24, keysOff = tieOff + 48
        u16(entries)
        u16(256); u16(4); u32(1); u32(8192)
        u16(257); u16(4); u32(1); u32(5574)
        u16(33550); u16(12); u32(3); u32(scaleOff)
        u16(33922); u16(12); u32(6); u32(tieOff)
        u16(34735); u16(3); u32(keys.count); u32(keysOff)
        u32(0)
        scale.forEach(f64)
        tie.forEach(f64)
        keys.forEach(u16)
        return d
    }

    func testReadsTimoGeoTIFF() throws {
        let data = Self.timoLikeGeoTIFF()
        let info = try GeoTIFFGeoref.read(data)
        XCTAssertEqual(info.width, 8192)
        XCTAssertEqual(info.height, 5574)
        XCTAssertEqual(info.crs, .utm(epsg: 32748))
        XCTAssertEqual(info.originX, 702_395.672409, accuracy: 1e-6)
        XCTAssertEqual(info.originY, 9_315_992.579392, accuracy: 1e-6)
        XCTAssertEqual(info.pixelSizeX, 0.2312297475472178, accuracy: 1e-12)

        let image = BasemapImage(fileName: "basemap.tif", originalName: "timo.tif", crs: info.crs, originX: info.originX,
                                 originY: info.originY, pixelSizeX: info.pixelSizeX, pixelSizeY: info.pixelSizeY,
                                 width: info.width, height: info.height)
        let zone = UTMZone(epsg: 32748)!
        let c = image.corners(in: zone)
        XCTAssertEqual(c[0].x, 702_395.672409, accuracy: 1e-3, "Kiri atas")
        XCTAssertEqual(c[0].y, 9_315_992.579392, accuracy: 1e-3)
        XCTAssertEqual(c[2].x, 702_395.672409 + 8192 * 0.23123, accuracy: 1e-2, "Kanan bawah")
        XCTAssertEqual(c[2].y, 9_315_992.579392 - 5574 * 0.23123, accuracy: 1e-2)
        let size = image.groundSizeM(in: zone)
        XCTAssertEqual(size.width, 1894.2, accuracy: 0.5)
        XCTAssertEqual(size.height, 1288.9, accuracy: 0.5)
    }

    func testOtherUTMZoneAndGeographicAreReprojected() {
        let zone48 = UTMZone(epsg: 32748)!, zone49 = UTMZone(epsg: 32749)!
        let ll = LatLon(lat: -6.2, lon: 107.6)
        let p49 = zone49.project(ll)
        let img49 = BasemapImage(fileName: "a.tif", originalName: "a.tif", crs: .utm(epsg: 32749), originX: p49.x, originY: p49.y,
                                 pixelSizeX: 1, pixelSizeY: 1, width: 10, height: 10)
        XCTAssertEqual(img49.corners(in: zone48)[0].distance(to: zone48.project(ll)), 0, accuracy: 0.01)
        let geo = BasemapImage(fileName: "b.tif", originalName: "b.tif", crs: .geographic, originX: 107.6, originY: -6.2,
                               pixelSizeX: 0.0001, pixelSizeY: 0.0001, width: 10, height: 10)
        XCTAssertEqual(geo.corners(in: zone48)[0].distance(to: zone48.project(ll)), 0, accuracy: 0.01)
    }

    func testRejectsPlainTIFFAndNonTIFF() throws {
        XCTAssertThrowsError(try GeoTIFFGeoref.read(Data("hello".utf8))) {
            XCTAssertEqual($0 as? GeoTIFFGeoref.GeorefError, .notTIFF)
        }
        // TIFF minimal tanpa tag GeoTIFF.
        var d = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        func u16(_ v: Int) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
        func u32(_ v: Int) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)]) }
        u16(2)
        u16(256); u16(3); u32(1); u32(4)
        u16(257); u16(3); u32(1); u32(4)
        u32(0)
        XCTAssertThrowsError(try GeoTIFFGeoref.read(d)) {
            XCTAssertEqual($0 as? GeoTIFFGeoref.GeorefError, .notGeoreferenced)
        }
    }

    func testOldProjectWithoutBasemapImageStillDecodes() throws {
        let json = #"{"id":"6575051A-2834-47E3-AD59-460D2FC5EA7D","name":"Lama","sheet":{"paper":{"name":"A4","shortMM":210,"longMM":297},"orientation":"portrait","marginMM":0,"scaleDenominator":4000},"sketchDPI":900,"areaLocked":false,"snapStepM":10,"createdAt":"2026-11-01T00:00:00Z","updatedAt":"2026-11-01T00:00:00Z"}"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        XCTAssertNil(try d.decode(Project.self, from: Data(json.utf8)).basemapImage)
    }

    func testScalePresetsStepBy500From1000() {
        XCTAssertEqual(MapPresets.scales.first, 1000)
        XCTAssertEqual(MapPresets.scales.last, 15000)
        XCTAssertEqual(MapPresets.scales.count, 29)
        XCTAssertTrue(zip(MapPresets.scales, MapPresets.scales.dropFirst()).allSatisfy { $1 - $0 == 500 })
        // Skala proyek lama tetap ada di daftar.
        for old in [3000, 4000, 5000, 7500, 10000, 15000] { XCTAssertTrue(MapPresets.scales.contains(old), "1:\(old)") }
        // Lembar A4 1:1000 = 210 × 297 m di lapangan.
        let s = SheetSpec(scaleDenominator: 1000)
        XCTAssertEqual(s.groundWidthM, 210, accuracy: 1e-9)
        XCTAssertEqual(s.groundHeightM, 297, accuracy: 1e-9)
    }

    func testAreaBackupRestoresPreviousLockedArea() throws {
        var p = Project(name: "Uji", crsEPSG: 32748, frameOrigin: Point2D(x: 702_920, y: 9_314_750), areaLocked: true)
        let backup = AreaBackup(of: p)
        // Pilih ulang area: buka kunci, ganti skala/orientasi dan geser frame.
        p.areaBackup = backup
        p.areaLocked = false
        p.sheet.scaleDenominator = 2500
        p.sheet.orientation = .landscape
        p.frameOrigin = Point2D(x: 1, y: 2)
        // Tersimpan di project.json dan terbaca lagi.
        let e = JSONEncoder(), d = JSONDecoder()
        e.dateEncodingStrategy = .iso8601; d.dateDecodingStrategy = .iso8601
        var back = try d.decode(Project.self, from: e.encode(p))
        XCTAssertEqual(back.areaBackup, backup)
        // Batal → area lama, terkunci, cadangan dihapus.
        try XCTUnwrap(back.areaBackup).restore(into: &back)
        XCTAssertTrue(back.areaLocked)
        XCTAssertNil(back.areaBackup)
        XCTAssertEqual(back.frameOrigin, Point2D(x: 702_920, y: 9_314_750))
        XCTAssertEqual(back.sheet.scaleDenominator, 4000)
        XCTAssertEqual(back.sheet.orientation, .portrait)
    }

    func testReadsTIFFDateTimeWhenPresent() throws {
        XCTAssertNil(try GeoTIFFGeoref.read(Self.timoLikeGeoTIFF()).dateTime, "Tanpa tag DateTime")
        // GeoTIFF minimal lat/lon dengan tag 306 DateTime (ASCII).
        var d = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        func u16(_ v: Int) { d.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
        func u32(_ v: Int) { d.append(contentsOf: (0..<4).map { UInt8(v >> (8 * $0) & 0xFF) }) }
        func f64(_ v: Double) { d.append(contentsOf: (0..<8).map { UInt8(v.bitPattern >> (8 * UInt64($0)) & 0xFF) }) }
        let date = Array("2024:05:17 10:22:31".utf8) + [0]
        let keys = [1, 1, 0, 2, 1024, 0, 1, 2, 2048, 0, 1, 4326]
        let entries = 6, ifdSize = 2 + entries * 12 + 4
        let scaleOff = 8 + ifdSize, tieOff = scaleOff + 24, keysOff = tieOff + 48, dateOff = keysOff + keys.count * 2
        u16(entries)
        u16(256); u16(4); u32(1); u32(100)
        u16(257); u16(4); u32(1); u32(100)
        u16(306); u16(2); u32(date.count); u32(dateOff)
        u16(33550); u16(12); u32(3); u32(scaleOff)
        u16(33922); u16(12); u32(6); u32(tieOff)
        u16(34735); u16(3); u32(keys.count); u32(keysOff)
        u32(0)
        [0.0001, 0.0001, 0].forEach(f64)
        [0, 0, 0, 107.6, -6.2, 0].forEach(f64)
        keys.forEach(u16)
        d.append(contentsOf: date)
        let info = try GeoTIFFGeoref.read(d)
        XCTAssertEqual(info.crs, .geographic)
        XCTAssertEqual(info.dateTime, "2024:05:17 10:22:31")

        var image = BasemapImage(fileName: "a.tif", originalName: "a.tif", crs: .geographic, originX: 0, originY: 0,
                                 pixelSizeX: 1, pixelSizeY: 1, width: 1, height: 1)
        image.dateTime = "2024:05:17 10:22:31"
        XCTAssertEqual(image.dateLabel, "17-05-2024")
    }
}
