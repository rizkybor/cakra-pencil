@testable import CakraCore
import XCTest

/// Sketch notes (a drawing on the map with a note) and per-item visibility of tracks and notes.
final class FieldSketchTests: XCTestCase {
    let zone = UTMZone(number: 48, isNorth: false)!
    let t0 = Date(timeIntervalSince1970: 1_794_000_000)

    /// A loop around a thicket and an open line along a path.
    private var loop: [[Point2D]] {
        [[Point2D(x: 700_000, y: 9_300_000), Point2D(x: 700_040, y: 9_300_000), Point2D(x: 700_040, y: 9_300_030),
          Point2D(x: 700_000, y: 9_300_030), Point2D(x: 700_001, y: 9_300_001)]]
    }

    private var line: [[Point2D]] {
        [[Point2D(x: 700_100, y: 9_300_000), Point2D(x: 700_150, y: 9_300_010)],
         [Point2D(x: 700_150, y: 9_300_010), Point2D(x: 700_200, y: 9_300_000)]]
    }

    private func sketchNote(_ strokes: [[Point2D]], category: FieldNote.Category = .vegetation) -> FieldNote {
        FieldNote(position: FieldNote.sketchAnchor(strokes)!, createdAt: t0, category: category, text: "Thicket", sketch: strokes)
    }

    // MARK: Coding

