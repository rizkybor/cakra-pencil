import CoreGraphics
import ImageIO
import XCTest
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

    /// Busur meridian WGS84 ke 45° = 4.984.944,378 m, jadi N = k0 × busur di meridian tengah.
    func testMeridianArcAt45Degrees() {
        let zone = UTMZone(number: 31, isNorth: true)!
        let p = zone.project(LatLon(lat: 45, lon: 3))
        XCTAssertEqual(p.x, 500_000, accuracy: 1e-6)
        XCTAssertEqual(p.y, 0.9996 * 4_984_944.378, accuracy: 0.001)
    }

    /// Nilai acuan dihitung dengan rumus seri USGS (Snyder 1987) yang independen dari deret Krüger.
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
    /// Tabel "Ukuran area A4 per skala" di PRD FR-1.
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
        XCTAssertFalse(wf.text.contains(","), "World file harus memakai titik desimal")
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
    /// Uji roundtrip G1: titik yang digambar di koordinat X,Y harus jatuh di piksel yang
    /// dihitung balik dari world file, dengan selisih ≤ 1 piksel.
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
        XCTAssertLessThanOrEqual(errorPx, 1.0, "Selisih \(errorPx) px")
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
        // Titik bulat: ambil centroid piksel dengan alpha tertinggi. Baris memori 0 = baris atas gambar.
        var sumX = 0.0, sumY = 0.0, sumW = 0.0
        for row in 0..<h {
            for col in 0..<w {
                let a = Double(data[row * w * 4 + col * 4 + 3])
                if a > 0 { sumX += Double(col) * a; sumY += Double(row) * a; sumW += a }
            }
        }
        XCTAssertGreaterThan(sumW, 0, "Goresan tidak ter-render")
        return (Int((sumX / sumW).rounded()), Int((sumY / sumW).rounded()))
    }
}

final class ExportPerformanceTests: XCTestCase {
    /// Budget PRD: export A4 900 dpi (TIFF + world file) < 20 detik di iPad Air M1.
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
        // Seluruhnya di luar frame: tidak ikut.
        Stroke(colorHex: "#000000", widthMM: 0.14, points: [Point2D(x: 700_000, y: 9_000_000), Point2D(x: 700_010, y: 9_000_010)]),
    ]
    var request: VectorExportRequest {
        VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: strokes)
    }

    func testSymbolTableGroupsByColorWidthAndKind() {
        let t = SketchSymbolTable(strokes: request.exportedStrokes)
        XCTAssertEqual(t.symbols.map(\.code), ["990.1", "990.2", "990.3"])
        XCTAssertEqual(t.symbols[0].name, "Sketsa Coklat 0.14 mm")
        XCTAssertEqual(t.symbols[0].dxfLayer, "990_1_SKETSA_COKLAT_014")
        XCTAssertTrue(t.symbols[2].isPoint)
    }

    /// Koordinat .omap (µm kertas, y ke bawah) dihitung balik ke UTM lewat georeferensi di file yang sama.
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
                // Pembulatan 1 µm kertas = 4 mm di tanah pada 1:4000.
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
        let coklat = try XCTUnwrap(vertices["990_1_SKETSA_COKLAT_014"])
        XCTAssertEqual(coklat.count, 5)
        XCTAssertEqual(coklat[0].x, 788_200.1234, accuracy: 1e-9)
        XCTAssertEqual(coklat[0].y, 9_237_000.5678, accuracy: 1e-9)
        XCTAssertEqual(vertices["990_2_SKETSA_HITAM_035"]?.count, 2)
        XCTAssertEqual(points["990_3_SKETSA_BIRU_050_TITIK"], [Point2D(x: 788_400, y: 9_237_300)])
        XCTAssertNil(vertices.keys.first { $0.contains("700") })
    }

    func testExportWritesSelectedFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try VectorExporter.export(request, formats: [.omap, .dxf], to: dir)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["uji.omap", "uji.dxf"])
    }
}

