@testable import CakraCore
import XCTest

/// Size audit of every OCCA ISOM 2017-2 / ISSprOM 2019-2 symbol against the IOF specifications (Rev 6, Jan 2024; values
/// from the extracted reference), at the base scale and after enlargement to the map scale.
final class OccaSymbolSizeAuditTests: XCTestCase {
    typealias Line = (w: Double, dash: [Double]?)
    typealias Double2 = (edge: Double, inner: Double)

    // MARK: Expected values (paper mm at the base scale)

    static let isomLines: [String: Line] = [
        "101": (0.14, nil), "102": (0.25, nil), "103": (0.1, [2.0, 0.2]), "104": (0.25, nil), "105.1": (0.18, nil),
        "105.2": (0.18, nil), "106": (0.18, nil), "107": (0.25, nil), "108": (0.25, nil), "201": (0.35, nil),
        "202": (0.25, nil), "202.1": (0.25, nil), "301.2": (0.12, nil), "302.1": (0.1, nil), "302.2": (0.1, [1.25, 0.25]),
        "304": (0.3, nil), "305": (0.18, nil), "306": (0.18, [1.25, 0.25]), "307.1": (0.12, nil), "309": (0.25, nil),
        "415": (0.1, nil), "416": (0.22, nil), "416.1": (0.14, [0.3, 0.2]), "501.1": (0.1, nil), "503": (0.35, nil),
        "504": (0.35, [3.0, 0.25]), "505": (0.25, [2.0, 0.25]), "506": (0.18, [1.0, 0.25]), "507": (0.18, nil),
        "508": (0.14, [2.0, 0.25]), "510": (0.14, nil), "512": (0.18, nil), "513.1": (0.14, nil), "513.2": (0.14, nil),
        "514": (0.14, nil), "515": (0.25, nil), "516": (0.14, nil), "517": (0.14, nil), "518": (0.25, nil),
        "520.1": (0.18, nil), "521.2": (0.2, nil), "522.1": (0.1, nil), "523": (0.16, nil), "528": (0.14, nil),
        "529": (0.25, nil), "601": (0.1, nil), "601.1": (0.12, nil),
        "705": (0.35, nil), "707": (0.35, [2.0, 0.5]), "708": (0.7, nil), "709.1": (0.25, nil), "709.2": (0.25, [3.0, 0.5]),
    ]
    static let isomDouble: [String: Double2] = ["502": (0.14, 0.3), "509": (0.1, 0.25), "511": (0.2, 0.2), "532": (0.1, 0.4), "215": (0.1, 0.3)]
    /// Dotted lines: centre-to-centre spacing.
    static let isomDots: [String: Double] = ["108": 0.45, "309": 0.45, "416": 0.45]
    /// Point symbols: outside measure width × height (white masks excluded).
    static let isomPoints: [String: (Double, Double)] = [
        "109": (0.5, 0.5), "110": (0.8, 0.4), "111": (0.8, 0.4), "112": (0.8, 0.7), "115": (0.9, 0.9), "203.1": (0.8, 0.7),
        "203.2": (0.9, 0.9), "204": (0.4, 0.4), "205": (0.6, 0.6), "303": (0.8, 0.7), "311": (0.8, 0.8), "312": (0.9, 0.45),
        "313": (0.9, 0.9), "417": (0.9, 0.9), "418": (0.6, 0.6), "419": (0.9, 0.9), "524": (1.4 + 0.16, 0.8), "525": (1.0, 1.0),
        "526": (0.8, 0.8), "530": (0.8, 0.8), "531": (0.8, 0.8), "603": (0.3, 0.3),
    ]

