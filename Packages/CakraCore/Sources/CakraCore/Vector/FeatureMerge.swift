import Foundation

// MARK: - Merge objects (OCAD "Merge" / OOM "Unify areas" + "Connect paths")

/// Result of merging two objects.
public struct MergeResult: Hashable, Sendable {
    public var feature: Feature
    /// Areas merged via polygons (fallback when the exact outlines can't be resolved): bezier curves became straight points.
    public var flattenedCurves: Bool
    /// The merged areas enclose a new hole (e.g. a ring of areas); it is kept as a hole of the result.
    public var formedHole: Bool
}

extension BezierNode {
    /// The same node with direction reversed (in ↔ out handles).
    public var reversed: BezierNode { BezierNode(point: point, inHandle: outHandle, outHandle: inHandle) }
}

extension Feature {
    /// Mergeable: same kind (line–line or area–area) and same symbol; objects without a symbol
    /// match if their colors are equal.
    public func canMerge(with o: Feature) -> Bool {
        guard id != o.id, kind == o.kind, kind != .point else { return false }
        if let a = symbolCode { return a == o.symbolCode }
        return o.symbolCode == nil && colorHex.lowercased() == o.colorHex.lowercased()
    }

    /// Node order reversed (same shape).
    public var reversedNodes: [BezierNode] { nodes.reversed().map(\.reversed) }

    // MARK: Lines

    /// Shortest distance between the endpoints of two lines (m).
    public func endpointGap(to o: Feature) -> Double {
        guard kind == .line, o.kind == .line, let a0 = nodes.first, let a1 = nodes.last,
              let b0 = o.nodes.first, let b1 = o.nodes.last else { return .infinity }
        return [a0.point.distance(to: b0.point), a0.point.distance(to: b1.point),
                a1.point.distance(to: b0.point), a1.point.distance(to: b1.point)].min()!
    }

    /// Join two lines at the nearest pair of endpoints (≤ `tolerance` m). Endpoints that are apart meet at
    /// their midpoint; curve handles at the joint are kept. The result uses the identity and style of `self`.
    public func joiningLine(_ o: Feature, tolerance: Double) -> Feature? {
        guard canMerge(with: o), kind == .line, nodes.count >= 2, o.nodes.count >= 2 else { return nil }
        let a0 = nodes.first!.point, a1 = nodes.last!.point, b0 = o.nodes.first!.point, b1 = o.nodes.last!.point
        // (distance, front part, back part): the front's end meets the back's start.
        // (distance, front part, back part, self's end at the joint = end?, o's end = end?)
        let options: [(Double, [BezierNode], [BezierNode], Bool, Bool)] = [
            (a1.distance(to: b0), nodes, o.nodes, true, false),
            (a1.distance(to: b1), nodes, o.reversedNodes, true, true),
            (a0.distance(to: b0), reversedNodes, o.nodes, false, false),
            (a0.distance(to: b1), o.nodes, nodes, false, true),
        ]
        guard let best = options.min(by: { $0.0 < $1.0 }), best.0 <= tolerance else { return nil }
        // Lines that overlap at the joint (e.g. drawn following this line and ending at its endpoint) are not
        // joined: the result would fold back over itself.
        // Stays small even with a loose joint gap: only lines that truly overlap (from follow object).
        let overlap = 0.05
        if let s = best.3 ? segments.last : segments.first, let d = o.nearestPathPosition(to: s.point(at: 0.5))?.distance, d <= overlap {
            return nil
        }
        if let s = best.4 ? o.segments.last : o.segments.first, let d = nearestPathPosition(to: s.point(at: 0.5))?.distance, d <= overlap {
            return nil
        }
        var head = best.1, tail = best.2
        let end = head.removeLast(), start = tail.removeFirst()
        let meet = Point2D(x: (end.point.x + start.point.x) / 2, y: (end.point.y + start.point.y) / 2)
        let joint = BezierNode(point: meet, inHandle: end.inHandle.map { $0 + (meet - end.point) },
                               outHandle: start.outHandle.map { $0 + (meet - start.point) })
        var f = self
        f.nodes = head + [joint] + tail
        return f
    }