    func testSketchCodableAndBackwardCompatible() throws {
        let n = sketchNote(loop)
        let back = try JSONDecoder().decode(FieldNote.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back, n)
        XCTAssertEqual(back.sketch, loop)
        XCTAssertTrue(back.hasSketch)

        // Notes without a sketch or a hidden state are written exactly as before: no new keys.
        let plain = FieldNote(position: Point2D(x: 1, y: 2), category: .boulder)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as! [String: Any]
        for key in ["sketch", "sketchEditedAt", "isVisible"] { XCTAssertNil(json[key], key) }

        // A note from an older file (no sketch, no visibility) loads visible without a sketch.
        let old = try JSONDecoder().decode(FieldNote.self, from: Data(#"""
        {"id":"8C1B7F0E-3C55-4B8B-9E39-6D1E2C9A1F00","position":{"x":700000,"y":9300000},"createdAt":0,
         "category":"boulder","text":"","photos":[],"isDone":false}
        """#.utf8))
        XCTAssertNil(old.sketch)
        XCTAssertFalse(old.hasSketch)
        XCTAssertTrue(old.isShown)
    }

    func testFieldJSONRoundTripInPackage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sketch-\(UUID().uuidString).cakra")
        defer { try? FileManager.default.removeItem(at: dir) }
        var hidden = sketchNote(line, category: .path)
        hidden.isShown = false
        let data = FieldData(notes: [sketchNote(loop), hidden])
        try CakraPackage.write(ProjectDocument(project: Project(name: "Sketch"), field: data), to: dir)
        let back = try CakraPackage.read(at: dir).field
        XCTAssertEqual(back, data)
        XCTAssertFalse(back.notes[1].isShown)
        XCTAssertEqual(back.visibleNotes.map(\.id), [data.notes[0].id])
    }

    // MARK: Geometry

    func testAnchorClosedAndBounds() {
        let n = sketchNote(loop)
        // The anchor is a drawn point (on the loop), the one nearest the middle of the bounds.
        XCTAssertTrue(loop[0].contains(n.position))
        XCTAssertTrue(n.sketchIsClosed, "Ends meet: a loop")
        XCTAssertFalse(sketchNote(line, category: .path).sketchIsClosed, "Two strokes: not one closed shape")
        XCTAssertEqual(n.sketchBounds, Rect2D(minX: 700_000, minY: 9_300_000, maxX: 700_040, maxY: 9_300_030))
        XCTAssertEqual(sketchNote(line).sketchLengthM, 2 * hypot(50, 10), accuracy: 0.001)
        XCTAssertNil(FieldNote.sketchAnchor([]))

        // Field bounds include the sketch, not just the pin.
        let f = FieldData(notes: [n])
        XCTAssertEqual(f.bounds, n.sketchBounds)
    }

    func testSketchSuggestions() {
        for c in FieldNote.Category.allCases {
            XCTAssertFalse(c.suggestedLineCodes.isEmpty, c.rawValue)
            XCTAssertFalse(c.suggestedAreaCodes.isEmpty, c.rawValue)
        }
        XCTAssertEqual(FieldNote.Category.vegetation.suggestedSketchCodes(closed: true).first, "406", "Loop: area first")
        XCTAssertEqual(FieldNote.Category.path.suggestedSketchCodes(closed: false).first, "506", "Open stroke: line first")
    }

    // MARK: .occafield

    func testSketchTravelsInFieldPackage() throws {
        let field = FieldData(notes: [sketchNote(loop)])
        let pkg = try FieldPackage.make(field: field, since: nil, projectID: UUID(), projectName: "x", zone: zone) { _ in nil }
        let back = try FieldPackage.decode(pkg.encoded())
        XCTAssertEqual(back.field.notes[0].sketch, loop)
        XCTAssertEqual(back.field, field)
    }

    func testSinceIncludesRedrawnSketch() throws {
        var n = sketchNote(loop)
        n.sketchEditedAt = t0.addingTimeInterval(86_400 * 3)
        let old = FieldNote(position: Point2D(x: 1, y: 1), createdAt: t0)
        let field = FieldData(notes: [n, old])
        let pkg = try FieldPackage.make(field: field, since: t0.addingTimeInterval(86_400), projectID: UUID(), projectName: "x",
                                        zone: zone) { _ in nil }
        XCTAssertEqual(pkg.field.notes.map(\.id), [n.id], "Redrawn after the last export: sent again")
    }

    func testMergeSketchNotes() {
        let ipad = FieldData(notes: [sketchNote(loop), sketchNote(line, category: .path)])

        // New sketch notes are added once.
        var mac = FieldData()
        var r = mac.merge(ipad)
        XCTAssertEqual(r.newNotes, 2)
        XCTAssertEqual(mac.notes[0].sketch, loop)
        r = mac.merge(ipad)
        XCTAssertFalse(r.addedAnything, "No duplicates")
        XCTAssertEqual(mac.notes.count, 2)

        // Redrawn on the iPad later: the sketch (and its anchor) is updated, desk work kept.
        mac.notes[0].isDone = true
        mac.notes[0].text = "Thicket, edited at the desk"
        mac.notes[0].isShown = false
        var redrawn = ipad
        let newLoop = loop.map { $0.map { Point2D(x: $0.x + 5, y: $0.y) } }
        redrawn.notes[0].sketch = newLoop
        redrawn.notes[0].position = FieldNote.sketchAnchor(newLoop)!
        redrawn.notes[0].sketchEditedAt = t0.addingTimeInterval(3600)
        r = mac.merge(redrawn)
        XCTAssertEqual(r.updatedSketches, 1)
        XCTAssertEqual(r.alreadyThere, 1)
        XCTAssertTrue(r.addedAnything)
        XCTAssertEqual(r.summary, "1 updated sketch · 1 already in the project")
        XCTAssertEqual(mac.notes[0].sketch, newLoop)
        XCTAssertEqual(mac.notes[0].position, redrawn.notes[0].position)
        XCTAssertTrue(mac.notes[0].isDone)
        XCTAssertEqual(mac.notes[0].text, "Thicket, edited at the desk")
        XCTAssertFalse(mac.notes[0].isShown, "Local visibility kept")

        // An older sketch doesn't overwrite a newer local one.
        r = mac.merge(ipad)
        XCTAssertEqual(r.updatedSketches, 0)
        XCTAssertEqual(mac.notes[0].sketch, newLoop)

        // A note that gained a sketch on the other device gets it.
        let plainID = UUID()
        var local = FieldData(notes: [FieldNote(id: plainID, position: Point2D(x: 700_000, y: 9_300_000), createdAt: t0)])
        let other = FieldData(notes: [FieldNote(id: plainID, position: FieldNote.sketchAnchor(line)!, createdAt: t0, sketch: line)])
        XCTAssertEqual(local.merge(other).updatedSketches, 1)
        XCTAssertEqual(local.notes[0].sketch, line)
    }

    func testReprojectSketch() {
        let other = UTMZone(number: 49, isNorth: false)!
        let f = FieldData(notes: [sketchNote(loop)])
        let moved = f.reprojected(from: zone, to: other)
        for (a, b) in zip(f.notes[0].sketchPoints, moved.notes[0].sketchPoints) {
            let la = zone.unproject(a), lb = other.unproject(b)
            XCTAssertEqual(la.lat, lb.lat, accuracy: 1e-7)
            XCTAssertEqual(la.lon, lb.lon, accuracy: 1e-7)
        }
        XCTAssertNotEqual(moved.notes[0].sketchPoints[0].x, loop[0][0].x, accuracy: 1)
    }

    // MARK: Visibility

    func testLegacyShowAllSwitchesBecomePerItem() throws {
        let note = FieldNote(position: Point2D(x: 1, y: 2), createdAt: t0)
        let track = FieldTrack(name: "Track 1", points: [.init(position: Point2D(x: 0, y: 0)), .init(position: Point2D(x: 10, y: 0))])
        var legacy = FieldData(tracks: [track], notes: [note])
        legacy.showTracks = false
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(FieldData.self, from: enc.encode(legacy))
        XCTAssertTrue(back.showTracks, "The switch is folded into the tracks")
        XCTAssertFalse(back.tracks[0].isVisible)
        XCTAssertTrue(back.notes[0].isShown, "Notes were shown")
        XCTAssertTrue(back.visibleTracks.isEmpty)

        // Minimal old file: both switches on, nothing hidden.
        let old = try JSONDecoder().decode(FieldData.self, from: Data(#"{"tracks":[],"notes":[],"showTracks":true,"showNotes":false}"#.utf8))
        XCTAssertTrue(old.showNotes)
    }

    func testMergeKeepsLocalVisibilityAndShowsNewItems() {
        let a = FieldTrack(name: "Track 1", points: [.init(position: Point2D(x: 0, y: 0)), .init(position: Point2D(x: 10, y: 0))])
        var hiddenOnIPad = FieldTrack(name: "Track 2", points: a.points)
        hiddenOnIPad.isVisible = false
        var hiddenNote = FieldNote(position: Point2D(x: 1, y: 1), createdAt: t0)
        hiddenNote.isShown = false
        var mac = FieldData(tracks: [a])
        mac.tracks[0].isVisible = false
        var ipad = FieldData(tracks: [a, hiddenOnIPad], notes: [hiddenNote])
        ipad.tracks[0].isVisible = true
        mac.merge(ipad)
        XCTAssertFalse(mac.tracks[0].isVisible, "Hidden at the desk: stays hidden")
        XCTAssertTrue(mac.tracks[1].isVisible, "New tracks arrive visible")
        XCTAssertTrue(mac.notes[0].isShown, "New notes arrive visible")
    }
}
