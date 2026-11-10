import Foundation

/// The repeated parts of ISOM/ISSprOM symbols that are not a plain fill or stroke: area patterns (marsh lines, dashed
/// lines, visibility lines, scattered-tree holes, dots, random boulder triangles) and line decorations (cliff and earth
/// bank tags, wall dots and half dots, fence tags, ticks, chevrons, triangles, pylon bars, stairway steps, the edges of
/// transparent double lines, tapered lines). Pure geometry, shared by the map, raster, PDF and swatch renderers so they
/// all agree.
///
/// Coordinates are in any linear space ("units") with `unitsPerMM` units per paper millimetre: UTM meters, map points,
/// pixels or PDF points. `yUp` tells which way north is (true: UTM and PDF; false: map points and pixels).
public enum OrnamentMark: Hashable, Sendable {
    case line(Point2D, Point2D, widthMM: Double, colorHex: String)
    case dot(Point2D, diameterMM: Double, colorHex: String)
    case polygon([Point2D], colorHex: String)
    /// Open polyline, butt caps and mitre joins (edges of a transparent double line).
    case polyline([Point2D], widthMM: Double, colorHex: String)

    public var colorHex: String {
        switch self {
        case let .line(_, _, _, c), let .dot(_, _, c), let .polygon(_, c), let .polyline(_, _, c): return c
        }
    }
}

public enum SymbolOrnaments {
    /// Above this many marks in one area the pattern is drawn as a tint instead (zoomed far out).
    public static let maxMarks = 40_000

    // MARK: Random numbers (deterministic)