/// Pembaca .omap minimal untuk tes: georeferensi, jumlah simbol, dan koordinat objek.
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
    /// Kurva S: (0,0) → (100,0) dengan handle keluar (0,50) dan handle masuk (100,-50).
    let curve = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: [
        BezierNode(point: Point2D(x: 788_300, y: 9_237_200), outHandle: Point2D(x: 788_300, y: 9_237_250)),
        BezierNode(point: Point2D(x: 788_400, y: 9_237_200), inHandle: Point2D(x: 788_400, y: 9_237_150)),
    ], createdAt: Date(timeIntervalSince1970: 1_790_000_000)) // detik bulat: ISO-8601 tidak menyimpan pecahan

    func testSegmentMatchesCubicFormula() {
        let s = curve.segments[0]
        XCTAssertTrue(s.isCurve)
        // t = 0,5: (p0 + 3c1 + 3c2 + p3) / 8
        let mid = s.point(at: 0.5)
        XCTAssertEqual(mid.x, 788_350, accuracy: 1e-9)
        XCTAssertEqual(mid.y, 9_237_200, accuracy: 1e-9)
        XCTAssertEqual(s.point(at: 0.25).y, 9_237_200 + 3 * 0.75 * 0.75 * 0.25 * 50 - 3 * 0.75 * 0.25 * 0.25 * 50, accuracy: 1e-9)
    }

    func testFlattenStaysWithinTolerance() {
        let pts = curve.flattened(tolerance: 0.2)
        XCTAssertEqual(pts.first, curve.nodes[0].point)
        XCTAssertEqual(pts.last, curve.nodes[1].point)
        // Setiap titik kurva harus dekat ke polyline hasil perataan.
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
        XCTAssertEqual(tri.segments.count, 3, "Area tertutup: segmen terakhir kembali ke titik awal")
        XCTAssertFalse(tri.segments.contains { $0.isCurve })
        XCTAssertEqual(tri.flattened(tolerance: 1).count, 4)
    }

    func testOmapCurveAndCloseFlags() {
        let ref = Point2D(x: 788_350, y: 9_237_200)
        let coords = OmapWriter.featureCoords(curve, reference: ref, scale: 4000)
        // Awal kurva berflag 1, lalu dua titik kontrol, lalu titik akhir.
        XCTAssertEqual(coords, ["-12500 0 1;", "-12500 -12500;", "12500 12500;", "12500 0;"])

        var area = curve
        area.kind = .area
        let closed = OmapWriter.featureCoords(area, reference: ref, scale: 4000)
        XCTAssertEqual(closed.last, "-12500 0 2;", "Path tertutup diakhiri titik awal berflag penutup")
        // Kurva (3 koordinat) + segmen penutup lurus (1) + titik penutup (1).
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
        XCTAssertEqual(req.exportedFeatures.count, 2, "Objek tersembunyi tidak ikut")

        let xml = OmapWriter.document(req)
        XCTAssertTrue(xml.contains("<area_symbol inner_color="))
        XCTAssertTrue(xml.contains("name=\"Area Hijau\""))
        XCTAssertTrue(xml.contains("<objects count=\"2\">"))
        XCTAssertNotNil(XMLParser(data: Data(xml.utf8)).parse() ? true : nil)

        let dxf = DXFWriter.document(req)
        XCTAssertTrue(dxf.contains("990_2_AREA_HIJAU"))
        // Kurva diratakan: jauh lebih banyak vertex dari 2 titik bezier.
        let lineVertices = dxf.components(separatedBy: "VERTEX\r\n8\r\n990_1_SKETSA_HITAM_025").count - 1
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
        // Titik tengah kurva (788350, 9237200) dan titik di t = 0,25 harus berwarna; titik pada garis lurus p0–p3 di t = 0,25 tidak.
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
        XCTAssertEqual(f.nodes[1].outHandle!.y, 30, accuracy: 1e-9, "Handle searah garis prev → next (horizontal)")
        let otherLen = f.nodes[1].inHandle!.distance(to: f.nodes[1].point)
        f.moveHandle(node: 1, isIn: false, to: Point2D(x: 30, y: 50))
        XCTAssertEqual(f.nodes[1].inHandle!.x, 30, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[1].inHandle!.y, 30 - otherLen, accuracy: 1e-9, "Handle seberang segaris, panjang tetap")
        f.toggleSmooth(at: 1)
        XCTAssertFalse(f.nodes[1].isSmooth)
    }
}

final class OcadReaderTests: XCTestCase {
    /// File OCAD 12 minimal: 1 string skala, 1 warna, 1 simbol garis, 1 objek garis bezier.
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

        // Blok string.
        let strBlock = append(Data(count: 4 + 256 * 16))
        let scale = append(Data(scalePar.utf8) + Data([0]))
        let color = append(Data("Brown\tn5\tc0\tm56\ty100\tk18".utf8) + Data([0]))
        for (i, (pos, len, type)) in [(scale, scalePar.utf8.count + 1, Int32(1039)), (color, 26, Int32(9))].enumerated() {
            put(UInt32(pos), at: strBlock + 4 + i * 16)
            put(UInt32(len), at: strBlock + 8 + i * 16)
            put(type, at: strBlock + 12 + i * 16)
        }
        put(UInt32(strBlock), at: 32)

