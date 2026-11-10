import Foundation

// MARK: - Cut areas with a shape or path, cut lines with a box (OCAD "Cut hole / Split area", OOM "Cut away")

/// Why a shape/path cut changed nothing.
public enum ShapeCutFailure: Error, Equatable, Sendable {
    /// The cutting shape, path or box doesn't reach the object.
    case noOverlap
    /// The shape lies completely inside one of the area's holes: there is nothing filled to cut away.
    case insideHole
    /// The path doesn't cut the area into pieces (it must cross the edge at least twice, or run from edge to edge
    /// through holes so that a part comes loose).
    case notCrossing
    /// The outlines could not be resolved (e.g. a path that crosses itself inside the area).
    case unresolved
}

extension Feature {
    /// Area minus a closed shape (rectangle, ellipse, closed pen path): the part of the area inside `shape` is
    /// removed. Success with several features = the area fell apart into pieces (the largest keeps this object's id;
    /// the others get new ids and an empty name); success with `[]` = the shape covered the whole area.
    ///
    /// Holes: a shape completely inside the filled part becomes a new hole; a shape overlapping a hole enlarges it;
    /// a shape covering a hole absorbs it; a shape across the outer edge and a hole opens the hole to the outside.
    /// Every resulting piece keeps the holes that lie inside it.
    ///
    /// Works on the exact bezier segments of all outlines: they are split at their intersections (de Casteljau),
    /// so curves away from and along the cut stay curves; nodes that are not touched are kept as they are.
    /// `eps`: distance (m) at which points count as the same / a point counts as lying on an edge.
    public func subtractingShape(_ shape: [BezierNode], eps: Double = 1e-4) -> Result<[Feature], ShapeCutFailure> {
        guard kind == .area, nodes.count >= 3, shape.count >= 3 else { return .failure(.unresolved) }
        guard let a = ShapeCut.Region(self, eps: eps) else { return .failure(.unresolved) }
        let b = ShapeCut.Outline(nodes: shape, closed: true, eps: eps)
        guard b.area != 0 else { return .failure(.unresolved) }
        let B = ShapeCut.Region(outer: b.counterclockwise, holes: [])
        guard a.box.intersects(B.box) else { return .failure(.noOverlap) }
        guard let r = ShapeCut.combine(a, B, op: .subtract, eps: eps) else { return .failure(.unresolved) }
        if !r.changed {
            if let p = b.segments.first?.p0, a.holes.contains(where: { ShapeCut.locate(p, in: $0.polygon, eps: a.locateTolerance) == .inside }) {
                return .failure(.insideHole)
            }
            return .failure(.noOverlap)                                 // apart, or touching the edge only
        }
        if r.loops.isEmpty { return .success([]) }                      // covers the whole area
        return pieces(from: r.loops, region: a, cutPoints: r.points, eps: eps)
    }

    /// Split an area along an open path (pen or freehand): every stretch of the path between two crossings of the
    /// area's edges (outer edge or hole edges) that runs inside the filled part becomes a new edge on both sides, so
    /// the area falls apart into pieces; holes go to the piece they lie in, a hole the path runs through is split
    /// between the pieces. The path must cut off at least one piece; ends of the path inside the area are ignored.
    public func splittingArea(along path: [BezierNode], eps: Double = 1e-4) -> Result<[Feature], ShapeCutFailure> {
        guard kind == .area, nodes.count >= 3, path.count >= 2 else { return .failure(.unresolved) }
        guard let a = ShapeCut.Region(self, eps: eps) else { return .failure(.unresolved) }
        let p = ShapeCut.Outline(nodes: path, closed: false, eps: eps)
        guard a.box.intersects(p.box) else { return .failure(.noOverlap) }
        var points: [Point2D] = []
        var pathHits: [ShapeCut.Hit] = []
        var kept: [ShapeCut.Chunk] = []
        var whole: [[CubicSegment]] = []
        for ring in a.rings {
            let h = ShapeCut.hits(ring.segments, p.segments, eps: eps, points: &points)
            pathHits += h.b
            if h.a.isEmpty { whole.append(ring.segments) } else {
                kept += ShapeCut.chunks(ring.segments, hits: h.a, closed: true, points: points)
            }
        }
        if pathHits.isEmpty {
            return p.segments.contains(where: { a.locate($0.p0) == .inside }) ? .failure(.notCrossing) : .failure(.noOverlap)
        }
        let pChunks = ShapeCut.chunks(p.segments, hits: pathHits, closed: false, points: points)
        for c in pChunks where a.locate(c.midpoint.point) == .inside {
            var forward = c, backward = c.reversed
            forward.twin = kept.count + 1
            backward.twin = kept.count
            kept += [forward, backward]
        }
        guard kept.contains(where: { $0.twin != nil }) else { return .failure(.notCrossing) }
        guard let loops = ShapeCut.trace(kept) else { return .failure(.unresolved) }
        let result = pieces(from: loops + whole, region: a, cutPoints: points, eps: eps)
        if case let .success(list) = result, list.count < 2 { return .failure(.notCrossing) }
        return result
    }

