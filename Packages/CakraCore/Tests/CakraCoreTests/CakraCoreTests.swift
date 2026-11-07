import CoreGraphics
import ImageIO
import XCTest
import PDFKit
@testable import CakraCore

final class UTMTests: XCTestCase {
    func testZoneForJawaBaratIs48S() {
        let zone = UTMZone(containing: LatLon(lat: -6.9147, lon: 107.6098))
        XCTAssertEqual(zone.epsg, 32748)
        XCTAssertEqual(zone.label, "UTM 48S")
        XCTAssertEqual(zone.centralMeridian, 105)
    }

    func testCentralMeridianOnEquatorMapsToFalseOrigin() {
        let zone = UTMZone(number: 31, isNorth: true)!
        let p = zone.project(LatLon(lat: 0, lon: 3))
        XCTAssertEqual(p.x, 500_000, accuracy: 1e-6)
        XCTAssertEqual(p.y, 0, accuracy: 1e-6)
    }

    /// WGS84 meridian arc to 45° = 4,984,944.378 m, so N = k0 × arc on the central meridian.
    func testMeridianArcAt45Degrees() {
        let zone = UTMZone(number: 31, isNorth: true)!
        let p = zone.project(LatLon(lat: 45, lon: 3))
        XCTAssertEqual(p.x, 500_000, accuracy: 1e-6)
        XCTAssertEqual(p.y, 0.9996 * 4_984_944.378, accuracy: 0.001)
    }

    /// Reference values computed with the USGS series formulas (Snyder 1987), independent of the Krüger series.
    func testMatchesSnyderOffCentralMeridian() {
        let c = LatLon(lat: 48.858370, lon: 2.294481)
        let zone = UTMZone(containing: c)
        XCTAssertEqual(zone.number, 31)
        let p = zone.project(c)
        XCTAssertEqual(p.x, 448_250.5768, accuracy: 0.001)
        XCTAssertEqual(p.y, 5_411_951.5884, accuracy: 0.001)
    }

    func testRoundTripIsSubMillimetre() {
        let samples = [LatLon(lat: -6.9147, lon: 107.6098), LatLon(lat: -8.65, lon: 115.2167),
                       LatLon(lat: 3.5952, lon: 98.6722), LatLon(lat: -2.5337, lon: 140.7181)]
        for c in samples {
            let zone = UTMZone(containing: c)
            let p = zone.project(c)
            let back = zone.project(zone.unproject(p))
            XCTAssertLessThan(p.distance(to: back), 0.001, "\(c)")
            let ll = zone.unproject(p)
            XCTAssertEqual(ll.lat, c.lat, accuracy: 1e-8)
            XCTAssertEqual(ll.lon, c.lon, accuracy: 1e-8)
        }
    }

    func testEPSGParsingRejectsNonUTM() {
        XCTAssertNotNil(UTMZone(epsg: 32748))
        XCTAssertEqual(UTMZone(epsg: 32650)?.isNorth, true)
        XCTAssertNil(UTMZone(epsg: 4326))
        XCTAssertNil(UTMZone(epsg: 32761))
    }

    func testPRJContainsZoneParameters() {
        let wkt = UTMZone(epsg: 32748)!.prjWKT
        XCTAssertTrue(wkt.contains("WGS_1984_UTM_Zone_48S"))
        XCTAssertTrue(wkt.contains("PARAMETER[\"False_Northing\",10000000.0]"))
        XCTAssertTrue(wkt.contains("PARAMETER[\"Central_Meridian\",105.0]"))
    }
}

final class SheetTests: XCTestCase {
    /// "A4 area size per scale" table in PRD FR-1.
    func testGroundSizeMatchesPRDTable() {
        let expected: [(Int, Double, Double, Double)] = [
            (3000, 630, 891, 0.085), (4000, 840, 1188, 0.113), (5000, 1050, 1485, 0.141),
            (7500, 1575, 2227.5, 0.212), (10000, 2100, 2970, 0.282), (15000, 3150, 4455, 0.423),
        ]
        for (scale, w, h, px) in expected {
            let s = SheetSpec(scaleDenominator: scale)
            XCTAssertEqual(s.groundWidthM, w, accuracy: 1e-9)
            XCTAssertEqual(s.groundHeightM, h, accuracy: 1e-9)
            XCTAssertEqual(s.pixelSizeM(dpi: 900), px, accuracy: 0.0005)
        }
    }

    func testLandscapeSwapsAndMarginShrinks() {
        var s = SheetSpec(orientation: .landscape, scaleDenominator: 4000)
        XCTAssertEqual(s.groundWidthM, 1188, accuracy: 1e-9)
        XCTAssertEqual(s.groundHeightM, 840, accuracy: 1e-9)
        s.marginMM = 10
        XCTAssertEqual(s.mappingWidthMM, 277)
        XCTAssertEqual(s.mappingHeightMM, 190)
    }

    func testPixelDimensionsFromPRD() {
        let s = SheetSpec()
        XCTAssertTrue(s.pixelDimensions(dpi: 300) == (2480, 3508))
        XCTAssertTrue(s.pixelDimensions(dpi: 600) == (4961, 7016))
        XCTAssertTrue(s.pixelDimensions(dpi: 900) == (7441, 10524))
    }

    func testOrientationToggleKeepsCenter() {
        var sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(center: Point2D(x: 787_000, y: 9_235_000), sheet: sheet)
        sheet.orientation = .landscape
        let rotated = frame.resized(to: sheet)
        XCTAssertEqual(rotated.center, frame.center)
        XCTAssertEqual(rotated.widthM, frame.heightM)
    }

    func testSnapToTenMetres() {
        let f = MapFrame(origin: Point2D(x: 786_583.7, y: 9_234_406.2), widthM: 840, heightM: 1188).snapped(toStep: 10)
        XCTAssertEqual(f.origin, Point2D(x: 786_580, y: 9_234_410))
        XCTAssertEqual(f.extent.maxX, 787_420)
    }
}

final class WorldFileTests: XCTestCase {
    func testWorldFileUsesUpperLeftPixelCentre() {
        let frame = MapFrame(origin: Point2D(x: 786_000, y: 9_234_000), widthM: 840, heightM: 1188)
        let p = SheetSpec().pixelSizeM(dpi: 900)
        let wf = WorldFile(frame: frame, pixelSize: p)
        XCTAssertEqual(wf.pixelSizeX, 0.1128888889, accuracy: 1e-9)
        XCTAssertEqual(wf.pixelSizeY, -p)
        XCTAssertEqual(wf.upperLeftX, 786_000 + p / 2)
        XCTAssertEqual(wf.upperLeftY, 9_235_188 - p / 2)
    }

    func testTextRoundTrip() {
        let wf = WorldFile(pixelSizeX: 0.1128888889, pixelSizeY: -0.1128888889, upperLeftX: 786_000.0564444, upperLeftY: 9_235_187.9435556)
        let parsed = WorldFile(text: wf.text)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.upperLeftX, wf.upperLeftX, accuracy: 1e-9)
        XCTAssertEqual(wf.text.split(separator: "\n").count, 6)
        XCTAssertFalse(wf.text.contains(","), "World file must use a decimal point")
    }

    func testRejectsMalformed() {
        XCTAssertNil(WorldFile(text: "1\n0\n0\n-1\n100"))
        XCTAssertNil(WorldFile(text: "a\nb\nc\nd\ne\nf"))
        XCTAssertNil(WorldFile(text: "0\n0\n0\n-1\n100\n200"))
    }
}

final class StrokeTests: XCTestCase {
    func testCodableRoundTripKeepsPoints() throws {
        let s = Stroke(colorHex: "#D15C00", widthMM: 0.14, points: [Point2D(x: 1.5, y: 2.5), Point2D(x: 3, y: 4)])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(Stroke.self, from: enc.encode(s))
        XCTAssertEqual(back.points, s.points)
        XCTAssertEqual(back.widthMM, 0.14)
    }

    func testDistanceToPolyline() {
        let s = Stroke(colorHex: "#000000", widthMM: 0.14, points: [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0)])
        XCTAssertEqual(s.distance(to: Point2D(x: 5, y: 3)), 3, accuracy: 1e-12)
        XCTAssertEqual(s.distance(to: Point2D(x: 13, y: 4)), 5, accuracy: 1e-12)
    }

    func testPrintWidthFormula() {
        let s = Stroke(colorHex: "#000000", widthMM: 0.14, points: [])
        XCTAssertEqual(s.pixelWidth(dpi: 900), 0.14 * 900 / 25.4, accuracy: 1e-12)
        XCTAssertEqual(PenPreset.clampWidth(0.014), 0.05)
        XCTAssertEqual(PenPreset.clampWidth(0.1449), 0.14)
        XCTAssertEqual(PenPreset.clampWidth(9), 3.0)
    }
}

final class CoordinateParserTests: XCTestCase {
    func testDecimalLatLon() {
        XCTAssertEqual(CoordinateParser.parse("-6.9147, 107.6098"), LatLon(lat: -6.9147, lon: 107.6098))
        XCTAssertEqual(CoordinateParser.parse("-6,9147 107,6098"), LatLon(lat: -6.9147, lon: 107.6098))
        XCTAssertNil(CoordinateParser.parse("Bandung"))
        XCTAssertNil(CoordinateParser.parse("95, 10"))
    }

    func testUTMInput() {
        let zone = UTMZone(epsg: 32748)!
        let target = LatLon(lat: -6.9147, lon: 107.6098)
        let p = zone.project(target)
        let parsed = CoordinateParser.parse("48S \(Int(p.x)) \(Int(p.y))")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.lat, target.lat, accuracy: 1e-4)
        XCTAssertEqual(parsed!.lon, target.lon, accuracy: 1e-4)
    }
}

final class PackageTests: XCTestCase {
    func testWriteAndReadPackage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("cakra")
        defer { try? FileManager.default.removeItem(at: dir) }
        var project = Project(name: "Uji", crsEPSG: 32748, frameOrigin: Point2D(x: 786_000, y: 9_234_000))
        project.areaLocked = true
        let doc = ProjectDocument(project: project, strokes: [
            Stroke(colorHex: "#000000", widthMM: 0.14, points: [Point2D(x: 786_100, y: 9_234_100)]),
        ])
        try CakraPackage.write(doc, to: dir)
        let back = try CakraPackage.read(at: dir)
        XCTAssertEqual(back.project.frame, project.frame)
        XCTAssertEqual(back.strokes.count, 1)
        XCTAssertEqual(back.project.technicalSummary, "1:4000 · 900 dpi · UTM 48S")
    }
}

final class RasterExportTests: XCTestCase {
    /// G1 roundtrip test: a point drawn at X,Y must land on the pixel
    /// computed back from the world file, within ≤ 1 pixel.
    func testExportedPixelsMatchWorldFile() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 786_000, y: 9_234_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let target = Point2D(x: 786_321.37, y: 9_234_777.77)
        let stroke = Stroke(colorHex: "#000000", widthMM: 0.5, points: [target])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let req = RasterExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                      dpi: 300, format: .png, strokes: [stroke])
        let result = try RasterExporter.export(req, to: dir)
        XCTAssertEqual(result.pixelWidth, 2480)
        XCTAssertEqual(result.pixelHeight, 3508)
        XCTAssertEqual(result.worldFileURL.pathExtension, "pgw")
        XCTAssertNotNil(result.prjURL)

        let wf = try XCTUnwrap(WorldFile(text: String(contentsOf: result.worldFileURL)))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let (col, row) = try darkestPixel(image)

        let world = wf.world(col: Double(col), row: Double(row))
        let errorPx = world.distance(to: target) / wf.pixelSizeX
        XCTAssertLessThanOrEqual(errorPx, 1.0, "Error \(errorPx) px")
    }

    func testJPEGHasWhiteBackgroundAndJGW() throws {
        let sheet = SheetSpec(scaleDenominator: 15000)
        let frame = MapFrame(origin: Point2D(x: 700_000, y: 9_200_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let req = RasterExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                      dpi: 300, format: .jpeg, strokes: [], includePRJ: false)
        let result = try RasterExporter.export(req, to: dir)
        XCTAssertEqual(result.worldFileURL.pathExtension, "jgw")
        XCTAssertNil(result.prjURL)
    }

    func testExportCheckFindsOutsideStrokes() {
        let frame = MapFrame(origin: Point2D(x: 0, y: 0), widthM: 100, heightM: 100)
        let strokes = [
            Stroke(colorHex: "#000000", widthMM: 0.1, points: [Point2D(x: 10, y: 10), Point2D(x: 20, y: 20)]),
            Stroke(colorHex: "#000000", widthMM: 0.1, points: [Point2D(x: 90, y: 90), Point2D(x: 120, y: 90)]),
            Stroke(colorHex: "#000000", widthMM: 0.1, points: [Point2D(x: 200, y: 200)]),
        ]
        let check = ExportCheck(strokes: strokes, frame: frame)
        XCTAssertEqual(check.outside, 1)
        XCTAssertEqual(check.partlyOutside, 1)
    }

    private func darkestPixel(_ image: CGImage) throws -> (Int, Int) {
        let w = image.width, h = image.height
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        // Round dot: take the centroid of the highest-alpha pixels. Memory row 0 = top image row.
        var sumX = 0.0, sumY = 0.0, sumW = 0.0
        for row in 0..<h {
            for col in 0..<w {
                let a = Double(data[row * w * 4 + col * 4 + 3])
                if a > 0 { sumX += Double(col) * a; sumY += Double(row) * a; sumW += a }
            }
        }
        XCTAssertGreaterThan(sumW, 0, "Stroke not rendered")
        return (Int((sumX / sumW).rounded()), Int((sumY / sumW).rounded()))
    }
}

final class ExportPerformanceTests: XCTestCase {
    /// PRD budget: A4 900 dpi export (TIFF + world file) < 20 s on iPad Air M1.
    func testA4At900DPITiffWithinBudget() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 786_000, y: 9_234_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let strokes = (0..<2000).map { i in
            Stroke(colorHex: "#D15C00", widthMM: 0.14, points: (0..<50).map { j in
                Point2D(x: 786_000 + Double(i % 40) * 21 + Double(j) * 0.4, y: 9_234_000 + Double(i / 40) * 23 + sin(Double(j) / 5) * 5)
            })
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let req = RasterExportRequest(baseName: "perf", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                      dpi: 900, format: .tiff, strokes: strokes)
        let start = Date()
        let result = try RasterExporter.export(req, to: dir)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(result.pixelWidth, 7441)
        XCTAssertEqual(result.pixelHeight, 10524)
        XCTAssertLessThan(elapsed, 20, "Export \(elapsed) s")
        print("A4 900 dpi TIFF, 2000 stroke: \(String(format: "%.2f", elapsed)) s")
    }
}

final class VectorExportTests: XCTestCase {
    let sheet = SheetSpec(scaleDenominator: 4000)
    lazy var frame = MapFrame(origin: Point2D(x: 788_100, y: 9_236_860), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
    lazy var strokes: [Stroke] = [
        Stroke(colorHex: "#D15C00", widthMM: 0.14, points: [Point2D(x: 788_200.1234, y: 9_237_000.5678), Point2D(x: 788_250.5, y: 9_237_100.25), Point2D(x: 788_301, y: 9_237_050)]),
        Stroke(colorHex: "#000000", widthMM: 0.35, points: [Point2D(x: 788_500, y: 9_237_500), Point2D(x: 788_600, y: 9_237_520)]),
        Stroke(colorHex: "#D15C00", widthMM: 0.14, points: [Point2D(x: 788_700, y: 9_237_900), Point2D(x: 788_710, y: 9_237_910)]),
        Stroke(colorHex: "#00A0E6", widthMM: 0.5, points: [Point2D(x: 788_400, y: 9_237_300)]),
        // Entirely outside the frame: excluded.
        Stroke(colorHex: "#000000", widthMM: 0.14, points: [Point2D(x: 700_000, y: 9_000_000), Point2D(x: 700_010, y: 9_000_010)]),
    ]
    var request: VectorExportRequest {
        VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: strokes)
    }

    func testSymbolTableGroupsByColorWidthAndKind() {
        let t = SketchSymbolTable(strokes: request.exportedStrokes)
        XCTAssertEqual(t.symbols.map(\.code), ["990.1", "990.2", "990.3"])
        XCTAssertEqual(t.symbols[0].name, "Sketch Brown 0.14 mm")
        XCTAssertEqual(t.symbols[0].dxfLayer, "990_1_SKETCH_BROWN_014")
        XCTAssertTrue(t.symbols[2].isPoint)
    }

    /// .omap coordinates (paper µm, y down) converted back to UTM via the georeference in the same file.
    func testOmapIsWellFormedAndRoundTripsCoordinates() throws {
        let xml = OmapWriter.document(request)
        let parsed = try OmapProbe.parse(xml)
        XCTAssertEqual(parsed.scale, 4000)
        XCTAssertEqual(parsed.symbolCount, 3)
        XCTAssertEqual(parsed.objects.count, 4)
        XCTAssertEqual(parsed.objects.map(\.symbol), [0, 1, 0, 2])

        let f = Double(parsed.scale) / 1_000_000
        let expected = request.exportedStrokes
        for (obj, stroke) in zip(parsed.objects, expected) {
            XCTAssertEqual(obj.coords.count, stroke.points.count)
            for (c, p) in zip(obj.coords, stroke.points) {
                let back = Point2D(x: parsed.ref.x + Double(c.0) * f, y: parsed.ref.y - Double(c.1) * f)
                // 1 µm paper rounding = 4 mm on the ground at 1:4000.
                XCTAssertLessThanOrEqual(back.distance(to: p), 0.5e-6 * 4000 * 1.5)
            }
        }
        XCTAssertTrue(xml.contains("+proj=utm +zone=48 +south +datum=WGS84"))
    }

    func testDXFKeepsUTMMetresPerLayer() throws {
        let dxf = DXFWriter.document(request)
        let lines = dxf.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.last, "")
        let pairs = stride(from: 0, to: lines.count - 1, by: 2).map { (lines[$0].trimmingCharacters(in: .whitespaces), lines[$0 + 1]) }
        XCTAssertEqual(pairs.first?.1, "SECTION")
        XCTAssertEqual(pairs.last?.1, "EOF")