        // Blok simbol: 1 simbol garis 101.0 "Contour", warna 5, tebal 0,21 mm.
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
        // Simbol titik 204.0 "Boulder": 1 elemen titik (jenis 4) Ø 0,60 mm, warna 5.
        let point = append(Data(count: 824))
        put(Int32(824), at: point)
        put(Int32(204_000), at: point + 4)
        put(UInt8(1), at: point + 8)
        put(Int16(5), at: point + 28)
        for (i, u) in "Boulder".utf16.enumerated() { put(u, at: point + 56 + i * 2) }
        put(UInt16(3), at: point + 796)        // DataSize = 3 TCord (header 2 + 1 titik)
        put(Int16(4), at: point + 800)         // jenis: titik
        put(Int16(5), at: point + 804)         // warna
        put(Int16(60), at: point + 808)        // diameter 0,60 mm
        put(Int16(1), at: point + 810)         // 1 titik
        put(UInt32(point), at: symBlock + 8)
        // Simbol garis ganda 505.0: lebar 0,35 mm, tepi 0,10 mm warna 5, isi warna 5 (flag isi).
        let dbl = append(Data(count: 872))
        put(Int32(872), at: dbl)
        put(Int32(505_000), at: dbl + 4)
        put(UInt8(2), at: dbl + 8)
        for (i, u) in "Footpath".utf16.enumerated() { put(u, at: dbl + 56 + i * 2) }
        put(Int16(5), at: dbl + 796)
        put(Int16(0), at: dbl + 798)          // tanpa garis tengah
        put(Int16(3), at: dbl + 822)          // DblMode
        put(Int16(1), at: dbl + 824)          // DblFlags: isi
        put(Int16(5), at: dbl + 826)          // warna isi
        put(Int16(5), at: dbl + 828)          // warna tepi
        put(Int16(35), at: dbl + 832)         // lebar antar tepi
        put(Int16(10), at: dbl + 834)
        put(Int16(10), at: dbl + 836)
        put(UInt32(dbl), at: symBlock + 12)
        put(UInt32(symBlock), at: 8)

