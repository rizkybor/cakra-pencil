@testable import CakraCore
import XCTest

/// Size audit of every OCCA ISOM 2017-2 / ISSprOM 2019-2 symbol against the IOF specifications (Rev 6, Jan 2024; values
/// from the extracted reference) and every ISInOM 6.7.3 symbol (1:700), at the base scale and after enlargement to the
/// map scale.
final class OccaSymbolSizeAuditTests: XCTestCase {
    typealias Line = (w: Double, dash: [Double]?)
    typealias Double2 = (edge: Double, inner: Double)

    // MARK: Expected values (paper mm at the base scale)

    /// ISOM 2017-2 Rev 6 (text and precise definitions p.39–40).
    static let isomLines: [String: Line] = [
        "101": (0.14, nil), "102": (0.25, nil), "103": (0.1, [2.0, 0.2]), "104": (0.25, nil), "105.1": (0.18, nil),
        "105.2": (0.18, nil), "106": (0.18, [1.65, 0.35]), "107": (0.25, nil), "108": (0.25, nil), "201": (0.35, nil),
        "202": (0.25, nil), "202.1": (0.25, nil), "301.2": (0.12, nil), "302.1": (0.1, nil), "302.2": (0.1, [1.25, 0.25]),
        "304": (0.3, nil), "305": (0.18, nil), "306": (0.18, [1.25, 0.25]), "307.1": (0.12, nil), "309": (0.25, nil),
        "415": (0.1, nil), "416": (0.22, nil), "416.1": (0.14, [0.3, 0.2]), "501.1": (0.1, nil), "503": (0.35, nil),
        "504": (0.35, [3.0, 0.25]), "505": (0.25, [2.0, 0.25]), "506": (0.18, [1.0, 0.25]), "507": (0.18, [1.0, 0.25, 1.0, 0.8]),
        "508": (0.14, [2.0, 0.25]), "510": (0.14, nil), "512": (0.18, nil), "513.1": (0.14, nil), "513.2": (0.14, nil),
        "514": (0.14, [1.65, 0.35]), "515": (0.25, nil), "516": (0.14, nil), "517": (0.14, [1.65, 0.35]), "518": (0.25, nil),
        "520.1": (0.18, nil), "521.2": (0.2, nil), "522.1": (0.1, nil), "523": (0.16, nil), "528": (0.14, nil),
        "529": (0.25, nil), "601": (0.1, nil), "601.1": (0.12, nil),
        "705": (0.35, nil), "707": (0.35, [2.0, 0.5]), "708": (0.7, nil), "709.1": (0.25, nil), "709.2": (0.25, [3.0, 0.5]),
    ]
    /// Double lines with a fill: edge width, inside measure.
    static let isomDouble: [String: Double2] = ["502": (0.14, 0.3), "509": (0.1, 0.25)]
    /// Double lines with a transparent inside: edge width, centre-to-centre distance (215: two 0.10 lines, 0.10 gap;
    /// 511: 0.14 at ≥ 0.4 CC; 532: 0.1, ≥ 0.4 IM).
    static let isomEdges: [String: (edge: Double, cc: Double)] = ["215": (0.1, 0.2), "511": (0.14, 0.4), "532": (0.1, 0.5)]
    /// Dotted lines: centre-to-centre spacing.
    static let isomDots: [String: Double] = ["108": 0.45, "309": 0.45, "416": 0.45]
    /// Point symbols: outside measure width × height (white masks excluded; flat ends and mitred corners as drawn).
    static let isomPoints: [String: (Double, Double)] = [
        "109": (0.5, 0.5), "110": (0.8, 0.4), "111": (0.8, 0.4), "112": (0.7, 0.8), "115": (0.9, 0.9 * 3.0.squareRoot() / 2),
        "203.1": (0.7, 0.8), "203.2": (0.9, 0.9), "204": (0.4, 0.4), "205": (0.6, 0.6), "303": (0.7, 0.8), "311": (0.8, 0.8),
        "312": (0.9, 0.45), "417": (0.9, 0.9), "418": (0.6, 0.6), "419": (0.9, 0.9), "524": (1.4, 1.4), "525": (1.0, 1.0),
        "526": (0.8, 0.8), "527": (0.9, 0.9), "530": (0.8, 0.8), "531": (0.8, 0.8), "602": (4.0, 4.0), "603": (0.3, 0.3),
        "702": (0.6, 2.5), "712": (4.0, 4.0), "713": (3.5, 3.5),
    ]
    /// Point symbols inside a circle of this outside diameter (313 star).
    static let isomRound: [String: Double] = ["313": 0.9]
    /// Positions (centre of gravity) above the bottom of the symbol (outside measure).
    static let isomCentres: [String: Double] = ["111": 0.197, "112": 0.498, "303": 0.498, "203.1": 0.489, "312": 0.216, "713": 1.879]
    /// Positions below the top.
    static let isomCentresFromTop: [String: Double] = ["525": 0.308, "527": 0.354]
    /// Line decorations: kind, size, width, spacing, angle, pair distance, half-dot offset. Tags measured as the IOF
    /// drawings do: ISOM 104 / 201 / 202 from the line edge, 516 / 518 from the centre line (`reach`).
    static let isomDecorations: [String: Deco] = [
        "104": Deco(.tags, 0.4, 0.14, 0.5), "201": Deco(.tags, 0.4, 0.12, 0.5), "202.1": Deco(.tags, 0.4, 0.12, 0.5),
        "105.1": Deco(.dots, 0.45, 0, 2.0), "105.2": Deco(.halfDots, 0.45, 0, 1.0, offset: 0.07),
        "106": Deco(.dots, 0.45, 0, 2.0, onDashes: true), "107": Deco(.taper, 0.75, 0, 0),
        "510": Deco(.bars, 0.3, 0.14, 0), "512": Deco(.endTicks, 0.4, 0.18, 0, angle: 60),
        "513.1": Deco(.dots, 0.4, 0, 2.0), "513.2": Deco(.halfDots, 0.4, 0, 1.0, offset: 0.05),
        "514": Deco(.dots, 0.4, 0, 2.0, onDashes: true), "515": Deco(.dots, 0.6, 0, 3.0, pair: 0.8),
        "516": Deco(.tags, 0.4, 0.14, 2.0, angle: 60, reach: true), "517": Deco(.tags, 0.4, 0.14, 2.0, angle: 60, onDashes: true, reach: true),
        "518": Deco(.doubleTags, 0.4, 0.14, 2.5, angle: 60, pair: 0.6, reach: true),
        "528": Deco(.chevrons, 0.4, 0.14, 2.0, angle: 45), "529": Deco(.chevrons, 0.4, 0.14, 2.0, angle: 45, pair: 0.6),
    ]
    /// Area patterns: kind, size, spacing (random patterns: marks per mm² range), dashes, angle.
    static let isomPatterns: [String: [Pat]] = [
        "114": [Pat(.dots, 0.2, density: 7...9)], "212": [Pat(.dots, 0.2, density: 10...12)],
        "208": [Pat(.triangles, 0.8, density: 0.8...1.0, sides: [0.8, 0.6, 0.5])],
        "209": [Pat(.triangles, 0.8, density: 2...3, sides: [0.8, 0.6, 0.5])],
        "308": [Pat(.lines, 0.1, cc: 0.3, angle: 90)], "310": [Pat(.lines, 0.1, cc: 0.3, dash: [0.9, 0.25], angle: 90)],
        "414": [Pat(.lines, 0.2, cc: 0.85, dash: [1.3, 0.6])],
        "709": [Pat(.lines, 0.2, cc: 1.2, angle: 45), Pat(.lines, 0.2, cc: 1.2, angle: 135)],
    ]
    static let isomText: [String: Double] = ["102.1": 1.5, "603.1": 1.5, "704": 4.0]