    /// Cut out the parts of a line inside `polygon` (a box dragged on screen, as map coordinates), cutting the line
    /// exactly where it crosses the polygon's edge (curves are split at the exact parameter and stay curves).
    /// Returns the remaining pieces (the first keeps this object's id), `[]` if the box covers the whole line,
    /// nil if no part of the line lies inside the box. Closed lines are opened where the box cuts them.
    public func cuttingOut(_ polygon: [Point2D], eps: Double = 1e-4) -> [Feature]? {
        guard kind == .line, nodes.count >= 2, polygon.count >= 3 else { return nil }
        let line = ShapeCut.Outline(nodes: nodes, closed: false, eps: eps)
        let box = ShapeCut.Outline(nodes: polygon.map { BezierNode(point: $0) }, closed: true, eps: eps)
        guard line.box.intersects(box.box) else { return nil }
        let ring = isRingLine
        let hits = ShapeCut.hits(line.segments, box.segments, eps: eps)
        let locEps = box.locateTolerance
        if hits.a.isEmpty {
            guard let p = line.segments.first?.point(at: 0.5) else { return nil }
            return ShapeCut.locate(p, in: box.polygon, eps: locEps) == .inside ? [] : nil
        }
        let chunks = ShapeCut.chunks(line.segments, hits: hits.a, closed: ring, points: hits.points, includeEnds: !ring)
        let keep = chunks.map { ShapeCut.locate($0.midpoint.point, in: box.polygon, eps: locEps) != .inside }
        guard keep.contains(false) else { return nil }
        // Runs of consecutive kept chunks (touching the box edge without entering it doesn't split the line).
        var runs: [[CubicSegment]] = []
        var current: [CubicSegment]?
        for (c, k) in zip(chunks, keep) {
            if k { current = (current ?? []) + c.segments } else if let r = current { runs.append(r); current = nil }
        }
        if let r = current {
            // Closed line: the last run continues through the start point into the first run.
            if ring, keep.first == true, !runs.isEmpty { runs[0] = r + runs[0] } else { runs.append(r) }
        }
        let minLength = eps * 10
        var out: [Feature] = []
        for r in runs where r.reduce(0, { $0 + $1.approximateLength }) > minLength {
            let n = Feature.nodes(from: r)
            guard n.count >= 2 else { continue }
            var f = self
            if !out.isEmpty {
                f.id = UUID()
                f.name = ""
                f.createdAt = Date()
            }
            f.nodes = n
            out.append(f)
        }
        return out
    }