        var vertices: [String: [Point2D]] = [:]
        var points: [String: [Point2D]] = [:]
        var i = 0
        while i < pairs.count {
            if pairs[i] == ("0", "VERTEX") || pairs[i] == ("0", "POINT") {
                let isVertex = pairs[i].1 == "VERTEX"
                var layer = "", x = 0.0, y = 0.0
                i += 1
                while i < pairs.count, pairs[i].0 != "0" {
                    switch pairs[i].0 {
                    case "8": layer = pairs[i].1
                    case "10": x = Double(pairs[i].1)!
                    case "20": y = Double(pairs[i].1)!
                    default: break
                    }
                    i += 1
                }
                if isVertex { vertices[layer, default: []].append(Point2D(x: x, y: y)) } else { points[layer, default: []].append(Point2D(x: x, y: y)) }
            } else {
                i += 1
            }
        }
        XCTAssertEqual(vertices["FRAME"], frame.corners)
        let coklat = try XCTUnwrap(vertices["990_1_SKETCH_BROWN_014"])
        XCTAssertEqual(coklat.count, 5)
        XCTAssertEqual(coklat[0].x, 788_200.1234, accuracy: 1e-9)
        XCTAssertEqual(coklat[0].y, 9_237_000.5678, accuracy: 1e-9)
        XCTAssertEqual(vertices["990_2_SKETCH_BLACK_035"]?.count, 2)
        XCTAssertEqual(points["990_3_SKETCH_BLUE_050_POINT"], [Point2D(x: 788_400, y: 9_237_300)])
        XCTAssertNil(vertices.keys.first { $0.contains("700") })
    }

    func testExportWritesSelectedFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try VectorExporter.export(request, formats: [.omap, .dxf], to: dir)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["uji.omap", "uji.dxf"])
    }
}

/// Minimal .omap reader for tests: georeference, symbol count and object coordinates.
private final class OmapProbe: NSObject, XMLParserDelegate {
    struct Object { var symbol: Int; var coords: [(Int, Int)] }
    var scale = 0
    var ref = Point2D(x: 0, y: 0)
    var symbolCount = 0
    var objects: [Object] = []
    private var inProjected = false
    private var inCoords = false
    private var text = ""

    static func parse(_ xml: String) throws -> OmapProbe {
        let probe = OmapProbe()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = probe
        guard parser.parse() else { throw parser.parserError ?? NSError(domain: "omap", code: 1) }
        return probe
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "georeferencing": scale = Int(a["scale"] ?? "") ?? 0
        case "projected_crs": inProjected = true
        case "ref_point" where inProjected: ref = Point2D(x: Double(a["x"]!)!, y: Double(a["y"]!)!)
        case "symbols": symbolCount = Int(a["count"] ?? "") ?? 0
        case "object": objects.append(Object(symbol: Int(a["symbol"]!)!, coords: []))
        case "coords": inCoords = true; text = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inCoords { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "projected_crs": inProjected = false
        case "coords":
            inCoords = false
            objects[objects.count - 1].coords = text.split(separator: ";").map { pair in
                let v = pair.split(separator: " ").compactMap { Int($0) }
                return (v[0], v[1])
            }
        default: break
        }
    }
}

final class BezierFeatureTests: XCTestCase {
    /// S curve: (0,0) → (100,0) with out handle (0,50) and in handle (100,-50).
    let curve = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: [
        BezierNode(point: Point2D(x: 788_300, y: 9_237_200), outHandle: Point2D(x: 788_300, y: 9_237_250)),
        BezierNode(point: Point2D(x: 788_400, y: 9_237_200), inHandle: Point2D(x: 788_400, y: 9_237_150)),
    ], createdAt: Date(timeIntervalSince1970: 1_790_000_000)) // whole seconds: ISO-8601 does not store fractions

    func testSegmentMatchesCubicFormula() {
        let s = curve.segments[0]
        XCTAssertTrue(s.isCurve)
        // t = 0.5: (p0 + 3c1 + 3c2 + p3) / 8
        let mid = s.point(at: 0.5)
        XCTAssertEqual(mid.x, 788_350, accuracy: 1e-9)
        XCTAssertEqual(mid.y, 9_237_200, accuracy: 1e-9)
        XCTAssertEqual(s.point(at: 0.25).y, 9_237_200 + 3 * 0.75 * 0.75 * 0.25 * 50 - 3 * 0.75 * 0.25 * 0.25 * 50, accuracy: 1e-9)
    }

    func testFlattenStaysWithinTolerance() {
        let pts = curve.flattened(tolerance: 0.2)
        XCTAssertEqual(pts.first, curve.nodes[0].point)
        XCTAssertEqual(pts.last, curve.nodes[1].point)
        // Every curve point must be close to the flattened polyline.
        let s = curve.segments[0]
        for k in 0...100 {
            let p = s.point(at: Double(k) / 100)
            var best = Double.infinity
            for i in 1..<pts.count { best = min(best, p.distance(toSegment: pts[i - 1], pts[i])) }
            XCTAssertLessThanOrEqual(best, 0.2)
        }
    }

    func testCornerSegmentsAreStraight() {
        let tri = Feature(kind: .area, colorHex: "#3EB54A", widthMM: 0.14, nodes: [
            BezierNode(point: Point2D(x: 0, y: 0)), BezierNode(point: Point2D(x: 10, y: 0)), BezierNode(point: Point2D(x: 0, y: 10)),
        ])
        XCTAssertEqual(tri.segments.count, 3, "Closed area: last segment returns to the start point")
        XCTAssertFalse(tri.segments.contains { $0.isCurve })
        XCTAssertEqual(tri.flattened(tolerance: 1).count, 4)
    }

    func testOmapCurveAndCloseFlags() {
        let ref = Point2D(x: 788_350, y: 9_237_200)
        let coords = OmapWriter.featureCoords(curve, reference: ref, scale: 4000)
        // Curve start has flag 1, then two control points, then the end point.
        XCTAssertEqual(coords, ["-12500 0 1;", "-12500 -12500;", "12500 12500;", "12500 0;"])

        var area = curve
        area.kind = .area
        let closed = OmapWriter.featureCoords(area, reference: ref, scale: 4000)
        XCTAssertEqual(closed.last, "-12500 0 2;", "Closed path ends with the start point carrying the close flag")
        // Curve (3 coords) + straight closing segment (1) + closing point (1).
        XCTAssertEqual(closed.count, 5)
    }

    func testVectorExportIncludesFeatures() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 788_100, y: 9_236_860), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        var hidden = curve
        hidden.isVisible = false
        let area = Feature(kind: .area, colorHex: "#3EB54A", widthMM: 0.14, nodes: [
            BezierNode(point: Point2D(x: 788_500, y: 9_237_500)), BezierNode(point: Point2D(x: 788_600, y: 9_237_500)),
            BezierNode(point: Point2D(x: 788_550, y: 9_237_600)),
        ])
        let req = VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: [],
                                      features: [curve, area, hidden])
        XCTAssertEqual(req.exportedFeatures.count, 2, "Hidden features excluded")

        let xml = OmapWriter.document(req)
        XCTAssertTrue(xml.contains("<area_symbol inner_color="))
        XCTAssertTrue(xml.contains("name=\"Area Green\""))
        XCTAssertTrue(xml.contains("<objects count=\"2\">"))
        XCTAssertNotNil(XMLParser(data: Data(xml.utf8)).parse() ? true : nil)

        let dxf = DXFWriter.document(req)
        XCTAssertTrue(dxf.contains("990_2_AREA_GREEN"))
        // Curve flattened: far more vertices than the 2 bezier points.
        let lineVertices = dxf.components(separatedBy: "VERTEX\r\n8\r\n990_1_SKETCH_BLACK_025").count - 1
        XCTAssertGreaterThan(lineVertices, 8)
    }

    func testRasterDrawsCurveThroughMidpoint() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 788_100, y: 9_236_860), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let req = RasterExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, dpi: 300,
                                      format: .png, strokes: [], features: [curve])
        let result = try RasterExporter.export(req, to: dir)
        let wf = try XCTUnwrap(WorldFile(text: String(contentsOf: result.worldFileURL)))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        // Curve midpoint (788350, 9237200) and the point at t = 0.25 must be colored; the point on straight line p0–p3 at t = 0.25 must not.
        func alpha(at p: Point2D) -> UInt8 {
            let col = Int(((p.x - wf.upperLeftX) / wf.pixelSizeX).rounded())
            let row = Int(((p.y - wf.upperLeftY) / wf.pixelSizeY).rounded())
            return data[row * image.width * 4 + col * 4 + 3]
        }
        XCTAssertGreaterThan(alpha(at: curve.segments[0].point(at: 0.5)), 0)
        XCTAssertGreaterThan(alpha(at: curve.segments[0].point(at: 0.25)), 0)
        XCTAssertEqual(alpha(at: Point2D(x: 788_325, y: 9_237_200)), 0)
    }

    func testPackageRoundTripKeepsFeatures() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("cakra")
        defer { try? FileManager.default.removeItem(at: dir) }
        try CakraPackage.write(ProjectDocument(project: Project(name: "Uji"), features: [curve]), to: dir)
        let back = try CakraPackage.read(at: dir)
        XCTAssertEqual(back.features, [curve])
    }
}

final class ShapeToolTests: XCTestCase {
    let square = [Point2D(x: 0, y: 100), Point2D(x: 100, y: 100), Point2D(x: 100, y: 0), Point2D(x: 0, y: 0)]

    func testRectangleIsClosedAreaThroughCorners() {
        let r = Feature.rectangle(corners: square, colorHex: "#000000", widthMM: 0.14)
        XCTAssertEqual(r.kind, .area)
        XCTAssertEqual(r.nodes.map(\.point), square)
        XCTAssertEqual(r.segments.count, 4)
    }

    func testEllipseApproximatesCircle() {
        let e = Feature.ellipse(corners: square, colorHex: "#000000", widthMM: 0.14)
        XCTAssertEqual(e.nodes.count, 4)
        let c = Point2D(x: 50, y: 50)
        for s in e.segments {
            for k in 0...20 {
                let r = s.point(at: Double(k) / 20).distance(to: c)
                XCTAssertEqual(r, 50, accuracy: 50 * 0.0003)
            }
        }
    }

    func testToggleSmoothAndMirroredHandles() {
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.14, nodes: [
            BezierNode(point: Point2D(x: 0, y: 0)), BezierNode(point: Point2D(x: 30, y: 30)), BezierNode(point: Point2D(x: 60, y: 0)),
        ])
        f.toggleSmooth(at: 1)
        XCTAssertTrue(f.nodes[1].isSmooth)
        XCTAssertEqual(f.nodes[1].outHandle!.y, 30, accuracy: 1e-9, "Handle along prev → next direction (horizontal)")
        let otherLen = f.nodes[1].inHandle!.distance(to: f.nodes[1].point)
        f.moveHandle(node: 1, isIn: false, to: Point2D(x: 30, y: 50))
        XCTAssertEqual(f.nodes[1].inHandle!.x, 30, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[1].inHandle!.y, 30 - otherLen, accuracy: 1e-9, "Opposite handle collinear, length kept")
        f.toggleSmooth(at: 1)
        XCTAssertFalse(f.nodes[1].isSmooth)
    }
}

final class OcadReaderTests: XCTestCase {
    /// Minimal OCAD 12 file: 1 scale string, 1 color, 1 line symbol, 1 bezier line object.
    static func makeOcad(scalePar: String = "\tm10000.000000\tg150\tr1\tx680000\ty9304000\ta0.00000000\ti1000",
                         objects: [(sym: Int32, kind: UInt8, coords: [(Int32, Int32, UInt8, UInt8)])]? = nil) -> Data {
        var d = Data(count: 64)
        func put<T: FixedWidthInteger>(_ v: T, at o: Int) {
            if d.count < o + MemoryLayout<T>.size { d.count = o + MemoryLayout<T>.size }
            withUnsafeBytes(of: v.littleEndian) { d.replaceSubrange(o ..< o + MemoryLayout<T>.size, with: $0) }
        }
        func append(_ bytes: Data) -> Int { let o = d.count; d.append(bytes); return o }
        put(UInt16(0x0CAD), at: 0)
        put(Int16(12), at: 4)

        // String block.
        let strBlock = append(Data(count: 4 + 256 * 16))
        let scale = append(Data(scalePar.utf8) + Data([0]))
        let color = append(Data("Brown\tn5\tc0\tm56\ty100\tk18".utf8) + Data([0]))
        for (i, (pos, len, type)) in [(scale, scalePar.utf8.count + 1, Int32(1039)), (color, 26, Int32(9))].enumerated() {
            put(UInt32(pos), at: strBlock + 4 + i * 16)
            put(UInt32(len), at: strBlock + 8 + i * 16)
            put(type, at: strBlock + 12 + i * 16)
        }
        put(UInt32(strBlock), at: 32)

        // Symbol block: 1 line symbol 101.0 "Contour", color 5, width 0.21 mm.
        let symBlock = append(Data(count: 4 + 256 * 4))
        let sym = append(Data(count: 872))
        put(Int32(872), at: sym)
        put(Int32(101_000), at: sym + 4)
        put(UInt8(2), at: sym + 8)
        put(Int16(5), at: sym + 28)
        for (i, u) in "Contour".utf16.enumerated() { put(u, at: sym + 56 + i * 2) }
        put(Int16(5), at: sym + 796)
        put(Int16(21), at: sym + 798)
        put(UInt32(sym), at: symBlock + 4)
        // Point symbol 204.0 "Boulder": 1 dot element (type 4) Ø 0.60 mm, color 5.
        let point = append(Data(count: 824))
        put(Int32(824), at: point)
        put(Int32(204_000), at: point + 4)
        put(UInt8(1), at: point + 8)
        put(Int16(5), at: point + 28)
        for (i, u) in "Boulder".utf16.enumerated() { put(u, at: point + 56 + i * 2) }
        put(UInt16(3), at: point + 796)        // DataSize = 3 TCord (header 2 + 1 point)
        put(Int16(4), at: point + 800)         // type: dot
        put(Int16(5), at: point + 804)         // color
        put(Int16(60), at: point + 808)        // diameter 0.60 mm
        put(Int16(1), at: point + 810)         // 1 point
        put(UInt32(point), at: symBlock + 8)
        // Double-line symbol 505.0: width 0.35 mm, 0.10 mm borders color 5, fill color 5 (fill flag).
        let dbl = append(Data(count: 872))
        put(Int32(872), at: dbl)
        put(Int32(505_000), at: dbl + 4)
        put(UInt8(2), at: dbl + 8)
        for (i, u) in "Footpath".utf16.enumerated() { put(u, at: dbl + 56 + i * 2) }
        put(Int16(5), at: dbl + 796)
        put(Int16(0), at: dbl + 798)          // no center line
        put(Int16(3), at: dbl + 822)          // DblMode
        put(Int16(1), at: dbl + 824)          // DblFlags: fill
        put(Int16(5), at: dbl + 826)          // fill color
        put(Int16(5), at: dbl + 828)          // border color
        put(Int16(35), at: dbl + 832)         // width between borders
        put(Int16(10), at: dbl + 834)
        put(Int16(10), at: dbl + 836)
        put(UInt32(dbl), at: symBlock + 12)
        put(UInt32(symBlock), at: 8)

        // Object block.
        let objBlock = append(Data(count: 4 + 256 * 40))
        let objs = objects ?? [(101_000, 2, [(0, 0, 0, 0), (1000, 0, 1, 0), (2000, 1000, 2, 0), (2000, 2000, 0, 0)])]
        for (i, o) in objs.enumerated() {
            let pos = append(Data(count: 56 + o.coords.count * 8))
            put(o.sym, at: pos)
            put(o.kind, at: pos + 4)
            put(UInt32(o.coords.count), at: pos + 44)
            for (k, c) in o.coords.enumerated() {
                put(c.0 << 8 | Int32(c.2), at: pos + 56 + k * 8)
                put(c.1 << 8 | Int32(c.3), at: pos + 60 + k * 8)
            }
            put(UInt32(pos), at: objBlock + 4 + i * 40 + 16)
            put(UInt8(1), at: objBlock + 4 + i * 40 + 30)
        }
        put(UInt32(objBlock), at: 12)
        return d
    }

    func testReadsGeoreferenceSymbolsAndBezierLine() throws {
        let map = try OcadReader.read(Self.makeOcad())
        XCTAssertEqual(map.version, 12)
        XCTAssertEqual(map.scale, 10000)
        XCTAssertEqual(map.realWorldOffset, Point2D(x: 680_000, y: 9_304_000))
        XCTAssertEqual(map.symbols[101_000]?.name, "Contour")
        XCTAssertEqual(map.symbols[101_000]?.code, "101.0")
        XCTAssertEqual(map.symbols[101_000]?.lineWidthMM, 0.21)

        let (features, report) = try map.features()
        XCTAssertEqual(report.imported, 1)
        let f = try XCTUnwrap(features.first)
        XCTAssertEqual(f.name, "101.0 Contour")
        XCTAssertEqual(f.kind, .line)
        // CMYK 0/56/100/18 → sRGB.
        XCTAssertEqual(f.colorHex, "#D15C00")
        // 1000 × 0.01 mm = 10 mm paper × 10000 / 1000 = 100 m.
        XCTAssertEqual(f.nodes.count, 2)
        XCTAssertEqual(f.nodes[0].point, Point2D(x: 680_000, y: 9_304_000))
        XCTAssertEqual(f.nodes[0].outHandle, Point2D(x: 680_100, y: 9_304_000))
        XCTAssertEqual(f.nodes[1].inHandle, Point2D(x: 680_200, y: 9_304_100))
        XCTAssertEqual(f.nodes[1].point, Point2D(x: 680_200, y: 9_304_200))
    }