    // MARK: Areas

    /// Unite two areas. Adjoining areas (sharing a side via snapped points) are joined without
    /// changing their curves; overlapping areas are united via polygons. nil = not touching.
    /// `vertexTolerance`: distance at which points count as equal (m); `flattenTolerance`: curve flattening precision (m).
    /// Holes of both areas are kept; a union that encloses a gap (a ring of areas) gets that gap as a new hole.
    public func unitingArea(_ o: Feature, vertexTolerance: Double, flattenTolerance: Double,
                            allowOverlap: Bool = true) -> MergeResult? {
        guard canMerge(with: o), kind == .area, nodes.count >= 3, o.nodes.count >= 3 else { return nil }
        let holesBefore = holeRings.count + o.holeRings.count
        func result(_ f: Feature, flattened: Bool) -> MergeResult {
            MergeResult(feature: f, flattenedCurves: flattened, formedHole: f.holeRings.count > holesBefore)
        }
        if let f = stitchingArea(o, tolerance: vertexTolerance) { return result(f.keepingHoles(of: self, o), flattened: false) }
        // T-junction: a corner of one area falls in the middle of a side of the other (e.g. drawn snapping to that side).
        // Insert a node on that side (shape unchanged) so coincident sides have the same nodes in both areas.
        let a2 = insertingVertices(of: o, tolerance: vertexTolerance)
        let b2 = o.insertingVertices(of: self, tolerance: vertexTolerance)
        if a2.nodes.count != nodes.count || b2.nodes.count != o.nodes.count,
           let f = a2.stitchingArea(b2, tolerance: vertexTolerance) {
            return result(f.keepingHoles(of: self, o), flattened: false)
        }
        // Snapped along several separate sides (the two areas close a ring around a gap): merged automatically too.
        let ringOfSides = sharedSideChains(with: o, tolerance: vertexTolerance) > 1
            || a2.sharedSideChains(with: b2, tolerance: vertexTolerance) > 1
        guard allowOverlap || ringOfSides, let ba = bounds, let bb = o.bounds,
              ba.insetBy(-vertexTolerance).intersects(bb) else { return nil }
        // Exact union on the bezier outlines (curves kept, holes resolved).
        if let a = ShapeCut.Region(self, eps: vertexTolerance), let b = ShapeCut.Region(o, eps: vertexTolerance),
           let u = ShapeCut.combine(a, b, op: .union, eps: vertexTolerance) {
            guard case let .success(list) = pieces(from: u.loops, region: a, cutPoints: u.points, eps: vertexTolerance) else { return nil }
            return list.count == 1 ? result(list[0], flattened: false) : nil   // more than one piece: not touching
        }
        guard allowOverlap else { return nil }
        // Fallback: polygon union of the flattened outlines (outer rings only, holes of the inputs are re-added).
        let pa = PolygonUnion.ring(flattened(tolerance: flattenTolerance))
        let pb = PolygonUnion.ring(o.flattened(tolerance: flattenTolerance))
        guard let u = PolygonUnion.union(pa, pb, eps: max(vertexTolerance, 1e-6)) else { return nil }
        var f = self
        f.nodes = u.outer.map { BezierNode(point: $0) }
        f.holes = u.holes.map { $0.map { BezierNode(point: $0) } }
        f = f.keepingHoles(of: self, o, replacing: false)
        f.rotationDeg = rotationDeg
        let curved = nodes.contains(where: \.isSmooth) || o.nodes.contains(where: \.isSmooth)
        return result(f, flattened: curved)
    }

    /// This merged outline with the holes of the merged areas `a` and `b` (plus its own when `replacing` is false).
    private func keepingHoles(of a: Feature, _ b: Feature, replacing: Bool = true) -> Feature {
        var f = self
        let own = replacing ? [] : holeRings
        let all = own + a.holeRings + b.holeRings
        f.holes = all.isEmpty ? nil : all
        f.normalizeHoles()
        return f
    }

