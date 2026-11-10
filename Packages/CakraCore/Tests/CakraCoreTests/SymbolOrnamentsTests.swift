@testable import CakraCore
import CoreGraphics
import ImageIO
import XCTest

/// ISOM/ISSprOM area patterns and line decorations: geometry, and drawn by the raster export with OCCA's own symbols.
final class SymbolOrnamentsTests: XCTestCase {
    let marsh = AreaPattern(kind: .lines, colorHex: "#00A0E0", sizeMM: 0.1, spacingMM: 0.3, angleDeg: 90)

    func testMarshLinesAreHorizontalAndSpaced() throws {
        let marks = try XCTUnwrap(SymbolOrnaments.patternMarks(marsh, in: Rect2D(minX: 0, minY: 0, maxX: 10, maxY: 10), unitsPerMM: 1, yUp: true))
        XCTAssertEqual(marks.count, 35, accuracy: 2)
        for case let .line(a, b, w, _) in marks {
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9, "East–west lines")
            XCTAssertEqual(w, 0.1)
        }
        // Vertical lines for 407 (0° = north–south).
        let v = AreaPattern(kind: .lines, colorHex: "#00FF00", sizeMM: 0.12, spacingMM: 0.84)
        for case let .line(a, b, _, _) in try XCTUnwrap(SymbolOrnaments.patternMarks(v, in: Rect2D(minX: 0, minY: 0, maxX: 5, maxY: 5), unitsPerMM: 1, yUp: false)) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
        }
    }

    func testPatternIsAnchoredSoNeighboursLineUp() throws {
        let dots = AreaPattern(kind: .dots, colorHex: "#000000", sizeMM: 0.2, spacingMM: 0.8, angleDeg: 45)
        func centres(_ r: Rect2D) throws -> Set<String> {
            Set(try XCTUnwrap(SymbolOrnaments.patternMarks(dots, in: r, unitsPerMM: 1, yUp: true)).compactMap {
                if case let .dot(p, _, _) = $0, p.x >= 4.5, p.x <= 5.5, p.y >= 1, p.y <= 3 { return String(format: "%.4f,%.4f", p.x, p.y) }
                return nil
            })
        }
        XCTAssertEqual(try centres(Rect2D(minX: 0, minY: 0, maxX: 5.5, maxY: 4)), try centres(Rect2D(minX: 4.5, minY: 0, maxX: 10, maxY: 4)))
    }

    func testTooDenseBecomesTint() {
        XCTAssertNil(SymbolOrnaments.patternMarks(marsh, in: Rect2D(minX: 0, minY: 0, maxX: 1e6, maxY: 1e6), unitsPerMM: 1, yUp: true))
        XCTAssertEqual(SymbolOrnaments.tint(marsh), 1.0 / 3, accuracy: 1e-9)
        XCTAssertTrue(SymbolOrnaments.isPatternOnly(fillHex: "#ffffff", patterns: [marsh]))
        XCTAssertFalse(SymbolOrnaments.isPatternOnly(fillHex: "#FFBA35", patterns: [marsh]))
        XCTAssertFalse(SymbolOrnaments.isPatternOnly(fillHex: "#FFFFFF", patterns: nil), "405 forest stays a white fill")
    }

    func testCliffTagsOnTheRightAndEvenlySpaced() {
        let cliff = LineDecoration(kind: .tags, sizeMM: 0.5, widthMM: 0.12, spacingMM: 0.5)
        // Drawn west → east in a north-up space: right = south.
        let marks = SymbolOrnaments.decorationMarks(cliff, along: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)], unitsPerMM: 1,
                                                    lineWidthMM: 0.35, colorHex: "#000000", yUp: true)
        XCTAssertEqual(marks.count, 20)
        for case let .line(a, b, _, _) in marks {
            XCTAssertEqual(a.y, -0.175, accuracy: 1e-9, "Starts at the line edge")
            XCTAssertEqual(b.y, -0.675, accuracy: 1e-9, "Points to the right side")
        }
        // Screen space (y down): right of west → east is +y.
        let screen = SymbolOrnaments.decorationMarks(cliff, along: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)], unitsPerMM: 1,
                                                     lineWidthMM: 0.35, colorHex: "#000000", yUp: false)
        if case let .line(_, b, _, _) = screen[0] { XCTAssertGreaterThan(b.y, 0) }
    }

    func testWallDotsBridgeTicksAndBars() {
        let line = [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0), Point2D(x: 10, y: 10)]
        let wall = SymbolOrnaments.decorationMarks(LineDecoration(kind: .dots, sizeMM: 0.4, spacingMM: 2), along: line, unitsPerMM: 1,
                                                   lineWidthMM: 0.14, colorHex: "#000000", yUp: true)
        XCTAssertEqual(wall.count, 10)
        let bridge = SymbolOrnaments.decorationMarks(LineDecoration(kind: .ticks, sizeMM: 0.4, widthMM: 0.18, spacingMM: 0, angleDeg: 60),
                                                     along: line, unitsPerMM: 1, lineWidthMM: 0.18, colorHex: "#000000", yUp: true)
        XCTAssertEqual(bridge.count, 4, "Two ticks at each end")
        let pylons = SymbolOrnaments.decorationMarks(LineDecoration(kind: .bars, sizeMM: 0.3, widthMM: 0.14, spacingMM: 0),
                                                     along: line, unitsPerMM: 1, lineWidthMM: 0.14, colorHex: "#000000", yUp: true)
        XCTAssertEqual(pylons.count, 3, "A bar at every vertex")
    }

    /// The raster export draws marsh lines, scattered-tree holes, and fence tags with OCCA's ISOM set.
    func testRasterExportDrawsPatternsAndDecorations() throws {
        let file = OccaStandardSymbols.isomFile()
        let lookup: (String, String?) -> MapSymbol? = { code, _ in file.symbols.first { $0.code == code } }
        func feature(_ code: String, _ kind: FeatureKind, _ pts: [(Double, Double)]) throws -> Feature {
            let s = try XCTUnwrap(lookup(code, nil), code)
            return Feature(kind: kind, colorHex: s.colorHex, widthMM: s.drawingWidthMM, nodes: pts.map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) },
                           symbolCode: s.code, symbolName: s.name)
        }
        // 1:15000 at 600 dpi: 0.635 m per pixel, 600 px = 381 m.
        let dpi = 600, px = 15000 * 0.0254 / Double(dpi), size = 600
        let frame = MapFrame(origin: Point2D(x: 0, y: 0), widthM: Double(size) * px, heightM: Double(size) * px)
        let features = try [
            feature("308.0", .area, [(20, 200), (180, 200), (180, 360), (20, 360)]),
            feature("402.0", .area, [(200, 200), (360, 200), (360, 360), (200, 360)]),
            feature("516.0", .line, [(20, 100), (360, 100)]),
        ].withColorPriorities(lookup)
        XCTAssertNotNil(features[0].patterns)
        XCTAssertNotNil(features[2].decoration)

        let ctx = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        RasterExporter.drawFeatures(features, in: ctx, frame: frame, pixelSize: px, height: size, dpi: dpi)
        let img = try XCTUnwrap(ctx.makeImage())
        if let out = ProcessInfo.processInfo.environment["OCCA_ORNAMENT_PNG"],
           let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        // Count colours in a block of each area (row 0 = top of the image = north).
        func colours(x0: Double, y0: Double, x1: Double, y1: Double) -> (blue: Int, white: Int, yellow: Int) {
            var b = 0, w = 0, y = 0
            for yy in Int((frame.heightM - y1) / px)..<Int((frame.heightM - y0) / px) {
                for xx in Int(x0 / px)..<Int(x1 / px) {
                    let i = (yy * size + xx) * 4, r = Int(data[i]), g = Int(data[i + 1]), bl = Int(data[i + 2])
                    if bl > 180 && r < 120 { b += 1 } else if r > 240 && g > 240 && bl > 240 { w += 1 } else if r > 200 && g > 150 && bl < 120 { y += 1 }
                }
            }
            return (b, w, y)
        }
        let m = colours(x0: 60, y0: 240, x1: 140, y1: 320)
        XCTAssertGreaterThan(m.blue, 500, "Marsh lines drawn")
        XCTAssertGreaterThan(m.white, 500, "…with white between them (no solid fill)")
        let t = colours(x0: 240, y0: 240, x1: 320, y1: 320)
        XCTAssertGreaterThan(t.yellow, 2000, "402 yellow")
        XCTAssertGreaterThan(t.white, 300, "402 white holes")
        // Fence tags: black pixels south of the line (right of west → east).
        var tagPixels = 0
        let row = Int((frame.heightM - 100) / px)
        for yy in (row + 3)...(row + 9) { for xx in 100..<500 where data[(yy * size + xx) * 4] < 60 { tagPixels += 1 } }
        XCTAssertGreaterThan(tagPixels, 20, "Fence tags drawn")
    }

    /// .omap export writes the patterns as OOM hatch / dot patterns; reading the file back gives the same patterns.
    func testOmapExportRoundTripsPatterns() throws {
        let file = OccaStandardSymbols.isomFile()
        let lookup: (String, String?) -> MapSymbol? = { code, _ in file.symbols.first { $0.code == code } }
        let sheet = SheetSpec(scaleDenominator: 15000)
        let zone = UTMZone(epsg: 32748)!
        let frame = MapFrame(origin: Point2D(x: 700_000, y: 9_300_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        func area(_ code: String, _ x: Double) throws -> Feature {
            let s = try XCTUnwrap(lookup(code, nil))
            return Feature(kind: .area, colorHex: s.colorHex, widthMM: 0.1,
                           nodes: [(x, 9_300_100), (x + 100, 9_300_100), (x + 100, 9_300_200)].map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) },
                           symbolCode: s.code, symbolName: s.name)
        }
        let features = try [area("308.0", 700_100), area("402.0", 700_300), area("208.0", 700_500)].withColorPriorities(lookup)
        let xml = OmapWriter.document(VectorExportRequest(baseName: "p", frame: frame, sheet: sheet, zone: zone, strokes: [], features: features))
        XCTAssertTrue(xml.contains("<pattern type=\"1\""), "Marsh hatch written")
        let back = try OmapSymbolSet.read(Data(xml.utf8), name: "p", sourceFile: "p.omap")
        func pattern(_ code: String) throws -> AreaPattern { try XCTUnwrap(back.symbols.first { $0.code == code }?.patterns?.first, code) }
        let marsh = try pattern("308.0")
        XCTAssertEqual(marsh.kind, .lines)
        XCTAssertEqual(marsh.angleDeg, 90, accuracy: 0.01)
        XCTAssertEqual(marsh.spacingMM, 0.3, accuracy: 0.001)
        XCTAssertEqual(back.symbols.first { $0.code == "308.0" }?.colorHex, "#FFFFFF", "Still pattern-only")
        let trees = try pattern("402.0")
        XCTAssertEqual(trees.kind, .holes)
        XCTAssertEqual(trees.sizeMM, 0.4, accuracy: 0.001)
        XCTAssertEqual(try pattern("208.0").kind, .triangles)
    }

    /// OCAD (.ocd) area hatch and dot structures are read: the bundled BOF ISSprOM 2019-2 set.
    func testOcadHatchAndStructures() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../CakraPencil/Resources/SymbolSets/BOF O_Map 4000 O12 v1_ISSprOM2019-2.ocd")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("Bundled ISSprOM set not found") }
        let set = try OcadReader.read(data).symbolSet(name: "BOF", sourceFile: "x.ocd")
        func sym(_ code: String) throws -> MapSymbol { try XCTUnwrap(set.symbols.first { $0.code == code }, code) }
        let marsh = try sym("308.0")
        XCTAssertEqual(marsh.colorHex, "#FFFFFF", "Pattern only (fill off)")
        let ml = try XCTUnwrap(marsh.patterns?.first)
        XCTAssertEqual(ml.kind, .lines)
        XCTAssertEqual(ml.sizeMM, 0.12, accuracy: 1e-9); XCTAssertEqual(ml.spacingMM, 0.38, accuracy: 1e-9)
        XCTAssertEqual(ml.angleDeg, 90, accuracy: 1e-9, "ISSprOM 308: east–west lines 0.12 @ 0.38")
        XCTAssertEqual(try sym("407.0").patterns?.first?.angleDeg ?? -1, 0, accuracy: 1e-9, "North–south lines")
        XCTAssertEqual(try sym("709.0").patterns?.count, 2, "Out-of-bounds: cross hatching")
        let trees = try XCTUnwrap(sym("402.0").patterns?.first)
        XCTAssertEqual(trees.kind, .holes)
        XCTAssertEqual(trees.sizeMM, 0.6, accuracy: 1e-9); XCTAssertEqual(trees.spacingMM, 0.75, accuracy: 1e-9)
        XCTAssertNotEqual(try sym("402.0").colorHex, "#FFFFFF", "402 keeps its yellow")
        let cult = try XCTUnwrap(sym("412.0").patterns?.first)
        XCTAssertEqual(cult.kind, .dots); XCTAssertEqual(cult.sizeMM, 0.2, accuracy: 1e-9)
        XCTAssertNil(try sym("401.0").patterns, "Plain fill")
    }
}

