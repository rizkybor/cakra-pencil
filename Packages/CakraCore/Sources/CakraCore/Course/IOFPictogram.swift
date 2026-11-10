import CoreGraphics
import Foundation

/// IOF control description pictograms (columns C–H) as simple vector drawings in a unit box
/// (0…1, y up). Full-width rows (14.1, 15.x, 16.x) use a box 8 units wide and 1 unit high.
/// One definition is used for the PDF, PNG and the on-screen preview, so they look the same.
///
/// The shapes are simplified from the IOF 2024 specification so they stay legible in 5–7 mm cells.
public enum IOFPictogram {
    public enum Shape: Hashable, Sendable {
        /// Polyline (not closed).
        case line([Point2D])
        /// Closed polygon; `fill` = solid fill.
        case poly([Point2D], fill: Bool)
        case circle(Point2D, r: Double, fill: Bool)
        /// Arc from angle a0 to a1 (radians, counterclockwise).
        case arc(Point2D, r: Double, a0: Double, a1: Double)
        /// Small filled dots.
        case dots([Point2D], r: Double)
        /// Text centered in the box (column F dimensions), `size` relative to the box height.
        case text(String, at: Point2D, size: Double)
        /// Dashed polyline; dash and gap lengths in box units.
        case dashed([Point2D], dash: Double, gap: Double)
    }

    /// Line width relative to the box side.
    public static let lineWidth = 0.055

    // MARK: Shapes per symbol

    /// Shapes for one symbol; nil if the id is unknown.
    public static func shapes(_ id: String?) -> [Shape]? {
        guard let id, !id.isEmpty else { return nil }
        if let s = table[id] { return s }
        if id.hasPrefix("0.1"), let a = angle(String(id.dropFirst(3))) { return arrow(a) }
        let (base, dir) = IOFSymbols.splitDirection(id)
        if let dir, let a = angle(dir), IOFSymbols.isDirectional(base) {
            if base == "12.12" { return footWithDirection(a) }
            guard let north = directionalNorth[base] else { return nil }
            return rotated(north, by: a - .pi / 2)
        }
        // A directional base without direction (picker preview) points north.
        if IOFSymbols.isDirectional(id) { return shapes(id + "N") }
        return nil
    }

