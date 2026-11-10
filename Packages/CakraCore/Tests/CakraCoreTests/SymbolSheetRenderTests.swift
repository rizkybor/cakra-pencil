@testable import CakraCore
import CoreGraphics
import CoreText
import ImageIO
import XCTest

/// Visual check (not run by default): renders every symbol of OCCA's ISOM / ISSprOM sets and a colour-order scene to PNG
/// files. `OCCA_SYMBOL_SHEET_DIR=<folder>` turns it on; `OCCA_SYMBOL_SHEET_BEFORE=<folder>` adds the sets found there
/// (older `.occasym` files) above the current ones for a before / after comparison.
final class SymbolSheetRenderTests: XCTestCase {
    private let dpi = 900

    private func features(_ set: OccaSymbolFile, columns: Int, cell: (Double, Double), top: Double) -> (features: [Feature], labels: [(String, Point2D)], rows: Int) {
        let k = Double(set.scale) / 1000   // ground m per paper mm
        var out: [Feature] = [], labels: [(String, Point2D)] = []
        let list = set.symbols.filter { $0.kind != .text }
        for (i, s) in list.enumerated() {
            let x = Double(i % columns) * cell.0, y = top - Double(i / columns) * cell.1
            func g(_ px: Double, _ py: Double) -> BezierNode { BezierNode(point: Point2D(x: (x + px) * k, y: (y - py) * k)) }
            var f: Feature
            switch s.kind {
            case .line:
                f = Feature(kind: .line, colorHex: s.colorHex, widthMM: s.drawingWidthMM, nodes: [g(1, 6), g(5.5, 2.5), g(10, 5.5)],
                            symbolCode: s.code, symbolName: s.name)
                if let st = s.lineStyle { f.apply(st) }
            case .area:
                f = Feature(kind: .area, colorHex: s.colorHex, widthMM: 0.1, nodes: [g(1, 1.5), g(10.5, 1.5), g(10.5, 6.5), g(1, 6.5)],
                            symbolCode: s.code, symbolName: s.name)
            default:
                let big = (s.pointElements?.diameterMM ?? 1) < 2.5
                f = Feature.point(at: Point2D(x: (x + 5.5) * k, y: (y - 4) * k), elements: s.pointElements ?? [], sizeFactor: big ? 3 : 1,
                                  symbolCode: s.code, symbolName: s.name)
            }
            out.append(f)
            labels.append((s.code.hasSuffix(".0") ? String(s.code.dropLast(2)) : s.code, Point2D(x: x + 0.5, y: y - 7.6)))
        }
        let lookup = Dictionary(set.symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        return (out.withColorPriorities { code, _ in lookup[code] }, labels, (list.count + columns - 1) / columns)
    }

    private func write(_ ctx: CGContext, _ url: URL) throws {
        let img = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private func text(_ s: String, at p: CGPoint, size: Double, in ctx: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs)!)
        ctx.textPosition = p
        CTLineDraw(line, ctx)
    }

    private func sheet(_ sets: [(String, OccaSymbolFile)], to url: URL) throws {
        let columns = 12, cell = (12.0, 8.5)
        let pxPerMM = Double(dpi) / 25.4
        var blocks: [(String, OccaSymbolFile, Int)] = []
        for (title, f) in sets { blocks.append((title, f, features(f, columns: columns, cell: cell, top: 0).rows)) }
        let heightMM = blocks.reduce(0) { $0 + Double($1.2) * cell.1 + 8 }
        let w = Int(Double(columns) * cell.0 * pxPerMM), h = Int(heightMM * pxPerMM)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        var top = heightMM
        for (title, f, rows) in blocks {
            text(title, at: CGPoint(x: 1 * pxPerMM, y: (top - 5) * pxPerMM), size: 4 * pxPerMM, in: ctx)
            top -= 8
            let (list, labels, _) = features(f, columns: columns, cell: cell, top: top)
            let k = Double(f.scale) / 1000, p = k / pxPerMM
            let frame = MapFrame(origin: Point2D(x: 0, y: 0), widthM: Double(w) * p, heightM: Double(h) * p)
            RasterExporter.drawFeatures(list, in: ctx, frame: frame, pixelSize: p, height: h, dpi: dpi)
            for (code, at) in labels { text(code, at: CGPoint(x: at.x * pxPerMM, y: at.y * pxPerMM), size: 1.3 * pxPerMM, in: ctx) }
            top -= Double(rows) * cell.1
        }
        try write(ctx, url)
    }