    /// Copy with an extra node wherever a corner of `o` lies exactly on a side of this object (not on its nodes).
    func insertingVertices(of o: Feature, tolerance: Double) -> Feature {
        var f = self
        for v in o.nodes {
            guard !f.nodes.contains(where: { $0.point.distance(to: v.point) <= tolerance }),
                  let r = f.nearestPathPosition(to: v.point), r.distance <= tolerance,
                  let i = f.insertNode(at: r.position) else { continue }
            f.nodes[i] = f.nodes[i].moved(by: v.point - f.nodes[i].point)   // exactly at o's corner
        }
        return f
    }

    /// Number of separate chains of shared sides (snapped points) between the outer rings of two areas.
    func sharedSideChains(with o: Feature, tolerance: Double) -> Int {
        let (_, n, shared) = sharedSides(with: o, tolerance: tolerance)
        let edges = (0..<n).filter(shared)
        guard edges.count < n else { return 1 }
        return edges.filter { !shared(($0 - 1 + n) % n) }.count
    }

    /// Outer rings normalized counterclockwise; for each node of this area the matching node of `o`, and whether
    /// side i → i+1 is also a side of `o` (run the other way).
    private func sharedSides(with o: Feature, tolerance: Double) -> (match: [Int?], count: Int, shared: (Int) -> Bool) {
        let a = signedArea >= 0 ? nodes : reversedNodes
        let b = o.signedArea >= 0 ? o.nodes : o.reversedNodes
        let n = a.count, m = b.count
        var match = [Int?](repeating: nil, count: n)
        for i in 0..<n {
            var best: (Int, Double)?
            for k in 0..<m {
                let d = a[i].point.distance(to: b[k].point)
                if d <= tolerance, d < (best?.1 ?? .infinity) { best = (k, d) }
            }
            match[i] = best?.0
        }
        return (match, n, { i in
            guard let p = match[i], let q = match[(i + 1) % n] else { return false }
            return q == (p - 1 + m) % m
        })
    }

    /// Areas sharing a chain of consecutive nodes (at least one side): the shared chain is dropped, the rest joined.
    func stitchingArea(_ o: Feature, tolerance: Double) -> Feature? {
        // Normalize orientation (counterclockwise) so the shared chain runs in opposite directions in the two areas.
        let a = signedArea >= 0 ? nodes : reversedNodes
        let b = o.signedArea >= 0 ? o.nodes : o.reversedNodes
        let n = a.count, m = b.count
        var match = [Int?](repeating: nil, count: n)
        for i in 0..<n {
            var best: (Int, Double)?
            for k in 0..<m {
                let d = a[i].point.distance(to: b[k].point)
                if d <= tolerance, d < (best?.1 ?? .infinity) { best = (k, d) }
            }
            match[i] = best?.0
        }
        /// Side a[i]→a[i+1] is also a side of b (reversed).
        func shared(_ i: Int) -> Bool {
            guard let p = match[i], let q = match[(i + 1) % n] else { return false }
            return q == (p - 1 + m) % m
        }
        let edges = (0..<n).filter(shared)
        guard !edges.isEmpty, edges.count < n else { return nil }
        // Exactly one consecutive chain; more than one = there would be a hole → use the polygon path.
        let starts = edges.filter { !shared(($0 - 1 + n) % n) }
        guard starts.count == 1, let s = starts.first else { return nil }
        var e = s
        while shared((e + 1) % n) { e = (e + 1) % n }
        let i = s, j = (e + 1) % n            // chain a[i] … a[j]
        guard let bi = match[i], let bj = match[j] else { return nil }
        // Part of a outside the chain: a[j] … a[i]; then part of b outside the chain: b[bi+1] … b[bj-1].
        var out: [BezierNode] = []
        var k = j
        while true {
            out.append(a[k])
            if k == i { break }
            k = (k + 1) % n
        }
        out[0].inHandle = b[bj].inHandle.map { $0 + (a[j].point - b[bj].point) }
        out[out.count - 1].outHandle = b[bi].outHandle.map { $0 + (a[i].point - b[bi].point) }
        k = (bi + 1) % m
        while k != bj {
            out.append(b[k])
            k = (k + 1) % m
        }
        guard out.count >= 3 else { return nil }
        var f = self
        f.nodes = out
        return f
    }