        // Blok objek.
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
        // 1000 × 0,01 mm = 10 mm kertas × 10000 / 1000 = 100 m.
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
        // Terpotong di tengah blok objek.
        let full = Self.makeOcad()
        XCTAssertThrowsError(try OcadReader.read(full.prefix(full.count - 40)))
        // Tanpa georeferensi.
        let noGeo = try? OcadReader.read(Self.makeOcad(scalePar: "\tm4000\tr0"))
        XCTAssertThrowsError(try noGeo?.features()) { XCTAssertEqual($0 as? OcadReadError, .notGeoreferenced) }
        // Potongan acak tidak boleh crash.
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
        XCTAssertTrue(xml.contains("code=\"101.0\" name=\"Contour\""), "Kode ISOM asli, bukan 990.x")
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
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9, "Vertikal")
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
            XCTAssertTrue(e.contains(Rect2D(points: [a, b])!), "Terpotong di dalam frame")
            let angle = atan2(b.x - a.x, b.y - a.y) * 180 / .pi
            XCTAssertEqual(abs(angle), 5, accuracy: 1e-6)
        }
        // Jarak tegak lurus antar garis berurutan = spacing.
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
        let doc = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!), "PDF harus terbaca CoreGraphics")
        XCTAssertEqual(doc.numberOfPages, 1)
        let page = try XCTUnwrap(doc.page(at: 1))
        let media = page.getBoxRect(.mediaBox)
        XCTAssertEqual(media.width, 210 / 25.4 * 72, accuracy: 0.01)
        XCTAssertEqual(media.height, 297 / 25.4 * 72, accuracy: 0.01)

        let dict = try XCTUnwrap(page.dictionary)
        var vp: CGPDFArrayRef?
        XCTAssertTrue(CGPDFDictionaryGetArray(dict, "VP", &vp), "Halaman membawa /VP")
        var viewport: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFArrayGetDictionary(vp!, 0, &viewport))
        var measure: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(viewport!, "Measure", &measure))
        var subtype: UnsafePointer<CChar>?
        XCTAssertTrue(CGPDFDictionaryGetName(measure!, "Subtype", &subtype))
        XCTAssertEqual(String(cString: subtype!), "GEO")

        // GPTS pojok kiri bawah = lat/lon dari pojok kiri bawah frame.
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

        // BBox viewport = area peta di dalam margin 5 mm.
        var bbox: CGPDFArrayRef?
        XCTAssertTrue(CGPDFDictionaryGetArray(viewport!, "BBox", &bbox))
        var x0: CGPDFReal = 0
        CGPDFArrayGetNumber(bbox!, 0, &x0)
        XCTAssertEqual(Double(x0), 5 / 25.4 * 72, accuracy: 0.01)
    }

    func testContentHasVectorCurvesAndGrid() {
        let text = String(decoding: GeoPDFExporter.document(makeRequest()), as: UTF8.self)
        XCTAssertTrue(text.contains(" c\n"), "Kurva bezier sebagai operator c")
        XCTAssertTrue(text.contains("/GSGrid gs"))
        XCTAssertTrue(text.contains("WGS_1984_UTM_Zone_48S"))
        XCTAssertTrue(text.contains("Uji \\(PDF\\)"), "Kurung di judul di-escape")
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
        XCTAssertTrue(s.isDrawable, "Simbol titik dengan bentuk bisa digambar")
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
        // Ø 1,2 mm (1,0 + tebal 0,2) × 2 → jari-jari 1,2 mm → 4,8 m di 1:4000.
        XCTAssertEqual(f.pointRadiusM(sheet: SheetSpec(scaleDenominator: 4000)), 4.8, accuracy: 1e-9)
    }

    func testDrawingOrderFollowsColorPriority() {
        let fill = PointElement(kind: .dot, colorHex: "#C4FFBA", priority: 30, lineWidthMM: 0, diameterMM: 1.4, points: [])
        let ring = PointElement(kind: .circle, colorHex: "#3EB54A", priority: 5, lineWidthMM: 0.24, diameterMM: 0.96, points: [])
        XCTAssertEqual([ring, fill].drawingOrder.map(\.colorHex), ["#C4FFBA", "#3EB54A"], "Isi (prioritas rendah) digambar dulu")
    }

    func testPointsAppearInAllExports() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: 679_900, y: 9_303_900), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let (features, _) = try boulder().features()
        let zone = UTMZone(epsg: 32748)!

        let req = VectorExportRequest(baseName: "uji", frame: frame, sheet: sheet, zone: zone, strokes: [], features: features)
        XCTAssertEqual(req.exportedFeatures.count, 1, "Titik (1 node) tidak boleh tersaring")
        let xml = OmapWriter.document(req)
        XCTAssertTrue(xml.contains("<object type=\"0\""))
        XCTAssertTrue(xml.contains("code=\"204.0\" name=\"Boulder\""))
        XCTAssertTrue(DXFWriter.document(req).contains("POINT\r\n8\r\n204_0_BOULDER"))

        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: zone,
                                                                         strokes: [], features: features)), as: UTF8.self)
        XCTAssertTrue(pdf.contains(" c\n") && pdf.contains("h\nf\n"), "Titik sebagai lingkaran terisi")

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
        XCTAssertGreaterThan(data[row * image.width * 4 + col * 4 + 3], 200, "Pusat titik terisi")
        // Ø 0,6 mm @600 dpi ≈ 14 px: 12 px dari pusat harus kosong.
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
        // z = x / 10 → kontur 5 m di x = 50, 100, ...
        let g = grid { Float($0.x / 10) }
        var s = ContourSettings(isEnabled: true, intervalM: 5, smoothing: 0, minLengthMM: 0)
        s.indexEvery = 5
        let result = ContourGenerator.generate(g, settings: s, sheet: sheet)
        let xs = Set(result.lines.map { ($0.points.map(\.x).reduce(0, +) / Double($0.points.count)).rounded() })
        XCTAssertEqual(xs, [50, 100, 150, 200, 250])
        for line in result.lines {
            for p in line.points { XCTAssertEqual(p.x, line.elevation * 10, accuracy: 1e-6, "Interpolasi linear tepat di bidang") }
        }
        XCTAssertEqual(result.lines.first { $0.elevation == 25 }?.kind, .index, "25 = 5 × 5 → indeks")
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
        // 1:4000 → 30 mm kertas = 120 m: lingkaran kecil (keliling < 120 m) dibuang.
        let s = ContourSettings(intervalM: 10, smoothing: 0, minLengthMM: 30)
        let lines = ContourGenerator.generate(g, settings: s, sheet: sheet).lines
        XCTAssertFalse(lines.contains { $0.length < 120 })
        let f = try! XCTUnwrap(lines.first { $0.isClosed }).feature(settings: s)
        XCTAssertEqual(f.kind, .line)
        XCTAssertTrue(["101.0", "102.0"].contains(f.symbolCode ?? ""))
        XCTAssertEqual(f.nodes.first?.point, f.nodes.last?.point, "Kontur tertutup kembali ke titik awal")
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
        XCTAssertEqual(r.sample(Point2D(x: 680_005, y: 9_304_015), projectZone: zone), 1, "Pusat sel kiri atas")
        // Di antara sel 1 dan sel kosong: tetap ada nilai dari tetangga valid (tidak ikut NaN).
        XCTAssertFalse(r.sample(Point2D(x: 680_008, y: 9_304_012), projectZone: zone).isNaN)
        XCTAssertEqual(UTMZone(wkt: zone.prjWKT), zone)
    }

    /// TIFF float32 1 strip dengan tag GeoTIFF (UTM 48S).
    func makeGeoTIFF(width: Int, height: Int, values: [Float], compression: Int = 1, predictor: Int = 1) -> Data {
        var pixels = Data()
        for v in values { withUnsafeBytes(of: v.bitPattern.littleEndian) { pixels.append(contentsOf: $0) } }
        if predictor == 3 {
            // Predictor floating point: susun byte per bidang (MSB dulu), lalu selisih per byte.
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
        var entries: [(Int, Int, Int, [UInt8])] = [] // tag, type, count, nilai/isi
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
            XCTAssertEqual(r.values, values, "kompresi \(comp) predictor \(pred)")
            XCTAssertEqual(r.crs, .utm(zone))
            XCTAssertEqual(r.originX, 680_000)
            XCTAssertEqual(r.cellX, 10)
        }
    }

    /// LZW dari encoder sungguhan (ImageIO) agar decoder tidak hanya diuji dengan encoder buatan sendiri.
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
        XCTAssertEqual(Int(be32(f.shp, 24)) * 2, f.shp.count, "Panjang file dalam satuan 16-bit")
        XCTAssertEqual(le32(f.shp, 28), 1000)
        XCTAssertEqual(le32(f.shp, 32), 3, "PolyLine")
        XCTAssertEqual(led(f.shp, 36), 680_000)
        XCTAssertEqual(led(f.shp, 60), 9_304_210)
        // Record 1: nomor, tipe, 1 part, 3 titik, titik pertama.
        XCTAssertEqual(be32(f.shp, 100), 1)
        XCTAssertEqual(le32(f.shp, 108), 3)
        XCTAssertEqual(le32(f.shp, 108 + 36), 1)
        XCTAssertEqual(le32(f.shp, 108 + 40), 3)
        XCTAssertEqual(led(f.shp, 108 + 48), 680_000)
        XCTAssertEqual(led(f.shp, 108 + 56), 9_304_000)
        // .shx: 2 record, offset record 2 cocok dengan .shp.
        XCTAssertEqual(f.shx.count, 100 + 2 * 8)
        let off2 = Int(be32(f.shx, 108)) * 2
        XCTAssertEqual(be32(f.shp, off2), 2, "Offset .shx menunjuk record 2")
        // .dbf: 2 record, field ELEV berisi 125.00.
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
        XCTAssertTrue(kml.contains("<color>ff005cd1</color>"), "Warna KML aabbggrr dari #D15C00")
        XCTAssertTrue(kml.contains("Uji &amp; kontur"))
        XCTAssertTrue(kml.contains("<name>Index contour (1)</name>"))
    }

    /// KMZ diuji dengan `unzip` bawaan macOS: struktur ZIP dan CRC32 harus valid untuk alat lain.
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
        XCTAssertEqual(p.terminationStatus, 0, "unzip berhasil (CRC cocok)")
        XCTAssertEqual(String(decoding: out, as: UTF8.self), KML.document(lines, zone: zone, settings: ContourSettings(), title: "Uji"))
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926, "Vektor uji CRC-32 standar")
    }
}


