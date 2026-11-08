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

/// Notes → map objects: the link survives saving, and older files without it still load.
final class FieldNoteObjectTests: XCTestCase {
    func testFeatureLinkCodableAndBackwardCompatible() throws {
        let fid = UUID()
        let note = FieldNote(position: Point2D(x: 1, y: 2), category: .boulder, isDone: true, featureID: fid)
        let back = try JSONDecoder().decode(FieldNote.self, from: JSONEncoder().encode(note))
        XCTAssertEqual(back.featureID, fid)

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(note)) as! [String: Any]
        json.removeValue(forKey: "featureID")
        let old = try JSONDecoder().decode(FieldNote.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.featureID, "Notes saved before 1d load without a link")
    }

    func testEveryCategorySuggestsSymbols() {
        for c in FieldNote.Category.allCases { XCTAssertFalse(c.suggestedSymbolCodes.isEmpty, c.rawValue) }
        XCTAssertEqual(FieldNote.Category.boulder.suggestedSymbolCodes.first, "204")
    }
}

/// Stage 2: offset, pacing, vegetation, coverage, track → line.
final class FieldToolsTests: XCTestCase {
    let zone = UTMZone(number: 48, isNorth: false)!
    let origin = Point2D(x: 700_000, y: 9_300_000)

    func testOffsetBearingAndDistance() {
        let east = FieldOffset(from: origin, bearingDeg: 90, distanceM: 100).target(zone: zone)
        XCTAssertEqual(east.distance(to: origin), 100, accuracy: 0.01, "Exact distance on the grid")
        XCTAssertGreaterThan(east.x - origin.x, 99.9)
        // 500 km from the central meridian (105° E) the grid convergence shows: true north is not grid north.
        let north = FieldOffset(from: origin, bearingDeg: 0, distanceM: 100).target(zone: zone)
        XCTAssertEqual(north.y - origin.y, 100, accuracy: 0.1)
        XCTAssertGreaterThan(abs(north.x - origin.x), 0.05, "Convergence applied")
        XCTAssertLessThan(abs(north.x - origin.x), 3)
        XCTAssertEqual(FieldOffset(from: origin, bearingDeg: 225, distanceM: 0).target(zone: zone), origin)
    }

    func testPaceCalibration() {
        XCTAssertEqual(PaceCount.paceLength(knownDistanceM: 100, paces: 64) ?? 0, 1.5625, accuracy: 1e-9)
        XCTAssertNil(PaceCount.paceLength(knownDistanceM: 100, paces: 5), "20 m per pace is not plausible")
        XCTAssertNil(PaceCount.paceLength(knownDistanceM: 100, paces: 0))
    }