    /// Features from traced loops: positive loops are pieces (largest first, keeping this object's id), negative loops
    /// are holes, each given to the smallest piece that contains it. Nodes added at cut points on straight edges that
    /// turned out not to be corners are removed.
    func pieces(from loops: [[CubicSegment]], region: ShapeCut.Region, cutPoints: [Point2D],
                eps: Double) -> Result<[Feature], ShapeCutFailure> {
        let original = region.rings.flatMap(\.nodes)
        var outers: [(nodes: [BezierNode], area: Double, polygon: [Point2D])] = []
        var holes: [(nodes: [BezierNode], probe: Point2D)] = []
        for loop in loops {
            let polygon = ShapeCut.flatten(loop, tolerance: region.flattenTolerance)
            let area = ShapeCut.signedArea(polygon)
            guard abs(area) > eps * eps else { continue }   // sliver
            var n = Feature.nodes(from: loop)
            guard n.count >= 4, let last = n.popLast() else { continue }
            n[0].inHandle = last.inHandle.map { $0 + (n[0].point - last.point) }
            n = ShapeCut.removingStraightCutNodes(n, cutPoints: cutPoints, original: original, eps: eps)
            guard n.count >= 3 else { continue }
            if area > 0 {
                outers.append((n, area, polygon))
            } else if let probe = ShapeCut.interiorProbe(of: loop, polygon: polygon, eps: region.locateTolerance) {
                holes.append((n, probe))
            }
        }
        guard !outers.isEmpty else { return .failure(.unresolved) }
        outers.sort { $0.area > $1.area }
        var holesOf = [[[BezierNode]]](repeating: [], count: outers.count)
        for h in holes {
            // The smallest piece around the hole (pieces never overlap, so any containing piece is the right one).
            let owner = outers.indices.filter { ShapeCut.locate(h.probe, in: outers[$0].polygon, eps: 0) == .inside }
                .min { outers[$0].area < outers[$1].area }
            if let owner { holesOf[owner].append(h.nodes) }
        }
        var out: [Feature] = []
        let clockwise = Feature.signedArea(of: nodes) < 0
        for (k, piece) in outers.enumerated() {
            var f = self
            if k > 0 {
                f.id = UUID()
                f.name = ""
                f.createdAt = Date()
            }
            // Keep the original drawing direction (counterclockwise was only needed for the cut); holes run opposite.
            f.nodes = clockwise ? piece.nodes.reversed().map(\.reversed) : piece.nodes
            let hs = holesOf[k].map { clockwise ? $0.reversed().map(\.reversed) : $0 }
            f.holes = hs.isEmpty ? nil : hs
            out.append(f)
        }
        return .success(out)
    }
}

/// Cutting engine: two outlines made of cubic segments are split at all points where they meet (crossings, touches,
/// overlapping ends; each such point gets one shared id), the pieces between those points ("chunks") are classified
/// as inside/outside the other outline, and the kept chunks are chained into loops by id, turning as far left as
/// possible at branch points so pieces that only touch at a point stay separate.
enum ShapeCut {
    // MARK: Outline

    struct Outline {
        var nodes: [BezierNode]
        var closed: Bool
        var segments: [CubicSegment]
        /// Polyline approximation (for point-in-polygon tests only; the cut itself uses the exact segments).
        var polygon: [Point2D]
        var area: Double
        var box: Rect2D
        var flattenTolerance: Double
        var eps: Double

        init(nodes: [BezierNode], closed: Bool, eps: Double) {
            self.nodes = nodes
            self.closed = closed
            self.eps = eps
            segments = Feature(kind: closed ? .area : .line, colorHex: "#000000", widthMM: 0, nodes: nodes).segments
                .filter { !ShapeCut.isDegenerate($0) }
            let pts = nodes.flatMap { [$0.point] + [$0.inHandle, $0.outHandle].compactMap { $0 } }
            box = (Rect2D(points: pts) ?? Rect2D(minX: 0, minY: 0, maxX: 0, maxY: 0)).insetBy(-eps)
            // Location tests only need to tell sides apart: a fine polyline, but never coarser than 1/2000 of the size.
            flattenTolerance = max(eps, min(max(box.width, box.height) / 2000, eps * 20))
            polygon = ShapeCut.flatten(segments, tolerance: flattenTolerance)
            area = closed ? ShapeCut.signedArea(polygon) : 0
        }

        var locateTolerance: Double { max(eps, flattenTolerance) * 2 }

        var counterclockwise: Outline { area < 0 ? reversedOutline : self }
        var clockwise: Outline { area > 0 ? reversedOutline : self }

        private var reversedOutline: Outline {
            guard closed else { return self }
            var o = self
            o.nodes = nodes.reversed().map(\.reversed)
            o.segments = segments.reversed().map(\.reversedSegment)
            o.polygon = polygon.reversed()
            o.area = -area
            return o
        }
    }

    // MARK: Region (outer ring + holes)

    /// A filled region: a counterclockwise outer ring and clockwise holes, so the filled side is on the left of every ring.
    struct Region {
        var outer: Outline
        var holes: [Outline]

        init(outer: Outline, holes: [Outline]) {
            self.outer = outer
            self.holes = holes
        }