    /// SplitMix64 of a seed and a grid cell: the same cell of the same object always gets the same numbers, so a
    /// random pattern looks identical on every map tile, export and redraw.
    static func random(_ seed: UInt64, _ i: Int, _ j: Int, _ k: UInt64 = 0) -> Double {
        var z = seed &+ UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(bitPattern: Int64(j)) &* 0xC2B2_AE3D_27D4_EB4F &+ k &* 0x1656_67B1_9E37_79F9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    // MARK: Area patterns

    /// Marks of `pattern` covering `rect` (clip them to the area outline when drawing). Anchored to the coordinate origin,
    /// so neighbouring areas with the same pattern line up. nil = too many marks at this size; use `tint`.
    /// `seed` (e.g. `Feature.patternSeed`) makes random patterns differ between objects but stay the same on every redraw.
    public static func patternMarks(_ pattern: AreaPattern, in rect: Rect2D, unitsPerMM u: Double, yUp: Bool,
                                    maxMarks: Int = maxMarks, seed: UInt64 = 0) -> [OrnamentMark]? {
        let sp = pattern.spacingMM * u
        guard sp > 0, u > 0, rect.maxX > rect.minX, rect.maxY > rect.minY else { return [] }
        let a = pattern.angleDeg * .pi / 180
        // Direction along the lines / first grid axis (0° = north), and the perpendicular axis.
        let d = Point2D(x: sin(a), y: yUp ? cos(a) : -cos(a))
        let n = Point2D(x: -d.y, y: d.x)
        let corners = [Point2D(x: rect.minX, y: rect.minY), Point2D(x: rect.maxX, y: rect.minY),
                       Point2D(x: rect.minX, y: rect.maxY), Point2D(x: rect.maxX, y: rect.maxY)]
        func range(_ v: Point2D) -> (Double, Double) {
            let p = corners.map { $0.x * v.x + $0.y * v.y }
            return (p.min()!, p.max()!)
        }
        let (dn0, dn1) = range(n), (dd0, dd1) = range(d)
        let lines = Int(((dn1 - dn0) / sp).rounded(.up)) + 1
        let size = pattern.sizeMM
        switch pattern.kind {
        case .lines:
            guard lines <= maxMarks else { return nil }
            let dash = (pattern.dashMM ?? []).map { $0 * u }
            let period = dash.reduce(0, +)
            let dashed = dash.count >= 2 && dash.allSatisfy { $0 > 0 }
            if dashed, Double(lines) * (dd1 - dd0) / period > Double(maxMarks) { return nil }
            var out: [OrnamentMark] = []
            var k = (dn0 / sp).rounded(.down)
            while k * sp <= dn1 {
                let o = Point2D(x: n.x * k * sp, y: n.y * k * sp)
                func pt(_ s: Double) -> Point2D { Point2D(x: o.x + d.x * s, y: o.y + d.y * s) }
                if dashed {
                    // Dashes anchored to the origin; staggered rows start half a period later (310, 414).
                    let phase = pattern.staggered == true && Int(k).isMultiple(of: 2) == false ? period / 2 : 0
                    var s = ((dd0 - phase) / period).rounded(.down) * period + phase
                    while s <= dd1 {
                        var t = s
                        for (i, len) in dash.enumerated() {
                            if i.isMultiple(of: 2), t + len >= dd0, t <= dd1 {
                                out.append(.line(pt(t), pt(t + len), widthMM: size, colorHex: pattern.colorHex))
                            }
                            t += len
                        }
                        s += period
                    }
                } else {
                    out.append(.line(pt(dd0), pt(dd1), widthMM: size, colorHex: pattern.colorHex))
                }
                k += 1
            }
            return out
        case .dots, .holes, .triangles:
            let perLine = Int(((dd1 - dd0) / sp).rounded(.up)) + 1
            guard lines * perLine <= maxMarks else { return nil }
            var out: [OrnamentMark] = []
            let r = max(size, pattern.sidesMM?.max() ?? 0) * u / 2 + (pattern.jitterMM ?? 0) * u
            let isRandom = pattern.random == true, jitter = (pattern.jitterMM ?? 0) * u
            var j = (dn0 / sp).rounded(.down) - 1
            while j * sp <= dn1 + sp {
                let shift = pattern.staggered == true && Int(j).isMultiple(of: 2) == false ? 0.5 : 0
                var i = (dd0 / sp).rounded(.down) - 1
                while i * sp <= dd1 + sp {
                    let ii = Int(i), jj = Int(j)
                    // Random: anywhere in the cell; jitter: around the grid point; otherwise the grid point.
                    let fu = isRandom ? random(seed, ii, jj, 1) : 0, fv = isRandom ? random(seed, ii, jj, 2) : 0
                    var c = Point2D(x: n.x * (j + fv) * sp + d.x * (i + shift + fu) * sp, y: n.y * (j + fv) * sp + d.y * (i + shift + fu) * sp)
                    if jitter > 0 {
                        let ang = random(seed, ii, jj, 3) * 2 * .pi, dist = random(seed, ii, jj, 4) * jitter
                        c = Point2D(x: c.x + cos(ang) * dist, y: c.y + sin(ang) * dist)
                    }
                    if c.x >= rect.minX - r, c.x <= rect.maxX + r, c.y >= rect.minY - r, c.y <= rect.maxY + r {
                        if pattern.kind == .triangles {
                            let rot = isRandom ? random(seed, ii, jj, 5) * 360 : 0
                            let pts = pattern.sidesMM.flatMap { scalene($0, at: c, rotationDeg: rot, u: u, yUp: yUp) }
                                ?? triangle(at: c, sideMM: size, u: u, yUp: yUp, rotationDeg: rot)
                            out.append(.polygon(pts, colorHex: pattern.colorHex))
                        } else {
                            out.append(.dot(c, diameterMM: size, colorHex: pattern.colorHex))
                        }
                    }
                    i += 1
                }
                j += 1
            }
            return out
        }
    }

    /// Share of the area the pattern's marks cover (0…1): the colour strength to use when the marks are too small to draw.
    public static func tint(_ p: AreaPattern) -> Double {
        guard p.spacingMM > 0 else { return 0 }
        let cell = p.spacingMM * p.spacingMM
        switch p.kind {
        case .lines:
            var cover = p.sizeMM / p.spacingMM
            if let d = p.dashMM, d.count >= 2 {
                let total = d.reduce(0, +), on = d.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element).reduce(0, +)
                if total > 0 { cover *= on / total }
            }
            return min(1, cover)
        case .dots, .holes: return min(1, Double.pi * p.sizeMM * p.sizeMM / 4 / cell)
        case .triangles:
            if let s = p.sidesMM, s.count == 3 {
                let h = (s[0] + s[1] + s[2]) / 2
                return min(1, (h * (h - s[0]) * (h - s[1]) * (h - s[2])).squareRoot() / cell)
            }
            return min(1, 0.433 * p.sizeMM * p.sizeMM / cell)
        }
    }

