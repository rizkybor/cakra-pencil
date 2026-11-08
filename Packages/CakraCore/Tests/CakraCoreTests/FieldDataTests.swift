@testable import CakraCore
import XCTest

/// Fieldwork data: storage in the project package / .occa, GPX export and import, track statistics.
final class FieldDataTests: XCTestCase {
    let zone = UTMZone(number: 48, isNorth: false)!

    private func sample() -> FieldData {
        let t0 = Date(timeIntervalSince1970: 1_794_000_000)
        let track = FieldTrack(name: "Track 1", points: [
            .init(position: Point2D(x: 700_000, y: 9_300_000), time: t0, accuracyM: 4, elevationM: 50),
            .init(position: Point2D(x: 700_030, y: 9_300_040), time: t0.addingTimeInterval(30), accuracyM: 5, elevationM: 52),
            .init(position: Point2D(x: 700_060, y: 9_300_080), time: t0.addingTimeInterval(60), accuracyM: 6, elevationM: 55),
        ])
        let note = FieldNote(position: Point2D(x: 700_010, y: 9_300_020), createdAt: t0, category: .boulder,
                             text: "Boulder 1.5 m <north side>", photos: ["abc.jpg"], accuracyM: 4)
        let averaged = FieldNote(position: Point2D(x: 700_050, y: 9_300_050), createdAt: t0, category: .control,
                                 averaging: .init(samples: 25, accuracyM: 1.8, durationS: 25))
        return FieldData(tracks: [track], notes: [note, averaged])
    }

    func testTrackStatistics() {
        let t = sample().tracks[0]
        XCTAssertEqual(t.lengthM, 100, accuracy: 0.001, "Two 50 m legs")
        XCTAssertEqual(t.duration ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(t.typicalAccuracyM, 5)
        var f = sample()
        XCTAssertEqual(f.nextTrackName(), "Track 2")
        f.tracks.append(FieldTrack(name: "Track 7"))
        XCTAssertEqual(f.nextTrackName(), "Track 8")
        XCTAssertEqual(f.notes[1].title, "Averaged position")
        XCTAssertEqual(f.notes[0].title, "Boulder 1.5 m <north side>")
    }

    func testStoredInPackageAndArchive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("field-\(UUID().uuidString).cakra")
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = sample()
        try CakraPackage.write(ProjectDocument(project: Project(name: "Field"), field: data), to: dir)
        let photos = dir.appendingPathComponent(CakraPackage.fieldPhotosFolder)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF]).write(to: photos.appendingPathComponent("abc.jpg"))

        let back = try CakraPackage.read(at: dir)
        XCTAssertEqual(back.field, data, "field.json round trip")

        // .occa carries field.json and the photos.
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("field-out-\(UUID().uuidString).cakra")
        defer { try? FileManager.default.removeItem(at: out) }
        try ProjectArchive.unpack(ProjectArchive.pack(packageAt: dir), into: out)
        XCTAssertEqual(try CakraPackage.read(at: out).field, data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("field-photos/abc.jpg").path))

        // Empty field data: no field.json.
        try CakraPackage.write(ProjectDocument(project: Project(name: "Field")), to: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("field.json").path))
        XCTAssertTrue(try CakraPackage.read(at: dir).field.isEmpty)
    }

    func testGPXRoundTrip() throws {
        let data = sample()
        let gpx = GPX.export(data, zone: zone, name: "Survey & test")
        XCTAssertTrue(gpx.contains("<trk>") && gpx.contains("<wpt "))
        XCTAssertTrue(gpx.contains("Survey &amp; test") && gpx.contains("&lt;north side&gt;"), "XML escaped")
        let back = try GPX.read(Data(gpx.utf8), zone: zone)
        XCTAssertEqual(back.tracks.count, 1)
        XCTAssertEqual(back.notes.count, 2)
        for (a, b) in zip(data.tracks[0].points, back.tracks[0].points) {
            XCTAssertLessThan(a.position.distance(to: b.position), 0.1, "Track point within 10 cm")
            XCTAssertEqual(a.time, b.time)
            XCTAssertEqual(a.elevationM ?? 0, b.elevationM ?? 0, accuracy: 0.05)
        }
        XCTAssertEqual(back.tracks[0].name, "Track 1")
        XCTAssertEqual(back.tracks[0].source, "gpx")
        XCTAssertEqual(back.notes[0].category, .boulder, "Category kept via <type>")
        XCTAssertLessThan(back.notes[0].position.distance(to: data.notes[0].position), 0.1)
    }

    func testGPXFromAGPSWatch() throws {
        // Typical watch export: fractional seconds, no waypoints, a route.
        let gpx = """
        <?xml version="1.0"?><gpx version="1.1" creator="Watch" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>Morning run</name><trkseg>
        <trkpt lat="-6.2900000" lon="106.6300000"><ele>40.2</ele><time>2026-11-08T06:00:00.250Z</time></trkpt>
        <trkpt lat="-6.2901000" lon="106.6301000"><time>2026-11-08T06:00:05.250Z</time></trkpt>
        <trkpt lat="999" lon="106.6"></trkpt>
        </trkseg></trk>
        <rte><rtept lat="-6.29" lon="106.63"/><rtept lat="-6.291" lon="106.631"/></rte>
        </gpx>
        """
        let r = try GPX.read(Data(gpx.utf8), zone: zone, existingTracks: 1)
        XCTAssertEqual(r.tracks.count, 2, "Track and route")
        XCTAssertEqual(r.tracks[0].points.count, 2, "Invalid point skipped")
        XCTAssertNotNil(r.tracks[0].points[0].time, "Fractional seconds")
        XCTAssertEqual(r.tracks[0].name, "Morning run")
        XCTAssertEqual(r.tracks[0].colorHex, FieldTrack.palette[1], "Color after the existing track")
        XCTAssertThrowsError(try GPX.read(Data("<kml/>".utf8), zone: zone))
        XCTAssertThrowsError(try GPX.read(Data("<gpx version=\"1.1\"></gpx>".utf8), zone: zone))
    }
}

