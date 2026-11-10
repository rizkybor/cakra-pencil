import PDFKit
import XCTest
@testable import CakraCore

/// IOF Control Descriptions 2024: catalog, migration of 2018 data, directional column G symbols, special rows,
/// thick lines, heading rules, and Codable compatibility.
final class ControlDescriptions2024Tests: XCTestCase {
    /// Start → 6 controls (100 m apart) → finish.
    private func course(_ configure: (inout Course) -> Void = { _ in }) -> (CourseSet, Course) {
        let s = ControlPoint(kind: .start, position: Point2D(x: 0, y: 0))
        let cs = (1...6).map { i in ControlPoint(kind: .control, code: 30 + i, position: Point2D(x: Double(i) * 100, y: 0)) }
        let f = ControlPoint(kind: .finish, position: Point2D(x: 600, y: 250))
        var c = Course(name: "A", controlIDs: [s.id] + cs.map(\.id) + [f.id], climbM: 213)
        configure(&c)
        return (CourseSet(eventTitle: "Event", controls: [s] + cs + [f], courses: [c]), c)
    }

    // MARK: Catalog

    func testCatalogNames2024() {
        XCTAssertEqual(IOFSymbols.name("2.1"), "Cliff, crag")
        XCTAssertEqual(IOFSymbols.name("4.9"), "Prominent tree")
        XCTAssertEqual(IOFSymbols.name("5.8"), "Wall")
        XCTAssertEqual(IOFSymbols.name("5.21"), "Canopy")
        XCTAssertEqual(IOFSymbols.name("5.23"), "Out of bounds area")
        XCTAssertEqual(IOFSymbols.name("5.24"), "Railway")
        XCTAssertEqual(IOFSymbols.name("8.11"), "ruined")
        XCTAssertEqual(IOFSymbols.symbol("11.1")?.column, .f, "Bend belongs to column F")
        XCTAssertEqual(IOFSymbols.name("13.3"), "manned control")
        XCTAssertEqual(IOFSymbols.name("12.4NE"), "north east corner (inside)")
        XCTAssertEqual(IOFSymbols.name("12.6SW"), "south west tip")
        XCTAssertEqual(IOFSymbols.name("12.12NE"), "north east foot")
        XCTAssertEqual(IOFSymbols.name("12.11"), "foot")
        // Picker: no legacy symbols, column G once per base symbol, bend in F.
        XCTAssertFalse(IOFSymbols.pickerSymbols(in: .d).contains { $0.isLegacy })
        XCTAssertEqual(IOFSymbols.pickerSymbols(in: .g).map(\.id), (1...14).map { "12.\($0)" })
        XCTAssertTrue(IOFSymbols.pickerSymbols(in: .f).contains { $0.id == "11.1" })
        XCTAssertFalse(IOFSymbols.pickerSymbols(in: .h).contains { $0.id == IOFSymbols.Legacy.radio })
        // Every stored id (incl. all directions and legacy ids) draws a pictogram.
        XCTAssertEqual(IOFSymbols.all.filter { IOFPictogram.shapes($0.id) == nil }.map(\.id), [])
    }

    func testDirectionalLocationIDs() {
        XCTAssertTrue(IOFSymbols.splitDirection("12.4NE") == ("12.4", "NE"))
        XCTAssertTrue(IOFSymbols.splitDirection("12.12SW") == ("12.12", "SW"))
        XCTAssertTrue(IOFSymbols.splitDirection("12.1N") == ("12.1", "N"))
        XCTAssertTrue(IOFSymbols.splitDirection("12.10") == ("12.10", nil))
        XCTAssertTrue(IOFSymbols.splitDirection("x.bend") == ("x.bend", nil))
        for base in IOFSymbols.directionalLocations {
            for dir in IOFSymbols.directions { XCTAssertNotNil(IOFSymbols.symbol(base + dir), base + dir) }
        }
        XCTAssertNil(IOFSymbols.symbol("12.8N"), "Upper part has no direction")
        // Rotation: the corner (inside) dot points the way the corner points.
        func dot(_ id: String) -> Point2D? {
            IOFPictogram.shapes(id)?.compactMap { if case let .dots(p, _) = $0 { return p.first } else { return nil } }.first
        }
        let n = dot("12.4N")!, e = dot("12.4E")!, sw = dot("12.4SW")!
        XCTAssertGreaterThan(n.y, 0.5)
        XCTAssertGreaterThan(e.x, 0.5)
        XCTAssertEqual(e.y, 0.5, accuracy: 1e-9)
        XCTAssertLessThan(sw.x, 0.5)
        XCTAssertLessThan(sw.y, 0.5)
        XCTAssertEqual(IOFPictogram.shapes("12.4"), IOFPictogram.shapes("12.4N"), "Base id previews as north")
        XCTAssertEqual(ControlDescription(feature: "1.9", location: "12.12NE").text, "Hill, north east foot")
        XCTAssertEqual(ControlDescription(feature: "4.1", location: "12.4E").text, "Open land, east corner (inside)")
        XCTAssertEqual(ControlDescription(feature: "5.2", dimension: "11.1").text, "Track / path, bend")
        XCTAssertEqual(ControlDescription(feature: "2.1", dimension: "0.5/3").text, "Cliff, 0.5 m / 3 m")
        XCTAssertEqual(ControlDescription(feature: "1.5", dimension: "5x5").text, "Quarry, 5 m x 5 m")
        XCTAssertEqual(IOFPictogram.dimensionShapes("2/3")?.count, 3, "9.4 heights of two features: two numbers + diagonal")
    }