    /// Pattern-only areas (marsh, good-visibility vegetation, boulder field, out-of-bounds hatching): the white "fill"
    /// is not painted, only the pattern — things below stay visible, as in OCAD and OOM.
    public static func isPatternOnly(fillHex: String, patterns: [AreaPattern]?) -> Bool {
        guard let patterns, !patterns.isEmpty else { return false }
        let h = fillHex.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return h == "FFFFFF"
    }

    /// Equilateral triangle, by default pointing north (boulder fields), turned clockwise by `rotationDeg`.
    static func triangle(at c: Point2D, sideMM s: Double, u: Double, yUp: Bool, rotationDeg: Double = 0) -> [Point2D] {
        let h = s * sqrt(3) / 2
        return place([(0, 2 * h / 3), (-s / 2, -h / 3), (s / 2, -h / 3)], at: c, rotationDeg: rotationDeg, u: u, yUp: yUp)
    }

    /// Scalene triangle from its three sides (first = base), centred on its centroid, turned clockwise by `rotationDeg`.
    static func scalene(_ sides: [Double], at c: Point2D, rotationDeg: Double, u: Double, yUp: Bool) -> [Point2D]? {
        guard sides.count == 3, let a = sides.first, a > 0 else { return nil }
        let b = sides[1], cc = sides[2]
        let x = (b * b - cc * cc + a * a) / (2 * a), y2 = b * b - x * x
        guard y2 > 0 else { return nil }
        let pts = [(0.0, 0.0), (a, 0.0), (x, y2.squareRoot())]
        let gx = (a + x) / 3, gy = y2.squareRoot() / 3
        return place(pts.map { ($0.0 - gx, $0.1 - gy) }, at: c, rotationDeg: rotationDeg, u: u, yUp: yUp)
    }

    /// Paper-mm points (x east, y north) turned clockwise and placed at `c` in units.
    private static func place(_ pts: [(Double, Double)], at c: Point2D, rotationDeg: Double, u: Double, yUp: Bool) -> [Point2D] {
        let t = rotationDeg * .pi / 180, up: Double = yUp ? 1 : -1
        return pts.map { p in
            let x = p.0 * cos(t) + p.1 * sin(t), y = -p.0 * sin(t) + p.1 * cos(t)
            return Point2D(x: c.x + x * u, y: c.y + up * y * u)
        }
    }

    // MARK: Line decorations

    /// Marks along a line (`points` = the line flattened, in drawing order), for the decoration and its `more`
    /// decorations. Tags, half dots, triangles and one-sided ticks go on the right side of the drawing direction (reverse
    /// the line to move them to the other side), as in OCAD. `dashMM` = the line's dash pattern (paper mm), for marks
    /// centred on its dashes.
    public static func decorationMarks(_ deco: LineDecoration, along points: [Point2D], unitsPerMM u: Double,
                                       lineWidthMM: Double, colorHex: String, yUp: Bool, dashMM: [Double]? = nil) -> [OrnamentMark] {
        guard points.count > 1, u > 0 else { return [] }
        let path = Path(points)
        guard path.total > 0 else { return [] }
        return deco.all.flatMap { single($0, path: path, u: u, lineWidthMM: lineWidthMM, colorHex: colorHex, yUp: yUp, dashMM: dashMM) }
    }

    /// A flattened line with arc-length lookup.
    struct Path {
        var points: [Point2D]
        var seg: [(a: Point2D, b: Point2D, len: Double, start: Double)] = []
        var total = 0.0