/// IOF course symbols as course objects (702, 707–715) and the leg gap (705).
final class CourseIOFSymbolTests: XCTestCase {
    let sheet = SheetSpec(scaleDenominator: 15000)

    func testPointSymbolsUseOCCAShapes() throws {
        let aid = CourseItem(kind: .firstAid, points: [Point2D(x: 0, y: 0)])
        let marks = aid.marks(sheet: sheet)
        // 712: a cross of two 4.0 × 1.33 mm bars with flat ends (= 60 m × 19.95 m at 1:15000), lower purple.
        let bars = marks.compactMap { if case let .fill(p, _) = $0 { return p } else { return nil } }
        XCTAssertEqual(bars.count, 2)
        for bar in bars {
            let b = try XCTUnwrap(Rect2D(points: bar))
            XCTAssertEqual(max(b.maxX - b.minX, b.maxY - b.minY), 60, accuracy: 0.01)
            XCTAssertEqual(min(b.maxX - b.minX, b.maxY - b.minY), 19.95, accuracy: 0.01, "Thick arms")
        }
        XCTAssertTrue(marks.contains(.level(.lower)), "712 is lower purple")
        XCTAssertEqual(marks.suffix(2), [.width(nil), .level(nil)], "Width and level reset afterwards")
        XCTAssertEqual(aid.kind.placement, .tap)
        XCTAssertLessThan(aid.hitDistance(to: Point2D(x: 10, y: 0), sheet: sheet), 0.001, "Tap on the symbol selects it")
    }