        /// The area of `f` with its holes; nil if the outer ring has no area.
        init?(_ f: Feature, eps: Double) {
            let o = Outline(nodes: f.nodes, closed: true, eps: eps)
            guard o.area != 0 else { return nil }
            outer = o.counterclockwise
            holes = f.holeRings.map { Outline(nodes: $0, closed: true, eps: eps) }.filter { $0.area != 0 }.map(\.clockwise)
        }

        var rings: [Outline] { [outer] + holes }
        var box: Rect2D { outer.box }
        var locateTolerance: Double { outer.locateTolerance }
        var flattenTolerance: Double { outer.flattenTolerance }

        /// Inside the filled part (inside the outer ring, outside every hole), outside, or on an edge (within `eps`).
        func locate(_ p: Point2D, eps: Double? = nil) -> Location {
            let e = eps ?? locateTolerance
            var inside = false
            for r in rings {
                switch ShapeCut.locate(p, in: r.polygon, eps: e) {
                case .boundary: return .boundary
                case .inside: inside.toggle()
                case .outside: break
                }
            }
            return inside ? .inside : .outside
        }
    }

    enum BooleanOp { case subtract, union }

    /// Boolean of two regions on their exact segments: `a − b` or `a ∪ b`. Returns the traced loops (counterclockwise =
    /// filled pieces, clockwise = holes), the shared cut points, and whether anything changed compared with `a` alone
    /// (`false` = the outlines don't interact: apart, or only touching). nil = unresolvable geometry.
    static func combine(_ a: Region, _ b: Region, op: BooleanOp, eps: Double) -> (loops: [[CubicSegment]], points: [Point2D], changed: Bool)? {
        let locEps = a.locateTolerance
        var points: [Point2D] = []
        var hitsA = [[Hit]](repeating: [], count: a.rings.count)
        var hitsB = [[Hit]](repeating: [], count: b.rings.count)
        for (i, ra) in a.rings.enumerated() {
            for (j, rb) in b.rings.enumerated() where ra.box.intersects(rb.box) {
                let h = hits(ra.segments, rb.segments, eps: eps, points: &points)
                hitsA[i] += h.a
                hitsB[j] += h.b
            }
        }
        var kept: [Chunk] = []
        var whole: [[CubicSegment]] = []
        var changed = false
        // a's edges: kept where they lie outside b. On a shared edge: subtract keeps it when a's filled side (left)
        // stays outside b; union keeps it when a's outer side (right) isn't filled by b (same-direction edges once).
        func keepA(_ m: Point2D, _ tangent: Point2D) -> Bool {
            switch b.locate(m, eps: locEps) {
            case .outside: return true
            case .inside: return false
            case .boundary:
                let left = Point2D(x: -tangent.y, y: tangent.x) * (locEps * 4)
                let probe = op == .subtract ? m + left : m - left
                return b.locate(probe, eps: 0) != .inside
            }
        }
        for (i, ring) in a.rings.enumerated() {
            if hitsA[i].isEmpty {
                guard let s = ring.segments.first else { continue }
                let m = s.point(at: 0.5)
                if keepA(m, unit(s.point(at: 0.501) - s.point(at: 0.499)) ?? Point2D(x: 1, y: 0)) { whole.append(ring.segments) } else { changed = true }
                continue
            }
            for c in chunks(ring.segments, hits: hitsA[i], closed: true, points: points) {
                let (m, tangent) = c.midpoint
                if keepA(m, tangent) { kept.append(c) } else { changed = true }
            }
        }
        // b's edges: subtract adds those inside a's filled part (reversed: they become a's new edge, filled side left);
        // union adds those outside a. Edges on a's outline are covered by a's own chunks.
        func addB(_ m: Point2D) -> Bool {
            let loc = a.locate(m, eps: locEps)
            return op == .subtract ? loc == .inside : loc == .outside
        }
        for (j, ring) in b.rings.enumerated() {
            if hitsB[j].isEmpty {
                guard let s = ring.segments.first, addB(s.point(at: 0.5)) else {
                    if op == .union { changed = true }   // b swallowed by a: still a (successful) union
                    continue
                }
                whole.append(op == .subtract ? ring.segments.reversed().map(\.reversedSegment) : ring.segments)
                changed = true
                continue
            }
            for c in chunks(ring.segments, hits: hitsB[j], closed: true, points: points) where addB(c.midpoint.point) {
                kept.append(op == .subtract ? c.reversed : c)
                changed = true
            }
            if op == .union { changed = true }
        }
        guard let loops = trace(kept) else { return nil }
        return (loops + whole, points, changed)
    }