        init(_ points: [Point2D]) {
            self.points = points
            for (a, b) in zip(points, points.dropFirst()) {
                let l = a.distance(to: b)
                guard l > 0 else { continue }
                seg.append((a, b, l, total))
                total += l
            }
        }

        /// Position and unit tangent at distance s along the line.
        func at(_ s: Double) -> (p: Point2D, t: Point2D) {
            let s = min(max(s, 0), total)
            var lo = 0, hi = seg.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if seg[mid].start + seg[mid].len < s { lo = mid + 1 } else { hi = mid }
            }
            let g = seg[lo], f = (s - g.start) / g.len
            return (Point2D(x: g.a.x + (g.b.x - g.a.x) * f, y: g.a.y + (g.b.y - g.a.y) * f),
                    Point2D(x: (g.b.x - g.a.x) / g.len, y: (g.b.y - g.a.y) / g.len))
        }
    }

    private static func single(_ deco: LineDecoration, path: Path, u: Double, lineWidthMM: Double, colorHex: String, yUp: Bool,
                               dashMM: [Double]?) -> [OrnamentMark] {
        let points = path.points, total = path.total
        // Right of the drawing direction.
        func right(_ t: Point2D) -> Point2D { yUp ? Point2D(x: t.y, y: -t.x) : Point2D(x: -t.y, y: t.x) }
        func add(_ p: Point2D, _ v: Point2D, _ k: Double) -> Point2D { Point2D(x: p.x + v.x * k, y: p.y + v.y * k) }
        let ang = deco.angleDeg * .pi / 180
        func slanted(_ t: Point2D, side: Double = 1) -> Point2D {
            let r = right(t)
            return Point2D(x: t.x * cos(ang) + r.x * sin(ang) * side, y: t.y * cos(ang) + r.y * sin(ang) * side)
        }
        let half = lineWidthMM / 2 * u, size = deco.sizeMM * u, c = colorHex, w = deco.widthMM
        func tag(_ p: Point2D, _ t: Point2D, side: Double = 1) -> OrnamentMark {
            let v = slanted(t, side: side)
            return .line(add(p, v, half), add(p, v, half + size), widthMM: w, colorHex: c)
        }
        func tick(_ p: Point2D, _ t: Point2D) -> OrnamentMark {
            let v = slanted(t)
            return .line(add(p, v, -size / 2), add(p, v, size / 2), widthMM: w, colorHex: c)
        }
        func across(_ p: Point2D, _ t: Point2D, _ length: Double) -> OrnamentMark {
            let r = right(t)
            return .line(add(p, r, -length / 2), add(p, r, length / 2), widthMM: w, colorHex: c)
        }
        /// Two marks `pairMM` apart along the line, or one mark at `p`.
        func paired(_ p: Point2D, _ t: Point2D, _ pair: Double?, _ mark: (Point2D) -> [OrnamentMark]) -> [OrnamentMark] {
            guard let pair, pair > 0 else { return mark(p) }
            let o = pair / 2 * u
            return mark(add(p, t, -o)) + mark(add(p, t, o))
        }

        switch deco.kind {
        case .edges:
            // Transparent double line: the two edges as offset polylines.
            let o = size / 2
            return [.polyline(offset(points, by: o, yUp: yUp), widthMM: w, colorHex: c),
                    .polyline(offset(points, by: -o, yUp: yUp), widthMM: w, colorHex: c)]
        case .taper:
            return [.polygon(tapered(path, widthMM: lineWidthMM, tipMM: deco.widthMM, lengthMM: deco.sizeMM, u: u, yUp: yUp), colorHex: c)]
        case .endTicks:
            // Ticks at both ends, pointing outward (away from the line) on the right side (ISOM 512 bridge edge). With
            // `pairMM`: on both sides, from lines `pairMM` apart (710.2 crossing section: the ends turned outward).
            var out: [OrnamentMark] = []
            let sides: [Double] = deco.pairMM == nil ? [1] : [1, -1]
            let from = deco.pairMM.map { $0 / 2 * u } ?? half
            for (s, dir) in [(0.0, -1.0), (total, 1.0)] {
                let (p, t) = path.at(s)
                let out2 = Point2D(x: t.x * dir, y: t.y * dir)
                for side in sides {
                    let r = right(t), rs = Point2D(x: r.x * side, y: r.y * side)
                    let base = add(p, rs, from)
                    let v = Point2D(x: out2.x * cos(ang) + rs.x * sin(ang), y: out2.y * cos(ang) + rs.y * sin(ang))
                    out.append(.line(base, add(base, v, size), widthMM: w, colorHex: c))
                }
            }
            return out
        default:
            break
        }

        // Spacing 0: marks at the ends (bridge / tunnel ticks) or at every vertex (power line bars).
        if deco.spacingMM <= 0 && deco.onDashes != true {
            switch deco.kind {
            case .bars:
                return points.indices.compactMap { i -> OrnamentMark? in
                    let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
                    let l = a.distance(to: b)
                    guard l > 0 else { return nil }
                    return across(points[i], Point2D(x: (b.x - a.x) / l, y: (b.y - a.y) / l), size)
                }
            default:
                // Bridge: short ticks at both ends, splayed outward on both sides.
                var out: [OrnamentMark] = []
                for (s, dir) in [(0.0, -1.0), (total, 1.0)] {
                    let (p, t) = path.at(s)
                    let t2 = Point2D(x: t.x * dir, y: t.y * dir)
                    for side in [1.0, -1.0] {
                        let r = right(t2)
                        let base = add(p, r, half * side)
                        let v = Point2D(x: t2.x * cos(ang) + r.x * sin(ang) * side, y: t2.y * cos(ang) + r.y * sin(ang) * side)
                        out.append(.line(base, add(base, v, size), widthMM: w, colorHex: c))
                    }
                }
                return out
            }
        }

        // Positions along the line: centred on each dash of the line's dash pattern, or evenly spaced with equal
        // margins at both ends.
        var positions: [Double] = []
        if deco.onDashes == true, let dash = dashMM, dash.count >= 2, dash.allSatisfy({ $0 > 0 }) {
            let d = dash.map { $0 * u }, period = d.reduce(0, +)
            guard total / period < 20_000 else { return [] }
            var s = 0.0
            while s < total {
                var t = s
                for (i, len) in d.enumerated() {
                    if i.isMultiple(of: 2), t + len / 2 <= total { positions.append(t + len / 2) }
                    t += len
                }
                s += period
            }
        } else {
            let sp = max(deco.spacingMM, 0.01) * u
            let count = Int(total / sp)
            guard count < 20_000 else { return [] }
            let start = (total - Double(max(count - 1, 0)) * sp) / 2
            positions = (0..<max(count, total > sp / 2 ? 1 : 0)).map { start + Double($0) * sp }
        }
        var out: [OrnamentMark] = []
        for s in positions {
            let (p, t) = path.at(s)
            switch deco.kind {
            case .tags:
                out.append(tag(p, t))
            case .doubleTags:
                out += paired(p, t, deco.pairMM ?? 0.5) { [tag($0, t)] }
            case .dots:
                out += paired(p, t, deco.pairMM) { [.dot($0, diameterMM: deco.sizeMM, colorHex: c)] }
            case .halfDots:
                let r = right(t), rad = size / 2, centre = add(p, r, (deco.offsetMM ?? 0) * u)
                let pts = (0...12).map { k -> Point2D in
                    let a = Double.pi * Double(k) / 12
                    return Point2D(x: centre.x + (t.x * cos(a) + r.x * sin(a)) * rad, y: centre.y + (t.y * cos(a) + r.y * sin(a)) * rad)
                }
                out.append(.polygon(pts, colorHex: c))
            case .ticks:
                out.append(tick(p, t))
            case .doubleTicks:
                out += paired(p, t, deco.pairMM ?? 0.5) { [tick($0, t)] }
            case .bars, .rungs:
                out.append(across(p, t, size))
            case .chevrons:
                // Vertex on the centre line, one arm on each side, both reaching forward at `angleDeg` ("<" drawn west → east).
                out += paired(p, t, deco.pairMM) { v in
                    [1.0, -1.0].map { side in .line(v, add(v, slanted(t, side: side), size), widthMM: w, colorHex: c) }
                }
            case .triangles:
                let r = right(t), h = size * sqrt(3) / 2
                out.append(.polygon([add(p, t, -size / 2), add(p, t, size / 2), add(p, r, h)], colorHex: c))
            case .edges, .taper, .endTicks:
                break
            }
        }
        return out
    }

    /// The polyline moved sideways by `d` units (positive = right of the drawing direction), with mitre joins.
    static func offset(_ points: [Point2D], by d: Double, yUp: Bool) -> [Point2D] {
        let pts = points.enumerated().filter { $0.offset == 0 || $0.element.distance(to: points[$0.offset - 1]) > 1e-12 }.map(\.element)
        guard pts.count > 1 else { return pts }
        func normal(_ a: Point2D, _ b: Point2D) -> Point2D {
            let l = a.distance(to: b), t = Point2D(x: (b.x - a.x) / l, y: (b.y - a.y) / l)
            return yUp ? Point2D(x: t.y, y: -t.x) : Point2D(x: -t.y, y: t.x)
        }
        let closed = pts.count > 2 && pts.first!.distance(to: pts.last!) < 1e-9
        return pts.indices.map { i in
            let prev = i > 0 ? normal(pts[i - 1], pts[i]) : (closed ? normal(pts[pts.count - 2], pts[0]) : nil)
            let next = i < pts.count - 1 ? normal(pts[i], pts[i + 1]) : (closed ? normal(pts[0], pts[1]) : nil)
            switch (prev, next) {
            case let (a?, b?):
                let m = Point2D(x: a.x + b.x, y: a.y + b.y), dot = 1 + a.x * b.x + a.y * b.y
                guard dot > 0.15 else { return Point2D(x: pts[i].x + b.x * d, y: pts[i].y + b.y * d) }   // mitre limit
                return Point2D(x: pts[i].x + m.x * d / dot, y: pts[i].y + m.y * d / dot)
            case let (a?, nil): return Point2D(x: pts[i].x + a.x * d, y: pts[i].y + a.y * d)
            case let (nil, b?): return Point2D(x: pts[i].x + b.x * d, y: pts[i].y + b.y * d)
            default: return pts[i]
            }
        }
    }

    /// Outline of a line `widthMM` wide whose ends narrow to `tipMM` over `lengthMM` (107 erosion gully).
    static func tapered(_ path: Path, widthMM: Double, tipMM: Double, lengthMM: Double, u: Double, yUp: Bool) -> [Point2D] {
        let total = path.total, taper = min(lengthMM * u, total / 2)
        // Samples: every vertex plus points inside the taper zones, so the narrowing is smooth.
        var s: [Double] = [0]
        for g in path.seg { s.append(g.start + g.len) }
        if taper > 0 { for k in 1...8 { s += [taper * Double(k) / 8, total - taper * Double(k) / 8] } }
        s = Array(Set(s.map { ($0 * 1e6).rounded() / 1e6 })).sorted()
        var left: [Point2D] = [], rightSide: [Point2D] = []
        for x in s {
            let (p, t) = path.at(x)
            let f = taper > 0 ? min(1, min(x, total - x) / taper) : 1
            let hw = (tipMM + (widthMM - tipMM) * f) / 2 * u
            let r = yUp ? Point2D(x: t.y, y: -t.x) : Point2D(x: -t.y, y: t.x)
            rightSide.append(Point2D(x: p.x + r.x * hw, y: p.y + r.y * hw))
            left.append(Point2D(x: p.x - r.x * hw, y: p.y - r.y * hw))
        }
        return left + rightSide.reversed()
    }

    // MARK: Geometry helpers

    /// A feature's outline as a polyline (curves flattened), mapped by `transform` (e.g. UTM → pixels).
    public static func polyline(_ f: Feature, steps: Int = 8, _ transform: (Point2D) -> Point2D) -> [Point2D] {
        guard let first = f.nodes.first else { return [] }
        var out = [transform(first.point)]
        for s in f.segments {
            if s.isCurve {
                for i in 1...steps {
                    let t = Double(i) / Double(steps), m = 1 - t
                    let x = m * m * m * s.p0.x + 3 * m * m * t * s.c1.x + 3 * m * t * t * s.c2.x + t * t * t * s.p3.x
                    let y = m * m * m * s.p0.y + 3 * m * m * t * s.c1.y + 3 * m * t * t * s.c2.y + t * t * t * s.p3.y
                    out.append(transform(Point2D(x: x, y: y)))
                }
            } else {
                out.append(transform(s.p3))
            }
        }
        if f.closesPath, let p = out.first { out.append(p) }
        return out
    }
}