    /// ISSprOM 2019-2 Rev 6 (text and precise definitions p.30–31).
    static let sprLines: [String: Line] = [
        "101": (0.21, nil), "102": (0.3, nil), "103": (0.15, [3.0, 0.3]), "104": (0.27, nil),
        "105.1": (0.27, nil), "105.2": (0.27, nil), "107": (0.37, nil), "108": (0.37, nil), "201": (0.5, nil),
        "202": (0.3, nil), "202.1": (0.3, nil), "301.2": (0.18, nil), "302.1": (0.18, nil), "305": (0.21, nil),
        "306": (0.21, [1.87, 0.37]), "307.1": (0.18, nil), "309": (0.37, nil), "415": (0.15, nil), "416": (0.25, nil),
        "501.1": (0.1, nil), "501.2": (0.1, [0.7, 0.2]), "506": (0.27, [1.5, 0.37]), "507": (0.27, [1.5, 0.37, 1.5, 1.5]),
        "508": (0.21, [4.5, 0.75]), "510": (0.14, nil), "512.1": (0.7, nil), "512.2": (0.2, [0.25, 0.2]), "513.1": (0.21, nil),
        "513.2": (0.21, nil), "515": (0.4, nil), "516": (0.21, nil), "518": (0.4, nil), "520.1": (0.1, nil),
        "521.1": (0.14, nil), "522.2": (0.1, nil), "528": (0.21, nil), "529": (0.4, nil), "601": (0.14, nil), "601.1": (0.18, nil),
        "705": (0.35, nil), "707": (0.35, [2.0, 0.5]), "708": (1.0, nil), "709.1": (0.4, nil), "709.2": (0.4, [3.0, 0.5]),
        "714.1": (0.1, nil),
    ]
    static let sprDouble: [String: Double2] = ["505": (0.12, 0.35), "509.1": (0.1, 0.25)]
    static let sprEdges: [String: (edge: Double, cc: Double)] = ["509.2": (0.08, 0.3), "511": (0.14, 1.5), "532": (0.1, 0.5), "710.2": (0.35, 1.5)]
    static let sprDots: [String: Double] = ["108": 0.6, "309": 0.6, "416": 0.6]
    static let sprPoints: [String: (Double, Double)] = [
        "109": (0.75, 0.75), "110": (1.2, 0.6), "111": (1.2, 0.6), "112": (1.1, 1.25), "115": (1.35, 1.35 * 3.0.squareRoot() / 2),
        "203": (1.1, 1.25), "204": (0.6, 0.6), "205": (0.9, 0.9), "303": (1.1, 1.25), "311": (0.9, 0.9), "312": (1.2, 0.6),
        "417": (1.2, 1.2), "418": (0.8, 0.8), "419": (1.2, 1.2), "519": (1.5, 1.4), "522.1": (0.5, 0.5), "524": (2.1, 2.1),
        "525": (1.5, 1.5), "526": (1.0, 1.0), "527": (1.5, 1.5), "530": (1.0, 1.0), "531": (1.2, 1.2), "602": (4.0, 4.0),
        "702": (0.6, 2.5),
    ]
    static let sprRound: [String: Double] = ["313": 1.2]
    static let sprCentres: [String: Double] = ["111": 0.6 - 0.296, "312": 0.6 - 0.296, "112": 0.778, "203": 0.778, "303": 0.778]
    static let sprCentresFromTop: [String: Double] = ["525": 0.462, "527": 0.59]
    static let sprDecorations: [String: Deco] = [
        // 104 / 201 / 202: tags 0.75 outside measure including the line (`om`).
        "104": Deco(.tags, 0.75, 0.21, 0.75, om: true), "201": Deco(.tags, 0.75, 0.18, 0.75, om: true),
        "202.1": Deco(.tags, 0.75, 0.18, 0.75, om: true),
        "105.1": Deco(.dots, 0.7, 0, 3.75), "105.2": Deco(.halfDots, 0.7, 0, 1.9, offset: 0.11), "107": Deco(.taper, 0.75, 0, 0),
        "510": Deco(.bars, 0.3, 0.14, 0), "512.1": Deco(.triangles, 0.7, 0, 0.7),
        "513.1": Deco(.dots, 0.6, 0, 3.75), "513.2": Deco(.halfDots, 0.6, 0, 1.9, offset: 0.09),
        "516": Deco(.tags, 0.75, 0.14, 3.75, angle: 60, reach: true), "518": Deco(.doubleTags, 0.75, 0.14, 3.75, angle: 60, pair: 0.9, reach: true),
        "528": Deco(.chevrons, 0.75, 0.14, 3.75, angle: 45), "529": Deco(.chevrons, 0.75, 0.14, 3.75, angle: 45, pair: 0.9),
    ]
    static let sprPatterns: [String: [Pat]] = [
        "208": [Pat(.triangles, 0.96, density: 0.5...0.8, sides: [0.96, 0.72, 0.6])],
        "308": [Pat(.lines, 0.12, cc: 0.38, angle: 90)], "310": [Pat(.lines, 0.12, cc: 0.38, dash: [1.0, 0.35], angle: 90)],
        "414": [Pat(.lines, 0.3, cc: 1.3, dash: [2.0, 0.9])], "533": [Pat(.dots, 0.55, cc: 0.75, angle: 45)],
        "709": [Pat(.lines, 0.2, cc: 1.2, angle: 45), Pat(.lines, 0.2, cc: 1.2, angle: 135)],
    ]
    static let sprText: [String: Double] = ["102.1": 1.52, "704": 4.0]

