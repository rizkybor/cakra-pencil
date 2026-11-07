import CakraCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class ExportBackgroundTests: XCTestCase {
    private let sheet = SheetSpec(scaleDenominator: 4000)
    private let zone = UTMZone(epsg: 32748)!
    private var frame: MapFrame { MapFrame(origin: Point2D(x: 788_000, y: 9_237_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM) }

    /// Solid red PNG of `w` × `h` pixels.
    private func redPNG(_ w: Int, _ h: Int) -> Data {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// Background covering the frame plus 10 m on every side.
    private func background(opacity: Double = 1) -> ExportBackground {
        let e = frame.extent
        let corners = [Point2D(x: e.minX - 10, y: e.maxY + 10), Point2D(x: e.maxX + 10, y: e.maxY + 10),
                       Point2D(x: e.maxX + 10, y: e.minY - 10), Point2D(x: e.minX - 10, y: e.minY - 10)]
        return ExportBackground(imageData: redPNG(40, 60), pixelWidth: 40, pixelHeight: 60, corners: corners, opacity: opacity,
                                attribution: "Imagery © Apple Maps", fileExtension: "png")
    }

    func testWorldFileMapsPixelCentersToCorners() {
        let bg = background()
        let wf = bg.worldFile
        let tl = wf.world(col: -0.5, row: -0.5), br = wf.world(col: 39.5, row: 59.5)
        XCTAssertEqual(tl.x, bg.corners[0].x, accuracy: 1e-6)
        XCTAssertEqual(tl.y, bg.corners[0].y, accuracy: 1e-6)
        XCTAssertEqual(br.x, bg.corners[2].x, accuracy: 1e-6)
        XCTAssertEqual(br.y, bg.corners[2].y, accuracy: 1e-6)
    }

    func testRasterDrawsBackgroundUnderMap() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var req = RasterExportRequest(baseName: "bg", frame: frame, sheet: sheet, zone: zone, dpi: 72, format: .png, strokes: [])
        req.background = background()
        let result = try RasterExporter.export(req, to: dir)
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(result.imageURL as CFURL, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        // Read the center pixel: red from the background.
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: -img.width / 2, y: -img.height / 2, width: img.width, height: img.height))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(px[0], 200)
        XCTAssertLessThan(px[1], 40)
    }

    func testGeoPDFEmbedsBackgroundWithOpacityAndCredit() {
        var req = GeoPDFRequest(title: "bg", frame: frame, sheet: sheet, zone: zone, strokes: [], features: [])
        req.background = background(opacity: 0.6)
        let pdf = String(decoding: GeoPDFExporter.document(req), as: UTF8.self)
        XCTAssertTrue(pdf.contains("/ImBg Do"))
        XCTAssertTrue(pdf.contains("/GSBg << /Type /ExtGState /ca 0.6"))
        XCTAssertTrue(pdf.contains("(Imagery \\251 Apple Maps) Tj") || pdf.contains("Apple Maps) Tj"))
        let plain = String(decoding: GeoPDFExporter.document(GeoPDFRequest(title: "bg", frame: frame, sheet: sheet, zone: zone,
                                                                           strokes: [], features: [])), as: UTF8.self)
        XCTAssertFalse(plain.contains("/ImBg"))
    }

    func testVectorExportWritesSidecarAndOmapTemplate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var req = VectorExportRequest(baseName: "bg", frame: frame, sheet: sheet, zone: zone, strokes: [])
        req.background = background()
        let urls = try VectorExporter.export(req, formats: [.omap, .dxf], to: dir)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)), ["bg.omap", "bg.dxf", "bg_basemap.png", "bg_basemap.pgw", "bg_basemap.prj"])
        let xml = OmapWriter.document(req)
        XCTAssertTrue(xml.contains("<template type=\"TemplateImage\""))
        XCTAssertTrue(xml.contains("path=\"bg_basemap.png\""))
        XCTAssertTrue(xml.contains("first_front_template=\"1\""))
        XCTAssertNotNil(XMLParser(data: Data(xml.utf8)).parse() ? true : nil)
    }
}
