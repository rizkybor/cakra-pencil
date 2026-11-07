import CakraCore
import XCTest

final class ImagerySnapshotTests: XCTestCase {
    private let frame = [LatLon(lat: -6.890, lon: 107.610), LatLon(lat: -6.890, lon: 107.618),
                         LatLon(lat: -6.901, lon: 107.618), LatLon(lat: -6.901, lon: 107.610)]

    private func snapshot(pad: Double) -> ImagerySnapshot {
        ImagerySnapshot(mapType: "satellite", fileName: ImagerySnapshot.imagePath(for: "satellite"),
                        north: -6.890 + pad, south: -6.901 - pad, west: 107.610 - pad, east: 107.618 + pad,
                        width: 2900, height: 4000)
    }

    func testFitsOnlyWhenCoveringFrameWithEnoughDetail() {
        XCTAssertTrue(snapshot(pad: 0.0003).fits(frame))
        XCTAssertFalse(snapshot(pad: -0.0003).fits(frame), "Frame sticks out of the image")
        XCTAssertFalse(snapshot(pad: 0.01).fits(frame), "Image far larger than the frame: capture again for detail")
        XCTAssertFalse(snapshot(pad: 0.0003).fits([]))
    }

    func testPixelSizeTargetsResolutionAndCapsLongSide() {
        let a4 = ImagerySnapshot.pixelSize(widthM: 900, heightM: 1260)
        XCTAssertEqual(a4.height, 4096)
        XCTAssertEqual(Double(a4.width) / Double(a4.height), 900.0 / 1260.0, accuracy: 0.001)
        let small = ImagerySnapshot.pixelSize(widthM: 250, heightM: 500)
        XCTAssertEqual(small.width, 1000)
        XCTAssertEqual(small.height, 2000)
    }

    func testMetersPerPixel() {
        let s = snapshot(pad: 0)
        XCTAssertEqual(s.metersPerPixel, 0.008 * 111_320 * cos(-6.8955 * .pi / 180) / 2900, accuracy: 1e-6)
    }

    func testArchiveLeavesOutCapturedImagery() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(ImagerySnapshot.folder), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("project.json"))
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent(ImagerySnapshot.imagePath(for: "satellite")))
        let entries = try ProjectArchive.entries(of: ProjectArchive.pack(packageAt: dir))
        XCTAssertEqual(Set(entries.keys), ["project.json"])
    }
}

final class DMSFormatTests: XCTestCase {
    func testDegreesMinutesSecondsWithHemisphere() {
        XCTAssertEqual(Fmt.dms(LatLon(lat: -6.327046, lon: 106.430935)), "6°19'37.37\"S  106°25'51.37\"E")
        XCTAssertEqual(Fmt.dms(LatLon(lat: 51.5, lon: -0.1275)), "51°30'00.00\"N  0°07'39.00\"W")
        // 59.996″ rounds up into the next minute.
        XCTAssertEqual(Fmt.dms(LatLon(lat: 1 + 59.0 / 60 + 59.996 / 3600, lon: 0)), "2°00'00.00\"N  0°00'00.00\"E")
    }
}