    static let sprLines: [String: Line] = [
        "101": (0.21, nil), "102": (0.3, nil), "103": (0.15, [3.0, 0.3]), "104": (0.27, nil), "104.1": (0.37, nil),
        "105.1": (0.27, nil), "105.2": (0.27, nil), "107": (0.37, nil), "108": (0.37, nil), "201": (0.5, nil),
        "202": (0.3, nil), "202.1": (0.3, nil), "301.2": (0.18, nil), "302.1": (0.18, nil), "305": (0.21, nil),
        "306": (0.21, [1.87, 0.37]), "307.1": (0.18, nil), "309": (0.37, nil), "415": (0.15, nil), "416": (0.25, nil),
        "501.1": (0.1, nil), "501.2": (0.1, [0.7, 0.2]), "506": (0.27, [1.5, 0.37]), "507": (0.27, nil),
        "508": (0.21, [4.5, 0.75]), "510": (0.14, nil), "511": (0.14, nil), "512.2": (0.2, [0.25, 0.2]), "513.1": (0.21, nil),
        "513.2": (0.21, nil), "515": (0.4, nil), "516": (0.21, nil), "518": (0.4, nil), "520.1": (0.1, nil),
        "521.1": (0.14, nil), "522.2": (0.1, nil), "528": (0.21, nil), "529": (0.4, nil), "601": (0.14, nil), "601.1": (0.18, nil),
        "705": (0.35, nil), "707": (0.35, [2.0, 0.5]), "708": (1.0, nil), "709.1": (0.4, nil), "709.2": (0.4, [3.0, 0.5]),
        "710.2": (0.35, nil), "714.1": (0.1, nil),
    ]
    static let sprDouble: [String: Double2] = ["505": (0.12, 0.35), "509.1": (0.1, 0.25), "509.2": (0.08, 0.22), "532": (0.1, 0.4)]
    static let sprDots: [String: Double] = ["108": 0.6, "309": 0.6, "416": 0.6]
    static let sprPoints: [String: (Double, Double)] = [
        "109": (0.75, 0.75), "110": (1.2, 0.6), "111": (1.2, 0.6), "112": (1.1, 1.25), "115": (1.35, 1.35), "203": (1.1, 1.25),
        "204": (0.6, 0.6), "205": (0.9, 0.9), "303": (1.1, 1.25), "311": (0.9, 0.9), "312": (1.2, 0.6), "313": (1.2, 1.2),
        "417": (1.2, 1.2), "418": (0.8, 0.8), "419": (1.2, 1.2), "522.1": (0.5, 0.5), "524": (2.1 + 0.25, 1.2), "525": (1.5, 1.5),
        "526": (1.0, 1.0), "527": (1.5, 0.88), "530": (1.0, 1.0), "531": (1.2, 1.2),
    ]

    // MARK: Helpers

    private func sym(_ f: OccaSymbolFile, _ code: String) throws -> MapSymbol {
        let full = code.contains(".") ? code : code + ".0"
        return try XCTUnwrap(f.symbols.first { $0.code == full }, "\(f.standard) \(code) missing")
    }

    /// Outside-measure bounding box of a point symbol (paper mm), white masks excluded.
    private func bbox(_ s: MapSymbol, mask: String = "#FFFFFF") -> (Double, Double) {
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for e in s.pointElements ?? [] where !(e.colorHex == mask && e.priority > (s.colorPriority ?? 0)) {
            let r: Double
            switch e.kind {
            case .dot: r = e.diameterMM / 2
            case .circle: r = e.diameterMM / 2 + e.lineWidthMM / 2
            case .line: r = e.lineWidthMM / 2
            case .area: r = 0
            }
            for p in e.points { minX = min(minX, p.x - r); maxX = max(maxX, p.x + r); minY = min(minY, p.y - r); maxY = max(maxY, p.y + r) }
        }
        return (maxX - minX, maxY - minY)
    }

    private func audit(_ f: OccaSymbolFile, lines: [String: Line], doubles: [String: Double2], dots: [String: Double],
                       points: [String: (Double, Double)], control: Double, finish: [Double], start: Double) throws {
        for (code, e) in lines {
            let st = try XCTUnwrap(try sym(f, code).lineStyle, "\(code) line style")
            XCTAssertEqual(st.widthMM, e.w, accuracy: 0.001, "\(f.standard) \(code) width")
            if let d = e.dash { XCTAssertEqual(st.dashMM, d, "\(f.standard) \(code) dash") }
        }
        for (code, e) in doubles {
            let st = try XCTUnwrap(try sym(f, code).lineStyle)
            XCTAssertEqual(st.casing?.innerWidthMM ?? -1, e.inner, accuracy: 0.001, "\(f.standard) \(code) inside")
            XCTAssertEqual(st.widthMM, e.inner + 2 * e.edge, accuracy: 0.001, "\(f.standard) \(code) edges")
        }
        for (code, cc) in dots {
            let d = try XCTUnwrap(try sym(f, code).lineStyle?.dashMM)
            XCTAssertEqual(d[0] + d[1], cc, accuracy: 0.001, "\(f.standard) \(code) dot spacing")
        }
        for (code, e) in points {
            let b = bbox(try sym(f, code))
            XCTAssertEqual(b.0, e.0, accuracy: 0.011, "\(f.standard) \(code) width OM")
            XCTAssertEqual(b.1, e.1, accuracy: 0.011, "\(f.standard) \(code) height OM")
        }
        XCTAssertEqual(try sym(f, "703").pointElements?.first?.diameterMM ?? 0, control, accuracy: 0.001, "control circle")
        XCTAssertEqual(try sym(f, "706").pointElements?.map(\.diameterMM).sorted(), finish, "finish")
        let tri = try XCTUnwrap(try sym(f, "701").pointElements?.first?.points)
        XCTAssertEqual(hypot(tri[1].x - tri[2].x, tri[1].y - tri[2].y), start, accuracy: 0.001, "start triangle side")
        // Every line and point of the set is covered by the audit (except a few with figure-only sizes).
        let figureOnly: Set<String> = ["101.1", "103.1", "207.0", "512.1", "519.0", "527.0", "602.0", "701.0", "702.0", "703.0",
                                       "706.0", "710.0", "710.1", "711.0", "712.0", "713.0", "715.0"]
        let covered = Set((Array(lines.keys) + Array(doubles.keys) + Array(points.keys)).map { $0.contains(".") ? $0 : $0 + ".0" })
        for s in f.symbols where (s.kind == .line || s.kind == .point) && !covered.contains(s.code) && !figureOnly.contains(s.code) {
            XCTFail("\(f.standard) \(s.code) \(s.name) has no expected size in the audit")
        }
    }