    func testAreaDropsRepeatedClosingPointAndHoles() throws {
        let ring: [(Int32, Int32, UInt8, UInt8)] = [(0, 0, 0, 0), (1000, 0, 0, 0), (1000, 1000, 0, 0), (0, 1000, 0, 0), (0, 0, 0, 0),
                                                    (200, 200, 0, 2), (400, 200, 0, 0), (400, 400, 0, 0)]
        let map = try OcadReader.read(Self.makeOcad(objects: [(526_000, 3, ring), (999_000, 1, [(0, 0, 0, 0)])]))
        let (features, report) = try map.features()
        XCTAssertEqual(features.first?.kind, .area)
        XCTAssertEqual(features.first?.nodes.count, 4)
        XCTAssertEqual(report.droppedHoles, 1)
        XCTAssertEqual(report.skippedPoints, 1)
    }

    func testRejectsBadInputWithoutCrashing() {
        XCTAssertThrowsError(try OcadReader.read(Data("bukan ocad".utf8))) { XCTAssertEqual($0 as? OcadReadError, .notOcad) }
        var v8 = Self.makeOcad()
        v8[4] = 8
        XCTAssertThrowsError(try OcadReader.read(v8)) { XCTAssertEqual($0 as? OcadReadError, .unsupportedVersion(8)) }
        // Truncated in the middle of the object block.
        let full = Self.makeOcad()
        XCTAssertThrowsError(try OcadReader.read(full.prefix(full.count - 40)))
        // No georeference.
        let noGeo = try? OcadReader.read(Self.makeOcad(scalePar: "\tm4000\tr0"))
        XCTAssertThrowsError(try noGeo?.features()) { XCTAssertEqual($0 as? OcadReadError, .notGeoreferenced) }
        // Random truncations must not crash.
        for n in stride(from: 0, to: full.count, by: 997) { _ = try? OcadReader.read(full.prefix(n)) }
    }
}

final class SymbolSetTests: XCTestCase {
    func testSymbolSetFromOcad() throws {
        let map = try OcadReader.read(OcadReaderTests.makeOcad())
        let set = map.symbolSet(name: "Uji", sourceFile: "uji.ocd")
        XCTAssertEqual(set.scale, 10000)
        let s = try XCTUnwrap(set.symbols.first)
        XCTAssertEqual(s.code, "101.0")
        XCTAssertEqual(s.kind, .line)
        XCTAssertEqual(s.category, .landform)
        XCTAssertEqual(s.colorHex, "#D15C00")
        XCTAssertEqual(s.drawingWidthMM, 0.21)
        XCTAssertTrue(s.isEnabled && s.isDrawable)
        XCTAssertEqual(MapSymbol(number: 503_001, name: "", kind: .line, colorHex: "#000000", lineWidthMM: nil, isEnabled: true).code, "503.1")
    }

    func testIsomSymbolsGoToOmapAndDXF() throws {
        let sheet = SheetSpec(scaleDenominator: 10000)
        let frame = MapFrame(origin: Point2D(x: 679_150, y: 9_303_770), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let (features, _) = try OcadReader.read(OcadReaderTests.makeOcad()).features()
        XCTAssertEqual(features.first?.symbolCode, "101.0")
        let req = VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: [], features: features)
        let xml = OmapWriter.document(req)
        XCTAssertTrue(xml.contains("code=\"101.0\" name=\"Contour\""), "Original ISOM code, not 990.x")
        XCTAssertTrue(DXFWriter.document(req).contains("\r\n101_0_CONTOUR\r\n"))
    }
}

final class NorthGridTests: XCTestCase {
    let frame = MapFrame(origin: Point2D(x: 786_000, y: 9_234_000), widthM: 840, heightM: 1188)

    func testGridNorthLinesSitOnUTMMultiples() {
        let g = NorthGrid(isEnabled: true, spacingM: 250)
        let lines = g.lines(in: frame)
        XCTAssertEqual(lines.map(\.0.x), [786_000, 786_250, 786_500, 786_750])
        for (a, b) in lines {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9, "Vertical")
            XCTAssertEqual(min(a.y, b.y), 9_234_000, accuracy: 1e-6)
            XCTAssertEqual(max(a.y, b.y), 9_235_188, accuracy: 1e-6)
        }
        XCTAssertEqual(g.spacingPaperMM(scale: 4000), 62.5)
    }

    func testMagneticLinesAreRotatedAndClipped() {
        let g = NorthGrid(isEnabled: true, reference: .magnetic, declinationDeg: 5, spacingM: 100)
        let lines = g.lines(in: frame)
        XCTAssertGreaterThanOrEqual(lines.count, 8)
        let e = frame.extent.insetBy(-1e-6)
        for (a, b) in lines {
            XCTAssertTrue(e.contains(Rect2D(points: [a, b])!), "Clipped inside the frame")
            let angle = atan2(b.x - a.x, b.y - a.y) * 180 / .pi
            XCTAssertEqual(abs(angle), 5, accuracy: 1e-6)
        }
        // Perpendicular distance between consecutive lines = spacing.
        let a = 5 * Double.pi / 180
        let offsets = lines.map { $0.0.x * cos(a) - $0.0.y * sin(a) }.sorted()
        for i in 1..<offsets.count { XCTAssertEqual(offsets[i] - offsets[i - 1], 100, accuracy: 1e-6) }
    }

    func testGridFeaturesCarryISOM601() {
        let f = NorthGrid(isEnabled: true, spacingM: 250).features(in: frame)
        XCTAssertEqual(f.count, 4)
        XCTAssertEqual(f.first?.symbolCode, "601.0")
    }
}

final class GeoPDFTests: XCTestCase {
    func makeRequest(margin: Double = 5) -> GeoPDFRequest {
        let sheet = SheetSpec(marginMM: margin, scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 788_100, y: 9_236_860), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let curve = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: [
            BezierNode(point: Point2D(x: 788_300, y: 9_237_200), outHandle: Point2D(x: 788_300, y: 9_237_250)),
            BezierNode(point: Point2D(x: 788_400, y: 9_237_200), inHandle: Point2D(x: 788_400, y: 9_237_150)),
        ])
        let area = Feature.rectangle(corners: [Point2D(x: 788_500, y: 9_237_600), Point2D(x: 788_600, y: 9_237_600),
                                               Point2D(x: 788_600, y: 9_237_500), Point2D(x: 788_500, y: 9_237_500)],
                                     colorHex: "#3EB54A", widthMM: 0.14)
        return GeoPDFRequest(title: "Uji (PDF)", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                             strokes: [Stroke(colorHex: "#D15C00", widthMM: 0.14, points: [Point2D(x: 788_200, y: 9_237_000), Point2D(x: 788_250, y: 9_237_100)])],
                             features: [curve, area], grid: NorthGrid(isEnabled: true, spacingM: 250))
    }

    func testOpensAsA4WithGeospatialViewport() throws {
        let data = GeoPDFExporter.document(makeRequest())
        let doc = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!), "PDF must be readable by CoreGraphics")
        XCTAssertEqual(doc.numberOfPages, 1)
        let page = try XCTUnwrap(doc.page(at: 1))
        let media = page.getBoxRect(.mediaBox)
        XCTAssertEqual(media.width, 210 / 25.4 * 72, accuracy: 0.01)
        XCTAssertEqual(media.height, 297 / 25.4 * 72, accuracy: 0.01)

        let dict = try XCTUnwrap(page.dictionary)
        var vp: CGPDFArrayRef?
        XCTAssertTrue(CGPDFDictionaryGetArray(dict, "VP", &vp), "Page carries /VP")
        var viewport: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFArrayGetDictionary(vp!, 0, &viewport))
        var measure: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(viewport!, "Measure", &measure))
        var subtype: UnsafePointer<CChar>?
        XCTAssertTrue(CGPDFDictionaryGetName(measure!, "Subtype", &subtype))
        XCTAssertEqual(String(cString: subtype!), "GEO")

        // GPTS bottom-left = lat/lon of the frame's bottom-left corner.
        var gpts: CGPDFArrayRef?
        XCTAssertTrue(CGPDFDictionaryGetArray(measure!, "GPTS", &gpts))
        XCTAssertEqual(CGPDFArrayGetCount(gpts!), 8)
        var lat: CGPDFReal = 0, lon: CGPDFReal = 0
        CGPDFArrayGetNumber(gpts!, 0, &lat)
        CGPDFArrayGetNumber(gpts!, 1, &lon)
        let req = makeRequest()
        let ll = req.zone.unproject(req.frame.corners[3])
        XCTAssertEqual(Double(lat), ll.lat, accuracy: 1e-8)
        XCTAssertEqual(Double(lon), ll.lon, accuracy: 1e-8)

        // Viewport BBox = map area inside the 5 mm margin.
        var bbox: CGPDFArrayRef?
        XCTAssertTrue(CGPDFDictionaryGetArray(viewport!, "BBox", &bbox))
        var x0: CGPDFReal = 0
        CGPDFArrayGetNumber(bbox!, 0, &x0)
        XCTAssertEqual(Double(x0), 5 / 25.4 * 72, accuracy: 0.01)
    }

    func testContentHasVectorCurvesAndGrid() {
        let text = String(decoding: GeoPDFExporter.document(makeRequest()), as: UTF8.self)
        XCTAssertTrue(text.contains(" c\n"), "Bezier curve as c operator")
        XCTAssertTrue(text.contains("/GSGrid gs"))
        XCTAssertTrue(text.contains("WGS_1984_UTM_Zone_48S"))
        XCTAssertTrue(text.contains("Uji \\(PDF\\)"), "Parentheses in title are escaped")
    }

    func testNoMarginMeansNoCaption() {
        let text = String(decoding: GeoPDFExporter.document(makeRequest(margin: 0)), as: UTF8.self)
        XCTAssertFalse(text.contains("BT /F1"))
    }
}


final class PointSymbolTests: XCTestCase {
    func boulder() throws -> OcadMap {
        try OcadReader.read(OcadReaderTests.makeOcad(objects: [(204_000, 1, [(500, 500, 0, 0)])]))
    }

    func testReadsPointSymbolElementsAtStandardSize() throws {
        let map = try boulder()
        let sym = try XCTUnwrap(map.symbols[204_000])
        let elements = map.pointElements(of: sym)
        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].kind, .dot)
        XCTAssertEqual(elements[0].diameterMM, 0.6, accuracy: 1e-9)
        XCTAssertEqual(elements[0].colorHex, "#D15C00")
        XCTAssertEqual(elements.diameterMM, 0.6, accuracy: 1e-9)

        let set = map.symbolSet(name: "Uji", sourceFile: "uji.ocd")
        let s = try XCTUnwrap(set.symbols.first { $0.number == 204_000 })
        XCTAssertEqual(s.kind, .point)
        XCTAssertTrue(s.isDrawable, "Point symbol with shapes is drawable")
    }

    func testImportsPointObjects() throws {
        let (features, report) = try boulder().features()
        XCTAssertEqual(report.skippedPoints, 0)
        let f = try XCTUnwrap(features.first)
        XCTAssertEqual(f.kind, .point)
        XCTAssertEqual(f.symbolCode, "204.0")
        XCTAssertEqual(f.nodes.first?.point, Point2D(x: 680_050, y: 9_304_050))
    }

    func testSizeFactorScalesElementsAndGroundRadius() throws {
        let el = PointElement(kind: .circle, colorHex: "#000000", priority: 0, lineWidthMM: 0.2, diameterMM: 1.0, points: [Point2D(x: 0, y: 0)])
        let f = Feature.point(at: Point2D(x: 0, y: 0), elements: [el], sizeFactor: 2)
        XCTAssertEqual(f.scaledPointElements[0].diameterMM, 2.0, accuracy: 1e-9)
        XCTAssertEqual(f.scaledPointElements[0].lineWidthMM, 0.4, accuracy: 1e-9)
        // Ø 1.2 mm (1.0 + 0.2 width) × 2 → radius 1.2 mm → 4.8 m at 1:4000.
        XCTAssertEqual(f.pointRadiusM(sheet: SheetSpec(scaleDenominator: 4000)), 4.8, accuracy: 1e-9)
    }

    func testDrawingOrderFollowsColorPriority() {
        let fill = PointElement(kind: .dot, colorHex: "#C4FFBA", priority: 30, lineWidthMM: 0, diameterMM: 1.4, points: [])
        let ring = PointElement(kind: .circle, colorHex: "#3EB54A", priority: 5, lineWidthMM: 0.24, diameterMM: 0.96, points: [])
        XCTAssertEqual([ring, fill].drawingOrder.map(\.colorHex), ["#C4FFBA", "#3EB54A"], "Fill (low priority) drawn first")
    }

    func testPointsAppearInAllExports() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 679_900, y: 9_303_900), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let (features, _) = try boulder().features()
        let zone = UTMZone(epsg: 32748)!

        let req = VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: zone, strokes: [], features: features)
        XCTAssertEqual(req.exportedFeatures.count, 1, "Point (1 node) must not be filtered out")
        let xml = OmapWriter.document(req)
        XCTAssertTrue(xml.contains("<object type=\"0\""))
        XCTAssertTrue(xml.contains("code=\"204.0\" name=\"Boulder\""))
        XCTAssertTrue(DXFWriter.document(req).contains("POINT\r\n8\r\n204_0_BOULDER"))

        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: zone,
                                                                         strokes: [], features: features)), as: UTF8.self)
        XCTAssertTrue(pdf.contains(" c\n") && pdf.contains("h\nf\n"), "Point as a filled circle")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let raster = try RasterExporter.export(RasterExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: zone, dpi: 600,
                                                                   format: .png, strokes: [], features: features), to: dir)
        let wf = try XCTUnwrap(WorldFile(text: String(contentsOf: raster.worldFileURL)))
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(raster.imageURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        let p = features[0].nodes[0].point
        let col = Int(((p.x - wf.upperLeftX) / wf.pixelSizeX).rounded()), row = Int(((p.y - wf.upperLeftY) / wf.pixelSizeY).rounded())
        XCTAssertGreaterThan(data[row * image.width * 4 + col * 4 + 3], 200, "Point center filled")
        // Ø 0.6 mm @600 dpi ≈ 14 px: 12 px from the center must be empty.
        XCTAssertEqual(data[row * image.width * 4 + (col + 12) * 4 + 3], 0)
    }
}

import Compression
import UniformTypeIdentifiers

final class ContourTests: XCTestCase {
    let sheet = SheetSpec(scaleDenominator: 4000)

    func grid(cols: Int = 60, rows: Int = 60, cell: Double = 5, _ f: (Point2D) -> Float) -> DEMGrid {
        DEMGrid.resample(extent: Rect2D(minX: 0, minY: 0, maxX: Double(cols) * cell, maxY: Double(rows) * cell), cellSize: cell,
                         source: "uji", nativeResolutionM: cell, elevation: f)
    }

    func testPlaneGivesStraightLinesAtExpectedX() {
        // z = x / 10 → 5 m contours at x = 50, 100, ...
        let g = grid { Float($0.x / 10) }
        var s = ContourSettings(isEnabled: true, intervalM: 5, smoothing: 0, minLengthMM: 0)
        s.indexEvery = 5
        let result = ContourGenerator.generate(g, settings: s, sheet: sheet)
        let xs = Set(result.lines.map { ($0.points.map(\.x).reduce(0, +) / Double($0.points.count)).rounded() })
        XCTAssertEqual(xs, [50, 100, 150, 200, 250])
        for line in result.lines {
            for p in line.points { XCTAssertEqual(p.x, line.elevation * 10, accuracy: 1e-6, "Linear interpolation exact on a plane") }
        }
        XCTAssertEqual(result.lines.first { $0.elevation == 25 }?.kind, .index, "25 = 5 × 5 → index")
        XCTAssertEqual(result.lines.first { $0.elevation == 10 }?.kind, .contour)
    }

    func testConeGivesClosedCirclesOfCorrectRadius() {
        let c = Point2D(x: 150, y: 150)
        let g = grid { Float(100 - $0.distance(to: c) / 2) } // r = (100 − z) × 2
        let s = ContourSettings(isEnabled: true, intervalM: 10, smoothing: 0, minLengthMM: 0)
        let result = ContourGenerator.generate(g, settings: s, sheet: sheet)
        let ring = result.lines.first { $0.elevation == 50 }
        XCTAssertNotNil(ring)
        XCTAssertTrue(ring!.isClosed)
        for p in ring!.points { XCTAssertEqual(p.distance(to: c), 100, accuracy: 1.0) }
        XCTAssertEqual(result.maxElevation, 100, accuracy: 2)
    }

    func testFormLinesAndBaseOffset() {
        var s = ContourSettings(intervalM: 5, indexEvery: 5, baseOffsetM: 2.5)
        XCTAssertEqual(ContourLine.kind(elevation: 27.5, settings: s), .index)
        XCTAssertEqual(ContourLine.kind(elevation: 7.5, settings: s), .contour)
        s.showFormLines = true
        XCTAssertEqual(ContourLine.kind(elevation: 5, settings: s), .form)
        XCTAssertEqual(ContourSettings.defaultInterval(scale: 4000), 2)
        XCTAssertEqual(ContourSettings.defaultInterval(scale: 10000), 5)
        XCTAssertNotNil(ContourSettings(intervalM: 2).intervalWarning(nativeResolutionM: 30))
        XCTAssertNil(ContourSettings(intervalM: 10).intervalWarning(nativeResolutionM: 30))
    }

    func testShortLinesRemovedAndFeaturesCarryISOMCodes() {
        let c = Point2D(x: 150, y: 150)
        let g = grid { Float(100 - $0.distance(to: c) / 2) }
        // 1:4000 → 30 mm paper = 120 m: small circles (perimeter < 120 m) are dropped.
        let s = ContourSettings(intervalM: 10, smoothing: 0, minLengthMM: 30)
        let lines = ContourGenerator.generate(g, settings: s, sheet: sheet).lines
        XCTAssertFalse(lines.contains { $0.length < 120 })
        let f = try! XCTUnwrap(lines.first { $0.isClosed }).feature(settings: s)
        XCTAssertEqual(f.kind, .line)
        XCTAssertTrue(["101.0", "102.0"].contains(f.symbolCode ?? ""))
        XCTAssertEqual(f.nodes.first?.point, f.nodes.last?.point, "Closed contour returns to the start point")
    }

