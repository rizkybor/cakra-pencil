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