    struct Deco {
        var kind: LineDecoration.Kind, size: Double, width: Double, spacing: Double
        var angle: Double = 90, pair: Double? = nil, offset: Double? = nil, onDashes = false
        /// `size` is measured from the centre line (fence tags) / including the line (`om`), not from the line edge.
        var reach = false, om = false

        init(_ kind: LineDecoration.Kind, _ size: Double, _ width: Double, _ spacing: Double, angle: Double = 90, pair: Double? = nil,
             offset: Double? = nil, onDashes: Bool = false, reach: Bool = false, om: Bool = false) {
            self.kind = kind; self.size = size; self.width = width; self.spacing = spacing; self.angle = angle
            self.pair = pair; self.offset = offset; self.onDashes = onDashes; self.reach = reach; self.om = om
        }
    }

    struct Pat {
        var kind: AreaPattern.Kind, size: Double, cc: Double?, density: ClosedRange<Double>?, dash: [Double]?, angle: Double, sides: [Double]?

        init(_ kind: AreaPattern.Kind, _ size: Double, cc: Double? = nil, density: ClosedRange<Double>? = nil, dash: [Double]? = nil,
             angle: Double = 0, sides: [Double]? = nil) {
            self.kind = kind; self.size = size; self.cc = cc; self.density = density; self.dash = dash; self.angle = angle; self.sides = sides
        }
    }