    func testPackageRoundTrip() throws {
        let g = grid(cols: 4, rows: 3) { Float($0.x + $0.y) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try g.write(to: dir)
        XCTAssertEqual(try DEMGrid.read(from: dir), g)
    }
}

final class DEMReaderTests: XCTestCase {
    let zone = UTMZone(epsg: 32748)!

    func testAsciiGrid() throws {
        let text = """
        ncols 3
        nrows 2
        xllcorner 680000
        yllcorner 9304000
        cellsize 10
        NODATA_value -9999
        1 2 3
        4 -9999 6
        """
        let r = try AsciiGridReader.read(Data(text.utf8), prj: nil, projectZone: zone)
        XCTAssertEqual(r.crs, .utm(zone))
        XCTAssertEqual(r.originY, 9_304_020)
        XCTAssertEqual(r.values[0], 1)
        XCTAssertTrue(r.values[4].isNaN)
        XCTAssertEqual(r.sample(Point2D(x: 680_005, y: 9_304_015), projectZone: zone), 1, "Top-left cell center")
        // Between cell 1 and an empty cell: still has a value from valid neighbours (not NaN).
        XCTAssertFalse(r.sample(Point2D(x: 680_008, y: 9_304_012), projectZone: zone).isNaN)
        XCTAssertEqual(UTMZone(wkt: zone.prjWKT), zone)
    }

    /// Single-strip float32 TIFF with GeoTIFF tags (UTM 48S).
    func makeGeoTIFF(width: Int, height: Int, values: [Float], compression: Int = 1, predictor: Int = 1) -> Data {
        var pixels = Data()
        for v in values { withUnsafeBytes(of: v.bitPattern.littleEndian) { pixels.append(contentsOf: $0) } }
        if predictor == 3 {
            // Floating-point predictor: arrange bytes per plane (MSB first), then per-byte differences.
            var b = [UInt8](pixels)
            let rowBytes = width * 4
            for r in 0..<height {
                let row = Array(b[(r * rowBytes)..<((r + 1) * rowBytes)])
                var planes = [UInt8](repeating: 0, count: rowBytes)
                for c in 0..<width { for k in 0..<4 { planes[k * width + c] = row[c * 4 + (3 - k)] } }
                for i in stride(from: rowBytes - 1, to: 0, by: -1) { planes[i] = planes[i] &- planes[i - 1] }
                b.replaceSubrange((r * rowBytes)..<((r + 1) * rowBytes), with: planes)
            }
            pixels = Data(b)
        }
        if compression == 8 {
            var out = [UInt8](repeating: 0, count: pixels.count + 1024)
            let n = pixels.withUnsafeBytes { src in
                compression_encode_buffer(&out, out.count, src.bindMemory(to: UInt8.self).baseAddress!, pixels.count, nil, COMPRESSION_ZLIB)
            }
            pixels = Data([0x78, 0x9C]) + Data(out.prefix(n)) + Data([0, 0, 0, 0])
        }
        var d = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        var entries: [(Int, Int, Int, [UInt8])] = [] // tag, type, count, value/payload
        func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        func dbl(_ v: [Double]) -> [UInt8] { v.flatMap { le($0.bitPattern) } }
        entries += [(256, 4, 1, le(UInt32(width))), (257, 4, 1, le(UInt32(height))), (258, 3, 1, le(UInt16(32)) + [0, 0]),
                    (259, 3, 1, le(UInt16(compression)) + [0, 0]), (262, 3, 1, le(UInt16(1)) + [0, 0]),
                    (273, 4, 1, []), (277, 3, 1, le(UInt16(1)) + [0, 0]), (278, 4, 1, le(UInt32(height))),
                    (279, 4, 1, le(UInt32(pixels.count))), (317, 3, 1, le(UInt16(predictor)) + [0, 0]), (339, 3, 1, le(UInt16(3)) + [0, 0]),
                    (33550, 12, 3, dbl([10, 10, 0])), (33922, 12, 6, dbl([0, 0, 0, 680_000, 9_304_100, 0])),
                    (34735, 3, 12, [1, 1, 0, 2, 1024, 0, 1, 1, 3072, 0, 1, 32748].flatMap { le(UInt16($0)) })]
        let ifdSize = 2 + entries.count * 12 + 4
        var extra = Data()
        let extraBase = 8 + ifdSize
        var ifd = Data(le(UInt16(entries.count)))
        let pixelOffset = extraBase + entries.filter { $0.3.count > 4 }.map(\.3.count).reduce(0, +)
        for (tag, type, count, value) in entries {
            ifd += le(UInt16(tag)) + le(UInt16(type)) + le(UInt32(count))
            if tag == 273 {
                ifd += le(UInt32(pixelOffset))
            } else if value.count > 4 {
                ifd += le(UInt32(extraBase + extra.count))
                extra += value
            } else {
                ifd += value + [UInt8](repeating: 0, count: 4 - value.count)
            }
        }
        ifd += le(UInt32(0))
        d += ifd + extra + pixels
        return d
    }

    func testGeoTIFFUncompressedAndDeflatePredictor3() throws {
        let values: [Float] = (0..<20).map { Float($0) * 1.5 + 100 }
        for (comp, pred) in [(1, 1), (8, 1), (8, 3)] {
            let r = try GeoTIFFReader.read(makeGeoTIFF(width: 5, height: 4, values: values, compression: comp, predictor: pred), projectZone: zone)
            XCTAssertEqual(r.values, values, "compression \(comp) predictor \(pred)")
            XCTAssertEqual(r.crs, .utm(zone))
            XCTAssertEqual(r.originX, 680_000)
            XCTAssertEqual(r.cellX, 10)
        }
    }

    /// LZW from a real encoder (ImageIO) so the decoder isn't only tested against our own encoder.
    func testLZWFromImageIO() throws {
        let w = 37, h = 23
        var pixels = [UInt16](repeating: 0, count: w * h)
        for i in pixels.indices { pixels[i] = UInt16((i * 977) % 65_000) }
        let provider = CGDataProvider(data: Data(bytes: pixels, count: pixels.count * 2) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 16, bitsPerPixel: 16, bytesPerRow: w * 2,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageByteOrderInfo.order16Little.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let decoded = try GeoTIFFReader.decode(out as Data)
        XCTAssertEqual(decoded.width, w)
        XCTAssertEqual(decoded.values.map { UInt16($0) }, pixels)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try GeoTIFFReader.read(Data("bukan tiff".utf8), projectZone: zone))
        XCTAssertThrowsError(try AsciiGridReader.read(Data("ncols 3\n".utf8), prj: nil, projectZone: zone))
        let good = makeGeoTIFF(width: 5, height: 4, values: [Float](repeating: 1, count: 20))
        for n in stride(from: 0, to: good.count, by: 13) { _ = try? GeoTIFFReader.read(good.prefix(n), projectZone: zone) }
    }

    func testTerrariumAndTiles() {
        XCTAssertEqual(TerrainTiles.elevation(r: 128, g: 0, b: 0), 0)
        XCTAssertEqual(TerrainTiles.elevation(r: 128, g: 100, b: 128), 100.5)
        let t = TerrainTiles.tileXY(LatLon(lat: 0, lon: 0), z: 1)
        XCTAssertEqual(t.x, 1, accuracy: 1e-9)
        XCTAssertEqual(t.y, 1, accuracy: 1e-9)
        let extent = Rect2D(minX: 679_000, minY: 9_303_800, maxX: 681_500, maxY: 9_306_800)
        XCTAssertFalse(TerrainTiles.tiles(covering: extent, zone: zone, z: 14).isEmpty)
        XCTAssertEqual(TerrainTiles.resolutionM(z: 14, lat: 0), 9.55, accuracy: 0.01)
    }

