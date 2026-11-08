import Foundation

/// IOF course symbols as course objects: 702 map issue point, 707 marked route, 708 out-of-bounds boundary, 709
/// out-of-bounds area, 710 crossing point, 711 out-of-bounds route, 712 first aid, 713 refreshment, 715 map exchange.
/// Shapes and sizes come from OCCA's own course symbol definitions (ISOM 2017-2 §3.7, ISSprOM 2019-2 §4.7) and are
/// enlarged with the map like the control circles (×1.5 at 1:10000, ×1.333 at 1:3000).
extension CourseItem {
    /// OCCA's course symbols per standard; ISSprOM has no 711–713, the ISOM shapes are used there.
    private static let isomSymbols = Dictionary(OccaStandardSymbols.isomFile().symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
    private static let sprintSymbols = Dictionary(OccaStandardSymbols.issprFile().symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })

    static func iofSymbol(_ codes: [String], scale: Int) -> MapSymbol? {
        let sprint = MapStandard.for(scale: scale) == .issprom
        for code in codes {
            if sprint, let s = sprintSymbols[code] { return s }
            if !sprint, let s = isomSymbols[code] { return s }
        }
        return codes.lazy.compactMap { isomSymbols[$0] }.first
    }

    private var iofCodes: [String] {
        switch kind {
        case .mapIssue: return ["702.0"]
        case .markedRoute: return ["707.0"]
        case .outOfBoundsBoundary: return ["708.0"]
        case .outOfBoundsArea: return ["709.0"]
        case .crossingPoint: return ["710.0", "710.1"]
        case .outOfBoundsRoute: return ["711.0"]
        case .firstAid: return ["712.0"]
        case .refreshment: return ["713.0"]
        case .mapExchange: return ["715.0"]
        default: return []
        }
    }

    /// Ground meters per paper mm for course symbols (map scale × IOF enlargement).
    static func courseMetersPerMM(sheet: SheetSpec) -> Double {
        let scale = sheet.scaleDenominator
        return sheet.groundMeters(forPaperMM: 1) * MapStandard.for(scale: scale).enlargement(scale: scale)
    }

    /// Half the size of a point course symbol on the ground (for selection).
    func iofSymbolRadiusM(sheet: SheetSpec) -> Double {
        let d = Self.iofSymbol(iofCodes, scale: sheet.scaleDenominator)?.pointElements?.diameterMM ?? 4
        return max(d, 2) / 2 * Self.courseMetersPerMM(sheet: sheet)
    }

    func iofMarks(sheet: SheetSpec) -> [CourseMark] {
        let mpm = Self.courseMetersPerMM(sheet: sheet)
        let scale = sheet.scaleDenominator
        guard let sym = Self.iofSymbol(iofCodes, scale: scale) else { return [] }
        switch kind.placement {
        case .tap:
            guard let c = points.first else { return [] }
            return Self.pointMarks(sym.pointElements ?? [], at: c, mpm: mpm)
        case .line:
            guard points.count >= 2 else { return [] }
            if kind == .outOfBoundsRoute, let cross = Self.iofSymbol(["711.0"], scale: scale)?.pointElements {
                // Crosses 3.0 mm every 5 mm along the route (ISOM: 4–6 mm apart); no line.
                return Self.positions(along: points, every: 5 * mpm).flatMap { Self.pointMarks(cross, at: $0, mpm: mpm) }
            }
            let w = (sym.lineStyle?.widthMM ?? sym.drawingWidthMM) * mpm
            if let dash = sym.lineStyle?.dashMM, dash.count >= 2 {
                return [.width(w)] + Self.dashes(points, dash: dash[0] * mpm, gap: dash[1] * mpm).map { .polyline($0, closed: false) } + [.width(nil)]
            }
            return [.width(w), .polyline(points, closed: false), .width(nil)]
        case .area:
            let poly = outline
            guard poly.count >= 3, let b = Rect2D(points: poly) else { return [] }
            var marks: [CourseMark] = []
            // Hatching 0.2 @ 1.2 mm at 45°, clipped to the rectangle, then the solid boundary line (709.1).
            for p in sym.patterns ?? [] {
                guard let lines = SymbolOrnaments.patternMarks(p, in: b, unitsPerMM: mpm, yUp: true, maxMarks: 5000) else { continue }
                marks.append(.width(p.sizeMM * mpm))
                for case let .line(a, z, _, _) in lines {
                    if let seg = Self.clip(a, z, to: b) { marks.append(.polyline([seg.0, seg.1], closed: false)) }
                }
            }
            if let edge = Self.iofSymbol(["709.1"], scale: scale)?.lineStyle {
                marks.append(.width(edge.widthMM * mpm))
                marks.append(.polyline(poly, closed: true))
            }
            return marks + [.width(nil)]
        }
    }