    /// ISInOM 6.7.3 at 1:700.
    static let inLines: [String: Line] = [
        "1102": (0.8, nil), "1103": (0.4, nil), "1103.1": (0.4, nil), "1103.2": (0.3, nil), "1103.3": (0.3, nil),
        "516": (0.21, nil), "518": (0.4, nil), "1104": (0.3, nil), "1105": (0.35, nil), "1106": (0.32, nil), "520.2": (0.2, nil),
        "1110": (0.1, nil), "1111": (0.15, [0.8, 0.3]), "1201": (0.21, nil), "1202": (0.3, nil), "1204": (0.3, nil),
        "1207.1": (0.4, nil), "512.2": (0.2, [0.25, 0.2]), "1223": (0.1, nil), "301.2": (0.18, nil), "302.4": (0.18, nil),
        "1404": (0.16, nil), "1775": (0.7, nil), "1784": (2.5, nil), "1785": (1.25, nil),
        "705": (0.35, nil), "707": (0.35, [2.0, 0.75]), "708": (1.0, nil), "709.4": (0.4, nil), "714.1": (0.1, nil),
    ]
    static let inDots: [String: Double] = ["1106": 0.5]
    static let inPoints: [String: (Double, Double)] = [
        "1107": (0.7, 0.7), "1108": (1.58, 1.58), "1109": (0.56, 0.56), "1302": (0.96, 1.08), "1303": (0.91, 0.91),
        "417": (1.2, 1.2), "418": (0.8, 0.8), "526": (0.96, 0.96), "530": (0.96, 0.96), "1771.1": (2.39, 3.69),
        // 531: the OCAD shape, 1.2 OM with flat line ends (this box counts the diagonal ends as round: 1.26).
        "531": (1.26, 1.26),
    ]
    /// ISInOM symbols whose sizes come from the figures (spiral stairs, sink, water feature, directions…) or that are
    /// approximations (512.1, 1216, 1771.2).
    static let inFigureOnly: Set<String> = ["702.0", "512.1", "1201.1", "1208.0", "1209.0", "1210.0", "1211.0", "1216.0", "1304.0", "1305.0",
                                            "1703.0", "1720.0", "1771.2", "1772.0", "1773.0", "1774.0"]

