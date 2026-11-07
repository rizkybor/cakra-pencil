import Foundation

// MARK: - Follow object (OCAD "Follow" / cursor guide)

/// Position along an object's outline: segment number `segment`, parameter `t` (0…1) within that segment.
public struct PathPosition: Hashable, Sendable {
    public var segment: Int
    public var t: Double

    public init(segment: Int, t: Double) {
        self.segment = segment
        self.t = t
    }

    /// Order along the path (for comparing two positions).
    public var order: Double { Double(segment) + t }
}

extension CubicSegment {
    /// Curve piece between t0 and t1 (de Casteljau). Straight segments stay straight.
    public func sub(_ t0: Double, _ t1: Double) -> CubicSegment {
        if !isCurve {
            return CubicSegment(p0: point(at: t0), c1: point(at: t0), c2: point(at: t1), p3: point(at: t1), isCurve: false)
        }
        // Part [t0, 1], then its initial part up to (t1 - t0) / (1 - t0).
        let right = t0 <= 0 ? self : split(at: t0).1
        let u = t0 >= 1 ? 0 : (t1 - t0) / (1 - t0)
        return u >= 1 ? right : right.split(at: u).0
    }

    /// Split at t into two curves.
    public func split(at t: Double) -> (CubicSegment, CubicSegment) {
        func lerp(_ a: Point2D, _ b: Point2D) -> Point2D { Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        let a = lerp(p0, c1), b = lerp(c1, c2), c = lerp(c2, p3)
        let d = lerp(a, b), e = lerp(b, c)
        let m = lerp(d, e)
        return (CubicSegment(p0: p0, c1: a, c2: d, p3: m, isCurve: isCurve),
                CubicSegment(p0: m, c1: e, c2: c, p3: p3, isCurve: isCurve))
    }

    /// Nearest point on the segment: (t, point, distance).
    public func nearest(to p: Point2D) -> (t: Double, point: Point2D, distance: Double) {
        if !isCurve {
            let d = p3 - p0
            let len2 = d.x * d.x + d.y * d.y
            let t = len2 > 0 ? min(1, max(0, ((p.x - p0.x) * d.x + (p.y - p0.y) * d.y) / len2)) : 0
            let q = point(at: t)
            return (t, q, q.distance(to: p))
        }
        // Coarse sampling, then refine around the best sample.
        var best = (t: 0.0, point: p0, distance: p0.distance(to: p))
        let n = 32
        for k in 0...n {
            let t = Double(k) / Double(n), q = point(at: t), d = q.distance(to: p)
            if d < best.distance { best = (t, q, d) }
        }
        var step = 1.0 / Double(n)
        for _ in 0..<12 {
            step /= 2
            for t in [best.t - step, best.t + step] where t >= 0 && t <= 1 {
                let q = point(at: t), d = q.distance(to: p)
                if d < best.distance { best = (t, q, d) }
            }
        }
        return best
    }

    /// Approximate length (16-step polyline).
    var approximateLength: Double {
        guard isCurve else { return p0.distance(to: p3) }
        var len = 0.0, prev = p0
        for k in 1...16 {
            let q = point(at: Double(k) / 16)
            len += prev.distance(to: q)
            prev = q
        }
        return len
    }
}

extension Feature {
    /// Nearest point on the object's outline (line or area).
    public func nearestPathPosition(to p: Point2D) -> (position: PathPosition, point: Point2D, distance: Double)? {
        guard kind != .point else { return nil }
        var best: (PathPosition, Point2D, Double)?
        for (i, s) in segments.enumerated() {
            let r = s.nearest(to: p)
            if r.distance < (best?.2 ?? .infinity) { best = (PathPosition(segment: i, t: r.t), r.point, r.distance) }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }

    /// Position of the i-th node on the path.
    public func pathPosition(ofNode i: Int) -> PathPosition {
        let count = segments.count
        if !isClosed, i >= count { return PathPosition(segment: max(count - 1, 0), t: 1) }
        return PathPosition(segment: i % max(count, 1), t: 0)
    }

    public func point(at pos: PathPosition) -> Point2D? {
        let segs = segments
        guard segs.indices.contains(pos.segment) else { return nodes.first?.point }
        return segs[pos.segment].point(at: pos.t)
    }

    /// Path piece from `a` to `b`, moving forward in the object's node order (areas: may wrap past the start point).
    private func forwardSegments(from a: PathPosition, to b: PathPosition) -> [CubicSegment] {
        let segs = segments
        guard !segs.isEmpty else { return [] }
        let n = segs.count
        if a.segment == b.segment, a.t <= b.t {
            return b.t - a.t > 1e-9 ? [segs[a.segment].sub(a.t, b.t)] : []
        }
        var out: [CubicSegment] = []
        if a.t < 1 { out.append(segs[a.segment].sub(a.t, 1)) }
        var k = (a.segment + 1) % n
        var guardCount = 0
        while k != b.segment, guardCount < n {
            out.append(segs[k])
            k = (k + 1) % n
            guardCount += 1
        }
        if b.t > 0 { out.append(segs[b.segment].sub(0, b.t)) }
        return out
    }

    /// Object shape between two positions, as bezier nodes from `a` to `b` (both inclusive).
    /// Lines: direction follows the position order. Areas / closed lines: via the shorter side.
    /// `via`: a point the stroke passes through (areas: pick the side closer to this point, not the shortest).
    public func followNodes(from a: PathPosition, to b: PathPosition, via: Point2D? = nil) -> [BezierNode] {
        var segs: [CubicSegment]
        // Closed lines (end = start point) are treated like areas: may wrap past the start point.
        if isClosed || isRingLine {
            let fwd = forwardSegments(from: a, to: b)
            let back = Self.reversed(forwardSegments(from: b, to: a))
            if let via {
                func gap(_ s: [CubicSegment]) -> Double { s.map { $0.nearest(to: via).distance }.min() ?? .infinity }
                segs = gap(fwd) <= gap(back) ? fwd : back
            } else {
                let lf = fwd.reduce(0) { $0 + $1.approximateLength }, lb = back.reduce(0) { $0 + $1.approximateLength }
                segs = lf <= lb ? fwd : back
            }
        } else if a.order <= b.order {
            segs = forwardSegments(from: a, to: b)
        } else {
            segs = Self.reversed(forwardSegments(from: b, to: a))
        }
        return Self.nodes(from: segs)
    }

    /// Path piece forward from `a` to `b` in the object's node order (areas: wrapping past the start point if needed).
    public func forwardNodes(from a: PathPosition, to b: PathPosition) -> [BezierNode] {
        Self.nodes(from: forwardSegments(from: a, to: b))
    }

    static func nodes(from segments: [CubicSegment]) -> [BezierNode] {
        let segs = segments.filter { !($0.p0.distance(to: $0.p3) < 1e-9 && !$0.isCurve) }
        guard let first = segs.first else { return [] }
        var nodes = [BezierNode(point: first.p0)]
        for s in segs {
            if s.isCurve { nodes[nodes.count - 1].outHandle = s.c1 }
            nodes.append(BezierNode(point: s.p3, inHandle: s.isCurve ? s.c2 : nil))
        }
        return nodes
    }

    private static func reversed(_ segs: [CubicSegment]) -> [CubicSegment] {
        segs.reversed().map { CubicSegment(p0: $0.p3, c1: $0.c2, c2: $0.c1, p3: $0.p0, isCurve: $0.isCurve) }
    }
}

// MARK: - Strokes that follow objects

/// Freehand drawing along existing objects: a part of the stroke that hugs one object (within `radius`)
/// for at least 2 × radius is replaced by that object's exact shape; the rest is smoothed as usual.
public enum GuideTrace {
    public static func trace(_ points: [Point2D], guides: [Feature], radius: Double, simplifyTolerance: Double) -> [BezierNode] {
        guard points.count >= 2 else { return points.map { BezierNode(point: $0) } }
        let candidates = guides.filter { $0.kind != .point }
        // Nearest guide object per stroke point.
        let hits: [(Int, PathPosition, Point2D)?] = points.map { p in
            var best: (Int, PathPosition, Point2D, Double)?
            for (k, f) in candidates.enumerated() {
                guard let b = f.bounds, p.x >= b.minX - radius, p.x <= b.maxX + radius,
                      p.y >= b.minY - radius, p.y <= b.maxY + radius,
                      let r = f.nearestPathPosition(to: p), r.distance <= radius,
                      r.distance < (best?.3 ?? .infinity) else { continue }
                best = (k, r.position, r.point, r.distance)
            }
            return best.map { ($0.0, $0.1, $0.2) }
        }
        var out: [BezierNode] = []
        var free: [Point2D] = []
        func flush() {
            guard !free.isEmpty else { return }
            let simple = free.count > 2 ? ContourGenerator.simplify(free, tolerance: simplifyTolerance) : free
            for p in simple where out.last.map({ $0.point.distance(to: p) > 1e-9 }) ?? true { out.append(BezierNode(point: p)) }
            free = []
        }
        var i = 0
        while i < points.count {
            guard let h = hits[i] else { free.append(points[i]); i += 1; continue }
            var j = i
            while j + 1 < points.count, let n = hits[j + 1], n.0 == h.0 { j += 1 }
            var length = 0.0
            if j > i { for k in i..<j { length += points[k].distance(to: points[k + 1]) } }
            if length >= radius * 2, let last = hits[j] {
                flush()
                let via = points[(i + j) / 2]
                let follow = candidates[h.0].followNodes(from: h.1, to: last.1, via: via)
                for n in follow {
                    if let l = out.last, l.point.distance(to: n.point) <= 1e-9 {
                        out[out.count - 1].outHandle = n.outHandle
                    } else {
                        out.append(n)
                    }
                }
            } else {
                free.append(contentsOf: points[i...j])
            }
            i = j + 1
        }
        flush()
        return out
    }
}