    func testVegetationNoteTitleAndCompatibility() throws {
        let n = FieldNote(position: origin, category: .vegetation, vegetation: .walk)
        XCTAssertEqual(n.title, "408 Walk")
        let back = try JSONDecoder().decode(FieldNote.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back.vegetation, .walk)
        XCTAssertEqual(VegetationClass.allCases.map(\.code), (401...410).map(String.init))
        let old = try JSONDecoder().decode(FieldData.self, from: Data(#"{"tracks":[],"notes":[],"showTracks":true,"showNotes":true}"#.utf8))
        XCTAssertEqual(old.coverageRadius, 25)
        XCTAssertNil(old.showCoverage)
    }

    func testCoverage() {
        let area = Rect2D(minX: 0, minY: 0, maxX: 1000, maxY: 1000)
        // A straight 1000 m walk through the middle, 25 m each side → 5 % of 1 km².
        let t = FieldTrack(name: "t", points: [.init(position: Point2D(x: 0, y: 500)), .init(position: Point2D(x: 1000, y: 500))])
        XCTAssertEqual(FieldCoverage.fraction(of: area, tracks: [t], radiusM: 25), 0.05, accuracy: 0.006)
        XCTAssertEqual(FieldCoverage.fraction(of: area, tracks: [], radiusM: 25), 0)
        XCTAssertEqual(FieldCoverage.fraction(of: area, tracks: [t], radiusM: 2000), 1)
    }

    func testTrackLineParts() {
        let t = FieldTrack(name: "t", points: [
            .init(position: Point2D(x: 0, y: 0)), .init(position: Point2D(x: 100, y: 0)),
            .init(position: Point2D(x: 100.2, y: 50)), .init(position: Point2D(x: 100, y: 100)),
            .init(position: Point2D(x: 500, y: 100), startsSegment: true), .init(position: Point2D(x: 600, y: 100)),
        ])
        XCTAssertEqual(t.lengthM, 300, accuracy: 0.01)
        let all = t.lineParts()
        XCTAssertEqual(all.count, 2, "Split at the pause gap")
        XCTAssertEqual(all[0].count, 4)
        XCTAssertEqual(t.lineParts(toleranceM: 1)[0].count, 3, "Nearly straight point simplified away")
        // First half: 0…150 m along the recorded length → ends 50 m up the second leg.
        let half = t.lineParts(from: 0, to: 0.5)
        XCTAssertEqual(half.count, 1)
        XCTAssertEqual(half[0].last!.y, 50, accuracy: 0.5)
        let tail = t.lineParts(from: 0.9, to: 1)
        XCTAssertEqual(tail.count, 1)
        XCTAssertEqual(tail[0].first!.x, 570, accuracy: 0.01)
        XCTAssertTrue(t.lineParts(from: 0.6, to: 0.4).isEmpty)
    }
}

/// `.occafield`: iPad → Mac field data without the drawing; merge without duplicates.
final class FieldPackageTests: XCTestCase {
    let zone = UTMZone(number: 48, isNorth: false)!
    let day1 = Date(timeIntervalSince1970: 1_794_000_000)
    lazy var day5 = day1.addingTimeInterval(4 * 86_400)

    func sample() -> FieldData {
        FieldData(tracks: [
            FieldTrack(name: "Track 1", points: [.init(position: Point2D(x: 700_000, y: 9_300_000), time: day1),
                                                 .init(position: Point2D(x: 700_100, y: 9_300_000), time: day1.addingTimeInterval(60))]),
            FieldTrack(name: "Track 2", points: [.init(position: Point2D(x: 701_000, y: 9_300_000), time: day5),
                                                 .init(position: Point2D(x: 701_100, y: 9_300_000), time: day5.addingTimeInterval(60))]),
        ], notes: [
            FieldNote(position: Point2D(x: 700_050, y: 9_300_010), createdAt: day1, category: .boulder, photos: ["a.jpg"]),
            FieldNote(position: Point2D(x: 701_050, y: 9_300_010), createdAt: day5, category: .cliff, text: "Cliff 3 m", photos: ["b.jpg"]),
        ])
    }

    func testRoundTripAndSince() throws {
        let field = sample()
        let pid = UUID()
        let all = try FieldPackage.make(field: field, since: nil, projectID: pid, projectName: "Forest", zone: zone) { Data($0.utf8) }
        let back = try FieldPackage.decode(all.encoded())
        XCTAssertEqual(back.field, field)
        XCTAssertEqual(back.manifest.projectID, pid)
        XCTAssertEqual(back.manifest.zone, zone)
        XCTAssertEqual(back.photos["a.jpg"], Data("a.jpg".utf8))
        XCTAssertEqual(back.photos.count, 2)

        let new = try FieldPackage.make(field: field, since: day5, projectID: pid, projectName: "Forest", zone: zone) { Data($0.utf8) }
        XCTAssertEqual(new.field.tracks.map(\.name), ["Track 2"], "Only day 5")
        XCTAssertEqual(new.field.notes.count, 1)
        XCTAssertEqual(Array(new.photos.keys), ["b.jpg"])

        XCTAssertThrowsError(try FieldPackage.make(field: FieldData(), since: nil, projectID: pid, projectName: "x", zone: zone) { _ in nil })
        XCTAssertThrowsError(try FieldPackage.decode(Data("CPENCIL1xxxx".utf8))) { XCTAssertEqual($0 as? FieldPackage.PackageError, .notFieldData) }
    }

    func testMergeKeepsDeskWorkAndSkipsDuplicates() {
        let ipad = sample()
        // The Mac has day 1: note 1 processed (done, linked to an object), track renamed.
        var mac = FieldData(tracks: [ipad.tracks[0]], notes: [ipad.notes[0]])
        mac.tracks[0].name = "North edge"
        mac.notes[0].isDone = true
        let fid = UUID()
        mac.notes[0].featureID = fid

        let r = mac.merge(ipad, existingPhotos: ["a.jpg"])
        XCTAssertEqual(r.newTracks, 1)
        XCTAssertEqual(r.newNotes, 1)
        XCTAssertEqual(r.alreadyThere, 2)
        XCTAssertEqual(r.newPhotos, ["b.jpg"])
        XCTAssertEqual(mac.tracks.map(\.name), ["North edge", "Track 2"], "Desk rename kept")
        XCTAssertTrue(mac.notes[0].isDone, "Done state kept")
        XCTAssertEqual(mac.notes[0].featureID, fid, "Object link kept")
        XCTAssertEqual(r.summary, "1 new track, 1 new note · 2 already in the project")

        // Importing the same file again adds nothing.
        let again = mac.merge(ipad, existingPhotos: ["a.jpg", "b.jpg"])
        XCTAssertFalse(again.addedAnything)
        XCTAssertEqual(mac.tracks.count, 2)
        XCTAssertEqual(mac.notes.count, 2)
    }

    func testMergeExtendsTrackAndRenamesClash() {
        var ipad = sample()
        var mac = FieldData(tracks: [ipad.tracks[0]])
        ipad.tracks[0].points.append(.init(position: Point2D(x: 700_200, y: 9_300_000), time: day1.addingTimeInterval(120)))
        // A track from another iPad, also called "Track 1".
        ipad.tracks.append(FieldTrack(name: "Track 1", points: ipad.tracks[1].points))
        let r = mac.merge(ipad)
        XCTAssertEqual(r.extendedTracks, 1)
        XCTAssertEqual(mac.tracks[0].points.count, 3, "Recording continued after the last export")
        XCTAssertEqual(mac.tracks.map(\.name), ["Track 1", "Track 2", "Track 1 (2)"])
    }

    func testReprojectToAnotherZone() {
        let other = UTMZone(number: 49, isNorth: false)!
        let f = sample()
        let moved = f.reprojected(from: zone, to: other)
        let a = zone.unproject(f.notes[0].position), b = other.unproject(moved.notes[0].position)
        XCTAssertEqual(a.lat, b.lat, accuracy: 1e-7)
        XCTAssertEqual(a.lon, b.lon, accuracy: 1e-7)
        XCTAssertNotEqual(moved.notes[0].position.x, f.notes[0].position.x, accuracy: 1)
    }
}

/// Photo markups (Apple Pencil drawings) travel with the photos.
final class FieldPhotoMarkupTests: XCTestCase {
    func testMarkupFilesTravelInFieldData() throws {
        let zone = UTMZone(number: 48, isNorth: false)!
        var note = FieldNote(position: Point2D(x: 700_000, y: 9_300_000), category: .boulder, photos: ["a.jpg", "b.jpg"])
        note.markedPhotos = ["a.jpg"]
        XCTAssertEqual(note.markupFiles, ["a.jpg.drawing"])
        let field = FieldData(notes: [note])
        XCTAssertEqual(field.photoFiles, ["a.jpg", "b.jpg"], "Photo count unchanged")
        XCTAssertEqual(field.attachmentFiles, ["a.jpg", "b.jpg", "a.jpg.drawing"])

        let pkg = try FieldPackage.make(field: field, since: nil, projectID: UUID(), projectName: "x", zone: zone) { Data($0.utf8) }
        let back = try FieldPackage.decode(pkg.encoded())
        XCTAssertEqual(back.photos["a.jpg.drawing"], Data("a.jpg.drawing".utf8))
        XCTAssertEqual(back.field.notes[0].markedPhotos, ["a.jpg"])

        // The Mac has the note without markup: import adds the markup file and the flag.
        var mac = FieldData(notes: [FieldNote(id: note.id, position: note.position, category: .boulder, photos: ["a.jpg", "b.jpg"])])
        let r = mac.merge(back.field, existingPhotos: ["a.jpg", "b.jpg"])
        XCTAssertEqual(r.newPhotos, ["a.jpg.drawing"])
        XCTAssertTrue(mac.notes[0].hasMarkup("a.jpg"))
    }
}