    // MARK: Migration

    private func migrated(_ d: ControlDescription) -> ControlDescription { d.migratedFrom2018() }

    func testMigrationColumnG() {
        let table: [String: String] = [
            "11.1N": "12.1N", "11.1NE": "12.1NE", "11.1SW": "12.1SW", "11.3": "12.8", "11.4": "12.9", "11.5": "12.10",
            "11.6": "12.13", "11.7": "12.11", "11.8": "12.4N", "11.9": "12.5N", "11.10": "12.6N", "11.12": "12.7N",
            "11.13": "12.3N", "11.15": "12.14", "11.2": IOFSymbols.Legacy.topEdge, "11.14": IOFSymbols.Legacy.beginning,
        ]
        for (old, new) in table {
            XCTAssertEqual(migrated(ControlDescription(feature: "2.4", location: old)).location, new, old)
        }
        // Bend: to column F when F is empty, otherwise kept as a legacy column G symbol.
        let bend = migrated(ControlDescription(feature: "5.2", location: "11.11"))
        XCTAssertEqual(bend.dimension, "11.1")
        XCTAssertNil(bend.location)
        let bendWithF = migrated(ControlDescription(feature: "5.2", dimension: "10.2", location: "11.11"))
        XCTAssertEqual(bendWithF.dimension, "10.2")
        XCTAssertEqual(bendWithF.location, IOFSymbols.Legacy.bend)
    }

    func testMigrationColumnsHAndD() {
        XCTAssertEqual(migrated(ControlDescription(other: "12.1")).other, "13.1")
        XCTAssertEqual(migrated(ControlDescription(other: "12.2")).other, "13.2")
        XCTAssertEqual(migrated(ControlDescription(other: "12.4")).other, "13.3")
        XCTAssertEqual(migrated(ControlDescription(other: "12.3")).other, IOFSymbols.Legacy.radio)
        XCTAssertEqual(migrated(ControlDescription(feature: "5.23")).feature, IOFSymbols.Legacy.barrier)
        XCTAssertEqual(migrated(ControlDescription(feature: "5.24")).feature, IOFSymbols.Legacy.rubbishBin)
        XCTAssertEqual(migrated(ControlDescription(feature: "5.21")).feature, "5.21", "Building pass through = canopy")
        // Per field: old H 12.x and new G 12.x never collide.
        let both = migrated(ControlDescription(feature: "2.4", location: "11.13", other: "12.1"))
        XCTAssertEqual(both.location, "12.3N")
        XCTAssertEqual(both.other, "13.1")
        XCTAssertEqual(migrated(ControlDescription(which: "0.1NE", feature: "2.4", appearance: "8.1", dimension: "1.5")),
                       ControlDescription(which: "0.1NE", feature: "2.4", appearance: "8.1", dimension: "1.5"), "Unchanged columns")
        // Legacy ids keep a name and pictogram, hidden from the picker.
        XCTAssertEqual(ControlDescription(feature: IOFSymbols.Legacy.barrier, other: IOFSymbols.Legacy.radio).text, "Barrier, radio / TV control")
    }

    func testMigrationRunsOnlyOnOldData() throws {
        var (set, _) = course()
        let i = 1
        set.controls[i].description = ControlDescription(feature: "5.24", location: "11.8", other: "12.4")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(set)) as! [String: Any]
        XCTAssertEqual(json["descriptionFormat"] as? Int, 2024)
        // New data: 5.24 is the 2024 railway, nothing changes.
        let same = try JSONDecoder().decode(CourseSet.self, from: JSONEncoder().encode(set))
        XCTAssertEqual(same.controls[i].description, set.controls[i].description)
        XCTAssertEqual(same, set)
        // Saved before the update (no format field): converted once.
        json.removeValue(forKey: "descriptionFormat")
        let old = try JSONDecoder().decode(CourseSet.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.controls[i].description, ControlDescription(feature: IOFSymbols.Legacy.rubbishBin, location: "12.4N", other: "13.3"))
        XCTAssertEqual(old.descriptionFormat, 2024)
        let again = try JSONDecoder().decode(CourseSet.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(again.controls[i].description, old.controls[i].description, "Round trip does not migrate twice")
    }