    /// A point strictly inside a closed loop (its polygon), found just beside the middle of one of its segments.
    static func interiorProbe(of loop: [CubicSegment], polygon: [Point2D], eps: Double) -> Point2D? {
        for s in loop {
            let m = s.point(at: 0.5)
            guard let t = unit(s.point(at: 0.501) - s.point(at: 0.499)) ?? unit(s.p3 - s.p0) else { continue }
            let normal = Point2D(x: -t.y, y: t.x)
            for d in [eps * 4, eps * 20, eps * 100] {
                for q in [m + normal * d, m - normal * d] where locate(q, in: polygon, eps: eps) == .inside { return q }
            }
        }
        return nil
    }

    // MARK: Intersections

    struct Hit {
        var segment: Int
        var t: Double
        var id: Int
    }

    /// All meeting points of outlines `a` and `b`, as hits on each (same id = same point) plus the points.
    static func hits(_ a: [CubicSegment], _ b: [CubicSegment], eps: Double) -> (a: [Hit], b: [Hit], points: [Point2D]) {
        var points: [Point2D] = []
        let h = hits(a, b, eps: eps, points: &points)
        return (h.a, h.b, points)
    }

    /// Meeting points of `a` and `b`, adding new points to `points` (shared by several outline pairs, so the same
    /// point gets the same id on every ring).
    static func hits(_ a: [CubicSegment], _ b: [CubicSegment], eps: Double, points: inout [Point2D]) -> (a: [Hit], b: [Hit]) {
        var ha: [Hit] = [], hb: [Hit] = []
        func id(_ p: Point2D) -> Int {
            if let i = points.firstIndex(where: { $0.distance(to: p) <= eps }) { return i }
            points.append(p)
            return points.count - 1
        }
        let boxesB = b.map(controlBox)
        for (i, s) in a.enumerated() {
            let boxA = controlBox(s)
            for (k, r) in b.enumerated() where overlaps(boxA, boxesB[k], eps) {
                for (ta, tb, p) in intersections(s, r, eps: eps) {
                    let n = id(p)
                    ha.append(Hit(segment: i, t: ta, id: n))
                    hb.append(Hit(segment: k, t: tb, id: n))
                }
            }
        }
        return (ha, hb)
    }

    /// Parameter pairs and points where two cubic segments meet (crossings, touches, overlapping ends).
    /// Recursive subdivision until both pieces are flat within `eps`, then exact straight-line tests; the parameter
    /// on a curve is refined to the point nearest the hit.
    static func intersections(_ a: CubicSegment, _ b: CubicSegment, eps: Double) -> [(Double, Double, Point2D)] {
        var out: [(Double, Double, Point2D)] = []
        func recurse(_ x: CubicSegment, _ x0: Double, _ x1: Double, _ y: CubicSegment, _ y0: Double, _ y1: Double, _ depth: Int) {
            guard overlaps(controlBox(x), controlBox(y), eps), out.count < 512 else { return }
            let fx = isFlat(x, eps), fy = isFlat(y, eps)
            if (fx && fy) || depth > 40 {
                for (s, u, p) in lineHits(x.p0, x.p3, y.p0, y.p3, eps: eps) {
                    var ta = x0 + s * (x1 - x0), tb = y0 + u * (y1 - y0)
                    if a.isCurve { ta = refine(a, p, around: ta, span: x1 - x0) }
                    if b.isCurve { tb = refine(b, p, around: tb, span: y1 - y0) }
                    out.append((ta, tb, p))
                }
                return
            }
            if !fx && (fy || extent(x) >= extent(y)) {
                let (l, r) = x.split(at: 0.5), m = (x0 + x1) / 2
                recurse(l, x0, m, y, y0, y1, depth + 1)
                recurse(r, m, x1, y, y0, y1, depth + 1)
            } else {
                let (l, r) = y.split(at: 0.5), m = (y0 + y1) / 2
                recurse(x, x0, x1, l, y0, m, depth + 1)
                recurse(x, x0, x1, r, m, y1, depth + 1)
            }
        }
        recurse(a, 0, 1, b, 0, 1, 0)
        return out
    }