#if canImport(CoreGraphics)
import CoreGraphics

/// Draws ornament marks with Core Graphics (map tiles, raster export, symbol swatches).
public enum OrnamentRenderer {
    static func color(_ hex: String, alpha: Double = 1) -> CGColor {
        let v = rgbComponents(hex: hex) ?? (0, 0, 0)
        return CGColor(red: v.r, green: v.g, blue: v.b, alpha: alpha)
    }

    public static func draw(_ marks: [OrnamentMark], in ctx: CGContext, unitsPerMM u: Double, minWidth: Double = 0) {
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setLineCap(.butt)
        for m in marks {
            switch m {
            case let .line(a, b, w, c):
                ctx.setStrokeColor(color(c))
                ctx.setLineWidth(max(w * u, minWidth))
                ctx.move(to: CGPoint(x: a.x, y: a.y))
                ctx.addLine(to: CGPoint(x: b.x, y: b.y))
                ctx.strokePath()
            case let .dot(p, d, c):
                let r = max(d * u / 2, minWidth / 2)
                ctx.setFillColor(color(c))
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            case let .polygon(pts, c):
                guard let f = pts.first else { continue }
                ctx.setFillColor(color(c))
                ctx.move(to: CGPoint(x: f.x, y: f.y))
                for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.x, y: p.y)) }
                ctx.closePath()
                ctx.fillPath()
            case let .polyline(pts, w, c):
                guard let f = pts.first, pts.count > 1 else { continue }
                ctx.setStrokeColor(color(c))
                ctx.setLineWidth(max(w * u, minWidth))
                ctx.setLineJoin(.miter)
                ctx.move(to: CGPoint(x: f.x, y: f.y))
                for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.x, y: p.y)) }
                ctx.strokePath()
                ctx.setLineJoin(.round)
            }
        }
        ctx.restoreGState()
    }

    /// The patterns of an area, clipped to `outline`, covering `rect` (the visible part of the area, same units).
    /// When the marks would be closer than `minSpacing` units (zoomed far out) the pattern becomes an even tint.
    public static func drawPatterns(_ patterns: [AreaPattern], outline: CGPath, rect: Rect2D, in ctx: CGContext,
                                    unitsPerMM u: Double, yUp: Bool, minSpacing: Double = 0, minWidth: Double = 0, seed: UInt64 = 0) {
        guard !patterns.isEmpty, rect.maxX > rect.minX, rect.maxY > rect.minY else { return }
        ctx.saveGState()
        ctx.addPath(outline)
        ctx.clip(using: .evenOdd)   // area holes are subpaths of the outline
        for p in patterns {
            let marks = p.spacingMM * u < minSpacing ? nil : SymbolOrnaments.patternMarks(p, in: rect, unitsPerMM: u, yUp: yUp, seed: seed)
            if let marks {
                draw(marks, in: ctx, unitsPerMM: u, minWidth: minWidth)
            } else {
                ctx.setFillColor(color(p.colorHex, alpha: SymbolOrnaments.tint(p)))
                ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.maxX - rect.minX, height: rect.maxY - rect.minY))
            }
        }
        ctx.restoreGState()
    }
}
#endif