    // MARK: Helpers

    private func sym(_ f: OccaSymbolFile, _ code: String) throws -> MapSymbol {
        let full = code.contains(".") ? code : code + ".0"
        return try XCTUnwrap(f.symbols.first { $0.code == full }, "\(f.standard) \(code) missing")
    }

    /// Outside-measure box of a point symbol (paper mm), white masks excluded: round line ends / joins add half the
    /// line width all round; flat (butt) ends and mitred corners follow the line's outline.
    private func outline(_ s: MapSymbol, mask: String = "#FFFFFF") -> [Point2D] {
        var out: [Point2D] = []
        for e in s.pointElements ?? [] where !(e.colorHex == mask && e.priority > (s.colorPriority ?? 0)) {
            switch e.kind {
            case .dot, .circle:
                let r = e.kind == .dot ? e.diameterMM / 2 : e.diameterMM / 2 + e.lineWidthMM / 2
                let c = e.points[0]
                out += (0..<72).map { i in Point2D(x: c.x + r * cos(Double(i) * .pi / 36), y: c.y + r * sin(Double(i) * .pi / 36)) }
            case .area:
                out += e.points
            case .line where e.flatEnds == true:
                let h = e.lineWidthMM / 2, p = e.points
                func n(_ a: Point2D, _ b: Point2D) -> Point2D {
                    let l = a.distance(to: b); return Point2D(x: -(b.y - a.y) / l * h, y: (b.x - a.x) / l * h)
                }
                for i in 0..<(p.count - 1) {
                    let v = n(p[i], p[i + 1])
                    out += [p[i] + v, p[i] - v, p[i + 1] + v, p[i + 1] - v]
                    // Mitre at the next vertex.
                    if i + 2 < p.count {
                        let w = n(p[i + 1], p[i + 2]), m = Point2D(x: v.x + w.x, y: v.y + w.y)
                        let dot = (v.x * w.x + v.y * w.y) / (h * h)
                        if dot > -0.99 {
                            let k = 2 / (1 + dot)
                            out += [p[i + 1] + Point2D(x: m.x * k / 2, y: m.y * k / 2), p[i + 1] - Point2D(x: m.x * k / 2, y: m.y * k / 2)]
                        }
                    }
                }
            case .line:
                let r = e.lineWidthMM / 2
                for c in e.points { out += [c + Point2D(x: r, y: 0), c - Point2D(x: r, y: 0), c + Point2D(x: 0, y: r), c - Point2D(x: 0, y: r)] }
            }
        }
        return out
    }

    private func bbox(_ s: MapSymbol) -> (w: Double, h: Double, minY: Double, maxY: Double) {
        let pts = outline(s)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return ((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0), ys.min() ?? 0, ys.max() ?? 0)
    }