    /// Straight pieces p–q and r–s: proper crossing, plus every end lying on the other piece (touches, collinear overlap).
    static func lineHits(_ p: Point2D, _ q: Point2D, _ r: Point2D, _ s: Point2D, eps: Double) -> [(Double, Double, Point2D)] {
        var out: [(Double, Double, Point2D)] = []
        let d1 = q - p, d2 = s - r
        let l1 = hypot(d1.x, d1.y), l2 = hypot(d2.x, d2.y)
        func param(_ x: Point2D, _ a: Point2D, _ d: Point2D, _ l: Double) -> Double {
            l > 0 ? min(1, max(0, ((x.x - a.x) * d.x + (x.y - a.y) * d.y) / (l * l))) : 0
        }
        let den = d1.x * d2.y - d1.y * d2.x
        if l1 > 0, l2 > 0, abs(den) > 1e-12 * l1 * l2 {
            let w = r - p
            let t = (w.x * d2.y - w.y * d2.x) / den, u = (w.x * d1.y - w.y * d1.x) / den
            let st = eps / l1, su = eps / l2
            if t >= -st, t <= 1 + st, u >= -su, u <= 1 + su {
                let tc = min(1, max(0, t))
                out.append((tc, min(1, max(0, u)), p + d1 * tc))
            }
        }
        for (e, u) in [(r, 0.0), (s, 1.0)] where e.distance(toSegment: p, q) <= eps { out.append((param(e, p, d1, l1), u, e)) }
        for (e, t) in [(p, 0.0), (q, 1.0)] where e.distance(toSegment: r, s) <= eps { out.append((t, param(e, r, d2, l2), e)) }
        return out
    }

    /// Curve parameter near `t` whose point is closest to `p` (bisection-style search within ± span).
    static func refine(_ s: CubicSegment, _ p: Point2D, around t: Double, span: Double) -> Double {
        var best = t, bestD = s.point(at: t).distance(to: p)
        var step = max(span, 1e-6)
        for _ in 0..<40 {
            step /= 2
            for c in [best - step, best + step] where c >= 0 && c <= 1 {
                let d = s.point(at: c).distance(to: p)
                if d < bestD { best = c; bestD = d }
            }
        }
        return best
    }

    static func controlBox(_ s: CubicSegment) -> Rect2D {
        Rect2D(points: s.isCurve ? [s.p0, s.c1, s.c2, s.p3] : [s.p0, s.p3])!
    }

    static func overlaps(_ a: Rect2D, _ b: Rect2D, _ eps: Double) -> Bool {
        a.minX <= b.maxX + eps && a.maxX >= b.minX - eps && a.minY <= b.maxY + eps && a.maxY >= b.minY - eps
    }

    static func isFlat(_ s: CubicSegment, _ eps: Double) -> Bool {
        guard s.isCurve else { return true }
        let tol = eps * 0.25
        return s.c1.distance(toSegment: s.p0, s.p3) <= tol && s.c2.distance(toSegment: s.p0, s.p3) <= tol
    }

    static func extent(_ s: CubicSegment) -> Double {
        let b = controlBox(s)
        return max(b.width, b.height)
    }

    static func isDegenerate(_ s: CubicSegment) -> Bool {
        s.p0.distance(to: s.p3) < 1e-12 && (!s.isCurve || (s.c1.distance(to: s.p0) < 1e-12 && s.c2.distance(to: s.p0) < 1e-12))
    }

    // MARK: Chunks

    struct Chunk {
        var segments: [CubicSegment]
        /// Cut point ids at both ends (nil = the open end of a path).
        var start: Int?
        var end: Int?
        /// Index of the same chunk in the opposite direction (split paths use both directions).
        var twin: Int?

        var reversed: Chunk {
            Chunk(segments: segments.reversed().map(\.reversedSegment), start: end, end: start, twin: nil)
        }

        /// Point halfway along the chunk and the direction there.
        var midpoint: (point: Point2D, tangent: Point2D) {
            let lengths = segments.map(\.approximateLength)
            var target = lengths.reduce(0, +) / 2
            for (k, s) in segments.enumerated() {
                let l = lengths[k]
                if target <= l || k == segments.count - 1 {
                    let t = l > 0 ? min(1, max(0, target / l)) : 0.5
                    let d = s.point(at: min(1, t + 1e-3)) - s.point(at: max(0, t - 1e-3))
                    return (s.point(at: t), ShapeCut.unit(d) ?? ShapeCut.unit(s.p3 - s.p0) ?? Point2D(x: 1, y: 0))
                }
                target -= l
            }
            return (segments.first?.p0 ?? Point2D(x: 0, y: 0), Point2D(x: 1, y: 0))
        }