    func testMarkedRouteIsDashed() {
        let route = CourseItem(kind: .markedRoute, points: [Point2D(x: 0, y: 0), Point2D(x: 375, y: 0)])  // 25 mm at 1:15000
        let dashes = route.marks(sheet: sheet).compactMap { if case let .polyline(p, _) = $0 { return p } else { return nil } }
        XCTAssertEqual(dashes.count, 10, "2.0 mm dash + 0.5 mm gap over 25 mm")
        XCTAssertEqual(dashes[0][1].x, 30, accuracy: 1e-6)
        XCTAssertEqual(dashes[1][0].x, 37.5, accuracy: 1e-6)
    }

    func testOutOfBoundsAreaHatchedInside() {
        let area = CourseItem(kind: .outOfBoundsArea, points: [Point2D(x: 0, y: 0), Point2D(x: 300, y: 200)])
        let marks = area.marks(sheet: sheet)
        let segs = marks.compactMap { if case let .polyline(p, false) = $0 { return p } else { return nil } }
        XCTAssertGreaterThan(segs.count, 10, "Hatch lines")
        for s in segs { for p in s { XCTAssertTrue(p.x >= -1e-6 && p.x <= 300 + 1e-6 && p.y >= -1e-6 && p.y <= 200 + 1e-6, "Clipped to the area") } }
        XCTAssertTrue(marks.contains { if case .polyline(_, true) = $0 { return true } else { return false } }, "Boundary line")
        XCTAssertEqual(area.hitDistance(to: Point2D(x: 150, y: 100), sheet: sheet), 0, "Inside selects")
    }

    func testOutOfBoundsRouteIsCrosses() {
        let route = CourseItem(kind: .outOfBoundsRoute, points: [Point2D(x: 0, y: 0), Point2D(x: 300, y: 0)])  // 20 mm
        let lines = route.marks(sheet: sheet).compactMap { if case let .polyline(p, _) = $0 { return p } else { return nil } }
        XCTAssertEqual(lines.count, 8, "4 crosses (every 5 mm) × 2 strokes")
    }

    func testSprintSizes() {
        let s4000 = SheetSpec(scaleDenominator: 4000)
        let boundary = CourseItem(kind: .outOfBoundsBoundary, points: [Point2D(x: 0, y: 0), Point2D(x: 100, y: 0)])
        XCTAssertTrue(boundary.marks(sheet: s4000).contains(.width(1.0 * 4)), "ISSprOM 708: 1.0 mm")
        XCTAssertTrue(boundary.marks(sheet: sheet).contains(.width(0.7 * 15)), "ISOM 708: 0.7 mm")
    }
}