final class LineStyleTests: XCTestCase {
    func testDoubleLineWidthFromOcad() throws {
        let map = try OcadReader.read(OcadReaderTests.makeOcad())
        let set = map.symbolSet(name: "Uji", sourceFile: "uji.ocd")
        let path = try XCTUnwrap(set.symbols.first { $0.number == 505_000 })
        XCTAssertEqual(path.drawingWidthMM, 0.45, accuracy: 1e-9, "Lebar total = 0,35 + tepi 0,10 (bukan tebakan 0,25)")
        XCTAssertEqual(path.lineStyle?.casing?.innerWidthMM ?? 0, 0.25, accuracy: 1e-9)
        let contour = try XCTUnwrap(set.symbols.first { $0.number == 101_000 })
        XCTAssertEqual(contour.drawingWidthMM, 0.21, accuracy: 1e-9, "Garis tunggal memakai tebal dari set")
        XCTAssertNil(contour.lineStyle?.casing)
    }

    func testSetWidthKeepsDoubleLineRatio() {
        var f = Feature(kind: .line, colorHex: "#FFFFFF", widthMM: 0.45, nodes: [])
        f.apply(LineStyle(colorHex: "#F5D9C4", widthMM: 0.45, casing: .init(colorHex: "#000000", innerWidthMM: 0.25)))
        f.setWidth(0.9)
        XCTAssertEqual(f.widthMM, 0.9)
        XCTAssertEqual(f.innerWidthMM!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(f.standardWidthMM, 0.45, "Tebal standar tetap untuk tombol Standar")
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
        // 1:4000 → 1 mm kertas = 4 m. Tengah garis = isi merah; 3 m dari sumbu (antara 2 m dan 4 m) = tepi biru.
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
        XCTAssertEqual(alpha(Point2D(x: 200, y: 500)), 255, "Area bersimbol: isi penuh")
        // Garis tepi 1 mm = 4 m di 1:4000, jadi 2 m di luar batas tertutup hanya bila ada garis tepi.
        XCTAssertEqual(alpha(Point2D(x: 98, y: 500)), 0, "Area bersimbol: tanpa garis tepi")
        XCTAssertLessThan(alpha(Point2D(x: 600, y: 500)), 120, "Area sketsa: isi transparan")
        XCTAssertEqual(alpha(Point2D(x: 499, y: 500)), 255, "Area sketsa: ada garis tepi (4 m berpusat di batas)")
    }

    func testDashedLinesFromOcadAndPDFOperators() throws {
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: [BezierNode(point: Point2D(x: 0, y: 0)), BezierNode(point: Point2D(x: 100, y: 0))])
        f.apply(LineStyle(colorHex: "#000000", widthMM: 0.25, casing: nil, dashMM: [1.5, 0.37], roundCaps: false))
        XCTAssertEqual(f.effectiveDashMM, [1.5, 0.37])
        f.setWidth(0.5)
        XCTAssertEqual(f.effectiveDashMM?[0] ?? 0, 3.0, accuracy: 1e-9, "Pola ikut skala tebal")

        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -10, y: -10), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let pdf = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                                         strokes: [], features: [f])), as: UTF8.self)
        XCTAssertTrue(pdf.contains("0 J 0 j ["), "Ujung rata + pola putus-putus di PDF")
    }
}