    // MARK: Sheet rows

    func testSpecialRowsAndThickLines() {
        let (set, c) = course { c in
            c.classes = " M45 M50 W21 "
            c.startDistanceM = 150
            c.finishRoute = .taped
            c.specialInstructions = [SpecialInstruction(kind: .tapedAway, afterControl: 2, lengthM: 60),
                                     SpecialInstruction(kind: .mapFlip, afterControl: 4),
                                     SpecialInstruction(kind: .crossingPoint, afterControl: 99, lengthM: 40)]
        }
        let d = DescriptionSheet(set, course: c)
        XCTAssertEqual(d.classes, "M45 M50 W21")
        XCTAssertEqual(d.headingRowCount, 2)
        XCTAssertEqual(d.climbText, "215 m", "Climb rounded to 5 m")
        let kinds = d.rows.map { r -> String in
            switch r.special {
            case .startDistance?: return "14.1"
            case let .instruction(k, _)?: return k.rawValue
            case nil: return r.kind == .control ? r.number : r.kind.rawValue
            }
        }
        XCTAssertEqual(kinds, ["14.1", "start", "1", "2", "15.1", "3", "4", "15.6", "5", "6", "15.3", "finish"])
        XCTAssertEqual(d.rows[0].text, "Distance to start triangle: 150 m")
        XCTAssertEqual(d.rows[4].text, "Follow taped route 60 m away from control")
        XCTAssertEqual(d.rows[10].text, "Mandatory crossing point", "No length for 15.3")
        XCTAssertEqual(d.rows.last?.finishRoute, .taped)
        XCTAssertEqual(d.rows.last?.text, "250 m from last control to finish, follow taped route")
        // Thick: both sides of each special instruction and after every 3rd control.
        let thick = d.rows.indices.filter { d.rows[$0].thickBelow }
        XCTAssertEqual(thick, [3, 4, 5, 6, 7, 9, 10])
        XCTAssertNil(d.rows[0].controlIndex)
        XCTAssertEqual(d.rows[2].controlIndex, 1, "Control rows map to the course list")
        XCTAssertEqual(d.rows.filter { $0.isFullWidth(symbols: true) }.count, 5)
        XCTAssertEqual(d.rows.filter { $0.isFullWidth(symbols: false) }.count, 4, "Text mode: finish keeps columns A/B")
        // Continuation columns keep rows and thick lines.
        let cols = d.columns(maxRows: 5)
        XCTAssertEqual(cols.flatMap(\.rows), d.rows)
        XCTAssertEqual(cols[1].rows.first?.thickBelow, true)
        XCTAssertEqual(GeoPDFExporter.descriptionTableHeight(d, cell: 10), Double(d.rows.count + 2 + 1) * 10)
        // Every full-width row has a drawing; text rows have none.
        for r in d.rows where r.isFullWidth(symbols: true) { XCTAssertNotNil(IOFPictogram.rowShapes(r), r.text) }
        XCTAssertNil(IOFPictogram.rowShapes(d.rows[2]))
    }

    func testFinishVariantsAndDefaults() {
        for (route, text) in [(FinishRoute.taped, "250 m from last control to finish, follow taped route"),
                              (.funnel, "250 m from last control to finish, navigate to finish funnel, then follow tapes"),
                              (.navigate, "Navigate 250 m to finish")] {
            let (set, c) = course { $0.finishRoute = route }
            XCTAssertEqual(DescriptionSheet(set, course: c).rows.last?.text, text)
        }
        let (set, c) = course()
        XCTAssertEqual(c.effectiveFinishRoute, .navigate, "Default 16.3")
        let d = DescriptionSheet(set, course: c)
        XCTAssertEqual(d.rows.indices.filter { d.rows[$0].thickBelow }, [3, 6])
        XCTAssertEqual(DescriptionSheet.climbText(212), "210 m")
        XCTAssertEqual(DescriptionSheet.climbText(2), "0 m")
        XCTAssertEqual(DescriptionSheet.climbText(nil), "")
    }

