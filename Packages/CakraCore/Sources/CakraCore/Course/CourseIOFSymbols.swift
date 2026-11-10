import Foundation

/// IOF course symbols as course objects: 702 map issue point, 707 marked route, 708 out-of-bounds boundary, 709
/// out-of-bounds area, 710 crossing point, 711 out-of-bounds route, 712 first aid, 713 refreshment, 715 map exchange.
/// Shapes and sizes come from OCCA's own course symbol definitions (ISOM 2017-2 §3.7, ISSprOM 2019-2 §4.7) and are
/// enlarged with the map like the control circles (×1.5 at 1:10000, ×1.333 at 1:3000).
extension CourseItem {
    /// OCCA's course symbols per standard; ISSprOM / ISInOM lack some (711–713), the ISOM shapes are used there.
    private static let isomSymbols = Dictionary(OccaStandardSymbols.isomFile().symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
    private static let sprintSymbols = Dictionary(OccaStandardSymbols.issprFile().symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
    private static let indoorSymbols = Dictionary(OccaStandardSymbols.isinomFile().symbols.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })

    static func iofSymbol(_ codes: [String], standard: MapStandard) -> MapSymbol? {
        let tables: [[String: MapSymbol]]
        switch standard {
        case .isom: tables = [isomSymbols]
        case .issprom: tables = [sprintSymbols, isomSymbols]
        case .isinom: tables = [indoorSymbols, sprintSymbols, isomSymbols]
        }
        for t in tables { for code in codes { if let s = t[code] { return s } } }
        return nil
    }

    private var iofCodes: [String] { Self.iofCodes(kind) }

    /// The symbol drawn for an IOF course object kind on a map with `sheet` (for previews, e.g. the Objects tab grid).
    public static func iofSymbol(for kind: Kind, sheet: SheetSpec) -> MapSymbol? {
        let codes = iofCodes(kind)
        return codes.isEmpty ? nil : iofSymbol(codes, standard: sheet.mapStandard)
    }

    private static func iofCodes(_ kind: Kind) -> [String] {
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

    /// Ground meters per paper mm for course symbols (map scale × the sheet standard's enlargement; indoor 1:700 = 1).
    static func courseMetersPerMM(sheet: SheetSpec) -> Double {
        sheet.groundMeters(forPaperMM: 1) * sheet.symbolEnlargement
    }

    /// Half the size of a point course symbol on the ground (for selection).
    func iofSymbolRadiusM(sheet: SheetSpec) -> Double {
        let d = Self.iofSymbol(iofCodes, standard: sheet.mapStandard)?.pointElements?.diameterMM ?? 4
        return max(d, 2) / 2 * Self.courseMetersPerMM(sheet: sheet)
    }

    /// Upper / lower purple level of a colour priority in OCCA's course symbols of `standard`.
    static func level(_ priority: Int?, _ standard: MapStandard) -> CourseLevel {
        guard let priority else { return .lower }
        if standard == .isinom {
            // ISInOM: everything above lower purple (n52) in its table is drawn on top.
            return priority < ColorHierarchy.lowerPurplePriority(for: .isinom) ? .upper : .lower
        }
        return priority == ColorHierarchy.upperPurplePriority() ? .upper : .lower
    }

    func iofMarks(sheet: SheetSpec) -> [CourseMark] {
        let mpm = Self.courseMetersPerMM(sheet: sheet)
        let standard = sheet.mapStandard
        guard let sym = Self.iofSymbol(iofCodes, standard: standard) else { return [] }
        let lvl: CourseMark = .level(Self.level(sym.colorPriority, standard))
        switch kind.placement {
        case .tap:
            guard let c = points.first else { return [] }
            return Self.pointMarks(sym.pointElements ?? [], at: c, mpm: mpm, standard: standard) + [.level(nil)]
        case .line:
            guard points.count >= 2 else { return [] }
            if kind == .outOfBoundsRoute, let cross = Self.iofSymbol(["711.0"], standard: standard)?.pointElements {
                // Crosses 3.0 mm every 5 mm along the route (ISOM: 4–6 mm apart); no line.
                return Self.positions(along: points, every: 5 * mpm).flatMap { Self.pointMarks(cross, at: $0, mpm: mpm, standard: standard) } + [.level(nil)]
            }
            let w = (sym.lineStyle?.widthMM ?? sym.drawingWidthMM) * mpm
            if let dash = Feature.validDash(sym.lineStyle?.dashMM) {
                return [lvl, .width(w)] + Self.dashes(points, pattern: dash.map { $0 * mpm }).map { .polyline($0, closed: false) }
                    + [.width(nil), .level(nil)]
            }
            return [lvl, .width(w), .polyline(points, closed: false), .width(nil), .level(nil)]
        case .area:
            let poly = outline
            guard poly.count >= 3, let b = Rect2D(points: poly) else { return [] }
            var marks: [CourseMark] = [lvl]
            // Cross-hatching 0.2 @ 1.2 mm at ±45°, clipped to the area outline, then the solid boundary line (709.1).
            for p in sym.patterns ?? [] {
                guard let lines = SymbolOrnaments.patternMarks(p, in: b, unitsPerMM: mpm, yUp: true, maxMarks: 5000) else { continue }
                marks.append(.width(p.sizeMM * mpm))
                for case let .line(a, z, _, _) in lines {
                    for seg in Self.clip(a, z, toPolygon: poly) { marks.append(.polyline([seg.0, seg.1], closed: false)) }
                }
            }
            if let edge = Self.iofSymbol(["709.1", "709.4"], standard: standard) {
                marks.append(.level(Self.level(edge.colorPriority, standard)))
                marks.append(.width((edge.lineStyle?.widthMM ?? 0.25) * mpm))
                marks.append(.polyline(poly, closed: true))
            }
            return marks + [.width(nil), .level(nil)]
        }
    }

    /// Point symbol elements (paper mm, y up) as overprint marks at `c`, each at its upper / lower purple level.
    static func pointMarks(_ elements: [PointElement], at c: Point2D, mpm: Double, standard: MapStandard = .isom) -> [CourseMark] {
        var out: [CourseMark] = []
        func at(_ p: Point2D) -> Point2D { Point2D(x: c.x + p.x * mpm, y: c.y + p.y * mpm) }
        for e in elements.drawingOrder {
            let o = e.points.first ?? Point2D(x: 0, y: 0)
            out.append(.level(level(e.priority, standard)))
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
        guard dash > 0, gap > 0 else { return [pts] }
        return dashes(pts, pattern: [dash, gap])
    }

    /// A polyline cut into dashes by a dash pattern [dash, gap, dash, gap…] (2 or 4 values, e.g. 507's pairs of dashes),
    /// in the polyline's units.
    static func dashes(_ pts: [Point2D], pattern: [Double]) -> [[Point2D]] {
        guard Feature.validDash(pattern) != nil else { return [pts] }
        var out: [[Point2D]] = []
        var current: [Point2D] = []
        var k = 0, left = pattern[0]
        var on: Bool { k.isMultiple(of: 2) }
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
                k = (k + 1) % pattern.count
                left = pattern[k]
            }
            left -= l
            if on { if current.isEmpty { current = [p] }; current.append(b) }
        }
        if on, current.count >= 2 { out.append(current) }
        // A route ending exactly at the end of a gap leaves a zero-length dash.
        return out.filter { d in zip(d, d.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } > 1e-9 }
    }

    /// The parts of segment a–b inside polygon `poly` (even-odd rule): 709 hatching follows the area outline, not its
    /// bounding box.
    static func clip(_ a: Point2D, _ b: Point2D, toPolygon poly: [Point2D]) -> [(Point2D, Point2D)] {
        guard poly.count >= 3 else { return [] }
        let dx = b.x - a.x, dy = b.y - a.y
        var ts: [Double] = [0, 1]
        for i in poly.indices {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            let ex = q.x - p.x, ey = q.y - p.y
            let den = dx * ey - dy * ex
            guard abs(den) > 1e-15 else { continue }
            let t = ((p.x - a.x) * ey - (p.y - a.y) * ex) / den
            let u = ((p.x - a.x) * dy - (p.y - a.y) * dx) / den
            if t > 0, t < 1, u >= 0, u <= 1 { ts.append(t) }
        }
        ts.sort()
        var out: [(Point2D, Point2D)] = []
        for (t0, t1) in zip(ts, ts.dropFirst()) where t1 - t0 > 1e-12 {
            let m = (t0 + t1) / 2
            guard contains(poly, Point2D(x: a.x + dx * m, y: a.y + dy * m)) else { continue }
            out.append((Point2D(x: a.x + dx * t0, y: a.y + dy * t0), Point2D(x: a.x + dx * t1, y: a.y + dy * t1)))
        }
        return out
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
