import XCTest
@testable import CakraCore

/// Basemap GeoTIFF: georeferensi dibaca dari tag, posisi pojok tepat di UTM proyek.
final class BasemapImageTests: XCTestCase {
    /// timo.tif: 8192 × 5574, EPSG:32748, piksel 0,23123 m, tiepoint (0,0) → (702395.672409, 9315992.579392).
    func testReadsTimoGeoTIFF() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../CakraPencil/timo.tif")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("timo.tif tidak ada") }
        let info = try GeoTIFFGeoref.read(data)
        XCTAssertEqual(info.width, 8192)
        XCTAssertEqual(info.height, 5574)
        XCTAssertEqual(info.crs, .utm(epsg: 32748))
        XCTAssertEqual(info.originX, 702_395.672409, accuracy: 1e-6)
        XCTAssertEqual(info.originY, 9_315_992.579392, accuracy: 1e-6)
        XCTAssertEqual(info.pixelSizeX, 0.23123, accuracy: 1e-5)

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
}