    // MARK: Tests

    func testISOMAtBaseScale() throws {
        try audit(OccaStandardSymbols.isomFile(), lines: Self.isomLines, doubles: Self.isomDouble, dots: Self.isomDots,
                  points: Self.isomPoints, control: 5.0, finish: [4.0, 6.0], start: 6.0)
    }

    func testISSprOMAtBaseScale() throws {
        try audit(OccaStandardSymbols.issprFile(), lines: Self.sprLines, doubles: Self.sprDouble, dots: Self.sprDots,
                  points: Self.sprPoints, control: 6.0, finish: [5.0, 7.0], start: 7.0)
    }

    /// Every symbol (lines, double lines, dashes, points, patterns, decorations) follows the map scale's enlargement.
    func testEverySymbolFollowsTheMapScale() throws {
        for (file, mapScales) in [(OccaStandardSymbols.isomFile(), [15000: 1.0, 10000: 1.5, 7500: 2.0]),
                                  (OccaStandardSymbols.issprFile(), [4000: 1.0, 3000: 4.0 / 3, 5000: 1.0])] {
            let base = file.symbolSet(sourceFile: "x.occasym")
            for (scale, expected) in mapScales {
                let k = base.sizeFactor(forMapScale: scale)
                XCTAssertEqual(k, expected, accuracy: 1e-9, "\(file.standard) at 1:\(scale)")
                let sized = base.scaled(by: k)
                for (a, b) in zip(base.symbols, sized.symbols) {
                    func near(_ x: Double?, _ y: Double?, _ what: String) {
                        guard let x, let y else { return }
                        XCTAssertEqual(y, x * k, accuracy: 0.0011, "\(file.standard) \(a.code) \(what) at 1:\(scale)")
                    }
                    near(a.lineWidthMM, b.lineWidthMM, "width")
                    near(a.lineStyle?.widthMM, b.lineStyle?.widthMM, "line width")
                    near(a.lineStyle?.casing?.innerWidthMM, b.lineStyle?.casing?.innerWidthMM, "inner width")
                    for (x, y) in zip(a.lineStyle?.dashMM ?? [], b.lineStyle?.dashMM ?? []) { near(x, y, "dash") }
                    for (x, y) in zip(a.pointElements ?? [], b.pointElements ?? []) {
                        near(x.diameterMM, y.diameterMM, "point diameter"); near(x.lineWidthMM, y.lineWidthMM, "point line")
                    }
                    for (x, y) in zip(a.patterns ?? [], b.patterns ?? []) { near(x.sizeMM, y.sizeMM, "pattern"); near(x.spacingMM, y.spacingMM, "pattern spacing") }
                    if let x = a.decoration, let y = b.decoration { near(x.sizeMM, y.sizeMM, "decoration"); near(x.spacingMM, y.spacingMM, "decoration spacing") }
                }
            }
        }
    }

    /// Objects already on the map follow a scale change (e.g. Reselect area 1:15000 → 1:10000).
    func testObjectsFollowAScaleChange() {
        XCTAssertEqual(MapStandard.symbolSizeFactor(fromScale: 15000, toScale: 10000), 1.5, accuracy: 1e-9)
        XCTAssertEqual(MapStandard.symbolSizeFactor(fromScale: 10000, toScale: 15000), 1 / 1.5, accuracy: 1e-9)
        XCTAssertEqual(MapStandard.symbolSizeFactor(fromScale: 4000, toScale: 3000), 4.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(MapStandard.symbolSizeFactor(fromScale: 4000, toScale: 10000), 1, "Sprint ↔ forest: unchanged")
        var road = Feature(name: "", kind: .line, colorHex: "#E8AE80", widthMM: 0.58, nodes: [])
        road.symbolCode = "502.0"; road.innerWidthMM = 0.3; road.casingColorHex = "#000000"; road.dashMM = [2.0, 0.25]
        let big = road.withSymbolSize(scaledBy: 1.5)
        XCTAssertEqual(big.widthMM, 0.87, accuracy: 0.001); XCTAssertEqual(big.innerWidthMM ?? 0, 0.45, accuracy: 0.001)
        XCTAssertEqual(big.dashMM, [3.0, 0.375])
        let sketch = Feature(name: "", kind: .line, colorHex: "#000000", widthMM: 0.3, nodes: [])
        XCTAssertEqual(sketch.withSymbolSize(scaledBy: 1.5).widthMM, 0.3, "Sketch lines without a symbol keep their width")
    }
}