    func testPDFPrintsSpecialRows() {
        let (set, c) = course { c in
            c.classes = "M45 W21"
            c.startDistanceM = 150
            c.finishRoute = .funnel
            c.specialInstructions = [SpecialInstruction(kind: .tapedBetween, afterControl: 1, lengthM: 300)]
        }
        let d = DescriptionSheet(set, course: c)
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        func pdf(_ symbols: Bool) -> String {
            var layout = CoursePrintLayout()
            layout.descriptionSymbols = symbols
            layout.separateDescriptionPage = true
            let data = GeoPDFExporter.document(GeoPDFRequest(title: "Event", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                             strokes: [], features: [], descriptions: d, printLayout: layout))
            XCTAssertNotNil(PDFDocument(data: data))
            return String(decoding: data, as: UTF8.self)
        }
        let symbols = pdf(true)
        XCTAssertTrue(symbols.contains("(M45 W21) Tj"), "Classes line")
        XCTAssertTrue(symbols.contains("(150 m) Tj"), "14.1 distance")
        XCTAssertTrue(symbols.contains("(300 m) Tj"), "15.2 length")
        XCTAssertTrue(symbols.contains("(250 m) Tj"), "16.2 finish distance")
        XCTAssertTrue(symbols.contains("IOF control descriptions 2024"))
        let text = pdf(false)
        XCTAssertTrue(text.contains("(Distance to start triangle: 150 m) Tj"))
        XCTAssertTrue(text.contains("(Follow taped route 300 m between controls) Tj"))
    }

    // MARK: Layout + Codable

    func testCellSizeClamp() throws {
        XCTAssertEqual(CoursePrintLayout.cellRangeMM, 5...7)
        var l = CoursePrintLayout()
        l.descriptionCellMM = 8
        let back = try JSONDecoder().decode(CoursePrintLayout.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.descriptionCellMM, 7, "Old 8 mm boxes clamp to 7 mm")
        l.descriptionCellMM = 6.5
        XCTAssertEqual(try JSONDecoder().decode(CoursePrintLayout.self, from: JSONEncoder().encode(l)).descriptionCellMM, 6.5)
    }

    func testCourseFieldsRoundTripAndOldJSON() throws {
        let (set, _) = course { c in
            c.classes = "M21"
            c.startDistanceM = 120
            c.finishRoute = .funnel
            c.specialInstructions = [SpecialInstruction(kind: .tapedToMapExchange, afterControl: 3, lengthM: 50),
                                     SpecialInstruction(kind: .outOfBoundsPassage, afterControl: 1)]
        }
        let back = try JSONDecoder().decode(CourseSet.self, from: JSONEncoder().encode(set))
        XCTAssertEqual(back, set)
        XCTAssertEqual(back.courses[0].specialInstructions?.map(\.kind), [.tapedToMapExchange, .outOfBoundsPassage])
        // A course saved by an older version (no new keys) still decodes.
        let old = #"{"id":"6F2C1F7E-8B0B-4C8B-9A47-3E1F0D2B9C11","name":"Old","kind":"normal","controlIDs":[],"competitors":0}"#
        let c = try JSONDecoder().decode(Course.self, from: Data(old.utf8))
        XCTAssertNil(c.classes)
        XCTAssertNil(c.startDistanceM)
        XCTAssertNil(c.specialInstructions)
        XCTAssertEqual(c.effectiveFinishRoute, .navigate)
    }

    /// Distance rows (14.1, 15.1/15.2/15.5, finish 16.1/16.2): the dashes stop the same distance from the label on
    /// both sides, for any label length.
    func testDistanceRowDashesAreSymmetricAroundTheLabel() {
        let rows: [DescriptionSheet.Row] = [50, 150, 1250].flatMap { m in
            [DescriptionSheet.Row.special(.startDistance(m)),
             .special(.instruction(.tapedAway, meters: m)),
             .special(.instruction(.tapedBetween, meters: m)),
             .special(.instruction(.tapedToMapExchange, meters: m))]
        }
        for row in rows {
            guard let shapes = IOFPictogram.rowShapes(row) else { return XCTFail("no shapes for \(row.text)") }
            let runs: [[Point2D]] = shapes.compactMap { if case let .dashed(pts, _, _) = $0 { return pts } else { return nil } }
            XCTAssertEqual(runs.count, 2, row.text)
            guard runs.count == 2 else { continue }
            // Inner ends (next to the label centred at x = 4).
            let inner = runs.map { $0.max { abs($0.x - 4) > abs($1.x - 4) }! }
            XCTAssertEqual(abs(inner[0].x - 4), abs(inner[1].x - 4), accuracy: 1e-9, row.text)
            // Each run is filled exactly with whole dashes: the dash pattern fits the run length.
            for case let .dashed(pts, dash, gap) in shapes {
                let length = abs(pts[1].x - pts[0].x)
                let n = ((length + gap) / (dash + gap)).rounded()
                XCTAssertEqual(n * dash + (n - 1) * gap, length, accuracy: 1e-9, row.text)
            }
        }
    }
}