    /// Typed column F dimensions ("1.5", "8x4", "1.0/2.5") as text; symbols 10.x as drawings.
    public static func dimensionShapes(_ value: String?) -> [Shape]? {
        guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        if let s = shapes(v), IOFSymbols.symbol(v)?.column == .f { return s }
        // "0.5/3" (9.3 height on slope) and "2/3" (9.4 heights of two features): two numbers split by a diagonal.
        let parts = v.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            let size = max(parts[0].count, parts[1].count) > 3 ? 0.26 : 0.32
            return [.text(parts[0], at: P(0.32, 0.7), size: size), .line([P(0.2, 0.15), P(0.8, 0.85)]),
                    .text(parts[1], at: P(0.68, 0.3), size: size)]
        }
        let t = v.replacingOccurrences(of: "x", with: "×").replacingOccurrences(of: "X", with: "×")
        return [.text(t, at: P(0.5, 0.5), size: t.count > 4 ? 0.3 : 0.4)]
    }

    private static func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    private static func angle(_ dir: String) -> Double? {
        let d: [String: Double] = ["E": 0, "NE": 45, "N": 90, "NW": 135, "W": 180, "SW": 225, "S": 270, "SE": 315]
        return d[dir].map { $0 * .pi / 180 }
    }

    /// Arrow from the center toward direction `a` (column C: northern, etc.).
    private static func arrow(_ a: Double) -> [Shape] {
        let tip = P(0.5 + 0.36 * cos(a), 0.5 + 0.36 * sin(a)), tail = P(0.5 - 0.36 * cos(a), 0.5 - 0.36 * sin(a))
        let l = P(tip.x - 0.2 * cos(a - 0.5), tip.y - 0.2 * sin(a - 0.5)), r = P(tip.x - 0.2 * cos(a + 0.5), tip.y - 0.2 * sin(a + 0.5))
        return [.line([tail, tip]), .line([l, tip, r])]
    }

    /// Rotates shapes around the box center by `a` radians (counterclockwise); text stays upright.
    static func rotated(_ shapes: [Shape], by a: Double) -> [Shape] {
        func r(_ p: Point2D) -> Point2D {
            let dx = p.x - 0.5, dy = p.y - 0.5
            return P(0.5 + dx * cos(a) - dy * sin(a), 0.5 + dx * sin(a) + dy * cos(a))
        }
        return shapes.map { shape in
            switch shape {
            case let .line(pts): return .line(pts.map(r))
            case let .poly(pts, fill): return .poly(pts.map(r), fill: fill)
            case let .circle(c, rr, fill): return .circle(r(c), r: rr, fill: fill)
            case let .arc(c, rr, a0, a1): return .arc(r(c), r: rr, a0: a0 + a, a1: a1 + a)
            case let .dots(pts, rr): return .dots(pts.map(r), r: rr)
            case let .text(t, at, size): return .text(t, at: r(at), size: size)
            case let .dashed(pts, dash, gap): return .dashed(pts.map(r), dash: dash, gap: gap)
            }
        }
    }

    /// Column G symbols 12.1–12.7 drawn pointing north; other directions are rotations of these.
    private static let directionalNorth: [String: [Shape]] = [
        // 12.1 side: circle (feature) with the flag dot outside.
        "12.1": [.circle(P(0.5, 0.42), r: 0.24, fill: false), .dots([P(0.5, 0.81)], r: 0.065)],
        // 12.2 edge: circle with a short tick across its edge.
        "12.2": [.circle(P(0.5, 0.46), r: 0.27, fill: false), .line([P(0.5, 0.62), P(0.5, 0.84)])],
        // 12.3 part: circle with the dot inside, near the edge.
        "12.3": [.circle(P(0.5, 0.5), r: 0.32, fill: false), .dots([P(0.5, 0.68)], r: 0.065)],
        // 12.4 corner (inside): the corner points north, dot inside the angle.
        "12.4": [.line([P(0.22, 0.48), P(0.5, 0.76), P(0.78, 0.48)]), .dots([P(0.5, 0.58)], r: 0.065)],
        // 12.5 corner (outside): dot outside the tip of the angle.
        "12.5": [.line([P(0.22, 0.3), P(0.5, 0.58), P(0.78, 0.3)]), .dots([P(0.5, 0.76)], r: 0.065)],
        // 12.6 tip: narrow angle (< 45°), dot just beyond the tip.
        "12.6": [.line([P(0.36, 0.16), P(0.5, 0.64), P(0.64, 0.16)]), .dots([P(0.5, 0.8)], r: 0.065)],
        // 12.7 end: line ending with a short cross bar.
        "12.7": [.line([P(0.5, 0.16), P(0.5, 0.78)]), .line([P(0.3, 0.78), P(0.7, 0.78)])],
    ]

    /// 12.12 foot with direction: circle (feature) and an upright foot mark "L" on the side of direction `a`.
    private static func footWithDirection(_ a: Double) -> [Shape] {
        let c = P(0.5 - 0.12 * cos(a), 0.5 - 0.12 * sin(a))
        let m = P(0.5 + 0.3 * cos(a), 0.5 + 0.3 * sin(a))
        return [.circle(c, r: 0.24, fill: false),
                .line([P(m.x - 0.05, m.y + 0.12), P(m.x - 0.05, m.y - 0.06), P(m.x + 0.08, m.y - 0.06)])]
    }

    /// Quadratic Bézier as a polyline.
    private static func curve(_ p0: Point2D, _ c: Point2D, _ p1: Point2D, steps: Int = 12) -> [Point2D] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps), u = 1 - t
            return P(u * u * p0.x + 2 * u * t * c.x + t * t * p1.x, u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
        }
    }

    private static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, fill: Bool = false) -> Shape {
        .poly([P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)], fill: fill)
    }

    private static func triangle(_ cx: Double, _ cy: Double, _ s: Double) -> Shape {
        .poly([P(cx - s, cy - s * 0.8), P(cx + s, cy - s * 0.8), P(cx, cy + s * 0.9)], fill: true)
    }

    private static func dashes(_ y: Double, from x0: Double = 0.15, to x1: Double = 0.85, count: Int = 3) -> [Shape] {
        let step = (x1 - x0) / Double(count * 2 - 1)
        return (0..<count).map { i in .line([P(x0 + Double(i * 2) * step, y), P(x0 + Double(i * 2 + 1) * step, y)]) }
    }

    private static func grid(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, n: Int = 4) -> [Shape] {
        (0...n).flatMap { i -> [Shape] in
            let t = Double(i) / Double(n)
            return [.line([P(x0 + (x1 - x0) * t, y0), P(x0 + (x1 - x0) * t, y1)]), .line([P(x0, y0 + (y1 - y0) * t), P(x1, y0 + (y1 - y0) * t)])]
        }
    }

    private static func scatter(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, n: Int) -> [Point2D] {
        (0..<n).flatMap { i in (0..<n).map { j in
            P(x0 + (x1 - x0) * (Double(i) + (j % 2 == 0 ? 0.25 : 0.75)) / Double(n), y0 + (y1 - y0) * (Double(j) + 0.5) / Double(n))
        } }
    }

    private static func tree(_ cx: Double, _ cy: Double, _ r: Double) -> [Shape] {
        [.circle(P(cx, cy + r * 0.4), r: r, fill: false), .line([P(cx, cy - r * 0.6), P(cx, cy - r * 1.8)])]
    }

    // swiftlint:disable:next function_body_length
    private static let table: [String: [Shape]] = {
        var t: [String: [Shape]] = [:]
        let c = P(0.5, 0.5)

        // C: which
        t["0.2"] = [.line([P(0.15, 0.68), P(0.85, 0.68)]), .line([P(0.15, 0.32), P(0.85, 0.32)]), .dots([P(0.5, 0.68)], r: 0.09)]
        t["0.3"] = [.line([P(0.15, 0.68), P(0.85, 0.68)]), .line([P(0.15, 0.32), P(0.85, 0.32)]), .dots([P(0.5, 0.32)], r: 0.09)]
        t["0.4"] = [.line([P(0.15, 0.78), P(0.85, 0.78)]), .line([P(0.15, 0.5), P(0.85, 0.5)]), .line([P(0.15, 0.22), P(0.85, 0.22)]),
                    .dots([P(0.5, 0.5)], r: 0.09)]

        // D: landforms
        t["1.1"] = [.line([P(0.12, 0.3), P(0.42, 0.3), P(0.58, 0.7), P(0.88, 0.7)])]
        t["1.2"] = [.arc(P(0.5, 0.3), r: 0.32, a0: 0, a1: .pi)]
        t["1.3"] = [.arc(P(0.5, 0.7), r: 0.32, a0: .pi, a1: 2 * .pi)]
        t["1.4"] = [.line([P(0.12, 0.65), P(0.88, 0.65)])] + [0.22, 0.42, 0.62, 0.82].map { .line([P($0, 0.65), P($0, 0.4)]) }
        t["1.5"] = [.arc(c, r: 0.32, a0: .pi * 0.15, a1: .pi * 0.85), .arc(c, r: 0.32, a0: .pi * 1.15, a1: .pi * 1.85)]
            + [0.3, 0.5, 0.7].map { .line([P($0, 0.82 - abs($0 - 0.5) * 0.4), P($0, 0.62)]) }
        t["1.6"] = [.line([P(0.12, 0.5), P(0.88, 0.5)])] + [0.25, 0.5, 0.75].flatMap { x -> [Shape] in
            [.line([P(x, 0.5), P(x, 0.72)]), .line([P(x, 0.5), P(x, 0.28)])]
        }
        t["1.7"] = [.line([P(0.15, 0.78), P(0.85, 0.5), P(0.15, 0.22)])]
        t["1.8"] = [.dots([0.18, 0.34, 0.5, 0.66, 0.82].map { P($0, 0.5) }, r: 0.05)]
        t["1.9"] = [.circle(c, r: 0.34, fill: false)]
        t["1.10"] = [.circle(c, r: 0.16, fill: true)]
        t["1.11"] = [.arc(P(0.05, 0.5), r: 0.3, a0: -.pi / 2.6, a1: .pi / 2.6), .arc(P(0.95, 0.5), r: 0.3, a0: .pi - .pi / 2.6, a1: .pi + .pi / 2.6)]
        t["1.12"] = [.circle(c, r: 0.32, fill: false)] + [0.0, 0.5, 1.0, 1.5].map { k in
            let a = k * .pi
            return .line([P(0.5 + 0.32 * cos(a), 0.5 + 0.32 * sin(a)), P(0.5 + 0.18 * cos(a), 0.5 + 0.18 * sin(a))])
        }
        t["1.13"] = [.arc(P(0.5, 0.62), r: 0.26, a0: .pi, a1: 2 * .pi)]
        t["1.14"] = [.line([P(0.25, 0.75), P(0.5, 0.25), P(0.75, 0.75)])]
        t["1.15"] = [.line([P(0.15, 0.7), P(0.25, 0.5), P(0.35, 0.7)]), .line([P(0.6, 0.45), P(0.7, 0.25), P(0.8, 0.45)]),
                     .dots([P(0.7, 0.75), P(0.25, 0.25), P(0.5, 0.5)], r: 0.06)]
        t["1.16"] = (0..<4).map { k in
            let a = Double(k) * .pi / 4
            return .line([P(0.5 - 0.28 * cos(a), 0.5 - 0.28 * sin(a)), P(0.5 + 0.28 * cos(a), 0.5 + 0.28 * sin(a))])
        }

        // D: rock and boulders
        t["2.1"] = [.line([P(0.12, 0.7), P(0.88, 0.7)]), .poly([P(0.2, 0.7), P(0.3, 0.7), P(0.25, 0.32)], fill: true),
                    .poly([P(0.45, 0.7), P(0.55, 0.7), P(0.5, 0.32)], fill: true), .poly([P(0.7, 0.7), P(0.8, 0.7), P(0.75, 0.32)], fill: true)]
        t["2.2"] = [.poly([P(0.38, 0.15), P(0.62, 0.15), P(0.58, 0.85), P(0.42, 0.85)], fill: true)]
        t["2.3"] = [.poly([P(0.2, 0.5), P(0.8, 0.8), P(0.8, 0.2)], fill: true)]
        t["2.4"] = [triangle(0.5, 0.47, 0.3)]
        t["2.5"] = [triangle(0.3, 0.7, 0.15), triangle(0.7, 0.68, 0.13), triangle(0.32, 0.3, 0.13), triangle(0.72, 0.28, 0.15)]
        t["2.6"] = [triangle(0.35, 0.36, 0.17), triangle(0.65, 0.36, 0.17), triangle(0.5, 0.66, 0.17)]
        t["2.7"] = [triangle(0.25, 0.72, 0.08), triangle(0.7, 0.75, 0.08), triangle(0.48, 0.5, 0.08), triangle(0.25, 0.26, 0.08),
                    triangle(0.75, 0.3, 0.08)]
        t["2.8"] = [box(0.18, 0.18, 0.82, 0.82), .dots(scatter(0.18, 0.18, 0.82, 0.82, n: 3), r: 0.04)]
        t["2.9"] = [.line([P(0.3, 0.12), P(0.3, 0.88)]), .line([P(0.7, 0.12), P(0.7, 0.88)])]
            + [0.25, 0.5, 0.75].flatMap { y -> [Shape] in [.line([P(0.3, y), P(0.14, y)]), .line([P(0.7, y), P(0.86, y)])] }
        t["2.10"] = [.line([P(0.12, 0.6), P(0.88, 0.6)]), .line([P(0.12, 0.4), P(0.88, 0.4)]), .line([P(0.12, 0.6), P(0.12, 0.4)])]

        // D: water and marsh
        t["3.1"] = [.circle(c, r: 0.36, fill: false), .line([P(0.26, 0.56), P(0.74, 0.56)]), .line([P(0.26, 0.42), P(0.74, 0.42)])]
        t["3.2"] = [.circle(c, r: 0.26, fill: false), .line([P(0.36, 0.5), P(0.64, 0.5)])]
        t["3.3"] = [.arc(P(0.5, 0.6), r: 0.3, a0: .pi, a1: 2 * .pi), .line([P(0.3, 0.45), P(0.7, 0.45)])]
        t["3.4"] = [.line((0...12).map { i in P(0.12 + Double(i) * 0.76 / 12, 0.5 + 0.12 * sin(Double(i) * .pi / 3)) })]
        t["3.5"] = dashes(0.5, count: 4)
        t["3.6"] = dashes(0.5, count: 4) + [.dots([0.25, 0.5, 0.75].map { P($0, 0.32) }, r: 0.04)]
        t["3.7"] = dashes(0.72) + dashes(0.5, from: 0.25, to: 0.75, count: 2) + dashes(0.28)
        t["3.8"] = dashes(0.8) + dashes(0.2) + [.circle(c, r: 0.16, fill: false)]
        t["3.9"] = [.circle(c, r: 0.18, fill: false)] + [0.25, 0.75, 1.25, 1.75].map { k in
            let a = k * .pi
            return .line([P(0.5 + 0.18 * cos(a), 0.5 + 0.18 * sin(a)), P(0.5 + 0.36 * cos(a), 0.5 + 0.36 * sin(a))])
        }
        t["3.10"] = [.arc(P(0.38, 0.5), r: 0.18, a0: .pi / 2, a1: 1.5 * .pi), .line([P(0.38, 0.68), P(0.38, 0.32)]),
                     .line([P(0.38, 0.5), P(0.86, 0.5)])]
        t["3.11"] = [.line([P(0.22, 0.78), P(0.22, 0.25), P(0.78, 0.25), P(0.78, 0.78)]), .line([P(0.22, 0.6), P(0.78, 0.6)])]

        // D: vegetation
        t["4.1"] = [.circle(c, r: 0.32, fill: false)]
        t["4.2"] = [.circle(c, r: 0.32, fill: false), .dots(scatter(0.32, 0.32, 0.68, 0.68, n: 2), r: 0.04)]
        t["4.3"] = [.line([P(0.18, 0.18), P(0.18, 0.82), P(0.82, 0.82)]), .dots(scatter(0.24, 0.24, 0.84, 0.76, n: 3), r: 0.04)]
        t["4.4"] = [.circle(c, r: 0.32, fill: false), .dots(scatter(0.14, 0.82, 0.86, 0.95, n: 3) + scatter(0.14, 0.05, 0.86, 0.18, n: 3), r: 0.03)]
        t["4.5"] = grid(0.2, 0.2, 0.8, 0.8)
        t["4.6"] = grid(0.12, 0.38, 0.88, 0.62, n: 3)
        t["4.7"] = [.dots([0.15, 0.29, 0.43, 0.57, 0.71, 0.85].map { P($0, 0.5) }, r: 0.045)]
        t["4.8"] = [.circle(P(0.36, 0.42), r: 0.18, fill: false), .circle(P(0.64, 0.42), r: 0.18, fill: false), .circle(P(0.5, 0.66), r: 0.18, fill: false)]
        t["4.9"] = tree(0.5, 0.6, 0.22)
        t["4.10"] = [.line([P(0.5, 0.75), P(0.5, 0.42)]), .line([P(0.25, 0.22), P(0.5, 0.42), P(0.75, 0.22)]), .line([P(0.5, 0.42), P(0.5, 0.2)])]

        // D: man-made features
        t["5.1"] = [.line([P(0.12, 0.62), P(0.88, 0.62)]), .line([P(0.12, 0.38), P(0.88, 0.38)])]
        t["5.2"] = dashes(0.5, count: 3)
        t["5.3"] = dashes(0.5, count: 5)
        t["5.4"] = [.line([P(0.15, 0.78), P(0.3, 0.64), P(0.7, 0.64), P(0.85, 0.78)]), .line([P(0.15, 0.22), P(0.3, 0.36), P(0.7, 0.36), P(0.85, 0.22)])]
        t["5.5"] = [.line([P(0.1, 0.5), P(0.9, 0.5)]), .line([P(0.3, 0.38), P(0.3, 0.62)]), .line([P(0.7, 0.38), P(0.7, 0.62)])]
        t["5.6"] = [.line([P(0.25, 0.15), P(0.5, 0.85), P(0.75, 0.15)]), .line([P(0.34, 0.4), P(0.66, 0.4)]), .line([P(0.2, 0.68), P(0.8, 0.68)])]
        t["5.7"] = [.arc(P(0.5, 0.3), r: 0.3, a0: 0, a1: .pi), .line([P(0.2, 0.3), P(0.2, 0.18)]), .line([P(0.8, 0.3), P(0.8, 0.18)]),
                    .line([P(0.1, 0.18), P(0.9, 0.18)])]
        t["5.8"] = [.line([P(0.12, 0.5), P(0.88, 0.5)]), .dots([0.25, 0.5, 0.75].map { P($0, 0.5) }, r: 0.08)]
        t["5.9"] = [.line([P(0.12, 0.5), P(0.88, 0.5)])] + [0.28, 0.5, 0.72].flatMap { x -> [Shape] in
            [.line([P(x - 0.07, 0.4), P(x + 0.07, 0.6)]), .line([P(x - 0.07, 0.6), P(x + 0.07, 0.4)])]
        }
        t["5.10"] = [.line([P(0.1, 0.5), P(0.38, 0.5)]), .line([P(0.62, 0.5), P(0.9, 0.5)]), .line([P(0.38, 0.32), P(0.38, 0.68)]),
                     .line([P(0.62, 0.32), P(0.62, 0.68)])]
        t["5.11"] = [box(0.22, 0.22, 0.78, 0.78, fill: true)]
        t["5.12"] = [box(0.18, 0.18, 0.82, 0.82)]
        t["5.13"] = dashes(0.2, from: 0.2, to: 0.8, count: 2) + dashes(0.8, from: 0.2, to: 0.8, count: 2)
            + [.line([P(0.2, 0.2), P(0.2, 0.4)]), .line([P(0.2, 0.6), P(0.2, 0.8)]), .line([P(0.8, 0.2), P(0.8, 0.4)]), .line([P(0.8, 0.6), P(0.8, 0.8)])]
        t["5.14"] = [.line([P(0.1, 0.5), P(0.9, 0.5)]), .circle(P(0.3, 0.5), r: 0.08, fill: false), .circle(P(0.7, 0.5), r: 0.08, fill: false)]
        t["5.15"] = [.line([P(0.3, 0.15), P(0.42, 0.7)]), .line([P(0.7, 0.15), P(0.58, 0.7)]), box(0.34, 0.7, 0.66, 0.85)]
        t["5.16"] = [.line([P(0.3, 0.15), P(0.3, 0.6), P(0.7, 0.6), P(0.7, 0.15)]), .line([P(0.3, 0.6), P(0.3, 0.85)])]
        t["5.17"] = [.circle(c, r: 0.2, fill: false), .dots([c], r: 0.06)]
        t["5.18"] = [.line([P(0.4, 0.15), P(0.4, 0.85)]), .line([P(0.4, 0.75), P(0.68, 0.6)]), .line([P(0.4, 0.55), P(0.68, 0.4)])]
        t["5.19"] = [.circle(c, r: 0.3, fill: false), .dots([c], r: 0.12)]
        t["5.20"] = [box(0.4, 0.3, 0.6, 0.8, fill: true), .line([P(0.2, 0.22), P(0.8, 0.22)])]
        // 5.21 canopy: a roof on two posts.
        t["5.21"] = [.line([P(0.18, 0.78), P(0.82, 0.78)]), .line([P(0.34, 0.78), P(0.34, 0.18)]), .line([P(0.66, 0.78), P(0.66, 0.18)])]
        t["5.22"] = [.line([P(0.15, 0.2), P(0.15, 0.35), P(0.35, 0.35), P(0.35, 0.5), P(0.55, 0.5), P(0.55, 0.65), P(0.75, 0.65), P(0.75, 0.8)])]
        // 5.23 out of bounds area: a flower bed (square with a flower).
        t["5.23"] = [box(0.17, 0.17, 0.83, 0.83), .circle(c, r: 0.065, fill: false)] + (0..<5).map { k in
            let a = Double.pi / 2 + Double(k) * 2 * .pi / 5
            return .circle(P(0.5 + 0.15 * cos(a), 0.5 + 0.15 * sin(a)), r: 0.085, fill: false)
        }
        // 5.24 railway: a track with sleepers.
        t["5.24"] = {
            let a = P(0.14, 0.24), b = P(0.86, 0.76)
            let len = hypot(b.x - a.x, b.y - a.y), ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
            return [Shape.line([a, b])] + (1...6).map { i -> Shape in
                let t = Double(i) / 7, m = P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
                return .line([P(m.x - uy * 0.11, m.y + ux * 0.11), P(m.x + uy * 0.11, m.y - ux * 0.11)])
            }
        }()
        t["6.1"] = [.line([P(0.25, 0.25), P(0.75, 0.75)]), .line([P(0.25, 0.75), P(0.75, 0.25)])]
        t["6.2"] = [.circle(c, r: 0.26, fill: false)]

        // D: indoor (ISInOM 6.7.3), traced from the Purple Pen figures (200-unit box, y up).
        func pp(_ xy: [(Double, Double)]) -> [Point2D] { xy.map { P(0.5 + $0.0 / 200, 0.5 + $0.1 / 200) } }
        func ppFill(_ xy: [(Double, Double)]) -> Shape { .poly(pp(xy), fill: true) }
        func ppLine(_ xy: [(Double, Double)]) -> Shape { .line(pp(xy)) }
        // 7.119 Pillar: shaft with a wider base and capital.
        t["7.119"] = [
            ppFill([(-12.3, 39), (-12.3, -45.6), (11.7, -45.6), (11.7, 39)]),
            ppFill([(-28.2, -57.3), (27.6, -57.3), (18.6, -45.6), (-19.5, -45.6)]),
            ppFill([(-27.9, 51), (27.9, 51), (18.9, 39), (-19.2, 39)]),
        ]
        // 7.132 Toilet: cistern, bowl and seat ring (seen from the side).
        t["7.132"] = [
            ppFill([(-19.8, -41.4), (-3.9, -44.4), (7.2, -42.6), (19.5, -36.9), (22.2, -55.8), (16.2, -60.3), (-1.8, -66),
                    (-15.6, -66.3), (-26.4, -60.9), (-19.5, -41.7)]),
            ppFill([(8.7, 11.1), (33.9, 0.9), (39.9, 15.6), (41.4, 27.6), (41.7, 39.9), (40.5, 51.3), (37.8, 61.8), (34.2, 69),
                    (30, 74.1), (21.9, 78), (12.6, 74.1), (8.7, 69), (5.4, 60.9), (3.9, 49.2), (4.2, 35.7)]),
            ppFill([(31.5, -9.9), (19.5, -17.4), (3.9, -22.8), (-12.3, -24), (-23.7, -22.8), (-33.3, -19.8), (-30.9, -26.1),
                    (-26.4, -32.7), (-18, -38.7), (-7.5, -41.7), (1.5, -41.1), (10.8, -37.8), (18.9, -33.6), (24.3, -28.8),
                    (28.5, -22.5), (31.8, -9.9)]),
            // Seat ring: outer edge, then the opening in the opposite direction (a hole with the non-zero fill rule).
            ppFill([(33, -2.1), (28.8, -6.9), (14.7, -15.6), (1.2, -19.5), (-8.1, -20.1), (-18, -19.8), (-31.8, -16.5),
                    (-37.5, -12), (-37.5, -4.8), (-28.2, 3), (-14.7, 6.9), (-2.7, 8.7), (6.9, 9.3), (33.3, -1.5), (33, -2.1),
                    (-4.2, 3.3), (-6.3, 3), (-18.6, 0.3), (-24.6, -2.4), (-27, -7.8), (-24.3, -10.5), (-12.9, -13.2), (-3, -13.8),
                    (7.2, -11.7), (10.8, -10.8), (17.4, -6.3), (18, -3), (15, 0.6)]),
        ]
        // 7.133 Shower: pipe with a shower head and water drops.
        t["7.133"] = [
            ppLine([(-15.9, 21.3), (17.1, 39.6)]),
            ppLine([(7.7, 16.2), (9.9, 11.4)]), ppLine([(19.5, 23.1), (24.6, 18.9)]), ppLine([(-4.2, 9.3), (-3.3, 3)]),
            ppLine([(10.2, -5.4), (11.7, -10.5)]), ppLine([(40.5, 17.1), (45.6, 12.9)]), ppLine([(-7.2, -12.3), (-6.3, -18.3)]),
            ppLine([(26.1, 4.8), (30, 0.9)]),
            ppLine([(-42.3, -50.8), (-42, 38.4), (-38.7, 45.6), (-30, 52.2), (-18.9, 52.8), (-3.3, 43.5)]),
            ppFill([(15.6, 42.6), (11.4, 47.4), (3.9, 49.5), (-8.7, 47.1), (-18.3, 36.3), (-19.5, 29.7), (-17.7, 37.7)]),
        ]
        // 7.134 Sink: basin with a swan-neck tap and two handles.
        t["7.134"] = [
            ppFill([(-8.7, -4.8), (-6.6, 53.7), (0.6, 62.1), (18.9, 67.8), (29.4, 67.5), (39.3, 64.5), (48, 58.5), (54.3, 49.5),
                    (52.8, 45.9), (44.1, 42.9), (41.4, 42.9), (36, 49.8), (27.3, 54.3), (16.8, 53.7), (9, 49.2), (7.8, -4.8)]),
            ppFill([(-11.4, 13.8), (-15, 9), (-14.4, -0.3), (-11.4, -2.7), (-8.4, 1.5), (-8.1, 8.1)]),
            ppFill([(44.1, 34.8), (39.9, 20.7), (41.1, 15.3), (47.1, 13.2), (51.9, 16.2), (52.2, 21), (45.3, 34.8)]),
            ppFill([(-63.3, -23.1), (-46.5, -17.7), (-0.9, -14.1), (38.1, -16.8), (54, -20.1), (63.9, -25.2), (65.1, -21.6),
                    (59.7, -16.8), (45.9, -12.6), (0, -8.7), (-49.5, -12.6), (-63.9, -19.2), (-65.1, -21.6), (-62.4, -25.2)]),
            ppFill([(-64.5, -21), (-60.9, -35.1), (-48.6, -50.7), (-30, -62.1), (-3.3, -67.5), (18.9, -65.4), (40.8, -56.4),
                    (56.4, -42), (62.1, -32.1), (64.8, -21.3), (64.2, -21.6), (54.9, -25.8), (16.8, -30.9), (-27, -30.9),
                    (-48.9, -27.3), (-63.3, -21.6)]),
            ppFill([(10.8, 13.8), (7.5, 8.1), (7.2, 1.5), (10.8, -2.7), (14.4, 1.5), (14.4, 8.4)]),
        ]
        // 7.141 Table or bench: table top on legs, two stools.
        t["7.141"] = [
            ppFill([(-29.1, 0.6), (-18.3, 0.6), (-18.3, -1.8), (-20.1, -5.7), (-24.3, -6.9), (-28.2, -4.8)]),
            ppFill([(-45.9, 0.6), (-45.9, -26.7), (-44.4, -30.9), (-39.9, -32.4), (-35.7, -30.9), (-33.6, -26.7), (-33.6, 0.6)]),
            ppFill([(35.1, 0.6), (35.1, -26.7), (36.6, -30.9), (40.8, -32.4), (45.3, -30.9), (47.1, -26.7), (47.1, 0.6)]),
            ppFill([(20.4, 0.6), (31.5, 0.6), (31.5, -1.8), (29.7, -5.7), (25.2, -6.6), (21, -4.5)]),
            ppFill([(-30.9, 35.7), (35.1, 35.7), (57.6, 4.8), (-57.6, 4.8)]),
        ]
        // 7.142 Cupboard / shelf: cabinet with a door and shelves.
        t["7.142"] = [
            ppLine([(-48.3, 73.5), (-48.3, -69.6), (48.3, -69.6), (48.3, 73.5)]), ppLine([(-48.3, 73.5), (48.3, 73.5)]),
            ppLine([(-1.2, 69), (-1.2, -69)]), ppLine([(-25.5, 10.8), (-17.1, 10.8)]),
            ppLine([(-0.9, 47.4), (47.7, 47.4)]), ppLine([(-0.3, 23.1), (48.3, 23.1)]),
            ppLine([(-0.9, -8.1), (47.7, -8.1)]), ppLine([(-0.3, -41.1), (48.3, -41.1)]),
        ]
        // 7.143 Couch / sofa: back, seat cushions, arms and feet.
        t["7.143"] = [
            ppFill([(-43.5, 20.7), (-34.5, 16.2), (-32.1, 6.6), (32.1, 6.6), (34.8, 17.7), (45, 21), (44.7, 30.9), (40.8, 40.2),
                    (33, 43.5), (-34.2, 43.5), (-38.7, 42.3), (-43.8, 35.1)]),
            ppFill([(-31.8, 2.4), (-3, 2.4), (-3, -7.2), (-31.8, -7.2)]),
            ppFill([(-42.3, 3.9), (-42.9, 8.1), (-46.2, 12.9), (-51.6, 13.5), (-56.4, 10.8), (-59.1, 3), (-58.8, -29.1),
                    (58.8, -29.1), (58.8, 3), (57, 11.4), (54, 14.1), (48, 14.1), (45, 12), (43, 3.6), (42.5, -11.4), (-42, -11.4),
                    (-42, 3.6)]),
            ppFill([(39.9, -21.3), (39.9, -38.7), (52.5, -38.7), (52.5, -22.2)]),
            ppFill([(3.3, 2.4), (32.1, 2.4), (32.1, -7.2), (3.3, -7.2)]),
            ppFill([(-52.5, -21.3), (-52.5, -38.7), (-39.9, -38.7), (-39.9, -22.2)]),
        ]

        // E: appearance
        t["8.1"] = [.arc(P(0.5, 0.2), r: 0.42, a0: .pi * 0.22, a1: .pi * 0.78)]
        t["8.2"] = [.arc(P(0.5, 0.8), r: 0.42, a0: .pi * 1.22, a1: .pi * 1.78)]
        t["8.3"] = [.line([P(0.25, 0.85), P(0.25, 0.4)]), .arc(P(0.5, 0.4), r: 0.25, a0: .pi, a1: 2 * .pi), .line([P(0.75, 0.4), P(0.75, 0.85)])]
        t["8.4"] = grid(0.2, 0.2, 0.8, 0.8)
        t["8.5"] = [.dots((0..<16).map { i in
            let k = Double(i % 4) / 3, side = i / 4
            switch side {
            case 0: return P(0.2 + 0.6 * k, 0.2)
            case 1: return P(0.8, 0.2 + 0.6 * k)
            case 2: return P(0.8 - 0.6 * k, 0.8)
            default: return P(0.2, 0.8 - 0.6 * k)
            }
        }, r: 0.035)]
        t["8.6"] = [triangle(0.3, 0.68, 0.1), triangle(0.7, 0.68, 0.1), triangle(0.5, 0.3, 0.1)]
        t["8.7"] = dashes(0.72, count: 2) + dashes(0.5, count: 2) + dashes(0.28, count: 2)
        t["8.8"] = [.dots(scatter(0.18, 0.18, 0.82, 0.82, n: 4), r: 0.035)]
        t["8.9"] = [.poly([P(0.5, 0.88), P(0.28, 0.42), P(0.72, 0.42)], fill: false), .line([P(0.5, 0.42), P(0.5, 0.12)])]
        t["8.10"] = tree(0.5, 0.56, 0.24)
        t["8.11"] = [.line([P(0.25, 0.2), P(0.25, 0.6)]), .arc(P(0.5, 0.6), r: 0.25, a0: .pi * 0.45, a1: .pi),
                     .line([P(0.75, 0.2), P(0.75, 0.45)]), .line([P(0.62, 0.62), P(0.86, 0.2)])]

        // F: combinations and bend
        t["10.1"] = [.line([P(0.2, 0.2), P(0.8, 0.8)]), .line([P(0.2, 0.8), P(0.8, 0.2)])]
        t["10.2"] = [.line([P(0.2, 0.82), P(0.5, 0.5), P(0.8, 0.82)]), .line([P(0.5, 0.5), P(0.5, 0.15)])]
        t["11.1"] = [.line(curve(P(0.72, 0.84), P(-0.1, 0.5), P(0.72, 0.16)))]

        // G: flag location (feature = line/shape, flag = dot); 12.1–12.7 and 12.12 are directional (see `shapes`).
        t["12.8"] = [.line([P(0.34, 0.14), P(0.34, 0.86)]), .line([P(0.66, 0.14), P(0.66, 0.86)]), .dots([P(0.5, 0.72)], r: 0.065)]
        t["12.9"] = [.line([P(0.34, 0.14), P(0.34, 0.86)]), .line([P(0.66, 0.14), P(0.66, 0.86)]), .dots([P(0.5, 0.28)], r: 0.065)]
        t["12.10"] = [.line([P(0.32, 0.14), P(0.32, 0.6), P(0.68, 0.6), P(0.68, 0.14)]), .dots([P(0.5, 0.8)], r: 0.065)]
        t["12.11"] = [.line([P(0.36, 0.86), P(0.36, 0.2), P(0.76, 0.2)]), .dots([P(0.54, 0.34)], r: 0.065)]
        t["12.13"] = [.line([P(0.22, 0.5), P(0.22, 0.74), P(0.78, 0.74), P(0.78, 0.5)]), .dots([P(0.5, 0.54)], r: 0.065)]
        t["12.14"] = [.line([P(0.24, 0.74), P(0.76, 0.74)]), .line([P(0.24, 0.26), P(0.76, 0.26)]), .dots([c], r: 0.065)]

        // H: other information
        t["13.1"] = [box(0.4, 0.15, 0.6, 0.85, fill: true), box(0.15, 0.4, 0.85, 0.6, fill: true)]
        t["13.2"] = [.poly([P(0.25, 0.82), P(0.75, 0.82), P(0.65, 0.18), P(0.35, 0.18)], fill: false), .line([P(0.29, 0.6), P(0.71, 0.6)])]
        t["13.3"] = [.circle(P(0.5, 0.8), r: 0.08, fill: false), .line([P(0.5, 0.72), P(0.5, 0.4)]), .line([P(0.28, 0.58), P(0.72, 0.58)]),
                     .line([P(0.32, 0.12), P(0.5, 0.4), P(0.68, 0.12)])]

        // Legacy (IOF 2018) symbols kept for old projects, drawn as before.
        t[IOFSymbols.Legacy.barrier] = [.line([P(0.15, 0.5), P(0.85, 0.5)]), .line([P(0.15, 0.32), P(0.15, 0.68)]),
                                        .line([P(0.85, 0.32), P(0.85, 0.68)]), box(0.42, 0.42, 0.58, 0.58, fill: true)]
        t[IOFSymbols.Legacy.rubbishBin] = [.poly([P(0.3, 0.78), P(0.7, 0.78), P(0.64, 0.2), P(0.36, 0.2)], fill: false),
                                           .line([P(0.24, 0.78), P(0.76, 0.78)])]
        t[IOFSymbols.Legacy.topEdge] = [.arc(P(0.5, 0.25), r: 0.36, a0: .pi * 0.1, a1: .pi * 0.9), .dots([P(0.5, 0.61)], r: 0.07)]
        t[IOFSymbols.Legacy.beginning] = [.line([P(0.35, 0.65), P(0.88, 0.12)]), .dots([P(0.22, 0.78)], r: 0.07)]
        t[IOFSymbols.Legacy.bend] = [.line([P(0.75, 0.88), P(0.35, 0.5), P(0.75, 0.12)]), .dots([P(0.2, 0.5)], r: 0.07)]
        t[IOFSymbols.Legacy.radio] = [.line([P(0.62, 0.9), P(0.38, 0.5), P(0.62, 0.5), P(0.38, 0.1)]),
                                      .line([P(0.3, 0.2), P(0.38, 0.1), P(0.46, 0.2)])]
        return t
    }()

    // MARK: Full-width rows (14.1, 15.x, 16.x)

    /// Width of a full-width row in box units (columns A–H).
    public static let rowUnits = 8.0

    /// Shapes for a full-width row in a box 8 units wide and 1 unit high; nil for ordinary control rows.
    public static func rowShapes(_ row: DescriptionSheet.Row) -> [Shape]? {
        if let sp = row.special {
            switch sp {
            case let .startDistance(m): return route(from: .none, label: "\(m) m", to: .startTriangle)
            case let .instruction(kind, meters):
                let label = meters.map { "\($0) m" }
                switch kind {
                case .tapedAway: return route(from: .control, label: label, to: .arrowOnly)
                case .tapedBetween: return route(from: .control, label: label, to: .control)
                case .tapedToMapExchange: return route(from: .control, label: label, to: .startTriangle)
                case .crossingPoint:
                    return navigateEnds(.control) + [.arc(P(4, 1.45), r: 0.83, a0: .pi * 1.3, a1: .pi * 1.7),
                                                      .arc(P(4, -0.45), r: 0.83, a0: .pi * 0.3, a1: .pi * 0.7)]
                case .outOfBoundsPassage:
                    return navigateEnds(.control) + [.line([P(3.1, 0.84), P(3.32, 0.66), P(4.68, 0.66), P(4.9, 0.84)]),
                                                      .line([P(3.1, 0.16), P(3.32, 0.34), P(4.68, 0.34), P(4.9, 0.16)])]
                case .mapFlip:
                    // A map (rectangle) with a curved arrow: turn the map over.
                    return [.poly([P(3.4, 0.2), P(4.5, 0.2), P(4.5, 0.74), P(3.4, 0.74)], fill: false),
                            .line(curve(P(4.62, 0.2), P(4.98, 0.84), P(4.3, 0.8))),
                            .poly([P(4.1, 0.8), P(4.34, 0.95), P(4.34, 0.65)], fill: true)]
                }
            }
        }
        guard row.kind == .finish else { return nil }
        let label = row.finishMeters.map { "\($0) m" }
        switch row.finishRoute {
        case .taped: return route(from: .control, label: label, to: .finish)
        case .funnel:
            return [.circle(P(0.42, 0.5), r: 0.26, fill: false), .line([P(0.95, 0.74), P(1.2, 0.5), P(0.95, 0.26)])]
                + dashedLine(from: 1.2, to: 7.3, label: label) + arrowHead(7.32) + target(.finish)
        case .navigate:
            return navigateEnds(.finish) + (label.map { [.text($0, at: P(4, 0.5), size: labelSize)] } ?? [])
        }
    }

    private enum RowEnd { case none, control, finish, startTriangle, arrowOnly }

    private static let labelSize = 0.42

    /// Dashed route with the distance in the middle and an arrow into the target on the right.
    private static func route(from start: RowEnd, label: String?, to end: RowEnd) -> [Shape] {
        let x0 = start == .control ? 0.68 : 0.3
        let tip = end == .arrowOnly ? 7.62 : 7.32
        var out: [Shape] = start == .control ? [.circle(P(0.42, 0.5), r: 0.26, fill: false)] : []
        out += dashedLine(from: x0, to: tip - 0.02, label: label) + arrowHead(tip)
        return out + target(end)
    }

    private static func dashedLine(from x0: Double, to x1: Double, label: String?) -> [Shape] {
        let dash = 0.34, gap = 0.18
        /// Whole dashes that fill the run exactly from `a` to `b`: the dash and gap are stretched slightly so both
        /// ends land on a dash. Both runs then stop exactly the same distance from the text (symmetric gaps).
        func run(from a: Double, toward b: Double) -> Shape {
            let length = abs(b - a)
            let n = max(1, Int(((length + gap) / (dash + gap)).rounded()))
            let k = n > 1 ? length / (Double(n) * dash + Double(n - 1) * gap) : 1
            return .dashed([P(a, 0.5), P(b, 0.5)], dash: n > 1 ? dash * k : length, gap: gap * k)
        }
        guard let label else { return [run(from: x0, toward: x1)] }
        let half = Double(label.count) * labelSize * 0.28 + 0.22
        return [run(from: x0, toward: 4 - half), run(from: x1, toward: 4 + half), .text(label, at: P(4, 0.5), size: labelSize)]
    }

    private static func arrowHead(_ tip: Double) -> [Shape] {
        [.line([P(tip - 0.24, 0.68), P(tip, 0.5), P(tip - 0.24, 0.32)])]
    }

    /// Target symbol on the right end (center x 7.58).
    private static func target(_ end: RowEnd) -> [Shape] {
        let cx = 7.58
        switch end {
        case .finish: return [.circle(P(cx, 0.5), r: 0.26, fill: false), .circle(P(cx, 0.5), r: 0.16, fill: false)]
        case .control: return [.circle(P(cx, 0.5), r: 0.26, fill: false)]
        case .startTriangle:
            return [.poly((0..<3).map { i in
                let a = Double.pi / 2 + Double(i) * 2 * .pi / 3
                return P(cx + 0.3 * cos(a), 0.44 + 0.3 * sin(a))
            }, fill: false)]
        case .none, .arrowOnly: return []
        }
    }

    /// "Navigate" ends: control circle with an opening angle on the left, angle into the target on the right.
    private static func navigateEnds(_ end: RowEnd) -> [Shape] {
        [.circle(P(0.42, 0.5), r: 0.26, fill: false), .line([P(0.98, 0.76), P(0.68, 0.5), P(0.98, 0.24)]),
         .line([P(7.02, 0.76), P(7.32, 0.5), P(7.02, 0.24)])] + target(end)
    }

    // MARK: Drawing to CGContext (screen, PNG)

    /// Draw shapes in `rect` (context coordinates). `flipped`: context y points down (UIKit/SwiftUI).
    /// One box unit = the rect height (square cells: the side; full-width rows: 8 units wide).
    public static func draw(_ shapes: [Shape], in ctx: CGContext, rect: CGRect, flipped: Bool, color: CGColor) {
        let s = Double(rect.height)
        func pt(_ p: Point2D) -> CGPoint {
            CGPoint(x: rect.minX + p.x * s, y: flipped ? rect.maxY - p.y * s : rect.minY + p.y * s)
        }
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(lineWidth * s)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for shape in shapes {
            switch shape {
            case let .line(pts):
                guard let f = pts.first else { continue }
                ctx.move(to: pt(f))
                pts.dropFirst().forEach { ctx.addLine(to: pt($0)) }
                ctx.strokePath()
            case let .poly(pts, fill):
                guard let f = pts.first else { continue }
                ctx.move(to: pt(f))
                pts.dropFirst().forEach { ctx.addLine(to: pt($0)) }
                ctx.closePath()
                if fill { ctx.fillPath() } else { ctx.strokePath() }
            case let .circle(cc, r, fill):
                let p = pt(cc), rr = r * s
                let e = CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr)
                if fill { ctx.fillEllipse(in: e) } else { ctx.strokeEllipse(in: e) }
            case let .arc(cc, r, a0, a1):
                let n = 24
                for i in 0...n {
                    let a = a0 + (a1 - a0) * Double(i) / Double(n)
                    let q = pt(P(cc.x + r * cos(a), cc.y + r * sin(a)))
                    if i == 0 { ctx.move(to: q) } else { ctx.addLine(to: q) }
                }
                ctx.strokePath()
            case let .dots(pts, r):
                for d in pts {
                    let p = pt(d), rr = r * s
                    ctx.fillEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr))
                }
            case let .dashed(pts, dash, gap):
                guard let f = pts.first else { continue }
                ctx.saveGState()
                ctx.setLineCap(.butt)
                ctx.setLineDash(phase: 0, lengths: [dash * s, gap * s])
                ctx.move(to: pt(f))
                pts.dropFirst().forEach { ctx.addLine(to: pt($0)) }
                ctx.strokePath()
                ctx.restoreGState()
            case .text:
                break  // text is drawn by the caller (SwiftUI Text / PDF Tj)
            }
        }
        ctx.restoreGState()
    }

    // MARK: PDF operators

    /// PDF operators for shapes in the box (x0, y0, size) in pt (y up). Color follows the graphics state.
    static func pdf(_ shapes: [Shape], x0: Double, y0: Double, size: Double, textWidth: (String, Double) -> Double) -> String {
        func n(_ v: Double) -> String { GeoPDFExporter.n(v, 2) }
        func pt(_ p: Point2D) -> String { "\(n(x0 + p.x * size)) \(n(y0 + p.y * size))" }
        var c = "q \(n(lineWidth * size)) w 1 J 1 j\n"
        for shape in shapes {
            switch shape {
            case let .line(pts):
                guard let f = pts.first else { continue }
                c += "\(pt(f)) m " + pts.dropFirst().map { "\(pt($0)) l " }.joined() + "S\n"
            case let .poly(pts, fill):
                guard let f = pts.first else { continue }
                c += "\(pt(f)) m " + pts.dropFirst().map { "\(pt($0)) l " }.joined() + (fill ? "h f\n" : "h S\n")
            case let .circle(cc, r, fill):
                c += GeoPDFExporter.circlePath(center: Point2D(x: 0, y: 0), r: r * size, { "\(n(x0 + cc.x * size + $0.x)) \(n(y0 + cc.y * size + $0.y))" })
                    + (fill ? "f\n" : "S\n")
            case let .arc(cc, r, a0, a1):
                let steps = 16
                c += (0...steps).map { i -> String in
                    let a = a0 + (a1 - a0) * Double(i) / Double(steps)
                    return pt(P(cc.x + r * cos(a), cc.y + r * sin(a))) + (i == 0 ? " m " : " l ")
                }.joined() + "S\n"
            case let .dots(pts, r):
                for d in pts {
                    c += GeoPDFExporter.circlePath(center: Point2D(x: 0, y: 0), r: r * size, { "\(n(x0 + d.x * size + $0.x)) \(n(y0 + d.y * size + $0.y))" }) + "f\n"
                }
            case let .dashed(pts, dash, gap):
                guard let f = pts.first else { continue }
                c += "[\(n(dash * size)) \(n(gap * size))] 0 d 0 J \(pt(f)) m " + pts.dropFirst().map { "\(pt($0)) l " }.joined() + "S [] 0 d 1 J\n"
            case let .text(str, at, rel):
                let fs = rel * size
                let w = textWidth(str, fs)
                c += "BT /F1 \(n(fs)) Tf \(n(x0 + at.x * size - w / 2)) \(n(y0 + at.y * size - fs * 0.35)) Td (\(GeoPDFExporter.pdfString(str))) Tj ET\n"
            }
        }
        return c + "Q\n"
    }
}