/// Position averaging while standing still.
final class PositionAveragerTests: XCTestCase {
    func testAveragesFixesWeightedByAccuracy() throws {
        var a = PositionAverager()
        let t0 = Date(timeIntervalSince1970: 0)
        // Scatter of ±4 m around (100, 200); one accurate fix pulls towards its position.
        let offsets: [(Double, Double)] = [(4, 0), (-4, 0), (0, 4), (0, -4), (3, 3), (-3, -3), (3, -3), (-3, 3)]
        for (i, o) in offsets.enumerated() {
            a.add(.init(position: Point2D(x: 100 + o.0, y: 200 + o.1), accuracyM: 8, time: t0.addingTimeInterval(Double(i))))
        }
        let r = try XCTUnwrap(a.result)
        XCTAssertLessThan(r.position.distance(to: Point2D(x: 100, y: 200)), 0.01, "Symmetric scatter averages to the centre")
        XCTAssertEqual(r.samples, 8)
        XCTAssertEqual(r.durationS, 7, accuracy: 0.001)
        XCTAssertLessThan(r.accuracyM, 8, "Averaged accuracy better than one fix")
        XCTAssertGreaterThanOrEqual(r.accuracyM, 1, "Never better than 1 m")
    }

    func testIgnoresBadFixesAndOutliers() throws {
        var a = PositionAverager()
        XCTAssertFalse(a.add(.init(position: Point2D(x: 0, y: 0), accuracyM: 65)), "Too inaccurate")
        XCTAssertFalse(a.add(.init(position: Point2D(x: 0, y: 0), accuracyM: -1)), "Invalid")
        XCTAssertNil(a.result)
        for i in 0..<10 { a.add(.init(position: Point2D(x: 50 + Double(i % 2), y: 50), accuracyM: 5)) }
        a.add(.init(position: Point2D(x: 120, y: 50), accuracyM: 5))      // multipath jump 70 m away
        let r = try XCTUnwrap(a.result)
        XCTAssertEqual(r.samples, 10, "Jump dropped")
        XCTAssertEqual(r.position.x, 50.5, accuracy: 0.01)
        a.reset()
        XCTAssertNil(a.result)
    }
}

/// Pause / resume: a track with segments (the gap is not walked on record).
final class FieldTrackSegmentTests: XCTestCase {
    func testPauseResumeSegments() throws {
        let t0 = Date(timeIntervalSince1970: 1_794_000_000)
        let track = FieldTrack(name: "Track 1", points: [
            .init(position: Point2D(x: 700_000, y: 9_300_000), time: t0),
            .init(position: Point2D(x: 700_100, y: 9_300_000), time: t0.addingTimeInterval(100)),
            // Paused, walked 500 m away (not recorded), resumed 10 minutes later.
            .init(position: Point2D(x: 700_600, y: 9_300_000), time: t0.addingTimeInterval(700), startsSegment: true),
            .init(position: Point2D(x: 700_650, y: 9_300_000), time: t0.addingTimeInterval(750)),
        ])
        XCTAssertEqual(track.segments.count, 2)
        XCTAssertEqual(track.lengthM, 150, accuracy: 0.001, "100 m + 50 m; the 500 m gap is not counted")
        XCTAssertEqual(track.duration ?? 0, 150, accuracy: 0.001, "100 s + 50 s; the pause is not counted")

        // GPX: two <trkseg> in one <trk>, and back.
        let zone = UTMZone(number: 48, isNorth: false)!
        let gpx = GPX.export(FieldData(tracks: [track]), zone: zone, name: "x")
        XCTAssertEqual(gpx.components(separatedBy: "<trkseg>").count - 1, 2)
        let back = try GPX.read(Data(gpx.utf8), zone: zone)
        XCTAssertEqual(back.tracks.count, 1, "One track")
        XCTAssertEqual(back.tracks[0].segments.count, 2, "Two segments again")
        XCTAssertEqual(back.tracks[0].lengthM, 150, accuracy: 0.2)
        XCTAssertNil(back.tracks[0].points[0].startsSegment, "The first point needs no marker")
    }
}