        var startDirection: Point2D {
            guard let s = segments.first else { return Point2D(x: 1, y: 0) }
            let options = s.isCurve ? [s.c1 - s.p0, s.c2 - s.p0, s.p3 - s.p0] : [s.p3 - s.p0]
            return options.lazy.compactMap(ShapeCut.unit).first ?? Point2D(x: 1, y: 0)
        }

        var endDirection: Point2D {
            guard let s = segments.last else { return Point2D(x: 1, y: 0) }
            let options = s.isCurve ? [s.p3 - s.c2, s.p3 - s.c1, s.p3 - s.p0] : [s.p3 - s.p0]
            return options.lazy.compactMap(ShapeCut.unit).first ?? Point2D(x: 1, y: 0)
        }
    }

    /// Hits sorted along the path; a hit at the end of a segment counts as the start of the next one; one hit per id.
    static func ordered(_ hits: [Hit], count: Int, closed: Bool) -> [Hit] {
        let normalized = hits.map { h -> Hit in
            var h = h
            if h.t >= 1 - 1e-9, closed || h.segment < count - 1 {
                h.segment = (h.segment + 1) % count
                h.t = 0
            } else if h.t <= 1e-9 {
                h.t = 0
            }
            return h
        }.sorted { ($0.segment, $0.t) < ($1.segment, $1.t) }
        var seen = Set<Int>()
        return normalized.filter { seen.insert($0.id).inserted }
    }

    /// Pieces of a path between consecutive hits (closed paths wrap around). `includeEnds`: open paths also get the
    /// piece before the first and after the last hit.
    static func chunks(_ segs: [CubicSegment], hits: [Hit], closed: Bool, points: [Point2D], includeEnds: Bool = false) -> [Chunk] {
        let n = segs.count
        let h = ordered(hits, count: n, closed: closed)
        guard n > 0, !h.isEmpty else { return [] }
        var out: [Chunk] = []
        func add(_ from: (Int, Double), _ to: (Int, Double), _ a: Int?, _ b: Int?) {
            var s = piece(segs, from: from, to: to, closed: closed).filter { !isDegenerate($0) }
            guard !s.isEmpty else { return }
            // Ends exactly on the shared cut points, so both outlines meet in the same coordinates.
            if let a {
                s[0].p0 = points[a]
                if !s[0].isCurve { s[0].c1 = points[a] }
            }
            if let b {
                s[s.count - 1].p3 = points[b]
                if !s[s.count - 1].isCurve { s[s.count - 1].c2 = points[b] }
            }
            out.append(Chunk(segments: s, start: a, end: b))
        }
        if closed {
            for k in h.indices {
                let x = h[k], y = h[(k + 1) % h.count]
                add((x.segment, x.t), (y.segment, y.t), x.id, y.id)
            }
        } else {
            if includeEnds, h[0].segment > 0 || h[0].t > 0 { add((0, 0), (h[0].segment, h[0].t), nil, h[0].id) }
            for k in h.indices.dropLast() {
                add((h[k].segment, h[k].t), (h[k + 1].segment, h[k + 1].t), h[k].id, h[k + 1].id)
            }
            if includeEnds, let l = h.last { add((l.segment, l.t), (n - 1, 1), l.id, nil) }
        }
        return out
    }

    /// Segments from one path position forward to another (closed paths may wrap; equal positions = the whole loop).
    static func piece(_ segs: [CubicSegment], from: (Int, Double), to: (Int, Double), closed: Bool) -> [CubicSegment] {
        let n = segs.count
        let (i0, t0) = from, (i1, t1) = to
        if i0 == i1, t0 < t1 { return [segs[i0].sub(t0, t1)] }
        var out: [CubicSegment] = []
        if t0 < 1 { out.append(segs[i0].sub(t0, 1)) }
        var k = i0 + 1
        var guardCount = 0
        while guardCount <= n {
            guardCount += 1
            if closed { k %= n }
            if k == i1 || k >= n { break }
            out.append(segs[k])
            k += 1
        }
        if t1 > 0, i1 < n { out.append(segs[i1].sub(0, t1)) }
        return out
    }