    /// Signed area from its points (positive = counterclockwise, y north).
    public var signedArea: Double {
        let p = nodes.map(\.point)
        guard p.count >= 3 else { return 0 }
        var s = 0.0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }
}

// MARK: - Simple polygon union

/// Union of two simple polygons by edge classification: all edges are split at intersections, edges that
/// lie outside the other polygon (or shared edges in the same direction) are kept, then chained into rings.
/// Robust to coincident points/edges (the snapped-area case), which often makes other algorithms fail.
enum PolygonUnion {
    /// Ring without duplicate points, counterclockwise.
    static func ring(_ pts: [Point2D]) -> [Point2D] {
        var r: [Point2D] = []
        for p in pts where r.last.map({ $0.distance(to: p) > 1e-9 }) ?? true { r.append(p) }
        if let f = r.first, let l = r.last, r.count > 1, f.distance(to: l) <= 1e-9 { r.removeLast() }
        return area(r) >= 0 ? r : r.reversed()
    }

    static func area(_ p: [Point2D]) -> Double {
        guard p.count >= 3 else { return 0 }
        var s = 0.0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    /// nil if the two do not touch (result has more than one part).
    static func union(_ a: [Point2D], _ b: [Point2D], eps: Double) -> (outer: [Point2D], holes: [[Point2D]])? {
        guard a.count >= 3, b.count >= 3 else { return nil }
        let sa = split(a, by: b, eps: eps), sb = split(b, by: a, eps: eps)
        var kept: [(Point2D, Point2D)] = []
        for (p, q) in sa {
            let mid = Point2D(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            switch locate(mid, in: b, eps: eps) {
            case .outside: kept.append((p, q))
            case .inside: break
            case .boundary:
                // Shared edge: keep once if same direction (part of the outer boundary); opposite = interior edge.
                if sb.contains(where: { $0.0.distance(to: p) <= eps && $0.1.distance(to: q) <= eps }) { kept.append((p, q)) }
            }
        }
        for (p, q) in sb {
            let mid = Point2D(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            if case .outside = locate(mid, in: a, eps: eps) { kept.append((p, q)) }
        }
        let rings = trace(kept, eps: eps)
        let outers = rings.filter { area($0) > 0 }
        // Not touching at all = two outer rings; touching at a single point is also rejected.
        guard outers.count == 1, let outer = outers.first else { return nil }
        let holes = rings.filter { area($0) < -eps * eps }.map { simplify($0, eps: eps) }
        return (simplify(outer, eps: eps), holes)
    }

    private enum Location { case inside, outside, boundary }

    private static func locate(_ p: Point2D, in poly: [Point2D], eps: Double) -> Location {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if p.distance(toSegment: a, b) <= eps { return .boundary }
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside ? .inside : .outside
    }

    /// Split the edges of `poly` at every intersection and at every point of `other` lying on them.
    private static func split(_ poly: [Point2D], by other: [Point2D], eps: Double) -> [(Point2D, Point2D)] {
        var out: [(Point2D, Point2D)] = []
        for i in 0..<poly.count {
            let p = poly[i], q = poly[(i + 1) % poly.count]
            let d = q - p
            let len2 = d.x * d.x + d.y * d.y
            guard len2 > 0 else { continue }
            var cuts: [(Double, Point2D)] = []
            for k in 0..<other.count {
                let r = other[k], s = other[(k + 1) % other.count]
                if r.distance(toSegment: p, q) <= eps { cuts.append((param(r, p, d, len2), r)) }
                if let x = intersection(p, q, r, s) { cuts.append((param(x, p, d, len2), x)) }
            }
            var pts = [p]
            for (_, c) in cuts.filter({ $0.0 > 0 && $0.0 < 1 }).sorted(by: { $0.0 < $1.0 })
            where c.distance(to: pts.last!) > eps && c.distance(to: q) > eps {
                pts.append(c)
            }
            pts.append(q)
            for (u, v) in zip(pts, pts.dropFirst()) { out.append((u, v)) }
        }
        return out
    }

    private static func param(_ x: Point2D, _ p: Point2D, _ d: Point2D, _ len2: Double) -> Double {
        ((x.x - p.x) * d.x + (x.y - p.y) * d.y) / len2
    }

    /// Intersection of two non-parallel segments (inside both).
    private static func intersection(_ p: Point2D, _ q: Point2D, _ r: Point2D, _ s: Point2D) -> Point2D? {
        let d1 = q - p, d2 = s - r
        let den = d1.x * d2.y - d1.y * d2.x
        guard abs(den) > 1e-12 * max(1, hypot(d1.x, d1.y) * hypot(d2.x, d2.y)) else { return nil }
        let w = r - p
        let t = (w.x * d2.y - w.y * d2.x) / den
        let u = (w.x * d1.y - w.y * d1.x) / den
        guard t > 0, t < 1, u >= 0, u <= 1 else { return nil }
        return Point2D(x: p.x + t * d1.x, y: p.y + t * d1.y)
    }

    /// Chain directed edges into rings. At branching points, take the rightmost turn.
    private static func trace(_ edges: [(Point2D, Point2D)], eps: Double) -> [[Point2D]] {
        var used = [Bool](repeating: false, count: edges.count)
        var rings: [[Point2D]] = []
        for s in edges.indices where !used[s] {
            var ring: [Point2D] = []
            var cur = s
            var guardCount = 0
            while !used[cur], guardCount <= edges.count {
                guardCount += 1
                used[cur] = true
                let (p, q) = edges[cur]
                ring.append(p)
                if q.distance(to: edges[s].0) <= eps { break }
                let inDir = atan2(q.y - p.y, q.x - p.x)
                let next = edges.indices.filter { !used[$0] && edges[$0].0.distance(to: q) <= eps }
                    .min { turn(inDir, edges[$0]) < turn(inDir, edges[$1]) }
                guard let next else { ring = []; break }
                cur = next
            }
            if ring.count >= 3 { rings.append(ring) }
        }
        return rings
    }

    /// Left-turn angle (0…2π) from the incoming direction; small value = right turn.
    private static func turn(_ inDir: Double, _ e: (Point2D, Point2D)) -> Double {
        let out = atan2(e.1.y - e.0.y, e.1.x - e.0.x)
        var a = out - inDir + .pi   // 0 = U-turn
        while a <= 0 { a += 2 * .pi }
        while a > 2 * .pi { a -= 2 * .pi }
        return a
    }

    /// Remove points collinear with their neighbors (leftovers from edge splitting).
    private static func simplify(_ r: [Point2D], eps: Double) -> [Point2D] {
        var pts = r
        var changed = true
        while changed, pts.count > 3 {
            changed = false
            for i in pts.indices {
                let a = pts[(i - 1 + pts.count) % pts.count], b = pts[i], c = pts[(i + 1) % pts.count]
                if b.distance(toSegment: a, c) <= eps * 0.5 {
                    pts.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return pts
    }
}

// MARK: - Fill line with area (OCAD "Fill / make border")

extension Feature {
    /// Lines that can be filled with an area: at least 3 nodes.
    public var canFillWithArea: Bool { kind == .line && nodes.count >= 3 }

    /// Line endpoints meet (closed line) within `tolerance` m.
    public func isClosedLine(tolerance: Double) -> Bool {
        guard kind == .line, let a = nodes.first, let b = nodes.last, nodes.count >= 3 else { return false }
        return a.point.distance(to: b.point) <= tolerance
    }

    /// New area object with this line's shape and area symbol `s`; the line itself is unchanged.
    /// An end node coinciding with the start node is merged (the area closes itself); open lines are closed straight.
    public func filledArea(with s: MapSymbol, closeTolerance: Double) -> Feature? {
        guard canFillWithArea, s.kind == .area else { return nil }
        var pts = nodes
        if isClosedLine(tolerance: closeTolerance), let last = pts.popLast() {
            pts[0].inHandle = last.inHandle.map { $0 + (pts[0].point - last.point) }
        }
        guard pts.count >= 3 else { return nil }
        var f = Feature(kind: .line, colorHex: s.colorHex, widthMM: s.drawingWidthMM, nodes: pts)
        guard f.switchSymbol(to: s) else { return nil }
        f.name = ""
        return f
    }
}