    private func audit(_ f: OccaSymbolFile, lines: [String: Line], doubles: [String: Double2], dots: [String: Double],
                       points: [String: (Double, Double)], control: Double, finish: [Double], start: Double,
                       edges: [String: (edge: Double, cc: Double)] = [:], round: [String: Double] = [:],
                       centres: [String: Double] = [:], centresFromTop: [String: Double] = [:],
                       decorations: [String: Deco] = [:], patterns: [String: [Pat]] = [:], text: [String: Double] = [:],
                       moreFigureOnly: Set<String> = []) throws {
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
        for (code, e) in edges {
            let s = try sym(f, code)
            let d = try XCTUnwrap(s.decoration, "\(code) edges")
            XCTAssertEqual(d.kind, .edges, "\(f.standard) \(code): transparent double line")
            XCTAssertTrue(d.replacesLine)
            XCTAssertNil(s.lineStyle?.casing, "\(f.standard) \(code): no fill between the edges")
            XCTAssertEqual(d.widthMM, e.edge, accuracy: 0.001, "\(f.standard) \(code) edge width")
            XCTAssertEqual(d.sizeMM, e.cc, accuracy: 0.001, "\(f.standard) \(code) edge distance (CC)")
            XCTAssertEqual(s.lineStyle?.widthMM ?? 0, e.cc + e.edge, accuracy: 0.001, "\(f.standard) \(code) outside width")
        }
        for (code, cc) in dots {
            let d = try XCTUnwrap(try sym(f, code).lineStyle?.dashMM)
            XCTAssertEqual(d[0] + d[1], cc, accuracy: 0.001, "\(f.standard) \(code) dot spacing")
        }
        for (code, e) in points {
            let b = bbox(try sym(f, code))
            XCTAssertEqual(b.w, e.0, accuracy: 0.011, "\(f.standard) \(code) width OM")
            XCTAssertEqual(b.h, e.1, accuracy: 0.011, "\(f.standard) \(code) height OM")
        }
        for (code, om) in round {
            let r = outline(try sym(f, code)).map { hypot($0.x, $0.y) }.max() ?? 0
            XCTAssertEqual(2 * r, om, accuracy: 0.011, "\(f.standard) \(code) inside a circle of ø\(om)")
        }
        for (code, above) in centres {
            XCTAssertEqual(-bbox(try sym(f, code)).minY, above, accuracy: 0.011, "\(f.standard) \(code) centre of gravity above the bottom")
        }
        for (code, below) in centresFromTop {
            XCTAssertEqual(bbox(try sym(f, code)).maxY, below, accuracy: 0.011, "\(f.standard) \(code) centre of gravity below the top")
        }
        for (code, e) in decorations {
            let s = try sym(f, code)
            let d = try XCTUnwrap(s.decoration, "\(f.standard) \(code) decoration")
            let lw = s.lineStyle?.widthMM ?? 0
            let size = e.reach ? d.sizeMM + lw / 2 : e.om ? d.sizeMM + lw : d.sizeMM
            XCTAssertEqual(d.kind, e.kind, "\(f.standard) \(code) decoration kind")
            XCTAssertEqual(size, e.size, accuracy: 0.001, "\(f.standard) \(code) decoration size")
            XCTAssertEqual(d.widthMM, e.width, accuracy: 0.001, "\(f.standard) \(code) decoration width")
            XCTAssertEqual(d.spacingMM, e.spacing, accuracy: 0.001, "\(f.standard) \(code) decoration spacing")
            XCTAssertEqual(d.angleDeg, e.angle, accuracy: 0.001, "\(f.standard) \(code) decoration angle")
            XCTAssertEqual(d.pairMM, e.pair, "\(f.standard) \(code) pair distance")
            XCTAssertEqual(d.offsetMM, e.offset, "\(f.standard) \(code) half-dot offset")
            XCTAssertEqual(d.onDashes == true, e.onDashes, "\(f.standard) \(code) marks on the dashes")
        }
        for (code, list) in patterns {
            let ps = try XCTUnwrap(try sym(f, code).patterns, "\(f.standard) \(code) patterns")
            XCTAssertEqual(ps.count, list.count, "\(f.standard) \(code) pattern count")
            for (p, e) in zip(ps, list) {
                XCTAssertEqual(p.kind, e.kind, "\(f.standard) \(code) pattern kind")
                XCTAssertEqual(p.sizeMM, e.size, accuracy: 0.001, "\(f.standard) \(code) pattern size")
                if let cc = e.cc { XCTAssertEqual(p.spacingMM, cc, accuracy: 0.001, "\(f.standard) \(code) pattern spacing") }
                if let r = e.density {
                    XCTAssertTrue(r.contains(1 / (p.spacingMM * p.spacingMM)), "\(f.standard) \(code) \(1 / (p.spacingMM * p.spacingMM)) per mm² in \(r)")
                }
                XCTAssertEqual(p.dashMM, e.dash, "\(f.standard) \(code) pattern dashes")
                if e.dash != nil { XCTAssertEqual(p.staggered, true, "\(f.standard) \(code) rows offset") }
                XCTAssertEqual(p.angleDeg, e.angle, accuracy: 0.001, "\(f.standard) \(code) pattern angle")
                XCTAssertEqual(p.sidesMM, e.sides, "\(f.standard) \(code) triangle sides")
                if e.sides != nil { XCTAssertEqual(p.random, true, "\(f.standard) \(code) random placement and rotation") }
            }
        }
        for (code, h) in text { XCTAssertEqual(try sym(f, code).textSizeMM ?? 0, h, accuracy: 0.001, "\(f.standard) \(code) text height") }
        XCTAssertEqual(try sym(f, "703").pointElements?.first?.diameterMM ?? 0, control, accuracy: 0.001, "control circle")
        XCTAssertEqual(try sym(f, "706").pointElements?.map(\.diameterMM).sorted(), finish, "finish")
        let tri = try XCTUnwrap(try sym(f, "701").pointElements?.first?.points)
        XCTAssertEqual(hypot(tri[1].x - tri[2].x, tri[1].y - tri[2].y), start, accuracy: 0.001, "start triangle side")
        // Every line and point of the set is covered by the audit (except a few with figure-only sizes).
        let figureOnly: Set<String> = ["101.1", "103.1", "207.0", "512.1", "519.0", "701.0", "703.0",
                                       "706.0", "710.0", "710.1", "711.0", "715.0"]
        let covered = Set((Array(lines.keys) + Array(doubles.keys) + Array(edges.keys) + Array(points.keys) + Array(round.keys))
            .map { $0.contains(".") ? $0 : $0 + ".0" })
        for s in f.symbols where (s.kind == .line || s.kind == .point) && !covered.contains(s.code) && !figureOnly.contains(s.code)
            && !moreFigureOnly.contains(s.code) {
            XCTFail("\(f.standard) \(s.code) \(s.name) has no expected size in the audit")
        }
    }