    /// Point symbol elements (paper mm, y up) as overprint marks at `c`.
    static func pointMarks(_ elements: [PointElement], at c: Point2D, mpm: Double) -> [CourseMark] {
        var out: [CourseMark] = []
        func at(_ p: Point2D) -> Point2D { Point2D(x: c.x + p.x * mpm, y: c.y + p.y * mpm) }
        for e in elements.drawingOrder {
            let o = e.points.first ?? Point2D(x: 0, y: 0)
            switch e.kind {
            case .line:
                out.append(.width(e.lineWidthMM * mpm))
                out.append(.polyline(e.points.map(at), closed: false))
            case .circle:
                out.append(.width(e.lineWidthMM * mpm))
                out.append(.circle(center: at(o), radiusM: e.diameterMM / 2 * mpm))
            case .dot:
                let r = e.diameterMM / 2 * mpm, cc = at(o)
                out.append(.fill((0..<24).map { i in
                    let t = Double(i) / 24 * 2 * .pi
                    return Point2D(x: cc.x + r * cos(t), y: cc.y + r * sin(t))
                }, opacity: 1))
            case .area:
                out.append(.fill(e.points.map(at), opacity: 1))
            }
        }
        return out + [.width(nil)]
    }

    /// Positions every `step` along a polyline, starting half a step in.
    static func positions(along pts: [Point2D], every step: Double) -> [Point2D] {
        guard step > 0 else { return [] }
        var out: [Point2D] = []
        var next = step / 2
        var walked = 0.0
        for (a, b) in zip(pts, pts.dropFirst()) {
            let l = a.distance(to: b)
            guard l > 0 else { continue }
            while next <= walked + l, out.count < 2000 {
                let t = (next - walked) / l
                out.append(Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                next += step
            }
            walked += l
        }
        return out
    }

    /// A polyline cut into dashes (`dash` on, `gap` off).
    static func dashes(_ pts: [Point2D], dash: Double, gap: Double) -> [[Point2D]] {
        guard dash > 0, gap >= 0 else { return [pts] }
        var out: [[Point2D]] = []
        var current: [Point2D] = []
        var on = true, left = dash
        for (a, b) in zip(pts, pts.dropFirst()) {
            var p = a
            var l = a.distance(to: b)
            guard l > 0 else { continue }
            let ux = (b.x - a.x) / l, uy = (b.y - a.y) / l
            if on, current.isEmpty { current = [p] }
            while l >= left, out.count < 5000 {
                p = Point2D(x: p.x + ux * left, y: p.y + uy * left)
                l -= left
                if on { current.append(p); out.append(current); current = [] } else { current = [p] }
                on.toggle()
                left = on ? dash : gap
            }
            left -= l
            if on { if current.isEmpty { current = [p] }; current.append(b) }
        }
        if on, current.count >= 2 { out.append(current) }
        // A route ending exactly at the end of a gap leaves a zero-length dash.
        return out.filter { d in zip(d, d.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } > 1e-9 }
    }

    /// Segment a–b clipped to rectangle `r` (Liang–Barsky); nil if outside.
    static func clip(_ a: Point2D, _ b: Point2D, to r: Rect2D) -> (Point2D, Point2D)? {
        var t0 = 0.0, t1 = 1.0
        let dx = b.x - a.x, dy = b.y - a.y
        for (p, q) in [(-dx, a.x - r.minX), (dx, r.maxX - a.x), (-dy, a.y - r.minY), (dy, r.maxY - a.y)] {
            if p == 0 { if q < 0 { return nil }; continue }
            let t = q / p
            if p < 0 { if t > t1 { return nil }; t0 = max(t0, t) } else { if t < t0 { return nil }; t1 = min(t1, t) }
        }
        return (Point2D(x: a.x + dx * t0, y: a.y + dy * t0), Point2D(x: a.x + dx * t1, y: a.y + dy * t1))
    }
}