final class RotationTests: XCTestCase {
    func testRotateAreaClockwiseAroundCentroidAndBack() {
        let square = [Point2D(x: 0, y: 10), Point2D(x: 10, y: 10), Point2D(x: 10, y: 0), Point2D(x: 0, y: 0)]
        var f = Feature.rectangle(corners: square, colorHex: "#000000", widthMM: 0.14)
        let center = f.rotationPivot!
        f.setRotation(90)
        XCTAssertEqual(f.rotationDegrees, 90)
        // Searah jarum jam: titik kiri atas (0,10) pindah ke kanan atas (10,10).
        XCTAssertEqual(f.nodes[0].point.x, 10, accuracy: 1e-9)
        XCTAssertEqual(f.nodes[0].point.y, 10, accuracy: 1e-9)
        XCTAssertEqual(f.rotationPivot!.distance(to: center), 0, accuracy: 1e-9, "Pusat tidak bergeser")
        f.setRotation(37.5)
        f.setRotation(0)
        XCTAssertNil(f.rotationDeg)
        for (a, b) in zip(f.nodes.map(\.point), square) { XCTAssertEqual(a.distance(to: b), 0, accuracy: 1e-9, "Kembali ke posisi awal") }
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
        XCTAssertEqual(f.nodes[0].point, Point2D(x: 100, y: 200), "Posisi titik tetap")
        let p = f.scaledPointElements[0].points[0]
        XCTAssertEqual(p.x, 1, accuracy: 1e-9, "Garis vertikal jadi horizontal")
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
        XCTAssertTrue(xml.contains("rotation=\"-4.712389\""), "270° searah jarum jam = −3π/2 rad di OOM")
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
        XCTAssertNil(f.dashMM, "Putus-putus simbol lama hilang")
        XCTAssertEqual(f.roundCaps, true)
        XCTAssertEqual(f.nodes, nodes, "Bentuk objek tidak berubah")
        XCTAssertEqual(f.rotationDegrees, 30, "Rotasi dipertahankan")
        XCTAssertEqual(f.name, "101.0 Contour 3", "Nama bawaan ikut simbol baru, nomor urut tetap")
    }

    func testLineAndAreaSwapLikeOOM() {
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: path, symbolCode: "506.0", symbolName: "Small footpath")
        XCTAssertTrue(f.switchSymbol(to: vegetation))
        XCTAssertEqual(f.kind, .area)
        XCTAssertTrue(f.isSymbolArea)
        XCTAssertTrue(f.switchSymbol(to: footpath))
        XCTAssertEqual(f.kind, .line)
        XCTAssertEqual(f.dashMM, [1.5, 0.37])

        // Garis 2 titik tidak bisa jadi area.
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
        XCTAssertEqual(p.widthMM, 1.5, accuracy: 1e-9, "Ukuran pilihan user (150%) tetap")

        var line = Feature(kind: .line, colorHex: "#000000", widthMM: 0.25, nodes: path)
        XCTAssertFalse(line.switchSymbol(to: rock), "Garis tidak bisa jadi titik")
    }
}