    // MARK: Tracing

    /// Chain chunks into closed loops by their cut point ids, always taking the leftmost turn (a chunk's own twin only
    /// as a last resort). nil = an open end was found (unresolvable geometry).
    static func trace(_ chunks: [Chunk]) -> [[CubicSegment]]? {
        var used = [Bool](repeating: false, count: chunks.count)
        var loops: [[CubicSegment]] = []
        var byStart: [Int: [Int]] = [:]
        for (i, c) in chunks.enumerated() {
            guard let s = c.start, c.end != nil else { return nil }
            byStart[s, default: []].append(i)
        }
        for s in chunks.indices where !used[s] {
            used[s] = true
            var loop = chunks[s].segments
            var cur = s
            var steps = 0
            while true {
                steps += 1
                guard steps <= chunks.count + 1, let end = chunks[cur].end else { return nil }
                let inDir = chunks[cur].endDirection
                let options = (byStart[end] ?? []).filter { ($0 == s || !used[$0]) && $0 != chunks[cur].twin }
                guard let next = options.max(by: { turn(inDir, chunks[$0].startDirection) < turn(inDir, chunks[$1].startDirection) })
                else { return nil }
                if next == s { break }
                used[next] = true
                loop += chunks[next].segments
                cur = next
            }
            loops.append(loop)
        }
        return loops
    }

    /// Turn angle from direction `a` to direction `b` in (−π, π]; positive = left.
    static func turn(_ a: Point2D, _ b: Point2D) -> Double {
        atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
    }

    // MARK: Helpers

    enum Location { case inside, outside, boundary }

    static func locate(_ p: Point2D, in poly: [Point2D], eps: Double) -> Location {
        guard poly.count >= 3 else { return .outside }
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if eps > 0, p.distance(toSegment: a, b) <= eps { return .boundary }
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside ? .inside : .outside
    }

    static func flatten(_ segs: [CubicSegment], tolerance: Double) -> [Point2D] {
        guard let first = segs.first else { return [] }
        var pts = [first.p0]
        for s in segs {
            guard s.isCurve else { pts.append(s.p3); continue }
            let hull = s.p0.distance(to: s.c1) + s.c1.distance(to: s.c2) + s.c2.distance(to: s.p3)
            let steps = max(4, min(256, Int((hull / max(tolerance, 1e-9)).squareRoot().rounded(.up)) * 2))
            for k in 1...steps { pts.append(s.point(at: Double(k) / Double(steps))) }
        }
        if pts.count > 1, let f = pts.first, let l = pts.last, f.distance(to: l) < 1e-12 { pts.removeLast() }
        return pts
    }

    static func signedArea(_ p: [Point2D]) -> Double {
        guard p.count >= 3 else { return 0 }
        var s = 0.0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    static func unit(_ v: Point2D) -> Point2D? {
        let l = hypot(v.x, v.y)
        return l > 1e-12 ? Point2D(x: v.x / l, y: v.y / l) : nil
    }

    /// Corner nodes the cut added in the middle of a straight edge (the cut only touched there): removed again.
    /// Nodes of the original outline are always kept.
    static func removingStraightCutNodes(_ nodes: [BezierNode], cutPoints: [Point2D], original: [BezierNode], eps: Double) -> [BezierNode] {
        var n = nodes
        var i = 0
        while i < n.count, n.count > 3 {
            let a = n[(i - 1 + n.count) % n.count], b = n[i], c = n[(i + 1) % n.count]
            let straight = a.outHandle == nil && b.inHandle == nil && b.outHandle == nil && c.inHandle == nil
            if straight, b.point.distance(toSegment: a.point, c.point) <= eps * 0.5,
               cutPoints.contains(where: { $0.distance(to: b.point) <= eps }),
               !original.contains(where: { $0.point.distance(to: b.point) <= eps }) {
                n.remove(at: i)
            } else {
                i += 1
            }
        }
        return n
    }
}

extension CubicSegment {
    /// The same segment run backwards.
    var reversedSegment: CubicSegment { CubicSegment(p0: p3, c1: c2, c2: c1, p3: p0, isCurve: isCurve) }
}
