@testable import CakraCore
import CoreGraphics
import XCTest

/// The 2026-11 symbol review (ISOM 2017-2 / ISSprOM 2019-2 Rev 6 and IOF Printing and Colour Definitions Rev 4): new
/// pattern and decoration capabilities, 4-value dashes, colour levels, CMYK exports, course overprint levels, migration.
final class SymbolRev6Tests: XCTestCase {
    private func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }
    private let isom = OccaStandardSymbols.isomFile(), sprint = OccaStandardSymbols.issprFile()
    private func sym(_ f: OccaSymbolFile, _ code: String) throws -> MapSymbol { try XCTUnwrap(f.symbols.first { $0.code == code }, code) }
    private let line = [Point2D(x: 0, y: 0), Point2D(x: 20, y: 0)]

    // MARK: Area patterns

    func testDashedStaggeredLines() throws {
        let p = AreaPattern(kind: .lines, colorHex: "#00FFFF", sizeMM: 0.1, spacingMM: 1, angleDeg: 90, dashMM: [0.9, 0.25], staggered: true)
        let marks = try XCTUnwrap(SymbolOrnaments.patternMarks(p, in: Rect2D(minX: 0, minY: 0, maxX: 10, maxY: 3), unitsPerMM: 1, yUp: true))
        var rows: [Double: [Double]] = [:]
        for case let .line(a, b, _, _) in marks {
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
            XCTAssertEqual(abs(b.x - a.x), 0.9, accuracy: 1e-9, "Dash length")
            rows[(a.y * 1000).rounded() / 1000, default: []].append(min(a.x, b.x))
        }
        XCTAssertGreaterThan(rows.count, 2)
        // Neighbouring rows are offset by half the 1.15 period.
        let starts = rows.keys.sorted().prefix(2).map { rows[$0]!.map { ($0.truncatingRemainder(dividingBy: 1.15) + 1.15).truncatingRemainder(dividingBy: 1.15) } }
        XCTAssertEqual(abs((starts[0].first ?? 0) - (starts[1].first ?? 0)), 0.575, accuracy: 1e-6)
        XCTAssertEqual(SymbolOrnaments.tint(p), 0.1 * 0.9 / 1.15, accuracy: 1e-9, "Tint counts the gaps")
    }

    func testRandomTrianglesAreDeterministicPerObjectAndTileSafe() throws {
        let p = try XCTUnwrap(try sym(isom, "208.0").patterns?.first)
        XCTAssertEqual(p.random, true); XCTAssertEqual(p.sidesMM, [0.8, 0.6, 0.5])
        let r = Rect2D(minX: 0, minY: 0, maxX: 20, maxY: 20)
        let a = try XCTUnwrap(SymbolOrnaments.patternMarks(p, in: r, unitsPerMM: 1, yUp: true, seed: 7))
        XCTAssertEqual(a, try XCTUnwrap(SymbolOrnaments.patternMarks(p, in: r, unitsPerMM: 1, yUp: true, seed: 7)), "Same on every redraw")
        XCTAssertNotEqual(a, try XCTUnwrap(SymbolOrnaments.patternMarks(p, in: r, unitsPerMM: 1, yUp: true, seed: 8)), "Differs per object")
        // Density 0.8–1 per mm² (marks whose centroid lies inside).
        let inside = a.filter { m in
            guard case let .polygon(pts, _) = m else { return false }
            let cx = pts.map(\.x).reduce(0, +) / 3, cy = pts.map(\.y).reduce(0, +) / 3
            return cx >= 0 && cx < 20 && cy >= 0 && cy < 20
        }
        XCTAssertEqual(Double(inside.count) / 400, 0.9, accuracy: 0.1)
        // Scalene sides and random rotations.
        var angles = Set<Int>()
        for case let .polygon(pts, _) in a.prefix(30) {
            let sides = [pts[0].distance(to: pts[1]), pts[1].distance(to: pts[2]), pts[2].distance(to: pts[0])].sorted()
            XCTAssertEqual(sides[0], 0.5, accuracy: 1e-9); XCTAssertEqual(sides[1], 0.6, accuracy: 1e-9); XCTAssertEqual(sides[2], 0.8, accuracy: 1e-9)
            angles.insert(Int(atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x) * 180 / .pi / 30))
        }
        XCTAssertGreaterThan(angles.count, 4, "Rotations vary")
        // A tile (part of the area) gets exactly the marks of the whole area there.
        let tile = try XCTUnwrap(SymbolOrnaments.patternMarks(p, in: Rect2D(minX: 5, minY: 5, maxX: 9, maxY: 9), unitsPerMM: 1, yUp: true, seed: 7))
        XCTAssertFalse(tile.isEmpty)
        for m in tile { XCTAssertTrue(a.contains(m), "Tiles line up") }
    }

    func testJitteredDots() throws {
        let p = try XCTUnwrap(try sym(isom, "212.0").patterns?.first)
        XCTAssertNotNil(p.jitterMM)
        let marks = try XCTUnwrap(SymbolOrnaments.patternMarks(p, in: Rect2D(minX: 0, minY: 0, maxX: 5, maxY: 5), unitsPerMM: 1, yUp: true, seed: 1))
        let offGrid = marks.filter { m in
            guard case let .dot(c, _, _) = m else { return false }
            let fx = c.x / p.spacingMM - (c.x / p.spacingMM).rounded()
            return abs(fx) > 0.01
        }
        XCTAssertGreaterThan(offGrid.count, marks.count / 2, "Dots moved off the grid")
    }

    // MARK: Line decorations

    func testChevronsAndPairs() {
        let single = SymbolOrnaments.decorationMarks(LineDecoration(kind: .chevrons, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2, angleDeg: 45),
                                                     along: line, unitsPerMM: 1, lineWidthMM: 0.14, colorHex: "#000000", yUp: true)
        XCTAssertEqual(single.count, 20, "Two arms every 2 mm")
        for case let .line(a, b, _, _) in single {
            XCTAssertEqual(a.y, 0, accuracy: 1e-9, "Vertex on the centre line")
            XCTAssertEqual(a.distance(to: b), 0.4, accuracy: 1e-9, "Arm length from the centre line")
            XCTAssertEqual(abs(b.y), 0.4 * sin(.pi / 4), accuracy: 1e-9)
        }
        let pairs = SymbolOrnaments.decorationMarks(LineDecoration(kind: .chevrons, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2, angleDeg: 45, pairMM: 0.6),
                                                    along: line, unitsPerMM: 1, lineWidthMM: 0.25, colorHex: "#000000", yUp: true)
        XCTAssertEqual(pairs.count, 40)
        let dots = SymbolOrnaments.decorationMarks(LineDecoration(kind: .dots, sizeMM: 0.6, spacingMM: 3, pairMM: 0.8),
                                                   along: line, unitsPerMM: 1, lineWidthMM: 0.25, colorHex: "#000000", yUp: true)
        let xs = dots.compactMap { if case let .dot(p, _, _) = $0 { return p.x } else { return nil } }
        XCTAssertEqual(xs.count, 12, "515: pairs of dots")
        XCTAssertEqual(xs[1] - xs[0], 0.8, accuracy: 1e-9)
    }

    func testTrianglesEndTicksHalfDotsRungsEdgesTaper() throws {
        let tri = SymbolOrnaments.decorationMarks(LineDecoration(kind: .triangles, sizeMM: 0.7, spacingMM: 0.7, hidesLine: true),
                                                  along: line, unitsPerMM: 1, lineWidthMM: 0.7, colorHex: "#000000", yUp: true)
        XCTAssertEqual(tri.count, 28)
        for case let .polygon(pts, _) in tri { XCTAssertEqual(pts.map(\.y).min() ?? 0, -0.7 * 3.0.squareRoot() / 2, accuracy: 1e-9, "Peak on the right") }
        // ISOM 512: one-sided ticks at both ends, outward.
        let bridge = SymbolOrnaments.decorationMarks(LineDecoration(kind: .endTicks, sizeMM: 0.4, widthMM: 0.18, spacingMM: 0, angleDeg: 60),
                                                     along: line, unitsPerMM: 1, lineWidthMM: 0.18, colorHex: "#000000", yUp: true)
        XCTAssertEqual(bridge.count, 2)
        for case let .line(a, b, _, _) in bridge {
            XCTAssertLessThan(b.y, a.y, "Right side (south)")
            XCTAssertTrue(b.x < 0 || b.x > 20, "Pointing outward")
        }
        // Half dots with the flat side 0.07 from the centre line.
        let half = SymbolOrnaments.decorationMarks(LineDecoration(kind: .halfDots, sizeMM: 0.45, spacingMM: 1, offsetMM: 0.07),
                                                   along: line, unitsPerMM: 1, lineWidthMM: 0.18, colorHex: "#000000", yUp: true)
        if case let .polygon(pts, _) = half[0] {
            XCTAssertEqual(pts.map(\.y).max() ?? 0, -0.07, accuracy: 1e-9)
            XCTAssertEqual(pts.map(\.y).min() ?? 0, -0.07 - 0.225, accuracy: 1e-9)
        } else { XCTFail("half dot") }
        // 532: transparent double line with steps.
        let stair = try XCTUnwrap(try sym(isom, "532.0").decoration)
        let marks = SymbolOrnaments.decorationMarks(stair, along: line, unitsPerMM: 1, lineWidthMM: 0.6, colorHex: "#000000", yUp: true)
        let edges = marks.compactMap { if case let .polyline(p, w, _) = $0 { return (p, w) } else { return nil } }
        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(Set(edges.map { abs($0.0[0].y) }), [0.25], "Edges 0.5 apart")
        XCTAssertEqual(marks.filter { if case .line = $0 { return true } else { return false } }.count, 50, "Steps every 0.4")
        // Edges keep their distance around a corner (mitre).
        let corner = SymbolOrnaments.offset([P(0, 0), P(10, 0), P(10, 10)], by: 1, yUp: true)
        XCTAssertEqual(corner[1].x, 11, accuracy: 1e-9); XCTAssertEqual(corner[1].y, -1, accuracy: 1e-9)
        // 107: pointed ends, full width in the middle.
        let taper = SymbolOrnaments.decorationMarks(try XCTUnwrap(try sym(isom, "107.0").decoration), along: line, unitsPerMM: 1,
                                                    lineWidthMM: 0.25, colorHex: "#D15C00", yUp: true)
        guard case let .polygon(outline, _) = taper[0] else { return XCTFail("taper") }
        XCTAssertEqual(outline.map(\.y).max() ?? 0, 0.125, accuracy: 1e-9)
        XCTAssertTrue(outline.contains { abs($0.x) < 1e-9 && abs($0.y) < 1e-9 }, "Pointed start")
    }

    func testMarksCentredOnDashes() throws {
        let wall = try sym(isom, "514.0")
        let d = try XCTUnwrap(wall.decoration)
        let marks = SymbolOrnaments.decorationMarks(d, along: line, unitsPerMM: 1, lineWidthMM: 0.14, colorHex: "#000000", yUp: true,
                                                    dashMM: wall.lineStyle?.dashMM)
        let xs = marks.compactMap { if case let .dot(p, _, _) = $0 { return p.x } else { return nil } }
        XCTAssertEqual(xs.count, 10)
        XCTAssertEqual(xs[0], 0.825, accuracy: 1e-9, "Centre of the first 1.65 dash")
        XCTAssertEqual(xs[1] - xs[0], 2.0, accuracy: 1e-9)
    }

    // MARK: Dashes

    func testFourValueDashes() throws {
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.18, nodes: line.map { BezierNode(point: $0) }, symbolCode: "507.0")
        f.apply(try XCTUnwrap(try sym(isom, "507.0").lineStyle))
        XCTAssertEqual(f.effectiveDashMM, [1.0, 0.25, 1.0, 0.8])
        f.setWidth(0.36)
        XCTAssertEqual(f.effectiveDashMM?.reduce(0, +) ?? 0, 6.1, accuracy: 1e-9, "Scaled with the width")
        XCTAssertNil(Feature.validDash([1, 0.25, 1]), "Odd counts are not a dash pattern")
        // Course objects: pairs of dashes too.
        let pieces = CourseItem.dashes([P(0, 0), P(10, 0)], pattern: [1.0, 0.25, 1.0, 0.8])
        XCTAssertEqual(pieces.map { $0[0].x }.prefix(4).map { ($0 * 1000).rounded() / 1000 }, [0, 1.25, 3.05, 4.3])
    }

    // MARK: 709 clipping

    func testOutOfBoundsHatchClippedToThePolygon() {
        let tri = [P(0, 0), P(10, 0), P(0, 10)]
        let segs = CourseItem.clip(P(-5, 5), P(15, 5), toPolygon: tri)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].0.x, 0, accuracy: 1e-9); XCTAssertEqual(segs[0].1.x, 5, accuracy: 1e-9, "Ends at the hypotenuse, not the box")
        // Concave outline: two pieces.
        let u = [P(0, 0), P(10, 0), P(10, 10), P(7, 10), P(7, 3), P(3, 3), P(3, 10), P(0, 10)]
        XCTAssertEqual(CourseItem.clip(P(-1, 6), P(11, 6), toPolygon: u).count, 2)
        // The course object stays inside its rectangle and is cross-hatched.
        let sheet = SheetSpec(scaleDenominator: 15000)
        let area = CourseItem(kind: .outOfBoundsArea, points: [P(0, 0), P(300, 200)])
        let lines = area.marks(sheet: sheet).compactMap { if case let .polyline(p, closed) = $0, !closed { return p } else { return nil } }
        XCTAssertGreaterThan(lines.count, 20)
        for l in lines { for p in l { XCTAssertTrue(p.x > -1e-6 && p.x < 300 + 1e-6 && p.y > -1e-6 && p.y < 200 + 1e-6) } }
        XCTAssertTrue(area.marks(sheet: sheet).contains(.level(.upper)), "709 is upper purple")
    }

    func testIndoorCourseObjectsUseTheISInOMSize() throws {
        var sheet = SheetSpec(scaleDenominator: 700)
        sheet.standardOverride = .isinom
        XCTAssertEqual(CourseItem.courseMetersPerMM(sheet: sheet), 0.7, accuracy: 1e-9, "1:700 indoor = 100 %")
        XCTAssertEqual(CourseItem.iofSymbol(for: .markedRoute, sheet: sheet)?.lineStyle?.dashMM, [2.0, 0.75], "ISInOM 707")
        XCTAssertEqual(ContourSettings.defaults(sheet: sheet).contourWidthMM, 0.21, accuracy: 1e-9, "Contours not 5.7 × wider")
    }

    // MARK: Colour levels in drawing

    /// 417: the white mask is painted at "white over green and brown", so a contour crossing the tree stays visible.
    func testPointMaskDoesNotHideLines() throws {
        let lookup: (String, String?) -> MapSymbol? = { code, _ in self.isom.symbols.first { $0.code == code } }
        let tree = try sym(isom, "417.0"), contour = try sym(isom, "101.0")
        var c = Feature(kind: .line, colorHex: contour.colorHex, widthMM: 0.14, nodes: [P(-50, 0), P(50, 0)].map { BezierNode(point: $0) },
                        symbolCode: "101.0", symbolName: contour.name)
        c.apply(try XCTUnwrap(contour.lineStyle))
        let point = Feature.point(at: P(0, 0), elements: try XCTUnwrap(tree.pointElements), symbolCode: "417.0", symbolName: tree.name)
        let layered = [c, point].withColorPriorities(lookup)
        let paints = ColorHierarchy.paintOrder(layered)
        XCTAssertEqual(paints.count, 3, "Tree split into mask and ring")
        XCTAssertEqual(paints.map(\.index), [1, 0, 1], "Mask, contour, ring")
    }

    func testOverprintLevelsInPDFAndRaster() throws {
        let sheet = SheetSpec(marginMM: 5, scaleDenominator: 4000)
        let frame = MapFrame(origin: P(0, 0), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let c = P(frame.widthM / 2, frame.heightM / 2)
        let o = CourseOverprint(marks: [.circle(center: c, radiusM: 12), .level(.upper), .polyline([P(c.x - 30, c.y + 30), P(c.x + 30, c.y + 30)], closed: false)],
                                lineWidthM: 1.4, colorHex: "#A626FF")
        XCTAssertEqual(o.levels.lower.marks.count, 1); XCTAssertEqual(o.levels.upper.marks.count, 1)
        var black = Feature(kind: .line, colorHex: "#000000", widthMM: 0.4, nodes: [P(c.x - 30, c.y + 12), P(c.x + 30, c.y + 12)].map { BezierNode(point: $0) },
                            symbolCode: "515.0")
        black.colorPriority = OccaStandardSymbols.colorRow("black")
        var yellow = Feature(kind: .area, colorHex: "#FFBA36", widthMM: 0.1,
                             nodes: [P(c.x - 40, c.y - 40), P(c.x + 40, c.y - 40), P(c.x + 40, c.y + 40)].map { BezierNode(point: $0) }, symbolCode: "401.0")
        yellow.colorPriority = OccaStandardSymbols.colorRow("yellow100")
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "t", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                         strokes: [], features: [black, yellow], overprint: o)), as: UTF8.self)
        let yellowAt = try XCTUnwrap(pdf.range(of: "\(GeoPDFExporter.cmykString("#FFBA36")) k")).lowerBound
        let purple = pdf.ranges(of: "0.35 0.85 0 0 K").map(\.lowerBound)
        let blackAt = try XCTUnwrap(pdf.range(of: "0 0 0 1 K")).lowerBound
        XCTAssertEqual(purple.count, 2, "Lower and upper parts")
        XCTAssertLessThan(yellowAt, purple[0], "Lower purple above yellow")
        XCTAssertLessThan(purple[0], blackAt, "…and below black")
        XCTAssertLessThan(blackAt, purple[1], "Upper purple on top")
        XCTAssertFalse(pdf.contains("/BM /Multiply"))
    }

    // MARK: Exports

    func testPDFAndOmapUseSpecCMYK() throws {
        let brown = try sym(isom, "101.0")
        XCTAssertEqual(OccaStandardSymbols.cmyk(forHex: brown.colorHex), [0.25, 0.75, 1, 0])
        XCTAssertEqual(GeoPDFExporter.cmykString(try sym(isom, "501.0").colorHex), "0.1 0.35 0.5 0", "Brown 50 % paved: own CMYK")
        let sheet = SheetSpec(marginMM: 5, scaleDenominator: 15000)
        let zone = UTMZone(epsg: 32748)!
        let frame = MapFrame(origin: P(700_000, 9_300_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        var contour = Feature(kind: .line, colorHex: brown.colorHex, widthMM: 0.14,
                              nodes: [P(700_100, 9_300_100), P(700_500, 9_300_200)].map { BezierNode(point: $0) }, symbolCode: "101.0", symbolName: "Contour")
        contour.colorPriority = brown.colorPriority
        var path = Feature(kind: .line, colorHex: "#000000", widthMM: 0.18,
                           nodes: [P(700_100, 9_300_300), P(700_500, 9_300_300)].map { BezierNode(point: $0) }, symbolCode: "507.0", symbolName: "Less distinct small footpath")
        path.apply(try XCTUnwrap(try sym(isom, "507.0").lineStyle))
        let sketch = Stroke(colorHex: "#FF0000", widthMM: 0.3, points: [P(700_100, 9_300_400), P(700_300, 9_300_400)])
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "t", frame: frame, sheet: sheet, zone: zone,
                                                                         strokes: [sketch], features: [contour, path])), as: UTF8.self)
        XCTAssertTrue(pdf.contains("0.25 0.75 1 0 K"), "Contour in DeviceCMYK, Rev 4 brown")
        XCTAssertTrue(pdf.contains("1 0 0 RG"), "Sketch stays RGB")
        XCTAssertTrue(pdf.contains("[2.835 0.709 2.835 2.268] 0 d"), "507 pairs of dashes")
        let xml = OmapWriter.document(VectorExportRequest(baseName: "t", frame: frame, sheet: sheet, zone: zone, strokes: [], features: [contour, path]))
        XCTAssertTrue(xml.contains("c=\"0.250\" m=\"0.750\" y=\"1.000\" k=\"0.000\""), "OOM colour with the spec CMYK")
        XCTAssertTrue(xml.contains("dashed=\"true\" segment_length=\"4000\" end_length=\"0\""))
        XCTAssertTrue(xml.contains("dash_length=\"1000\" break_length=\"800\" dashes_in_group=\"2\" in_group_break_length=\"250\""), "507 as OOM dash groups")
    }

    // MARK: Migration

    func testOldOccaColoursAreRefreshed() throws {
        let lookup: (String, String?) -> MapSymbol? = { code, name in
            self.isom.symbols.first { $0.code == code && (name == nil || $0.name == name) } ?? self.isom.symbols.first { $0.code == code }
        }
        let oldBrown = OccaSymbolFile.Color(id: "", name: "", cmyk: [0, 0.56, 1, 0.18]).hex
        XCTAssertTrue(OccaStandardSymbols.legacyHexes.contains(oldBrown))
        let contour = Feature(kind: .line, colorHex: oldBrown, widthMM: 0.14, nodes: line.map { BezierNode(point: $0) },
                              symbolCode: "101.0", symbolName: "Contour")
        let custom = Feature(kind: .line, colorHex: "#123456", widthMM: 0.14, nodes: line.map { BezierNode(point: $0) },
                             symbolCode: "101.0", symbolName: "Contour")
        var cairn = Feature(kind: .point, colorHex: "#000000", widthMM: 0.8, nodes: [BezierNode(point: P(0, 0))],
                            symbolCode: "526.0", symbolName: "Cairn, memorial or boundary stone")
        cairn.name = "526.0 Cairn, memorial or boundary stone 3"
        cairn.pointElements = [PointElement(kind: .circle, colorHex: "#000000", priority: 1, lineWidthMM: 0.16, diameterMM: 0.64, points: [P(0, 0)])]
        var old507 = Feature(kind: .line, colorHex: "#000000", widthMM: 0.18, nodes: line.map { BezierNode(point: $0) },
                             symbolCode: "507.0", symbolName: "Less distinct small footpath")
        old507.dashMM = [1.0, 0.8]; old507.standardWidthMM = 0.18
        let out = try XCTUnwrap(OccaSymbolMigration.refreshed([contour, custom, cairn, old507], standard: .isom, lookup: lookup))
        XCTAssertEqual(out[0].colorHex, try sym(isom, "101.0").colorHex, "Old OCCA brown → Rev 4 brown")
        XCTAssertEqual(out[1].colorHex, "#123456", "Custom colour kept")
        XCTAssertEqual(out[2].symbolName, "Cairn"); XCTAssertEqual(out[2].name, "526.0 Cairn 3")
        XCTAssertEqual(out[2].pointElements, try sym(isom, "526.0").pointElements, "New shape (ring + centre dot)")
        XCTAssertEqual(out[3].dashMM, [1.0, 0.25, 1.0, 0.8])
        XCTAssertNil(OccaSymbolMigration.refreshed(out, standard: .isom, lookup: lookup), "Idempotent")
    }

    // MARK: Contours

    func testContourIntervalsPerStandard() {
        XCTAssertEqual(ContourSettings.intervalPresetsM(for: .isom), [5, 2.5])
        XCTAssertEqual(ContourSettings.intervalPresetsM(for: .issprom), [2, 2.5, 5])
        XCTAssertNil(ContourSettings.intervalHint(5, standard: .isom))
        XCTAssertNotNil(ContourSettings.intervalHint(2.5, standard: .isom), "Flat terrain only")
        XCTAssertNotNil(ContourSettings.intervalHint(5, standard: .issprom), "Steep areas only")
        XCTAssertNil(ContourSettings.intervalHint(2.5, standard: .issprom))
    }
}
