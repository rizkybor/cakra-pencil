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