    func testRenderSymbolSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["OCCA_SYMBOL_SHEET_DIR"] else { throw XCTSkip("Visual check only") }
        let before = ProcessInfo.processInfo.environment["OCCA_SYMBOL_SHEET_BEFORE"]
        func old(_ name: String) -> OccaSymbolFile? {
            before.flatMap { try? OccaSymbolFile.read(Data(contentsOf: URL(fileURLWithPath: $0).appendingPathComponent(name))) }
        }
        for (name, now, tag) in [(OccaStandardSymbols.isomFileName, OccaStandardSymbols.isomFile(), "ISOM"),
                                 (OccaStandardSymbols.issprFileName, OccaStandardSymbols.issprFile(), "ISSprOM")] {
            var sets: [(String, OccaSymbolFile)] = []
            if let o = old(name) { sets.append(("Before (\(o.name))", o)) }
            sets.append(("After (\(now.name), IOF Rev 6 + colour Rev 4)", now))
            try sheet(sets, to: URL(fileURLWithPath: dir).appendingPathComponent("OCCA-symbols-\(tag).png"))
        }
        try colourOrder(to: URL(fileURLWithPath: dir).appendingPathComponent("OCCA-colour-order.png"))
    }

    /// Lake over contours, marsh over green, road over paved area, 709 over the map, lower / upper purple.
    private func colourOrder(to url: URL) throws {
        let f = OccaStandardSymbols.isomFile()
        let lookup = Dictionary(f.symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        let k = 15.0   // m per mm at 1:15000
        func n(_ x: Double, _ y: Double) -> BezierNode { BezierNode(point: Point2D(x: x * k, y: y * k)) }
        func area(_ code: String, _ pts: [(Double, Double)]) -> Feature {
            let s = lookup[code]!
            return Feature(kind: .area, colorHex: s.colorHex, widthMM: 0.1, nodes: pts.map { n($0.0, $0.1) }, symbolCode: s.code, symbolName: s.name)
        }
        func line(_ code: String, _ pts: [(Double, Double)]) -> Feature {
            let s = lookup[code]!
            var l = Feature(kind: .line, colorHex: s.colorHex, widthMM: s.drawingWidthMM, nodes: pts.map { n($0.0, $0.1) }, symbolCode: s.code, symbolName: s.name)
            if let st = s.lineStyle { l.apply(st) }
            return l
        }
        // Object order is the "wrong" one on purpose (lower colours last): the colour order must fix it.
        var objs: [Feature] = [
            line("101.0", [(2, 4), (14, 12)]), line("101.0", [(2, 7), (14, 15)]), area("301.0", [(4, 3), (12, 3), (12, 13), (4, 13)]),
            line("102.0", [(1, 10), (15, 2)]),
            area("308.0", [(18, 3), (30, 3), (30, 13), (18, 13)]), area("410.0", [(17, 2), (25, 2), (25, 14), (17, 14)]),
            line("502.0", [(34, 8), (48, 8)]), area("501.0", [(36, 3), (46, 3), (46, 13), (36, 13)]),
            area("709.0", [(52, 3), (64, 3), (64, 13), (52, 13)]), area("521.0", [(55, 6), (59, 6), (59, 10), (55, 10)]),
            area("401.0", [(50, 2), (66, 2), (66, 14), (50, 14)]),
            line("516.0", [(70, 4), (84, 12)]), line("101.0", [(70, 10), (84, 6)]), line("305.0", [(70, 7), (84, 9)]),
            area("401.0", [(68, 2), (86, 2), (86, 14), (68, 14)]),
        ]
        objs.append(Feature.point(at: Point2D(x: 10 * k, y: 8 * k), elements: lookup["417.0"]!.pointElements!, sizeFactor: 2, symbolCode: "417.0",
                                  symbolName: lookup["417.0"]!.name))
        objs = objs.withColorPriorities { code, _ in lookup[code] }
        let sheet = SheetSpec(marginMM: 0, scaleDenominator: 15000)
        let frame = MapFrame(origin: Point2D(x: 0, y: 0), widthM: 88 * k, heightM: 16 * k)
        let c = Point2D(x: 77 * k, y: 8 * k)
        let o = CourseOverprint(marks: [.circle(center: c, radiusM: 2.5 * k), .polyline([Point2D(x: 70 * k, y: 3 * k), Point2D(x: 74.6 * k, y: 6.6 * k)], closed: false),
                                        .level(.upper), .width(0.35 * k), .polyline([Point2D(x: 79 * k, y: 3 * k), Point2D(x: 85 * k, y: 3 * k)], closed: false)],
                                lineWidthM: 0.35 * k, colorHex: "#A626FF")
        var req = RasterExportRequest(baseName: "order", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!, dpi: 600, format: .png,
                                      strokes: [], features: objs, includePRJ: false, overprint: o)
        req.background = nil
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("occa-order-\(UUID().uuidString)")
        let r = try RasterExporter.export(req, to: tmp)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.moveItem(at: r.imageURL, to: url)
        try FileManager.default.removeItem(at: tmp)
    }
}