    // MARK: Tests

    func testISOMAtBaseScale() throws {
        try audit(OccaStandardSymbols.isomFile(), lines: Self.isomLines, doubles: Self.isomDouble, dots: Self.isomDots,
                  points: Self.isomPoints, control: 5.0, finish: [4.0, 6.0], start: 6.0, edges: Self.isomEdges, round: Self.isomRound,
                  centres: Self.isomCentres, centresFromTop: Self.isomCentresFromTop, decorations: Self.isomDecorations,
                  patterns: Self.isomPatterns, text: Self.isomText)
    }

    func testISSprOMAtBaseScale() throws {
        try audit(OccaStandardSymbols.issprFile(), lines: Self.sprLines, doubles: Self.sprDouble, dots: Self.sprDots,
                  points: Self.sprPoints, control: 6.0, finish: [5.0, 7.0], start: 7.0, edges: Self.sprEdges, round: Self.sprRound,
                  centres: Self.sprCentres, centresFromTop: Self.sprCentresFromTop, decorations: Self.sprDecorations,
                  patterns: Self.sprPatterns, text: Self.sprText)
    }

    func testISInOMAtBaseScale() throws {
        try audit(OccaStandardSymbols.isinomFile(), lines: Self.inLines, doubles: [:], dots: Self.inDots,
                  points: Self.inPoints, control: 6.0, finish: [5.0, 7.0], start: 7.0, moreFigureOnly: Self.inFigureOnly)
    }

    /// Every symbol (lines, double lines, dashes, points, patterns, decorations) follows the map scale's enlargement.
    func testEverySymbolFollowsTheMapScale() throws {
        for (file, mapScales) in [(OccaStandardSymbols.isomFile(), [15000: 1.0, 10000: 1.5, 7500: 2.0]),
                                  (OccaStandardSymbols.issprFile(), [4000: 1.0, 3000: 4.0 / 3, 5000: 1.0]),
                                  (OccaStandardSymbols.isinomFile(), [700: 1.0, 500: 1.4, 350: 2.0, 1000: 1.0, 4000: 1.0])] {
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