final class CoursePlannerTests: XCTestCase {
    /// Start (0,0) → 31 (300,0) → 32 (300,400) → Finish (0,400). Lintasan A dan B berbagi kontrol 31.
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
        XCTAssertEqual(loads[c31]?.visits, 55, "Beban = jumlah peserta semua lintasan yang lewat")
        XCTAssertEqual(loads[c31]?.courseCount, 2)
        XCTAssertEqual(loads[c32]?.visits, 40)
        let shared = set.sharedLegLoads()
        XCTAssertEqual(shared.count, 1, "Leg Start→31 dipakai A dan B")
        XCTAssertEqual(shared.first?.visits, 55)
        XCTAssertTrue(set.warnings().isEmpty, "Lintasan contoh valid: \(set.warnings())")
    }

    func testAutomaticCodesSkipAmbiguous() {
        XCTAssertTrue(CourseSet.isAmbiguous(66))  // 99
        XCTAssertTrue(CourseSet.isAmbiguous(68))  // 89
        XCTAssertFalse(CourseSet.isAmbiguous(61), "19 di luar 31–255, jadi tidak tertukar")
        XCTAssertFalse(CourseSet.isAmbiguous(88), "88 terbalik tetap 88")
        XCTAssertFalse(CourseSet.isAmbiguous(31))
        var set = CourseSet(firstCode: 65)
        set.controls = [ControlPoint(kind: .control, code: 65, position: Point2D(x: 0, y: 0))]
        XCTAssertEqual(set.nextFreeCode(), 67, "66 dilewati (terbaca 99)")
        set.avoidAmbiguousCodes = false
        XCTAssertEqual(set.nextFreeCode(), 66)
    }

    func testWarningsForMissingFinishAndCloseControls() {
        var (set, a, _) = sample()
        set.controls.append(ControlPoint(kind: .control, code: 33, position: Point2D(x: 310, y: 10)))
        set.courses[0].controlIDs.removeLast()
        _ = a
        let w = set.warnings()
        XCTAssertTrue(w.contains { $0.contains("A: belum ada finish") })
        XCTAssertTrue(w.contains { $0.contains("31 dan 33") }, "Kontrol < 30 m diperingatkan")
    }

    func testOverprintGeometry() {
        let (set, a, _) = sample()
        let sheet = SheetSpec(scaleDenominator: 10000) // ISOM: lingkaran 5 mm = 50 m
        let o = CourseOverprint.make(set, course: a, sheet: sheet)
        XCTAssertEqual(o.lineWidthM, 3.5, accuracy: 1e-9)
        let circles = o.marks.compactMap { if case let .circle(_, r) = $0 { return r } else { return nil } }
        XCTAssertEqual(circles.sorted(), [25, 25, 25, 35], "2 kontrol + finish 5/7 mm")
        // Segitiga start menunjuk ke kontrol pertama (timur).
        guard case let .polyline(tri, true)? = o.marks.first(where: { if case .polyline(_, true) = $0 { return true } else { return false } }) else {
            return XCTFail("Segitiga start tidak ada")
        }
        XCTAssertEqual(tri[0].y, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(tri[0].x, 0)
        // Leg pertama berhenti di tepi segitiga dan lingkaran 31.
        let legs = o.marks.compactMap { if case let .polyline(p, false) = $0 { return p } else { return nil } }
        XCTAssertEqual(legs.count, 3)
        XCTAssertEqual(legs[0][1].x, 275, accuracy: 1e-6, "Leg berhenti di tepi lingkaran (300 − 25)")
        let texts = o.marks.compactMap { if case let .text(t, _, _) = $0 { return t } else { return nil } }
        XCTAssertEqual(Set(texts), ["1", "2"])
        // Semua kontrol: label = kode, tanpa leg.
        let all = CourseOverprint.make(set, course: nil, sheet: sheet)
        XCTAssertEqual(Set(all.marks.compactMap { if case let .text(t, _, _) = $0 { return t } else { return nil } }), ["31", "32"])
        XCTAssertTrue(all.marks.allSatisfy { if case .polyline(_, false) = $0 { return false } else { return true } })
        XCTAssertEqual(CourseStyle.standard(scale: 4000).controlDiameterMM, 6, "Sprint: ISSprOM")
    }

    func testDescriptionText() {
        let d = ControlDescription(which: "0.1N", feature: "2.4", dimension: "1.5", location: "11.1E")
        XCTAssertEqual(d.text, "Batu besar paling utara, 1,5 m, sisi timur")
        let (set, a, _) = sample()
        let sheet = DescriptionSheet(set, course: a)
        XCTAssertEqual(sheet.lengthText, "1,0 km")
        XCTAssertEqual(sheet.rows.map(\.kind), [.start, .control, .control, .finish])
        XCTAssertEqual(sheet.rows[1].code, "31")
        XCTAssertEqual(sheet.rows.last?.text, "Navigasi 300 m ke finish")
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
        // MapPosition 31: (300+100) m × 0,25 mm/m = 100 mm.
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
        XCTAssertTrue(pdf.contains("/Count 2"), "Halaman peta + lembar deskripsi")
        XCTAssertTrue(pdf.contains("(Batu besar, 1,5 m, sisi timur) Tj"))
        XCTAssertTrue(pdf.contains("0.651 0.149 1 RG"), "Overprint ungu")
    }
}

extension CoursePlannerTests {
    /// `CP_SAMPLE_DIR=… swift test --filter testWriteCourseSamples`: tulis contoh PDF + IOF XML untuk dicek visual.
    func testWriteCourseSamples() throws {
        guard let path = ProcessInfo.processInfo.environment["CP_SAMPLE_DIR"] else { throw XCTSkip("CP_SAMPLE_DIR tidak diset") }
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
        // Sedikit isi peta agar contoh mirip peta lomba: area hijau/kuning, jalan, dan bangunan.
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
        layout.subtitle = "Middle Distance"
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
        XCTAssertEqual(codes[set.controls[2].id], 65, "Kontrol pertama lintasan A")
        XCTAssertEqual(codes[set.controls[3].id], 67, "66 dilewati (terbaca 99)")
        XCTAssertEqual(codes[spare.id], 69, "Kontrol tak terpakai terakhir; 68 dilewati")
        XCTAssertNil(r.controls.first { $0.kind == .start }?.code)
    }
}