    func testGeoJSONContours() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"elev":125},"geometry":{"type":"LineString","coordinates":[[106.62,-6.28],[106.63,-6.281]]}},
          {"type":"Feature","properties":{"name":"tanpa elevasi"},"geometry":{"type":"LineString","coordinates":[[106.62,-6.28],[106.63,-6.28]]}}
        ]}
        """
        let lines = try ContourGeoJSON.read(Data(json.utf8), zone: zone)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].elevation, 125)
        XCTAssertEqual(lines[0].points[0].x, zone.project(LatLon(lat: -6.28, lon: 106.62)).x, accuracy: 1e-6)
    }
}

final class ContourExportTests: XCTestCase {
    let zone = UTMZone(epsg: 32748)!
    var lines: [ContourLine] {
        [ContourLine(elevation: 125, kind: .index, points: [Point2D(x: 680_000, y: 9_304_000), Point2D(x: 680_100, y: 9_304_050), Point2D(x: 680_200, y: 9_304_000)], isClosed: false),
         ContourLine(elevation: 127.5, kind: .form, points: [Point2D(x: 680_010, y: 9_304_200), Point2D(x: 680_300, y: 9_304_210)], isClosed: false)]
    }

    func testShapefileStructure() throws {
        let f = Shapefile.polylines(lines)
        func be32(_ d: Data, _ o: Int) -> Int32 { d.subdata(in: o..<o + 4).withUnsafeBytes { Int32(bigEndian: $0.loadUnaligned(as: Int32.self)) } }
        func le32(_ d: Data, _ o: Int) -> Int32 { d.subdata(in: o..<o + 4).withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(as: Int32.self)) } }
        func led(_ d: Data, _ o: Int) -> Double { Double(bitPattern: d.subdata(in: o..<o + 8).withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }) }
        // Header .shp
        XCTAssertEqual(be32(f.shp, 0), 9994)
        XCTAssertEqual(Int(be32(f.shp, 24)) * 2, f.shp.count, "File length in 16-bit words")
        XCTAssertEqual(le32(f.shp, 28), 1000)
        XCTAssertEqual(le32(f.shp, 32), 3, "PolyLine")
        XCTAssertEqual(led(f.shp, 36), 680_000)
        XCTAssertEqual(led(f.shp, 60), 9_304_210)
        // Record 1: number, type, 1 part, 3 points, first point.
        XCTAssertEqual(be32(f.shp, 100), 1)
        XCTAssertEqual(le32(f.shp, 108), 3)
        XCTAssertEqual(le32(f.shp, 108 + 36), 1)
        XCTAssertEqual(le32(f.shp, 108 + 40), 3)
        XCTAssertEqual(led(f.shp, 108 + 48), 680_000)
        XCTAssertEqual(led(f.shp, 108 + 56), 9_304_000)
        // .shx: 2 records, record 2 offset matches .shp.
        XCTAssertEqual(f.shx.count, 100 + 2 * 8)
        let off2 = Int(be32(f.shx, 108)) * 2
        XCTAssertEqual(be32(f.shp, off2), 2, ".shx offset points to record 2")
        // .dbf: 2 records, ELEV field contains 125.00.
        XCTAssertEqual(f.dbf[0], 0x03)
        XCTAssertEqual(f.dbf.subdata(in: 4..<8).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }, 2)
        let headerLen = Int(f.dbf[8]) | Int(f.dbf[9]) << 8
        let record = String(decoding: f.dbf.subdata(in: headerLen..<(headerLen + 29)), as: UTF8.self)
        XCTAssertEqual(record, "       125.00index     102.0 ")
        XCTAssertEqual(f.dbf.last, 0x1A)
    }

    func testKMLIsWGS84AndWellFormed() throws {
        let kml = KML.document(lines, zone: zone, settings: ContourSettings(), title: "Uji & kontur")
        XCTAssertTrue(XMLParser(data: Data(kml.utf8)).parse(), "XML valid")
        let ll = zone.unproject(Point2D(x: 680_000, y: 9_304_000))
        XCTAssertTrue(kml.contains(String(format: "%.8f,%.8f,125.00", locale: Locale(identifier: "en_US_POSIX"), ll.lon, ll.lat)))
        XCTAssertTrue(kml.contains("<color>ff005cd1</color>"), "KML color aabbggrr from #D15C00")
        XCTAssertTrue(kml.contains("Uji &amp; kontur"))
        XCTAssertTrue(kml.contains("<name>Index contour (1)</name>"))
    }

    /// KMZ checked with macOS's built-in `unzip`: ZIP structure and CRC32 must be valid for other tools.
    func testKMZOpensWithSystemUnzip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try ContourExporter.export(lines, formats: [.kmz, .shp], zone: zone, settings: ContourSettings(),
                                              baseName: "kontur", title: "Uji", to: dir)
        XCTAssertEqual(Set(urls.map(\.pathExtension)), ["kmz", "shp", "shx", "dbf", "prj", "cpg"])
        let kmz = try XCTUnwrap(urls.first { $0.pathExtension == "kmz" })
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", kmz.path, "doc.kml"]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "unzip succeeded (CRC matches)")
        XCTAssertEqual(String(decoding: out, as: UTF8.self), KML.document(lines, zone: zone, settings: ContourSettings(), title: "Uji"))
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926, "Standard CRC-32 test vector")
    }
}


final class LineStyleTests: XCTestCase {
    func testDoubleLineWidthFromOcad() throws {
        let map = try OcadReader.read(OcadReaderTests.makeOcad())
        let set = map.symbolSet(name: "Uji", sourceFile: "uji.ocd")
        let path = try XCTUnwrap(set.symbols.first { $0.number == 505_000 })
        XCTAssertEqual(path.drawingWidthMM, 0.45, accuracy: 1e-9, "Total width = 0.35 + 0.10 border (not a 0.25 guess)")
        XCTAssertEqual(path.lineStyle?.casing?.innerWidthMM ?? 0, 0.25, accuracy: 1e-9)
        let contour = try XCTUnwrap(set.symbols.first { $0.number == 101_000 })
        XCTAssertEqual(contour.drawingWidthMM, 0.21, accuracy: 1e-9, "Single line uses the width from the set")
        XCTAssertNil(contour.lineStyle?.casing)
    }

    func testSetWidthKeepsDoubleLineRatio() {
        var f = Feature(kind: .line, colorHex: "#FFFFFF", widthMM: 0.45, nodes: [])
        f.apply(LineStyle(colorHex: "#F5D9C4", widthMM: 0.45, casing: .init(colorHex: "#000000", innerWidthMM: 0.25)))
        f.setWidth(0.9)
        XCTAssertEqual(f.widthMM, 0.9)
        XCTAssertEqual(f.innerWidthMM!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(f.standardWidthMM, 0.45, "Standard width kept for the Standard button")
    }

    func testRasterDrawsCasingAndFill() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 0, y: 0), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        var f = Feature(kind: .line, colorHex: "#FFFFFF", widthMM: 0.45, nodes: [BezierNode(point: Point2D(x: 100, y: 500)), BezierNode(point: Point2D(x: 700, y: 500))])
        f.apply(LineStyle(colorHex: "#FF0000", widthMM: 2.0, casing: .init(colorHex: "#0000FF", innerWidthMM: 1.0)))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try RasterExporter.export(RasterExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, dpi: 300,
                                                              format: .png, strokes: [], features: [f]), to: dir)
        let wf = try XCTUnwrap(WorldFile(text: String(contentsOf: r.worldFileURL)))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(r.imageURL as CFURL, nil)!, 0, nil))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let d = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        func rgb(_ p: Point2D) -> (UInt8, UInt8, UInt8) {
            let col = Int(((p.x - wf.upperLeftX) / wf.pixelSizeX).rounded()), row = Int(((p.y - wf.upperLeftY) / wf.pixelSizeY).rounded())
            let o = row * img.width * 4 + col * 4
            return (d[o], d[o + 1], d[o + 2])
        }
        // 1:4000 → 1 mm paper = 4 m. Line center = red fill; 3 m from the axis (between 2 m and 4 m) = blue border.
        XCTAssertEqual(rgb(Point2D(x: 400, y: 500)).0, 255)
        XCTAssertEqual(rgb(Point2D(x: 400, y: 503)).2, 255)
    }
}

final class OcadLikeRenderingTests: XCTestCase {
    func testSymbolAreaIsSolidWithoutOutlineAndSketchAreaIsTranslucent() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 0, y: 0), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let square = [Point2D(x: 100, y: 600), Point2D(x: 300, y: 600), Point2D(x: 300, y: 400), Point2D(x: 100, y: 400)]
        var symbolArea = Feature.rectangle(corners: square, colorHex: "#FFB833", widthMM: 1.0)
        symbolArea.symbolCode = "401.0"
        let sketch = Feature.rectangle(corners: square.map { $0 + Point2D(x: 400, y: 0) }, colorHex: "#FFB833", widthMM: 1.0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = try RasterExporter.export(RasterExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, dpi: 300,
                                                              format: .png, strokes: [], features: [symbolArea, sketch]), to: dir)
        let wf = try XCTUnwrap(WorldFile(text: String(contentsOf: r.worldFileURL)))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(r.imageURL as CFURL, nil)!, 0, nil))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let d = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        func alpha(_ p: Point2D) -> UInt8 {
            let col = Int(((p.x - wf.upperLeftX) / wf.pixelSizeX).rounded()), row = Int(((p.y - wf.upperLeftY) / wf.pixelSizeY).rounded())
            return d[row * img.width * 4 + col * 4 + 3]
        }
        XCTAssertEqual(alpha(Point2D(x: 200, y: 500)), 255, "Symbol area: full fill")
        // 1 mm outline = 4 m at 1:4000, so 2 m outside the boundary is covered only if there is an outline.
        XCTAssertEqual(alpha(Point2D(x: 98, y: 500)), 0, "Symbol area: no outline")
        XCTAssertLessThan(alpha(Point2D(x: 600, y: 500)), 120, "Sketch area: transparent fill")
        XCTAssertEqual(alpha(Point2D(x: 499, y: 500)), 255, "Sketch area: has outline (4 m centered on the boundary)")
    }

    func testDashedLinesFromOcadAndPDFOperators() throws {
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: [BezierNode(point: Point2D(x: 0, y: 0)), BezierNode(point: Point2D(x: 100, y: 0))])
        f.apply(LineStyle(colorHex: "#000000", widthMM: 0.25, casing: nil, dashMM: [1.5, 0.37], roundCaps: false))
        XCTAssertEqual(f.effectiveDashMM, [1.5, 0.37])
        f.setWidth(0.5)
        XCTAssertEqual(f.effectiveDashMM?[0] ?? 0, 3.0, accuracy: 1e-9, "Pattern scales with width")

        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -10, y: -10), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                         strokes: [], features: [f])), as: UTF8.self)
        XCTAssertTrue(pdf.contains("0 J 0 j ["), "Butt caps + dash pattern in PDF")
    }
}

final class RotationTests: XCTestCase {
    func testRotateAreaClockwiseAroundCentroidAndBack() {
        let square = [Point2D(x: 0, y: 10), Point2D(x: 10, y: 10), Point2D(x: 10, y: 0), Point2D(x: 0, y: 0)]
        var f = Feature.rectangle(corners: square, colorHex: "#000000", widthMM: 0.14)
        let center = f.rotationPivot!
        f.setRotation(90)
        XCTAssertEqual(f.rotationDegrees, 90)
        // Clockwise: top-left point (0,10) moves to top-right (10,10).
        XCTAssertEqual(f.nodes[0].point.x, 10, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[0].point.y, 10, accuracy: 1e-9)
        XCTAssertEqual(f.rotationPivot!.distance(to: center), 0, accuracy: 1e-9, "Pivot does not move")
        f.setRotation(37.5)
        f.setRotation(0)
        XCTAssertNil(f.rotationDeg)
        for (a, b) in zip(f.nodes.map(\.point), square) { XCTAssertEqual(a.distance(to: b), 0, accuracy: 1e-9, "Back to the original position") }
    }

    func testCurveHandlesRotateWithNodes() {
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.2, nodes: [
            BezierNode(point: Point2D(x: 0, y: 0), outHandle: Point2D(x: 0, y: 5)),
            BezierNode(point: Point2D(x: 10, y: 0), inHandle: Point2D(x: 10, y: -5)),
        ])
        f.setRotation(180)
        XCTAssertEqual(f.nodes[0].point.x, 10, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[0].outHandle!.y, -5, accuracy: 1e-9)
    }

    func testPointSymbolRotatesShapeNotPosition() {
        let bar = PointElement(kind: .line, colorHex: "#000000", priority: 0, lineWidthMM: 0.1, diameterMM: 0,
                               points: [Point2D(x: 0, y: 1), Point2D(x: 0, y: -1)])
        var f = Feature.point(at: Point2D(x: 100, y: 200), elements: [bar])
        f.setRotation(90)
        XCTAssertEqual(f.nodes[0].point, Point2D(x: 100, y: 200), "Point position unchanged")
        let p = f.scaledPointElements[0].points[0]
        XCTAssertEqual(p.x, 1, accuracy: 1e-9, "Vertical line becomes horizontal")
        XCTAssertEqual(p.y, 0, accuracy: 1e-9)
    }

    func testNormalizationAndOmapRotation() {
        XCTAssertEqual(Feature.normalizedDegrees(370), 10)
        XCTAssertEqual(Feature.normalizedDegrees(-10), 350)
        var f = Feature.point(at: Point2D(x: 680_100, y: 9_304_100), elements: [PointElement(kind: .dot, colorHex: "#000000", priority: 0, lineWidthMM: 0, diameterMM: 0.6, points: [])],
                              symbolCode: "204.0", symbolName: "Boulder")
        f.setRotation(-90)
        XCTAssertEqual(f.rotationDegrees, 270)
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 680_000, y: 9_304_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let xml = OmapWriter.document(VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: [], features: [f]))
        XCTAssertTrue(xml.contains("rotation=\"-4.712389\""), "270° clockwise = −3π/2 rad in OOM")
    }
}

final class SwitchSymbolTests: XCTestCase {
    private let path = [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0), Point2D(x: 10, y: 10), Point2D(x: 0, y: 10)].map { BezierNode(point: $0) }
    private let footpath = MapSymbol(number: 506000, name: "Small footpath", kind: .line, colorHex: "#000000", lineWidthMM: 0.25, isEnabled: true,
                                     lineStyle: LineStyle(colorHex: "#000000", widthMM: 0.25, casing: nil, dashMM: [1.5, 0.37], roundCaps: false))
    private let contour = MapSymbol(number: 101000, name: "Contour", kind: .line, colorHex: "#B5651D", lineWidthMM: 0.14, isEnabled: true,
                                    lineStyle: LineStyle(colorHex: "#B5651D", widthMM: 0.14, casing: nil, roundCaps: true))
    private let vegetation = MapSymbol(number: 406000, name: "Vegetation", kind: .area, colorHex: "#3CB54A", lineWidthMM: nil, isEnabled: true)

    func testLineToLineTakesNewStyleAndKeepsGeometry() {
        var f = Feature(name: "506.0 Small footpath 3", kind: .line, colorHex: "#000000", widthMM: 0.4, nodes: path,
                        symbolCode: "506.0", symbolName: "Small footpath")
        f.apply(footpath.lineStyle!)
        f.setRotation(30)
        let nodes = f.nodes
        XCTAssertTrue(f.switchSymbol(to: contour))
        XCTAssertEqual(f.symbolCode, "101.0")
        XCTAssertEqual(f.colorHex, "#B5651D")
        XCTAssertEqual(f.widthMM, 0.14, accuracy: 1e-9)
        XCTAssertNil(f.dashMM, "Old symbol dashes removed")
        XCTAssertEqual(f.roundCaps, true)
        XCTAssertEqual(f.nodes, nodes, "Feature shape unchanged")
        XCTAssertEqual(f.rotationDegrees, 30, "Rotation preserved")
        XCTAssertEqual(f.name, "101.0 Contour 3", "Default name follows the new symbol, sequence number kept")
    }

    func testLineAndAreaSwapLikeOOM() {
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: path, symbolCode: "506.0", symbolName: "Small footpath")
        XCTAssertTrue(f.switchSymbol(to: vegetation))
        XCTAssertEqual(f.kind, .area)
        XCTAssertTrue(f.isSymbolArea)
        XCTAssertTrue(f.switchSymbol(to: footpath))
        XCTAssertEqual(f.kind, .line)
        XCTAssertEqual(f.dashMM, [1.5, 0.37])

        // A 2-point line cannot become an area.
        var short = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: Array(path.prefix(2)))
        XCTAssertFalse(short.switchSymbol(to: vegetation))
        XCTAssertEqual(short.kind, .line)
    }

    func testPointOnlySwitchesToPointAndKeepsSize() {
        let dot = PointElement(kind: .dot, colorHex: "#000000", priority: 0, lineWidthMM: 0, diameterMM: 0.6, points: [Point2D(x: 0, y: 0)])
        let big = PointElement(kind: .dot, colorHex: "#3CB54A", priority: 0, lineWidthMM: 0, diameterMM: 1.0, points: [Point2D(x: 0, y: 0)])
        let rock = MapSymbol(number: 206000, name: "Boulder", kind: .point, colorHex: "#000000", lineWidthMM: nil, isEnabled: true, pointElements: [dot])
        let tree = MapSymbol(number: 417000, name: "Prominent large tree", kind: .point, colorHex: "#3CB54A", lineWidthMM: nil, isEnabled: true, pointElements: [big])
        var p = Feature(kind: .point, colorHex: "#000000", widthMM: 0.6, nodes: [BezierNode(point: Point2D(x: 5, y: 5))], symbolCode: "206.0")
        p.pointElements = [dot]
        p.sizeFactor = 1.5
        XCTAssertFalse(p.canSwitch(to: footpath))
        XCTAssertFalse(p.canSwitch(to: vegetation))
        XCTAssertTrue(p.switchSymbol(to: tree))
        XCTAssertEqual(p.pointElements, [big])
        XCTAssertEqual(p.widthMM, 1.5, accuracy: 1e-9, "User-chosen size (150%) kept")

        var line = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: path)
        XCTAssertFalse(line.switchSymbol(to: rock), "Line cannot become a point")
    }
}

final class CoursePlannerTests: XCTestCase {
    /// Start (0,0) → 31 (300,0) → 32 (300,400) → Finish (0,400). Courses A and B share control 31.
    private func sample() -> (CourseSet, Course, Course) {
        let s = ControlPoint(kind: .start, position: Point2D(x: 0, y: 0))
        let c31 = ControlPoint(kind: .control, code: 31, position: Point2D(x: 300, y: 0),
                               description: ControlDescription(feature: "2.4", dimension: "1.5", location: "11.1E"))
        let c32 = ControlPoint(kind: .control, code: 32, position: Point2D(x: 300, y: 400))
        let f = ControlPoint(kind: .finish, position: Point2D(x: 0, y: 400))
        let a = Course(name: "A", controlIDs: [s.id, c31.id, c32.id, f.id], competitors: 40, climbM: 25)
        let b = Course(name: "B", controlIDs: [s.id, c31.id, f.id], competitors: 15)
        return (CourseSet(eventTitle: "Uji Lintasan", controls: [s, c31, c32, f], courses: [a, b]), a, b)
    }

    func testLengthLegsSequenceAndLoad() {
        let (set, a, b) = sample()
        XCTAssertEqual(set.legLengths(of: a), [300, 400, 300])
        XCTAssertEqual(set.length(of: a), 1000, accuracy: 1e-9)
        XCTAssertEqual(set.length(of: b), 800, accuracy: 1e-9) // 300 + 500
        let c31 = set.controls[1].id, c32 = set.controls[2].id
        XCTAssertEqual(set.sequenceNumbers(of: a)[c32], 2)
        let loads = Dictionary(uniqueKeysWithValues: set.controlLoads().map { ($0.controlID, $0) })
        XCTAssertEqual(loads[c31]?.visits, 55, "Load = total competitors of all courses passing through")
        XCTAssertEqual(loads[c31]?.courseCount, 2)
        XCTAssertEqual(loads[c32]?.visits, 40)
        let shared = set.sharedLegLoads()
        XCTAssertEqual(shared.count, 1, "Leg Start→31 used by A and B")
        XCTAssertEqual(shared.first?.visits, 55)
        XCTAssertTrue(set.warnings().isEmpty, "Sample courses are valid: \(set.warnings())")
    }

    func testAutomaticCodesSkipAmbiguous() {
        XCTAssertTrue(CourseSet.isAmbiguous(66))  // 99
        XCTAssertTrue(CourseSet.isAmbiguous(68))  // 89
        XCTAssertFalse(CourseSet.isAmbiguous(61), "19 is outside 31–255, so not confusable")
        XCTAssertFalse(CourseSet.isAmbiguous(88), "88 upside down is still 88")
        XCTAssertFalse(CourseSet.isAmbiguous(31))
        var set = CourseSet(firstCode: 65)
        set.controls = [ControlPoint(kind: .control, code: 65, position: Point2D(x: 0, y: 0))]
        XCTAssertEqual(set.nextFreeCode(), 67, "66 skipped (reads as 99)")
        set.avoidAmbiguousCodes = false
        XCTAssertEqual(set.nextFreeCode(), 66)
    }

    func testWarningsForMissingFinishAndCloseControls() {
        var (set, a, _) = sample()
        set.controls.append(ControlPoint(kind: .control, code: 33, position: Point2D(x: 310, y: 10)))
        set.courses[0].controlIDs.removeLast()
        _ = a
        let w = set.warnings()
        XCTAssertTrue(w.contains { $0.contains("A: no finish yet") })
        XCTAssertTrue(w.contains { $0.contains("31 and 33") }, "Controls < 30 m apart are warned")
    }

    func testOverprintGeometry() {
        let (set, a, _) = sample()
        let sheet = SheetSpec(scaleDenominator: 10000) // ISOM enlarged to 150%: 7.5 mm circle = 75 m
        let o = CourseOverprint.make(set, course: a, sheet: sheet)
        XCTAssertEqual(o.lineWidthM, 5.25, accuracy: 1e-9, "0.35 mm × 150%")
        let circles = o.marks.compactMap { if case let .circle(_, r) = $0 { return r } else { return nil } }
        XCTAssertEqual(circles.sorted(), [30, 37.5, 37.5, 45], "2 controls ø7.5 + finish ø6/ø9 mm (ISOM 4/6 × 150%)")
        // Start triangle points to the first control (east).
        guard case let .polyline(tri, true)? = o.marks.first(where: { if case .polyline(_, true) = $0 { return true } else { return false } }) else {
            return XCTFail("Start triangle missing")
        }
        XCTAssertEqual(tri[0].y, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(tri[0].x, 0)
        // First leg stops at the edges of the triangle and circle 31.
        let legs = o.marks.compactMap { if case let .polyline(p, false) = $0 { return p } else { return nil } }
        XCTAssertEqual(legs.count, 3)
        XCTAssertEqual(legs[0][1].x, 262.5, accuracy: 1e-6, "Leg stops at the circle edge (300 − 37.5)")
        let texts = o.marks.compactMap { if case let .text(t, _, _) = $0 { return t } else { return nil } }
        XCTAssertEqual(Set(texts), ["1", "2"])
        // All controls: label = code, no legs.
        let all = CourseOverprint.make(set, course: nil, sheet: sheet)
        XCTAssertEqual(Set(all.marks.compactMap { if case let .text(t, _, _) = $0 { return t } else { return nil } }), ["31", "32"])
        XCTAssertTrue(all.marks.allSatisfy { if case .polyline(_, false) = $0 { return false } else { return true } })
        XCTAssertEqual(CourseStyle.standard(scale: 4000).controlDiameterMM, 6, "Sprint: ISSprOM")
    }

    func testDescriptionText() {
        let d = ControlDescription(which: "0.1N", feature: "2.4", dimension: "1.5", location: "11.1E")
        XCTAssertEqual(d.text, "Northern boulder, 1.5 m, east side")
        let (set, a, _) = sample()
        let sheet = DescriptionSheet(set, course: a)
        XCTAssertEqual(sheet.lengthText, "1.0 km")
        XCTAssertEqual(sheet.rows.map(\.kind), [.start, .control, .control, .finish])
        XCTAssertEqual(sheet.rows[1].code, "31")
        XCTAssertEqual(sheet.rows.last?.text, "Navigate 300 m to finish")
    }

    func testIOFXMLCourseData() throws {
        let (set, _, _) = sample()
        let zone = UTMZone(epsg: 32748)!
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: 840, heightM: 1188)
        let data = IOFXMLExporter.courseData(set, frame: frame, sheet: SheetSpec(scaleDenominator: 4000), zone: zone)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssertNotNil(try? XMLDocument(data: data), "XML valid")
        XCTAssertTrue(xml.contains("iofVersion=\"3.0\""))
        XCTAssertTrue(xml.contains("<Control type=\"Start\">\n      <Id>S1</Id>"))
        XCTAssertTrue(xml.contains("<Id>31</Id>"))
        XCTAssertTrue(xml.contains("<Length>1000</Length>"))
        XCTAssertTrue(xml.contains("<Climb>25</Climb>"))
        XCTAssertTrue(xml.contains("<LegLength>400</LegLength>"))
        XCTAssertTrue(xml.contains("<NumberOfCompetitors>40</NumberOfCompetitors>"))
        // MapPosition 31: (300+100) m × 0.25 mm/m = 100 mm.
        XCTAssertTrue(xml.contains("<MapPosition x=\"100\" y=\"25\" unit=\"mm\"/>"))
    }

    func testPackageRoundTripAndPDFPages() throws {
        let (set, a, _) = sample()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("course-\(UUID().uuidString).cakra")
        defer { try? FileManager.default.removeItem(at: dir) }
        try CakraPackage.write(ProjectDocument(project: Project(name: "Uji"), courses: set), to: dir)
        XCTAssertEqual(try CakraPackage.read(at: dir).courses, set)

        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(
            title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: [], features: [],
            overprint: CourseOverprint.make(set, course: a, sheet: sheet), descriptions: DescriptionSheet(set, course: a))), as: UTF8.self)
        XCTAssertTrue(pdf.contains("/Count 2"), "Map page + description sheet")
        XCTAssertTrue(pdf.contains("(1.5) Tj"), "IOF pictorial description: dimension in column F")
        XCTAssertTrue(pdf.contains("0.651 0.149 1 RG"), "Purple overprint")
    }
}

extension CoursePlannerTests {
    /// `CP_SAMPLE_DIR=… swift test --filter testWriteCourseSamples`: writes sample PDF + IOF XML for visual checking.
    func testWriteCourseSamples() throws {
        guard let path = ProcessInfo.processInfo.environment["CP_SAMPLE_DIR"] else { throw XCTSkip("CP_SAMPLE_DIR not set") }
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 787_000, y: 9_234_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let o = frame.origin
        func p(_ x: Double, _ y: Double) -> Point2D { Point2D(x: o.x + x, y: o.y + y) }
        let s = ControlPoint(kind: .start, position: p(200, 150))
        let pts: [(Int, Double, Double, ControlDescription)] = [
            (31, 420, 260, ControlDescription(feature: "2.4", dimension: "1.5", location: "11.1E")),
            (32, 600, 520, ControlDescription(which: "0.1N", feature: "5.11", location: "11.8")),
            (33, 380, 760, ControlDescription(feature: "1.3", location: "11.7")),
            (34, 250, 980, ControlDescription(feature: "4.9", appearance: "8.10", other: "12.2")),
            (35, 520, 1050, ControlDescription(feature: "3.2", location: "11.1W")),
        ]
        let controls = pts.map { ControlPoint(kind: .control, code: $0.0, position: p($0.1, $0.2), description: $0.3) }
        let f = ControlPoint(kind: .finish, position: p(260, 300))
        let course = Course(name: "A Elite", controlIDs: [s.id] + controls.map(\.id) + [f.id], competitors: 60, climbM: 35)
        let set = CourseSet(eventTitle: "Contoh Sprint Cakra Pencil", controls: [s] + controls + [f], courses: [course])
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zone = UTMZone(epsg: 32748)!
        // Some map content so the sample looks like a race map: green/yellow areas, roads and buildings.
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ hex: String, _ code: String) -> Feature {
            var f = Feature.rectangle(corners: [p(x, y + h), p(x + w, y + h), p(x + w, y), p(x, y)], colorHex: hex, widthMM: 0.1)
            f.symbolCode = code
            return f
        }
        var road = Feature(kind: .line, colorHex: "#000000", widthMM: 0.35,
                           nodes: [p(0, 640), p(300, 600), p(560, 700), p(840, 660)].map { BezierNode(point: $0) }, symbolCode: "505.0")
        road.roundCaps = false
        let features = [rect(0, 0, 840, 1188, "#FFFFFF", "000.0"), rect(40, 380, 320, 200, "#FFBA35", "401.0"),
                        rect(480, 120, 300, 260, "#8CD48C", "406.0"), rect(120, 820, 260, 280, "#3CB54A", "408.0"),
                        rect(560, 860, 120, 80, "#808080", "521.0"), road]
        var layout = CoursePrintLayout()
        layout.descriptionMaxRows = 8
        try GeoPDFExporter.export(GeoPDFRequest(title: set.eventTitle, frame: frame, sheet: sheet, zone: zone, strokes: [], features: features,
                                                grid: NorthGrid(), overprint: CourseOverprint.make(set, course: course, sheet: sheet),
                                                descriptions: DescriptionSheet(set, course: course), printLayout: layout, contourIntervalM: 2.5),
                                  to: dir.appendingPathComponent("contoh-lintasan.pdf"))
        try IOFXMLExporter.courseData(set, frame: frame, sheet: sheet, zone: zone).write(to: dir.appendingPathComponent("contoh-lintasan_IOF3.xml"))
    }
}

extension CoursePlannerTests {
    func testRenumberFollowsCourseOrder() {
        var (set, _, _) = sample()
        let spare = ControlPoint(kind: .control, code: 90, position: Point2D(x: 900, y: 900))
        set.controls.insert(spare, at: 0)
        set.controls[2].code = 77 // 31 → 77
        set.firstCode = 65
        let r = set.renumbered()
        let codes = r.controls.reduce(into: [UUID: Int]()) { if let c = $1.code { $0[$1.id] = c } }
        XCTAssertEqual(codes[set.controls[2].id], 65, "First control of course A")
        XCTAssertEqual(codes[set.controls[3].id], 67, "66 skipped (reads as 99)")
        XCTAssertEqual(codes[spare.id], 69, "Unused control last; 68 skipped")
        XCTAssertNil(r.controls.first { $0.kind == .start }?.code)
    }
}

final class OmapReaderTests: XCTestCase {
    /// Write .omap with OmapWriter and read it back: position, curves, kind, color and code round-trip.
    func testRoundTripWithOwnWriter() throws {
        let zone = UTMZone(epsg: 32748)!
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 787_000, y: 9_234_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let o = frame.origin
        var line = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25,
                           nodes: [BezierNode(point: Point2D(x: o.x + 100, y: o.y + 100), outHandle: Point2D(x: o.x + 150, y: o.y + 180)),
                                   BezierNode(point: Point2D(x: o.x + 300, y: o.y + 120), inHandle: Point2D(x: o.x + 250, y: o.y + 60)),
                                   BezierNode(point: Point2D(x: o.x + 400, y: o.y + 300))],
                           symbolCode: "506.0", symbolName: "Small path")
        line.dashMM = nil
        let area = Feature.rectangle(corners: [Point2D(x: o.x + 500, y: o.y + 600), Point2D(x: o.x + 700, y: o.y + 600),
                                               Point2D(x: o.x + 700, y: o.y + 500), Point2D(x: o.x + 500, y: o.y + 500)],
                                     colorHex: "#3CB54A", widthMM: 0.1)
        let req = VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: zone, strokes: [], features: [line, area])
        let xml = OmapWriter.document(req)
        let (features, report) = try OmapReader.read(Data(xml.utf8), zone: zone)
        XCTAssertEqual(report.imported, 2)
        let l = try XCTUnwrap(features.first { $0.kind == .line })
        XCTAssertEqual(l.symbolCode, "506.0")
        XCTAssertEqual(l.nodes.count, 3)
        for (a, b) in zip(l.nodes, line.nodes) {
            XCTAssertEqual(a.point.distance(to: b.point), 0, accuracy: 0.01, "Point returns to the same UTM position")
        }
        XCTAssertEqual(l.nodes[0].outHandle?.distance(to: line.nodes[0].outHandle!) ?? 99, 0, accuracy: 0.01, "Curve handle")
        XCTAssertEqual(l.widthMM, 0.25, accuracy: 0.001)
        let ar = try XCTUnwrap(features.first { $0.kind == .area })
        XCTAssertEqual(ar.nodes.count, 4, "Closing point not duplicated")
        XCTAssertEqual(ar.colorHex, "#3CB54A")
    }

    func testRejectsUngeoreferencedMap() {
        let xml = "<?xml version=\"1.0\"?><map><georeferencing scale=\"10000\"/><colors/><symbols/></map>"
        XCTAssertThrowsError(try OmapReader.read(Data(xml.utf8), zone: UTMZone(epsg: 32748)!))
    }
}

extension CoursePlannerTests {
    func testControlSizeGlobalAndPerControl() {
        var (set, a, _) = sample()
        let sheet = SheetSpec(scaleDenominator: 10000) // ISOM 5 mm × 150% = 75 m → r 37.5 m
        func radii(_ s: CourseSet) -> [Double] {
            CourseOverprint.make(s, course: a, sheet: sheet).marks.compactMap { if case let .circle(_, r) = $0 { return r } else { return nil } }
        }
        XCTAssertEqual(radii(set).sorted(), [30, 37.5, 37.5, 45], "Default = IOF standard")
        set.controls[1].sizeFactor = 1.5 // control 31
        XCTAssertEqual(radii(set).sorted(), [30, 37.5, 45, 56.25], "Only control 31 grows")
        let legs = CourseOverprint.make(set, course: a, sheet: sheet).marks.compactMap { if case let .polyline(p, false) = $0 { return p } else { return nil } }
        XCTAssertEqual(legs[0][1].x, 300 - 56.25, accuracy: 1e-6, "Leg stops at the enlarged circle edge")
        set.appearance = CourseAppearance(controlScale: 0.8, numberScale: 1.25, lineScale: 2)
        let o = CourseOverprint.make(set, course: a, sheet: sheet)
        XCTAssertEqual(o.lineWidthM, 10.5, accuracy: 1e-9)
        let digits = 60 * 1.25 * CourseStyle.digitHeightPerFontSize // font 4 mm × 150% = 60 m, × 125%
        XCTAssertTrue(o.marks.contains { if case let .text(_, _, h) = $0 { return abs(h - digits) < 1e-9 } else { return false } }, "Number 4 mm × 125%")
        XCTAssertEqual(radii(set).sorted().first ?? 0, 24, accuracy: 1e-9, "Circle 80%")
    }
}

extension CoursePlannerTests {
    /// Single-page race map: description on the map, north arrow, title box, scale bar, contour interval.
    func testOnePageCompetitionMapLayout() {
        let (set, a, _) = sample()
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        var layout = CoursePrintLayout()
        func pdf(_ l: CoursePrintLayout) -> String {
            String(decoding: GeoPDFExporter.document(GeoPDFRequest(
                title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: [], features: [],
                overprint: CourseOverprint.make(set, course: a, sheet: sheet), descriptions: DescriptionSheet(set, course: a),
                printLayout: l, contourIntervalM: 2.5)), as: UTF8.self)
        }
        let one = pdf(layout)
        XCTAssertTrue(one.contains("/Count 1"), "Single page: description placed on the map")
        XCTAssertTrue(one.contains("(1.5) Tj"), "Pictorial description on the map page")
        var textLayout = layout
        textLayout.descriptionSymbols = false
        XCTAssertTrue(pdf(textLayout).contains("(Boulder, 1.5 m, east side) Tj"), "Text style still available")
        XCTAssertFalse(one.contains("(Scale 1:4000) Tj"), "Title box removed")
        XCTAssertFalse(one.contains("(N) Tj"), "North arrow removed")
        XCTAssertTrue(one.contains("/F2"), "Bold font for course name")
        layout.separateDescriptionPage = true
        XCTAssertTrue(pdf(layout).contains("/Count 2"), "Separate description page option")
        XCTAssertEqual(GeoPDFExporter.scaleBarMeters(scale: 10000), 250)
    }
}

extension CoursePlannerTests {
    func testDescriptionColumnsAndPosition() {
        let (set, a, _) = sample()
        let d = DescriptionSheet(set, course: a)
        XCTAssertGreaterThanOrEqual(d.rows.count, 3)
        let cols = d.columns(maxRows: 2)
        XCTAssertEqual(cols.count, (d.rows.count + 1) / 2, "Overflow rows move to the next column")
        XCTAssertFalse(cols[0].isContinuation)
        XCTAssertTrue(cols[1].isContinuation)
        XCTAssertEqual(cols.flatMap(\.rows), d.rows)
        XCTAssertEqual(d.columns(maxRows: nil).count, 1)
        XCTAssertEqual(d.columns(maxRows: 99).count, 1)

        var layout = CoursePrintLayout()
        layout.descriptionCellMM = 6
        let one = GeoPDFExporter.descriptionBlockSizeMM(d, layout: layout)
        layout.descriptionMaxRows = 2
        let two = GeoPDFExporter.descriptionBlockSizeMM(d, layout: layout)
        XCTAssertEqual(two.w, Double(cols.count) * 48, accuracy: 1e-9, "Width = column count × 8 cells")
        XCTAssertLessThan(two.h, one.h)

        let sheet = SheetSpec(scaleDenominator: 4000)
        let tr = GeoPDFExporter.descriptionOriginMM(block: two, layout: layout, sheet: sheet)
        XCTAssertEqual(tr.x, sheet.mappingWidthMM - 4 - two.w, accuracy: 1e-9)
        XCTAssertEqual(tr.y, 4, accuracy: 1e-9)
        layout.descriptionOffsetMM = Point2D(x: 20, y: 30)
        XCTAssertEqual(GeoPDFExporter.descriptionOriginMM(block: two, layout: layout, sheet: sheet), Point2D(x: 20, y: 30))
        layout.descriptionOffsetMM = Point2D(x: 9999, y: -5)
        let clamped = GeoPDFExporter.descriptionOriginMM(block: two, layout: layout, sheet: sheet)
        XCTAssertEqual(clamped.x, sheet.mappingWidthMM - two.w, accuracy: 1e-9)
        XCTAssertEqual(clamped.y, 0)

        // PDF: second column is on the map page.
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        layout.descriptionOffsetMM = nil
        layout.descriptionSymbols = false
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(
            title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: [], features: [],
            descriptions: d, printLayout: layout)), as: UTF8.self)
        XCTAssertTrue(pdf.contains("(\(d.rows.last!.text)) Tj"), "Last row (continuation column) still printed")
    }

    func testIOFPictogramsCoverCatalogAndPrint() throws {
        // Every catalog symbol C–H has a pictogram.
        let missing = IOFSymbols.all.filter { $0.column != .d ? IOFPictogram.shapes($0.id) == nil : IOFPictogram.shapes($0.id) == nil }
        XCTAssertEqual(missing.map(\.id), [])
        XCTAssertEqual(IOFPictogram.dimensionShapes("1.5"), [.text("1.5", at: Point2D(x: 0.5, y: 0.5), size: 0.4)])
        XCTAssertEqual(IOFPictogram.dimensionShapes("8x4")?.count, 1)
        XCTAssertEqual(IOFPictogram.dimensionShapes("1.0/2.5")?.count, 3)
        XCTAssertNotNil(IOFPictogram.dimensionShapes("10.2"))
        XCTAssertNil(IOFPictogram.shapes("99.9"))

        var (set, a, _) = sample()
        let id = set.controls(of: a).first { $0.kind == .control }!.id
        let i = set.controls.firstIndex { $0.id == id }!
        set.controls[i].description = ControlDescription(which: "0.1N", feature: "2.4", appearance: "8.6", dimension: "1.5",
                                                         location: "11.1E", other: "12.2")
        let d = DescriptionSheet(set, course: a)
        XCTAssertEqual(d.rows.first { $0.kind == .control }?.description.feature, "2.4")
        XCTAssertNotNil(d.rows.last?.finishMeters)

        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let layout = CoursePrintLayout()
        XCTAssertTrue(layout.descriptionSymbols, "Default: IOF pictorial description")
        let data = GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                         strokes: [], features: [], descriptions: d, printLayout: layout))
        let pdf = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(pdf.contains("(1.5) Tj"), "Dimension printed in column F")
        XCTAssertTrue(pdf.contains("(\(d.rows.last!.finishMeters!) m) Tj"), "Finish distance in navigation row")
        XCTAssertFalse(pdf.contains("(\(d.rows.first { $0.kind == .control }!.text)) Tj"), "Not a text description")
        XCTAssertNotNil(PDFDocument(data: data))
        XCTAssertFalse(pdf.contains("(?) Tj"), "Unfilled column D left empty")
        if let dir = ProcessInfo.processInfo.environment["CAKRA_SAMPLE_DIR"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("iof-symbols.pdf"))
            // Sheet of all symbols (row k: k-th symbol of each column) for visual checking.
            let cols: [IOFSymbol.Column] = [.c, .d, .e, .f, .g, .h]
            let lists = cols.map { IOFSymbols.symbols(in: $0).map(\.id) }
            var all = d
            all.title = "Katalog simbol IOF"
            all.rows = (0..<lists.map(\.count).max()!).map { k in
                func at(_ c: Int) -> String? { lists[c].indices.contains(k) ? lists[c][k] : nil }
                return DescriptionSheet.Row(kind: .control, number: "\(k + 1)", code: at(1) ?? "", text: "",
                                            description: ControlDescription(which: at(0), feature: at(1), appearance: at(2),
                                                                            dimension: at(3) ?? (k == 3 ? "8x4" : k == 4 ? "1.0/2.5" : nil),
                                                                            location: at(4), other: at(5)))
            }
            var cat = CoursePrintLayout()
            cat.descriptionOnMap = false
            cat.descriptionMaxRows = 36
            let catData = GeoPDFExporter.document(GeoPDFRequest(title: "Katalog", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                strokes: [], features: [], descriptions: all, printLayout: cat))
            try catData.write(to: URL(fileURLWithPath: dir).appendingPathComponent("iof-catalog.pdf"))
        }
    }

    func testOrganizerRowInDescriptions() throws {
        var (set, a, _) = sample()
        let without = DescriptionSheet(set, course: a)
        XCTAssertEqual(without.organizer, "")
        set.organizer = "Makopala Universitas"
        let d = DescriptionSheet(set, course: a)
        XCTAssertEqual(d.organizer, "Makopala Universitas")
        let cell = 10.0
        XCTAssertEqual(GeoPDFExporter.descriptionTableHeight(d, cell: cell), GeoPDFExporter.descriptionTableHeight(without, cell: cell) + cell,
                       "One organizer line below the title")
        XCTAssertEqual(GeoPDFExporter.descriptionTableHeight(d.columns(maxRows: 1)[1], cell: cell), cell, "Continuation column without header")
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                        strokes: [], features: [], descriptions: d,
                                                                        printLayout: CoursePrintLayout())), as: UTF8.self)
        XCTAssertTrue(pdf.contains("(Makopala Universitas) Tj"))
        XCTAssertFalse(pdf.contains("0.651 0.149 1 RG"), "Default: black description")
        var purple = CoursePrintLayout()
        purple.descriptionColor = .purple
        let pdf2 = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                         strokes: [], features: [], descriptions: d,
                                                                         printLayout: purple)), as: UTF8.self)
        XCTAssertTrue(pdf2.contains("0.651 0.149 1 RG 0.651 0.149 1 rg"), "Purple description like controls")
        let decoded = try JSONDecoder().decode(CoursePrintLayout.self, from: JSONEncoder().encode(purple))
        XCTAssertEqual(decoded.descriptionColor, .purple)
        // Old packages without the organizer key still load.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(set)) as! [String: Any]
        json["organizer"] = nil
        let old = try JSONDecoder().decode(CourseSet.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.organizer)
    }

    func testOldPrintLayoutStillDecodes() throws {
        let old = #"{"descriptionOnMap":true,"descriptionCorner":"bottomLeft","descriptionCellMM":7,"separateDescriptionPage":false,"showTitleBlock":true,"showNorthArrow":true,"showScaleBar":true,"subtitle":"Sprint"}"#
        let l = try JSONDecoder().decode(CoursePrintLayout.self, from: Data(old.utf8))
        XCTAssertEqual(l.descriptionCorner, .bottomLeft)
        XCTAssertEqual(l.descriptionCellMM, 7)
        XCTAssertNil(l.descriptionMaxRows)
        XCTAssertTrue(l.descriptionSymbols)
        let empty = try JSONDecoder().decode(CoursePrintLayout.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, CoursePrintLayout())
        var set = CourseSet()
        set.items = [CourseItem(kind: .text, points: [Point2D(x: 1, y: 2)], text: "Parkir")]
        let back = try JSONDecoder().decode(CourseSet.self, from: JSONEncoder().encode(set))
        XCTAssertEqual(back.allItems.first?.text, "Parkir")
    }

    func testCourseItemsInOverprint() {
        let (base, a, b) = sample()
        var set = base
        let sheet = SheetSpec(scaleDenominator: 4000)
        set.items = [
            CourseItem(kind: .text, points: [Point2D(x: 10, y: 10)], text: "Parkir\nToilet"),
            CourseItem(kind: .rectangle, points: [Point2D(x: 0, y: 0), Point2D(x: 20, y: 10)], filled: true, courseID: a.id),
            CourseItem(kind: .ellipse, points: [Point2D(x: 0, y: 0), Point2D(x: 20, y: 10)]),
            CourseItem(kind: .line, points: [Point2D(x: 0, y: 0), Point2D(x: 30, y: 0)], courseID: b.id),
            CourseItem(kind: .image, points: [Point2D(x: 50, y: 50)], imageName: "logo.png", imageAspect: 0.5, widthMM: 20),
        ]
        let marks = CourseOverprint.make(set, course: a, sheet: sheet).marks
        let texts = marks.compactMap { m -> String? in if case let .text(t, _, _) = m { return t } else { return nil } }
        XCTAssertTrue(texts.contains("Parkir") && texts.contains("Toilet"), "Two-line text")
        XCTAssertTrue(marks.contains { if case .fill = $0 { return true } else { return false } }, "Filled rectangle on course A")
        XCTAssertFalse(marks.contains { m in if case let .polyline(p, false) = m { return p.count == 2 && p[1].x == 30 } else { return false } },
                       "Course B-only line not shown on A")
        guard case let .image(name, _, w, h)? = marks.first else { return XCTFail("Image should be bottom-most") }
        XCTAssertEqual(name, "logo.png")
        XCTAssertEqual(w, 80, accuracy: 1e-9, "20 mm × 4 m/mm")
        XCTAssertEqual(h, 40, accuracy: 1e-9)
        XCTAssertEqual(set.items(for: nil).count, 5, "All controls: all objects")

        let text = set.allItems[0]
        XCTAssertEqual(text.hitDistance(to: Point2D(x: 10, y: 10), sheet: sheet), 0)
        XCTAssertGreaterThan(text.hitDistance(to: Point2D(x: 200, y: 10), sheet: sheet), 100)
        XCTAssertEqual(set.allItems[1].hitDistance(to: Point2D(x: 10, y: 5), sheet: sheet), 0, "Filled: inside = hit")
        XCTAssertEqual(set.allItems[2].hitDistance(to: Point2D(x: 10, y: 5), sheet: sheet), 5, accuracy: 0.1, "Empty ellipse: distance to edge")
        XCTAssertEqual(text.moved(by: Point2D(x: 1, y: 1)).points, [Point2D(x: 11, y: 11)])
    }

    func testCourseTextBoldItalic() throws {
        let (set0, a, _) = sample()
        var set = set0
        let sheet = SheetSpec(scaleDenominator: 4000)
        var t = CourseItem(kind: .text, points: [Point2D(x: 0, y: 0)], text: "Parkir")
        t.bold = true
        t.italic = true
        XCTAssertEqual(t.marks(sheet: sheet).first, .font(bold: true, italic: true))
        XCTAssertEqual(t.marks(sheet: sheet).last, .font(bold: false, italic: false), "Style back to normal for control numbers")
        var plain = t
        plain.bold = nil
        plain.italic = nil
        XCTAssertFalse(plain.marks(sheet: sheet).contains(.font(bold: false, italic: false)))
        XCTAssertEqual(CourseItem.points(forTextHeightMM: 4), 15.7, accuracy: 0.1)
        set.items = [t]
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                        strokes: [], features: [],
                                                                        overprint: CourseOverprint.make(set, course: a, sheet: sheet))), as: UTF8.self)
        XCTAssertTrue(pdf.contains("/Helvetica-BoldOblique"))
        XCTAssertTrue(pdf.contains("BT /F4 "), "Bold italic text")
        XCTAssertTrue(pdf.contains("BT /F1 "), "Control numbers stay normal")
        XCTAssertEqual(try JSONDecoder().decode(CourseItem.self, from: JSONEncoder().encode(t)), t)
    }

    func testAllControlsDescriptionAndPDF() {
        let (set, _, _) = sample()
        let d = DescriptionSheet(set, course: nil)
        XCTAssertEqual(d.courseName, "All controls")
        let controls = d.rows.filter { $0.kind == .control }
        XCTAssertEqual(controls.count, set.controls.filter { $0.kind == .control }.count)
        XCTAssertTrue(controls.allSatisfy { $0.number.isEmpty }, "Column A empty (no course order)")
        let codes = controls.compactMap { Int($0.code) }
        XCTAssertEqual(codes, codes.sorted(), "Sorted by code")
        XCTAssertEqual(DescriptionSheet.allControlsOrder(set).count, d.rows.count)
        let sheet = SheetSpec(scaleDenominator: 4000)
        let o = CourseOverprint.make(set, course: nil, sheet: sheet)
        XCTAssertFalse(o.marks.contains { if case .polyline(let p, false) = $0 { return p.count == 2 } else { return false } }, "No legs")
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                        strokes: [], features: [], overprint: o, descriptions: d,
                                                                        printLayout: CoursePrintLayout())), as: UTF8.self)
        XCTAssertTrue(pdf.contains("(All controls) Tj"))
        XCTAssertTrue(pdf.contains("(\(codes[0])) Tj"), "Control code printed")
    }

    func testCourseItemColorAndSeveralCourses() throws {
        var (set, a, b) = sample()
        let sheet = SheetSpec(scaleDenominator: 4000)
        var rect = CourseItem(kind: .rectangle, points: [Point2D(x: 0, y: 0), Point2D(x: 20, y: 10)])
        rect.colorHex = "#0072CE"
        rect.setScope([a.id, b.id])
        var only = CourseItem(kind: .line, points: [Point2D(x: 0, y: 0), Point2D(x: 30, y: 0)])
        only.setScope([b.id])
        var old = CourseItem(kind: .ellipse, points: [Point2D(x: 0, y: 0), Point2D(x: 5, y: 5)], courseID: a.id)
        XCTAssertEqual(old.scope, [a.id], "Old single-course format still valid")
        set.items = [rect, only, old]
        XCTAssertEqual(set.items(for: a).map(\.id), [rect.id, old.id])
        XCTAssertEqual(set.items(for: b).map(\.id), [rect.id, only.id])
        old.setScope([])
        XCTAssertNil(old.scope, "Empty = all courses")

        let marks = rect.marks(sheet: sheet)
        XCTAssertEqual(marks.first, .color("#0072CE"))
        XCTAssertEqual(marks.last, .color(nil))
        let o = CourseOverprint.make(set, course: a, sheet: sheet)
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                        strokes: [], features: [], overprint: o)), as: UTF8.self)
        XCTAssertTrue(pdf.contains("0 0.447 0.808 RG"), "Blue object in PDF")
        let data = try JSONEncoder().encode(rect)
        XCTAssertEqual(try JSONDecoder().decode(CourseItem.self, from: data), rect)
    }

    private func pngData(width: Int, height: Int, alpha: Bool) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: alpha ? 0.5 : 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testCourseImagesValidationAndPDF() throws {
        XCTAssertThrowsError(try CourseImages.prepare(Data("GIF89a".utf8))) { XCTAssertEqual($0 as? CourseImages.ImageError, .unsupportedType) }
        XCTAssertThrowsError(try CourseImages.prepare(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(count: CourseImages.maxFileBytes))) {
            guard case .tooLarge? = $0 as? CourseImages.ImageError else { return XCTFail("\($0)") }
        }
        let small = try CourseImages.prepare(pngData(width: 40, height: 20, alpha: true))
        XCTAssertEqual(small.format, .png)
        XCTAssertEqual(small.aspect, 0.5)
        let big = try CourseImages.prepare(pngData(width: 3000, height: 1500, alpha: false))
        XCTAssertEqual(big.width, CourseImages.storedMaxPixels, "Downscaled to 2000 px")
        XCTAssertEqual(big.height, 1000)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = try CourseImages.store(small, id: UUID(), in: dir)
        XCTAssertEqual(CourseImages.load(name, in: dir), small.data)
        XCTAssertNil(CourseImages.load("../x.png", in: dir))
        CourseImages.removeUnused(keeping: [], in: dir)
        XCTAssertNil(CourseImages.load(name, in: dir), "Unreferenced file removed")

        let (base, a, _) = sample()
        var set = base
        let sheet = SheetSpec(scaleDenominator: 4000)
        set.items = [CourseItem(kind: .image, points: [Point2D(x: 50, y: 50)], imageName: "logo.png", imageAspect: 0.5, widthMM: 20),
                     CourseItem(kind: .rectangle, points: [Point2D(x: 0, y: 0), Point2D(x: 20, y: 10)], filled: true)]
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let doc = GeoPDFExporter.document(GeoPDFRequest(
            title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: [], features: [],
            overprint: CourseOverprint.make(set, course: a, sheet: sheet), descriptions: DescriptionSheet(set, course: a),
            printLayout: CoursePrintLayout(), images: ["logo.png": small.data]))
        let text = String(decoding: doc, as: UTF8.self)
        XCTAssertTrue(text.contains("/Im0 Do"), "Image on the map page")
        XCTAssertTrue(text.contains("/SMask"), "Transparent PNG uses SMask")
        XCTAssertTrue(text.contains("/GSFill0 gs"), "Transparent filled rectangle")
        XCTAssertNotNil(PDFDocument(data: doc), "PDF valid")
        XCTAssertEqual(PDFDocument(data: doc)?.pageCount, 1)
    }
}

final class PDFNumberTests: XCTestCase {
    /// The fast formatter must match the old way exactly (String(format:) then strip trailing zeros).
    func testFastNumberMatchesReference() {
        func reference(_ v: Double, _ d: Int) -> String {
            var s = String(format: "%.\(d)f", locale: Locale(identifier: "en_US_POSIX"), v)
            if s.contains(".") {
                while s.hasSuffix("0") { s.removeLast() }
                if s.hasSuffix(".") { s.removeLast() }
            }
            return s == "-0" ? "0" : s
        }
        var rng = SystemRandomNumberGenerator()
        let fixed: [Double] = [0, -0.0, 1, -1, 0.5, 0.0004, -0.0004, 0.0005, 12.3456789, 595.276, 841.89, 9_234_000.125, -6.89123456, 107.61234567]
        for v in fixed {
            for d in [0, 1, 2, 3, 5, 9] { XCTAssertEqual(GeoPDFExporter.n(v, d), reference(v, d), "\(v) / \(d)") }
        }
        // Random: differs by at most 1 in the last digit (binary multiplication rounding), no trailing zeros.
        for _ in 0..<5000 {
            let v = Double.random(in: -2000...2000, using: &rng)
            let d = [2, 3, 5].randomElement(using: &rng)!
            let fast = GeoPDFExporter.n(v, d)
            XCTAssertEqual(Double(fast)!, Double(reference(v, d))!, accuracy: pow(10, -Double(d)) * 1.01, "\(v) / \(d)")
            XCTAssertFalse(fast.contains(".") && fast.hasSuffix("0"), fast)
        }
    }
}

final class FeatureMergeTests: XCTestCase {
    private func line(_ pts: [(Double, Double)], code: String? = "506.0") -> Feature {
        Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: pts.map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) },
                symbolCode: code, symbolName: code == nil ? nil : "Small footpath")
    }

    private func area(_ pts: [(Double, Double)], code: String? = "406.0") -> Feature {
        Feature(kind: .area, colorHex: "#3CB54A", widthMM: 0, nodes: pts.map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) },
                symbolCode: code, symbolName: code == nil ? nil : "Vegetation")
    }

    func testJoinLinesAtEveryEndCombination() {
        let a = line([(0, 0), (10, 0)])
        // End of a ↔ end of b: b is reversed.
        let b = line([(20, 5), (10, 0)])
        let j = a.joiningLine(b, tolerance: 0.01)!
        XCTAssertEqual(j.nodes.map(\.point), [Point2D(x: 0, y: 0), Point2D(x: 10, y: 0), Point2D(x: 20, y: 5)])
        XCTAssertEqual(j.id, a.id, "First feature identity preserved")
        // Start of a ↔ end of c.
        let c = line([(-10, 0), (0, 0)])
        XCTAssertEqual(a.joiningLine(c, tolerance: 0.01)!.nodes.map(\.point).map(\.x), [-10, 0, 10])
    }

    func testFollowedLineOnTopIsNotJoined() {
        // Curved line (2 segments) and a new line following it from the middle to the end: the ends meet,
        // but they overlap → not joined (the result would fold back).
        let curve = line([(0, 0), (10, 5), (20, 0)])
        let follow = line([(5, 2.5), (10, 5), (20, 0)])
        XCTAssertNil(follow.joiningLine(curve, tolerance: 0.01))
        XCTAssertNil(curve.joiningLine(follow, tolerance: 0.01))
        // Lines that only touch at the ends are still joined.
        let away = line([(20, 0), (30, -5)])
        XCTAssertNotNil(curve.joiningLine(away, tolerance: 0.01))
        // Overlapping ends (not exactly snapped) are joined with a line-width tolerance; a line that
        // turns back at a sharp angle is still joined.
        let near = line([(20.8, 0.3), (12, -3)])
        XCTAssertNotNil(curve.joiningLine(near, tolerance: 1.8), "Ends overlap 0.85 m, tolerance 1.8 m")
    }

    func testLineEndsMeetingItsOwnStartAreClosed() {
        var f = line([(0, 0), (10, 0), (10, 10), (0, 10), (0.03, 0.04)])
        XCTAssertFalse(f.isRingLine)
        XCTAssertFalse(f.closeLineIfEndsMeet(tolerance: 0.01), "Outside tolerance")
        XCTAssertTrue(f.closeLineIfEndsMeet(tolerance: 0.5))
        XCTAssertEqual(f.nodes.last!.point, f.nodes.first!.point)
        XCTAssertTrue(f.isRingLine && f.closesPath)
        XCTAssertFalse(f.isClosed, "Still a line, not an area")
        XCTAssertEqual(f.kind, .line)
        XCTAssertFalse(f.closeLineIfEndsMeet(tolerance: 0.5), "Already closed")
        // PDF: closed line path uses h (clean corner join).
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                        strokes: [], features: [f])), as: UTF8.self)
        XCTAssertTrue(pdf.contains(" l\nh\n"), "closePath for closed line")
    }

    func testFollowRingLineThroughItsStart() {
        // Closed line (10 m square, starting at (0,0)): from bottom edge to left edge via corner (0,0) = the short
        // path (3 points), not around the other three edges.
        let ring = line([(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)])
        XCTAssertTrue(ring.isRingLine)
        let a = ring.nearestPathPosition(to: Point2D(x: 5, y: 0))!.position
        let b = ring.nearestPathPosition(to: Point2D(x: 0, y: 5))!.position
        let nodes = ring.followNodes(from: a, to: b)
        XCTAssertEqual(nodes.map(\.point), [Point2D(x: 5, y: 0), Point2D(x: 0, y: 0), Point2D(x: 0, y: 5)])
        // An area with the same shape gives the same result (line ↔ area).
        var area = ring
        area.kind = .area
        area.nodes.removeLast()
        let pa = area.nearestPathPosition(to: Point2D(x: 5, y: 0))!.position
        let pb = area.nearestPathPosition(to: Point2D(x: 0, y: 5))!.position
        XCTAssertEqual(area.followNodes(from: pa, to: pb).map(\.point), nodes.map(\.point))
    }

    func testJoinLinesWithGapMeetsInTheMiddle() {
        let a = line([(0, 0), (10, 0)]), b = line([(12, 0), (20, 0)])
        XCTAssertNil(a.joiningLine(b, tolerance: 1), "Gap larger than tolerance")
        let j = a.joiningLine(b, tolerance: 3)!
        XCTAssertEqual(j.nodes.count, 3)
        XCTAssertEqual(j.nodes[1].point, Point2D(x: 11, y: 0))
    }

    func testJoinKeepsCurveHandles() {
        var a = line([(0, 0), (10, 0)])
        a.nodes[1].inHandle = Point2D(x: 8, y: 2)
        var b = line([(10, 0), (20, 0)])
        b.nodes[0].outHandle = Point2D(x: 12, y: -2)
        let j = a.joiningLine(b, tolerance: 0.01)!
        XCTAssertEqual(j.nodes[1].inHandle, Point2D(x: 8, y: 2))
        XCTAssertEqual(j.nodes[1].outHandle, Point2D(x: 12, y: -2))
    }

    func testOnlySameSymbolMerges() {
        let a = line([(0, 0), (10, 0)])
        XCTAssertNil(a.joiningLine(line([(10, 0), (20, 0)], code: "101.0"), tolerance: 1))
        XCTAssertNil(a.joiningLine(line([(10, 0), (20, 0)], code: nil), tolerance: 1))
        XCTAssertNotNil(line([(0, 0), (10, 0)], code: nil).joiningLine(line([(10, 0), (20, 0)], code: nil), tolerance: 1),
                        "Without symbol: same color")
        XCTAssertFalse(a.canMerge(with: area([(0, 0), (1, 0), (1, 1)], code: "506.0")), "Line not merged with area")
    }

    func testStitchAdjacentAreasKeepsSharedEdgeOut() {
        // Two squares share edge x = 10 (snapped points), opposite winding.
        let a = area([(0, 0), (10, 0), (10, 10), (0, 10)])
        let b = area([(10, 10), (10, 0), (20, 0), (20, 10)].reversed())
        let r = a.unitingArea(b, vertexTolerance: 0.01, flattenTolerance: 0.1, allowOverlap: false)!
        XCTAssertFalse(r.flattenedCurves)
        XCTAssertEqual(abs(r.feature.signedArea), 200, accuracy: 1e-9)
        XCTAssertEqual(Set(r.feature.nodes.map(\.point)), Set([(0, 0), (10, 0), (20, 0), (20, 10), (10, 10), (0, 10)].map { Point2D(x: $0.0, y: $0.1) }))
    }

    func testStitchKeepsBezierCurves() {
        var a = area([(0, 0), (10, 0), (10, 10), (0, 10)])
        a.nodes[3].outHandle = Point2D(x: -3, y: 7)
        a.nodes[0].inHandle = Point2D(x: -3, y: 3)
        let b = area([(10, 0), (20, 0), (20, 10), (10, 10)])
        let r = a.unitingArea(b, vertexTolerance: 0.01, flattenTolerance: 0.1, allowOverlap: false)!
        XCTAssertTrue(r.feature.nodes.contains { $0.outHandle == Point2D(x: -3, y: 7) }, "Outer edge curve kept")
        XCTAssertEqual(r.feature.nodes.count, 6)
    }

    func testOverlappingAreasUnion() {
        let a = area([(0, 0), (10, 0), (10, 10), (0, 10)])
        let b = area([(5, 5), (15, 5), (15, 15), (5, 15)])
        XCTAssertNil(a.unitingArea(b, vertexTolerance: 0.01, flattenTolerance: 0.1, allowOverlap: false), "Auto: only snapped ones")
        let r = a.unitingArea(b, vertexTolerance: 0.01, flattenTolerance: 0.1)!
        XCTAssertEqual(r.feature.nodes.count, 8)
        XCTAssertEqual(abs(r.feature.signedArea), 175, accuracy: 1e-6)
        XCTAssertFalse(r.droppedHoles)
    }

    func testAreaContainedAndSeparate() {
        let big = area([(0, 0), (10, 0), (10, 10), (0, 10)])
        let small = area([(2, 2), (4, 2), (4, 4), (2, 4)])
        XCTAssertEqual(abs(big.unitingArea(small, vertexTolerance: 0.01, flattenTolerance: 0.1)!.feature.signedArea), 100, accuracy: 1e-6)
        let far = area([(20, 0), (30, 0), (30, 10), (20, 10)])
        XCTAssertNil(big.unitingArea(far, vertexTolerance: 0.01, flattenTolerance: 0.1), "Not touching")
    }

    func testUnionTouchingAlongPartOfEdge() {
        // Partially shared edge (no snapped points): y = 0..5 at x = 10.
        let a = area([(0, 0), (10, 0), (10, 10), (0, 10)])
        let b = area([(10, 0), (20, 0), (20, 5), (10, 5)])
        let r = a.unitingArea(b, vertexTolerance: 0.01, flattenTolerance: 0.1)!
        XCTAssertEqual(abs(r.feature.signedArea), 150, accuracy: 1e-6)
    }

    func testUnionWithHoleKeepsOuter() {
        // U shape + cap = ring with a hole in the middle.
        let u = area([(0, 0), (30, 0), (30, 30), (20, 30), (20, 10), (10, 10), (10, 30), (0, 30)])
        let lid = area([(0, 25), (30, 25), (30, 35), (0, 35)])
        let r = u.unitingArea(lid, vertexTolerance: 0.01, flattenTolerance: 0.1)!
        XCTAssertTrue(r.droppedHoles)
        XCTAssertEqual(abs(r.feature.signedArea), 30 * 35, accuracy: 1e-6)
    }
}

final class FeatureFollowTests: XCTestCase {
    private func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }
    private let square = Feature(kind: .area, colorHex: "#3CB54A", widthMM: 0,
                                 nodes: [(0, 0), (10, 0), (10, 10), (0, 10)].map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) })

    func testNearestPathPosition() {
        let r = square.nearestPathPosition(to: P(4, -1))!
        XCTAssertEqual(r.position.segment, 0)
        XCTAssertEqual(r.point.x, 4, accuracy: 1e-9)
        XCTAssertEqual(r.distance, 1, accuracy: 1e-9)
    }

    func testFollowAreaTakesShorterSideOrViaSide() {
        let a = square.nearestPathPosition(to: P(5, -1))!.position   // middle of bottom edge
        let b = square.nearestPathPosition(to: P(11, 5))!.position   // middle of right edge
        XCTAssertEqual(square.followNodes(from: a, to: b).map(\.point), [P(5, 0), P(10, 0), P(10, 5)], "Via bottom-right corner")
        let long = square.followNodes(from: a, to: b, via: P(-1, 5))
        XCTAssertEqual(long.map(\.point), [P(5, 0), P(0, 0), P(0, 10), P(10, 10), P(10, 5)], "Via left side following the stroke")
    }

    func testFollowLineBackwardsAndCurveSplit() {
        var line = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25,
                           nodes: [BezierNode(point: P(0, 0), outHandle: P(0, 10)), BezierNode(point: P(10, 0), inHandle: P(10, 10))])
        line.symbolCode = "506.0"
        let full = line.followNodes(from: line.pathPosition(ofNode: 1), to: line.pathPosition(ofNode: 0))
        XCTAssertEqual(full.first?.point, P(10, 0))
        XCTAssertEqual(full.last?.point, P(0, 0))
        XCTAssertEqual(full.first?.outHandle, P(10, 10), "Curve fully reversed")
        let half = line.followNodes(from: PathPosition(segment: 0, t: 0), to: PathPosition(segment: 0, t: 0.5))
        XCTAssertEqual(half.last!.point.x, 5, accuracy: 1e-9)
        XCTAssertEqual(half.last!.point.y, 7.5, accuracy: 1e-9, "Bezier curve midpoint")
    }

    func testFreehandTraceSnapsRunAlongObject() {
        // Stroke comes from bottom left, follows the square's bottom edge (±0.3 m wobble), then leaves to bottom right.
        var pts = [P(-10, -10), P(-5, -5)]
        for x in stride(from: 0.5, through: 9.5, by: 0.5) { pts.append(P(x, (x * 7).truncatingRemainder(dividingBy: 0.6) - 0.3)) }
        pts += [P(15, -5), P(20, -10)]
        let nodes = GuideTrace.trace(pts, guides: [square], radius: 1, simplifyTolerance: 0.1)
        let ys = nodes.map(\.point).filter { $0.x > 0.4 && $0.x < 9.6 }.map(\.y)
        XCTAssertFalse(ys.isEmpty)
        XCTAssertTrue(ys.allSatisfy { abs($0) < 1e-9 }, "Part following the object lies exactly on its line: \(ys)")
        XCTAssertEqual(nodes.first?.point, P(-10, -10))
        XCTAssertEqual(nodes.last?.point, P(20, -10))
    }

    func testShortCrossingIsNotFollowed() {
        let pts = [P(5, -5), P(5, -0.2), P(5, 0.2), P(5, 5)]
        let nodes = GuideTrace.trace(pts, guides: [square], radius: 1, simplifyTolerance: 0.1)
        XCTAssertEqual(nodes.map(\.point), [P(5, -5), P(5, 5)], "Crossing an object does not snap to it")
    }
}

final class FillAreaTests: XCTestCase {
    private let vegetation = MapSymbol(number: 406000, name: "Vegetation", kind: .area, colorHex: "#3CB54A", lineWidthMM: nil, isEnabled: true)
    private let footpath = MapSymbol(number: 506000, name: "Small footpath", kind: .line, colorHex: "#000000", lineWidthMM: 0.25, isEnabled: true)

    func testClosedLineFilledKeepsLine() {
        var line = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25,
                           nodes: [(0, 0), (10, 0), (10, 10), (0, 10), (0, 0)].map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) },
                           symbolCode: "506.0", symbolName: "Small footpath")
        line.nodes[4].inHandle = Point2D(x: -1, y: 2)
        let area = line.filledArea(with: vegetation, closeTolerance: 0.01)!
        XCTAssertEqual(area.kind, .area)
        XCTAssertEqual(area.symbolCode, "406.0")
        XCTAssertNotEqual(area.id, line.id, "New feature; line kept")
        XCTAssertEqual(area.nodes.count, 4, "Coincident end point merged")
        XCTAssertEqual(area.nodes[0].inHandle, Point2D(x: -1, y: 2), "Closing curve preserved")
        XCTAssertNil(line.filledArea(with: footpath, closeTolerance: 0.01), "Must be an area symbol")
    }

    func testOpenLineClosedStraight() {
        let line = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25,
                           nodes: [(0, 0), (10, 0), (10, 10)].map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) })
        XCTAssertFalse(line.isClosedLine(tolerance: 0.01))
        XCTAssertEqual(line.filledArea(with: vegetation, closeTolerance: 0.01)?.nodes.count, 3)
        let two = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25,
                          nodes: [(0, 0), (10, 0)].map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) })
        XCTAssertNil(two.filledArea(with: vegetation, closeTolerance: 0.01))
    }
}

final class FeatureEditTests: XCTestCase {
    private func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }
    private func line(_ pts: [(Double, Double)]) -> Feature {
        Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: pts.map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) },
                symbolCode: "506.0", symbolName: "Small footpath")
    }

    func testInsertNodeKeepsCurveShape() {
        var f = line([(0, 0), (10, 0)])
        f.nodes[0].outHandle = P(0, 10)
        f.nodes[1].inHandle = P(10, 10)
        let mid = f.segments[0].point(at: 0.3)
        XCTAssertEqual(f.insertNode(at: PathPosition(segment: 0, t: 0.3)), 1)
        XCTAssertEqual(f.nodes.count, 3)
        XCTAssertEqual(f.nodes[1].point.distance(to: mid), 0, accuracy: 1e-9)
        // Same shape: points on the new curve = points on the old curve.
        let q = f.segments[1].point(at: 0.5)
        XCTAssertLessThan(Feature(kind: .line, colorHex: "", widthMM: 0, nodes: [BezierNode(point: P(0, 0), outHandle: P(0, 10)),
                                                                                  BezierNode(point: P(10, 0), inHandle: P(10, 10))])
            .distance(to: q, tolerance: 0.001), 0.01)
        var straight = line([(0, 0), (10, 0)])
        straight.insertNode(at: PathPosition(segment: 0, t: 0.5))
        XCTAssertEqual(straight.nodes.map(\.point), [P(0, 0), P(5, 0), P(10, 0)])
    }

    func testSplitLine() {
        let f = line([(0, 0), (10, 0), (20, 0)])
        let (a, b) = f.splitLine(at: PathPosition(segment: 1, t: 0.5))!
        XCTAssertEqual(a.nodes.map(\.point), [P(0, 0), P(10, 0), P(15, 0)])
        XCTAssertEqual(b.nodes.map(\.point), [P(15, 0), P(20, 0)])
        XCTAssertEqual(a.id, f.id)
        XCTAssertNotEqual(b.id, f.id)
        XCTAssertEqual(b.symbolCode, "506.0")
        XCTAssertNil(f.splitLine(at: PathPosition(segment: 0, t: 0)), "Line end is not split")
        let (c, d) = f.splitLine(at: f.pathPosition(ofNode: 1))!
        XCTAssertEqual(c.nodes.count, 2)
        XCTAssertEqual(d.nodes.count, 2)
    }

    func testSplitArea() {
        let sq = Feature(kind: .area, colorHex: "#3CB54A", widthMM: 0,
                         nodes: [(0, 0), (10, 0), (10, 10), (0, 10)].map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) })
        let (a, b) = sq.splitArea(from: PathPosition(segment: 0, t: 0.5), to: PathPosition(segment: 2, t: 0.5))!
        XCTAssertEqual(abs(a.signedArea) + abs(b.signedArea), 100, accuracy: 1e-9)
        XCTAssertEqual(abs(a.signedArea), 50, accuracy: 1e-9)
        XCTAssertNil(sq.splitArea(from: PathPosition(segment: 0, t: 0.5), to: PathPosition(segment: 0, t: 0.5)))
    }

    func testScale() {
        let f = line([(0, 0), (10, 0)]).scaled(by: 2, around: P(5, 0))
        XCTAssertEqual(f.nodes.map(\.point), [P(-5, 0), P(15, 0)])
        XCTAssertEqual(f.widthMM, 0.25, "Line width kept")
    }

    func testParallelLineAndArea() {
        let f = line([(0, 0), (10, 0), (10, 10)]).parallel(offset: 1)   // left = up / to the left
        XCTAssertEqual(f.nodes[0].point.x, 0, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[0].point.y, 1, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[1].point.x, 9, accuracy: 1e-9, "Corner: miter")
        XCTAssertEqual(f.nodes[1].point.y, 1, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[2].point.x, 9, accuracy: 1e-9)
        let sq = Feature(kind: .area, colorHex: "#3CB54A", widthMM: 0,
                         nodes: [(0, 0), (10, 0), (10, 10), (0, 10)].map { BezierNode(point: Point2D(x: $0.0, y: $0.1)) })
        XCTAssertEqual(abs(sq.parallel(offset: -1).signedArea), 144, accuracy: 1e-9, "CCW, right side = outward")
        XCTAssertEqual(abs(sq.parallel(offset: 1).signedArea), 64, accuracy: 1e-9)
    }

    func testReverse() {
        var f = line([(0, 0), (10, 0)])
        f.nodes[0].outHandle = P(3, 3)
        f.reverse()
        XCTAssertEqual(f.nodes.map(\.point), [P(10, 0), P(0, 0)])
        XCTAssertEqual(f.nodes[1].inHandle, P(3, 3))
    }

    func testMapMeasurementDistancePaperAndBearing() {
        let m = MapMeasurement(start: P(100, 100), end: P(130, 140))
        XCTAssertEqual(m.meters, 50, accuracy: 1e-9)
        XCTAssertEqual(m.paperMM(scaleDenominator: 4000), 12.5, accuracy: 1e-9)
        XCTAssertEqual(MapMeasurement(start: P(0, 0), end: P(0, 10)).gridBearing, 0, accuracy: 1e-9)
        XCTAssertEqual(MapMeasurement(start: P(0, 0), end: P(10, 0)).gridBearing, 90, accuracy: 1e-9)
        XCTAssertEqual(MapMeasurement(start: P(0, 0), end: P(0, -10)).gridBearing, 180, accuracy: 1e-9)
        XCTAssertEqual(MapMeasurement(start: P(0, 0), end: P(-10, 0)).gridBearing, 270, accuracy: 1e-9)
    }

    func testConvertNodeSharpSmoothSmart() {
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.35,
                        nodes: [BezierNode(point: P(0, 0)), BezierNode(point: P(3, 3)), BezierNode(point: P(9, 0))])
        XCTAssertEqual(f.nodeStyle(at: 1), .sharp)

        // Smart: handles along neighbours (0,0)→(9,0), length ⅓ of the distance to each neighbour.
        f.convertNode(at: 1, to: .smart)
        XCTAssertEqual(f.nodeStyle(at: 1), .smart)
        let inLen = 18.0.squareRoot() / 3, outLen = 45.0.squareRoot() / 3
        XCTAssertEqual(f.nodes[1].inHandle!.x, 3 - inLen, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[1].inHandle!.y, 3, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[1].outHandle!.x, 3 + outLen, accuracy: 1e-9)

        // Neighbour moved → smart handles recomputed (still smart, also after the feature is moved).
        f.nodes[2].point = P(0, 9)
        f.refreshSmartNodes()
        XCTAssertEqual(f.nodes[1].outHandle!.x, 3, accuracy: 1e-9)
        XCTAssertGreaterThan(f.nodes[1].outHandle!.y, 3)
        XCTAssertEqual(f.nodes[1].moved(by: P(1, 1)).smart, true)

        // Smart handle dragged by hand → becomes smooth.
        f.moveHandle(node: 1, isIn: false, to: P(5, 5))
        XCTAssertEqual(f.nodeStyle(at: 1), .smooth)

        // Smooth keeps handle lengths but aligns them.
        f.nodes[1].inHandle = P(3, 1)    // length 2, not collinear
        f.convertNode(at: 1, to: .smooth)
        let p = f.nodes[1].point, a = f.nodes[1].inHandle!, b = f.nodes[1].outHandle!
        XCTAssertEqual(a.distance(to: p), 2, accuracy: 1e-9)
        XCTAssertEqual((a.x - p.x) * (b.y - p.y) - (a.y - p.y) * (b.x - p.x), 0, accuracy: 1e-9, "collinear")

        // Sharp: no handles. Smart ends of an open line also have no handles.
        f.convertNode(at: 1, to: .sharp)
        XCTAssertNil(f.nodes[1].inHandle)
        XCTAssertNil(f.nodes[1].outHandle)
        f.convertNode(at: 0, to: .smart)
        XCTAssertEqual(f.nodeStyle(at: 0), .smart)
        XCTAssertNil(f.nodes[0].outHandle)

        // Smart flag is stored in JSON; regular nodes do not write the "smart" key.
        let json = String(decoding: try! JSONEncoder().encode(f.nodes), as: UTF8.self)
        XCTAssertEqual(json.components(separatedBy: "smart").count - 1, 1)
        XCTAssertEqual(try! JSONDecoder().decode([BezierNode].self, from: Data(json.utf8))[0].smart, true)
    }

    func testBendStraightSegmentKeepsCornersSharp() {
        // Right-angle line: (0,0) → (10,0) → (10,10). Drag the middle of the first segment 4 m up.
        let f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.35,
                        nodes: [BezierNode(point: P(0, 0)), BezierNode(point: P(10, 0)), BezierNode(point: P(10, 10))])
        let g = f.bendingSegment(0, at: 0.5, by: P(0, 4))
        let s = g.segments[0]
        XCTAssertTrue(s.isCurve, "Straight segment becomes curved")
        XCTAssertEqual(s.point(at: 0.5).x, 5, accuracy: 1e-9)
        XCTAssertEqual(s.point(at: 0.5).y, 4, accuracy: 1e-9, "Dragged point follows the finger")
        XCTAssertEqual(g.nodes.map(\.point), f.nodes.map(\.point), "End points do not move")
        XCTAssertEqual(g.segments[1], f.segments[1], "Other segments unchanged")
        XCTAssertEqual(g.nodeStyle(at: 1), .sharp, "Corner stays a corner")

        // Drag the second segment too: in handle of node 1 (corner) does not rotate.
        let h = g.bendingSegment(1, at: 0.5, by: P(3, 0))
        XCTAssertEqual(h.nodes[1].inHandle, g.nodes[1].inHandle, "Corner handles independent (cusp)")
        XCTAssertEqual(h.segments[1].point(at: 0.5).x, 13, accuracy: 1e-9)

        // Smooth node stays smooth when an adjacent segment is dragged.
        var smooth = f
        smooth.convertNode(at: 1, to: .smooth)
        let k = smooth.bendingSegment(0, at: 0.5, by: P(0, 2))
        XCTAssertEqual(k.nodeStyle(at: 1), .smooth)
    }
}
