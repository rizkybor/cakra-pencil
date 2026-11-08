import Foundation

/// The repeated parts of ISOM/ISSprOM symbols that are not a plain fill or stroke: area patterns (marsh lines, visibility
/// lines, scattered-tree holes, dots, boulder triangles) and line decorations (cliff and earth bank tags, wall dots,
/// fence tags, ticks). Pure geometry, shared by the map, raster, PDF and swatch renderers so they all agree.
///
/// Coordinates are in any linear space ("units") with `unitsPerMM` units per paper millimetre: UTM meters, map points,
/// pixels or PDF points. `yUp` tells which way north is (true: UTM and PDF; false: map points and pixels).
public enum OrnamentMark: Hashable, Sendable {
    case line(Point2D, Point2D, widthMM: Double, colorHex: String)
    case dot(Point2D, diameterMM: Double, colorHex: String)
    case polygon([Point2D], colorHex: String)

    public var colorHex: String {
        switch self {
        case let .line(_, _, _, c), let .dot(_, _, c), let .polygon(_, c): return c
        }
    }
}

public enum SymbolOrnaments {
    /// Above this many marks in one area the pattern is drawn as a tint instead (zoomed far out).
    public static let maxMarks = 40_000

    // MARK: Area patterns

    /// Marks of `pattern` covering `rect` (clip them to the area outline when drawing). Anchored to the coordinate origin,
    /// so neighbouring areas with the same pattern line up. nil = too many marks at this size; use `tint`.
    public static func patternMarks(_ pattern: AreaPattern, in rect: Rect2D, unitsPerMM u: Double, yUp: Bool,
                                    maxMarks: Int = maxMarks) -> [OrnamentMark]? {
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
            var out: [OrnamentMark] = []
            var k = (dn0 / sp).rounded(.down)
            while k * sp <= dn1 {
                let o = Point2D(x: n.x * k * sp, y: n.y * k * sp)
                out.append(.line(Point2D(x: o.x + d.x * dd0, y: o.y + d.y * dd0), Point2D(x: o.x + d.x * dd1, y: o.y + d.y * dd1),
                                 widthMM: size, colorHex: pattern.colorHex))
                k += 1
            }
            return out
        case .dots, .holes, .triangles:
            let perLine = Int(((dd1 - dd0) / sp).rounded(.up)) + 1
            guard lines * perLine <= maxMarks else { return nil }
            var out: [OrnamentMark] = []
            let r = size * u / 2
            var j = (dn0 / sp).rounded(.down)
            while j * sp <= dn1 + sp {
                var i = (dd0 / sp).rounded(.down)
                while i * sp <= dd1 + sp {
                    let c = Point2D(x: n.x * j * sp + d.x * i * sp, y: n.y * j * sp + d.y * i * sp)
                    if c.x >= rect.minX - r, c.x <= rect.maxX + r, c.y >= rect.minY - r, c.y <= rect.maxY + r {
                        if pattern.kind == .triangles {
                            out.append(.polygon(triangle(at: c, sideMM: size, u: u, yUp: yUp), colorHex: pattern.colorHex))
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
        switch p.kind {
        case .lines: return min(1, p.sizeMM / p.spacingMM)
        case .dots, .holes: return min(1, Double.pi * p.sizeMM * p.sizeMM / 4 / (p.spacingMM * p.spacingMM))
        case .triangles: return min(1, 0.433 * p.sizeMM * p.sizeMM / (p.spacingMM * p.spacingMM))
        }
    }

    /// Pattern-only areas (marsh, good-visibility vegetation, boulder field, out-of-bounds hatching): the white "fill"
    /// is not painted, only the pattern — things below stay visible, as in OCAD and OOM.
    public static func isPatternOnly(fillHex: String, patterns: [AreaPattern]?) -> Bool {
        guard let patterns, !patterns.isEmpty else { return false }
        let h = fillHex.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return h == "FFFFFF"
    }

    /// Equilateral triangle pointing north (boulder fields).
    static func triangle(at c: Point2D, sideMM s: Double, u: Double, yUp: Bool) -> [Point2D] {
        let h = s * sqrt(3) / 2 * u, half = s / 2 * u, up: Double = yUp ? 1 : -1
        return [Point2D(x: c.x, y: c.y + up * 2 * h / 3), Point2D(x: c.x - half, y: c.y - up * h / 3), Point2D(x: c.x + half, y: c.y - up * h / 3)]
    }

    // MARK: Line decorations

    /// Marks along a line (`points` = the line flattened, in drawing order). Tags and half dots go on the right side
    /// of the drawing direction (reverse the line to move them to the other side), as in OCAD.
    public static func decorationMarks(_ deco: LineDecoration, along points: [Point2D], unitsPerMM u: Double,
                                       lineWidthMM: Double, colorHex: String, yUp: Bool) -> [OrnamentMark] {
        guard points.count > 1, u > 0 else { return [] }
        var seg: [(a: Point2D, b: Point2D, len: Double, start: Double)] = []
        var total = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let l = a.distance(to: b)
            guard l > 0 else { continue }
            seg.append((a, b, l, total))
            total += l
        }
        guard total > 0 else { return [] }
        // Position and unit tangent at distance s along the line.
        func at(_ s: Double) -> (p: Point2D, t: Point2D) {
            let s = min(max(s, 0), total)
            let k = seg.firstIndex { $0.start + $0.len >= s } ?? seg.count - 1
            let g = seg[k], f = (s - g.start) / g.len
            return (Point2D(x: g.a.x + (g.b.x - g.a.x) * f, y: g.a.y + (g.b.y - g.a.y) * f),
                    Point2D(x: (g.b.x - g.a.x) / g.len, y: (g.b.y - g.a.y) / g.len))
        }
        // Right of the drawing direction.
        func right(_ t: Point2D) -> Point2D { yUp ? Point2D(x: t.y, y: -t.x) : Point2D(x: -t.y, y: t.x) }
        let ang = deco.angleDeg * .pi / 180
        func slanted(_ t: Point2D, side: Double = 1) -> Point2D {
            let r = right(t)
            return Point2D(x: t.x * cos(ang) + r.x * sin(ang) * side, y: t.y * cos(ang) + r.y * sin(ang) * side)
        }
        let half = lineWidthMM / 2 * u, size = deco.sizeMM * u, c = colorHex, w = deco.widthMM
        func tag(_ p: Point2D, _ t: Point2D, side: Double = 1) -> OrnamentMark {
            let v = slanted(t, side: side)
            return .line(Point2D(x: p.x + v.x * half, y: p.y + v.y * half),
                         Point2D(x: p.x + v.x * (half + size), y: p.y + v.y * (half + size)), widthMM: w, colorHex: c)
        }
        func tick(_ p: Point2D, _ t: Point2D) -> OrnamentMark {
            let v = slanted(t)
            return .line(Point2D(x: p.x - v.x * size / 2, y: p.y - v.y * size / 2),
                         Point2D(x: p.x + v.x * size / 2, y: p.y + v.y * size / 2), widthMM: w, colorHex: c)
        }

        // Spacing 0: marks at the ends (bridge / tunnel ticks) or at every vertex (power line bars).
        if deco.spacingMM <= 0 {
            switch deco.kind {
            case .bars:
                return points.indices.compactMap { i -> OrnamentMark? in
                    let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
                    let l = a.distance(to: b)
                    guard l > 0 else { return nil }
                    let r = right(Point2D(x: (b.x - a.x) / l, y: (b.y - a.y) / l))
                    return .line(Point2D(x: points[i].x - r.x * size, y: points[i].y - r.y * size),
                                 Point2D(x: points[i].x + r.x * size, y: points[i].y + r.y * size), widthMM: w, colorHex: c)
                }
            default:
                // Bridge: short ticks at both ends, splayed outward on both sides.
                var out: [OrnamentMark] = []
                for (s, dir) in [(0.0, -1.0), (total, 1.0)] {
                    let (p, t) = at(s)
                    let t2 = Point2D(x: t.x * dir, y: t.y * dir)
                    for side in [1.0, -1.0] {
                        let r = right(t2)
                        let base = Point2D(x: p.x + r.x * half * side, y: p.y + r.y * half * side)
                        let v = Point2D(x: t2.x * cos(ang) + r.x * sin(ang) * side, y: t2.y * cos(ang) + r.y * sin(ang) * side)
                        out.append(.line(base, Point2D(x: base.x + v.x * size, y: base.y + v.y * size), widthMM: w, colorHex: c))
                    }
                }
                return out
            }
        }

        let sp = deco.spacingMM * u
        let count = Int(total / sp)
        guard count < 20_000 else { return [] }
        // Centred along the line: equal margins at both ends.
        let start = (total - Double(max(count - 1, 0)) * sp) / 2
        var out: [OrnamentMark] = []
        for i in 0..<max(count, total > sp / 2 ? 1 : 0) {
            let (p, t) = at(start + Double(i) * sp)
            switch deco.kind {
            case .tags:
                out.append(tag(p, t))
            case .doubleTags:
                let o = 0.25 * u
                out.append(tag(Point2D(x: p.x - t.x * o, y: p.y - t.y * o), t))
                out.append(tag(Point2D(x: p.x + t.x * o, y: p.y + t.y * o), t))
            case .dots:
                out.append(.dot(p, diameterMM: deco.sizeMM, colorHex: c))
            case .halfDots:
                let r = right(t), rad = size / 2
                let pts = (0...12).map { k -> Point2D in
                    let a = Double.pi * Double(k) / 12
                    return Point2D(x: p.x + (t.x * cos(a) + r.x * sin(a)) * rad, y: p.y + (t.y * cos(a) + r.y * sin(a)) * rad)
                }
                out.append(.polygon(pts, colorHex: c))
            case .ticks:
                out.append(tick(p, t))
            case .doubleTicks:
                let o = 0.25 * u
                out.append(tick(Point2D(x: p.x - t.x * o, y: p.y - t.y * o), t))
                out.append(tick(Point2D(x: p.x + t.x * o, y: p.y + t.y * o), t))
            case .bars:
                let r = right(t)
                out.append(.line(Point2D(x: p.x - r.x * size, y: p.y - r.y * size), Point2D(x: p.x + r.x * size, y: p.y + r.y * size),
                                 widthMM: w, colorHex: c))
            }
        }
        return out
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
            }
        }
        ctx.restoreGState()
    }

    /// The patterns of an area, clipped to `outline`, covering `rect` (the visible part of the area, same units).
    /// When the marks would be closer than `minSpacing` units (zoomed far out) the pattern becomes an even tint.
    public static func drawPatterns(_ patterns: [AreaPattern], outline: CGPath, rect: Rect2D, in ctx: CGContext,
                                    unitsPerMM u: Double, yUp: Bool, minSpacing: Double = 0, minWidth: Double = 0) {
        guard !patterns.isEmpty, rect.maxX > rect.minX, rect.maxY > rect.minY else { return }
        ctx.saveGState()
        ctx.addPath(outline)
        ctx.clip()
        for p in patterns {
            let marks = p.spacingMM * u < minSpacing ? nil : SymbolOrnaments.patternMarks(p, in: rect, unitsPerMM: u, yUp: yUp)
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