final class OmapReaderTests: XCTestCase {
    /// Tulis .omap dengan OmapWriter lalu baca lagi: posisi, kurva, kind, warna, dan kode kembali sama.
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
            XCTAssertEqual(a.point.distance(to: b.point), 0, accuracy: 0.01, "Titik kembali ke posisi UTM yang sama")
        }
        XCTAssertEqual(l.nodes[0].outHandle?.distance(to: line.nodes[0].outHandle!) ?? 99, 0, accuracy: 0.01, "Handle kurva")
        XCTAssertEqual(l.widthMM, 0.25, accuracy: 0.001)
        let ar = try XCTUnwrap(features.first { $0.kind == .area })
        XCTAssertEqual(ar.nodes.count, 4, "Titik penutup tidak digandakan")
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
        let sheet = SheetSpec(scaleDenominator: 10000) // ISOM 5 mm = 50 m → r 25 m
        func radii(_ s: CourseSet) -> [Double] {
            CourseOverprint.make(s, course: a, sheet: sheet).marks.compactMap { if case let .circle(_, r) = $0 { return r } else { return nil } }
        }
        XCTAssertEqual(radii(set).sorted(), [25, 25, 25, 35], "Default = standar IOF")
        set.controls[1].sizeFactor = 1.5 // kontrol 31
        XCTAssertEqual(radii(set).sorted(), [25, 25, 35, 37.5], "Hanya kontrol 31 membesar")
        let legs = CourseOverprint.make(set, course: a, sheet: sheet).marks.compactMap { if case let .polyline(p, false) = $0 { return p } else { return nil } }
        XCTAssertEqual(legs[0][1].x, 300 - 37.5, accuracy: 1e-6, "Leg berhenti di tepi lingkaran yang diperbesar")
        set.appearance = CourseAppearance(controlScale: 0.8, numberScale: 1.25, lineScale: 2)
        let o = CourseOverprint.make(set, course: a, sheet: sheet)
        XCTAssertEqual(o.lineWidthM, 7, accuracy: 1e-9)
        XCTAssertTrue(o.marks.contains { if case let .text(_, _, h) = $0 { return abs(h - 50) < 1e-9 } else { return false } }, "Nomor 4 mm × 125%")
        XCTAssertEqual(radii(set).sorted().first ?? 0, 20, accuracy: 1e-9, "Lingkaran 80%")
    }
}

extension CoursePlannerTests {
    /// Peta lomba satu halaman: deskripsi di peta, panah utara, kotak judul, skala batang, interval kontur.
    func testOnePageCompetitionMapLayout() {
        let (set, a, _) = sample()
        let sheet = SheetSpec(scaleDenominator: 4000)
        let frame = MapFrame(origin: Point2D(x: -100, y: -100), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        var layout = CoursePrintLayout()
        layout.subtitle = "Sprint"
        func pdf(_ l: CoursePrintLayout) -> String {
            String(decoding: GeoPDFExporter.document(GeoPDFRequest(
                title: "Uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, strokes: [], features: [],
                overprint: CourseOverprint.make(set, course: a, sheet: sheet), descriptions: DescriptionSheet(set, course: a),
                printLayout: l, contourIntervalM: 2.5)), as: UTF8.self)
        }
        let one = pdf(layout)
        XCTAssertTrue(one.contains("/Count 1"), "Satu halaman: deskripsi menempel di peta")
        XCTAssertTrue(one.contains("(Batu besar, 1,5 m, sisi timur) Tj"), "Deskripsi ada di halaman peta")
        XCTAssertTrue(one.contains("(Skala 1:4000) Tj"))
        XCTAssertTrue(one.contains("(Interval kontur 2,5 m) Tj"))
        XCTAssertTrue(one.contains("(Sprint) Tj"))
        XCTAssertTrue(one.contains("(U) Tj"), "Panah utara")
        XCTAssertTrue(one.contains("(100 m) Tj"), "Skala batang 100 m = 25 mm pada 1:4000")
        XCTAssertTrue(one.contains("/F2"), "Huruf tebal untuk judul")
        layout.separateDescriptionPage = true
        XCTAssertTrue(pdf(layout).contains("/Count 2"), "Opsi halaman deskripsi terpisah")
        XCTAssertEqual(GeoPDFExporter.scaleBarMeters(scale: 10000), 250)
    }
}

final class PDFNumberTests: XCTestCase {
    /// Formatter cepat harus sama persis dengan cara lama (String(format:) lalu buang nol di belakang).
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
        // Acak: selisih paling banyak 1 digit terakhir (pembulatan perkalian biner), tanpa nol di belakang.
        for _ in 0..<5000 {
            let v = Double.random(in: -2000...2000, using: &rng)
            let d = [2, 3, 5].randomElement(using: &rng)!
            let fast = GeoPDFExporter.n(v, d)
            XCTAssertEqual(Double(fast)!, Double(reference(v, d))!, accuracy: pow(10, -Double(d)) * 1.01, "\(v) / \(d)")
            XCTAssertFalse(fast.contains(".") && fast.hasSuffix("0"), fast)
        }
    }
}
