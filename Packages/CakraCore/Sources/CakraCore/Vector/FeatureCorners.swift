import Foundation

// MARK: - Corner Tool (Affinity Designer "Corner Tool"): round sharp corners selectively

/// How a corner is cut off: a circular arc (Rounded) or a straight line between the two tangent points (Straight).
public enum CornerStyle: String, CaseIterable, Sendable {
    case rounded, straight
}

/// The sharp corner at one node: where its two edges leave it and how much room there is to round it.
///
/// Directions are the curve tangents at the node (the handle direction on a curved edge), so a corner between curves
/// is measured where the curves meet the node.
public struct CornerGeometry: Hashable, Sendable {
    /// The (sharp) corner point.
    public var point: Point2D
    /// Unit direction from the corner back along the incoming edge.
    public var towardPrevious: Point2D
    /// Unit direction from the corner along the outgoing edge.
    public var towardNext: Point2D
    /// Interior angle θ between the two edges (radians, 0 < θ < π).
    public var interiorAngle: Double
    /// Largest tangent distance: half of the shorter neighbouring edge, so two roundings on one edge never overlap.
    public var maxTangentDistance: Double

    /// Unit vector into the corner (between the two edges): the arc centre lies on it.
    public var bisector: Point2D {
        let s = towardPrevious + towardNext
        let l = hypot(s.x, s.y)
        return l > 1e-12 ? s * (1 / l) : Point2D(x: 0, y: 0)
    }

    /// Distance from the corner to each tangent point for radius `r`: d = r / tan(θ/2), clamped to `maxTangentDistance`.
    public func tangentDistance(radius r: Double) -> Double {
        guard r > 0 else { return 0 }
        return min(r / tan(interiorAngle / 2), maxTangentDistance)
    }

    /// Radius actually drawn for a requested radius (smaller when the edges are too short for it).
    public func effectiveRadius(_ r: Double) -> Double { tangentDistance(radius: r) * tan(interiorAngle / 2) }

    /// Largest radius that fits this corner.
    public var maxRadius: Double { maxTangentDistance * tan(interiorAngle / 2) }
}

extension Feature {
    /// The sharp corner at Node Tool index `i` (outer ring first, then holes; see `allNodes`), or nil when the node
    /// can't be rounded: a point object, an end point of an open line, a node whose edges continue straight on
    /// (collinear or smooth, turning less than 0.5°), or a node next to a zero-length edge.
    public func corner(at i: Int) -> CornerGeometry? {
        guard kind != .point, let (ring, local) = ringLocation(ofNode: i) else { return nil }
        return ringFeature(ring).ringCorner(at: local)
    }

    /// Node Tool indices of every node that can be rounded.
    public var roundableCornerIndices: [Int] { allNodes.indices.filter { corner(at: $0) != nil } }

    /// Round the nodes `indices` (Node Tool indices, holes included) with radius `radius` metres on the ground.
    public func roundingCorners(_ indices: Set<Int>, radius: Double, style: CornerStyle = .rounded) -> Feature {
        roundingCorners(radii: Dictionary(uniqueKeysWithValues: indices.map { ($0, radius) }), style: style)
    }

    /// Round each node in `radii` (Node Tool index → radius in metres) and return the new object (same id, symbol,
    /// style; holes stay holes).
    ///
    /// A rounded node is replaced by two nodes on its edges at the tangent distance d = r / tan(θ/2) (θ = interior
    /// angle), clamped to half of the shorter edge so neighbouring roundings never overlap. The two nodes get handles
    /// of length 4/3 · tan(φ/4) · r (φ = π − θ, the turned angle), the standard cubic approximation of a circular arc.
    /// A curved edge is measured along the curve and split there (de Casteljau); the arc then starts in the curve's
    /// direction at the split point, so the join stays smooth (the arc is a close approximation of a circle there).
    /// End points of open lines, straight-through nodes and radius ≤ 0 are left unchanged.
    public func roundingCorners(radii: [Int: Double], style: CornerStyle = .rounded) -> Feature {
        guard kind != .point else { return self }
        var perRing: [Int: [Int: Double]] = [:]
        for (i, r) in radii where r > 0 {
            guard let (ring, local) = ringLocation(ofNode: i) else { continue }
            perRing[ring, default: [:]][local] = r
        }
        guard !perRing.isEmpty else { return self }
        var out = self
        for (ring, local) in perRing {
            out.setRing(ring, ringFeature(ring).roundedRingNodes(radii: local, style: style))
        }
        return out
    }

    // MARK: One ring

    /// Corner of node `i` of this object's own `nodes` (one ring, holes ignored).
    private func ringCorner(at i: Int) -> CornerGeometry? {
        let n = nodes.count
        guard nodes.indices.contains(i), n >= 3 else { return nil }
        if !isClosed, i == 0 || i == n - 1 { return nil }
        let segs = segments
        let inSeg = segs[(i - 1 + segs.count) % segs.count], outSeg = segs[i % segs.count]
        guard let u = Self.unit(Self.endTangentBackward(inSeg)), let v = Self.unit(Self.startTangent(outSeg)) else { return nil }
        let dot = max(-1, min(1, u.x * v.x + u.y * v.y))
        let theta = acos(dot)
        // Turned angle below 0.5°: the edges continue straight on (collinear or a smooth node).
        guard Double.pi - theta > 0.5 * .pi / 180, theta > 1e-6 else { return nil }
        let lin = Self.arcLength(inSeg), lout = Self.arcLength(outSeg)
        guard lin > 1e-9, lout > 1e-9 else { return nil }
        return CornerGeometry(point: nodes[i].point, towardPrevious: u, towardNext: v, interiorAngle: theta,
                              maxTangentDistance: min(lin, lout) / 2)
    }

    private func roundedRingNodes(radii: [Int: Double], style: CornerStyle) -> [BezierNode] {
        let n = nodes.count
        let segs = segments
        guard n >= 3, !segs.isEmpty else { return nodes }
        // Tangent distance and corner per rounded node.
        var trim: [Int: (d: Double, corner: CornerGeometry)] = [:]
        for (i, r) in radii {
            guard let c = ringCorner(at: i) else { continue }
            let d = c.tangentDistance(radius: r)
            if d > 1e-9 { trim[i] = (d, c) }
        }
        guard !trim.isEmpty else { return nodes }
        // Each edge without the parts taken by the roundings at its ends.
        let pieces: [CubicSegment] = segs.enumerated().map { k, s in
            let a = trim[k]?.d ?? 0, b = trim[(k + 1) % n]?.d ?? 0
            guard a > 0 || b > 0 else { return s }
            let len = Self.arcLength(s)
            let t0 = a > 0 ? Self.parameter(s, atLength: a) : 0
            let t1 = b > 0 ? Self.parameter(s, atLength: len - b) : 1
            return s.sub(t0, max(t0, t1))
        }
        var out: [BezierNode] = []
        for i in 0..<n {
            let inPiece: CubicSegment? = (isClosed || i > 0) ? pieces[(i - 1 + segs.count) % segs.count] : nil
            let outPiece: CubicSegment? = i < segs.count ? pieces[i] : nil
            if let t = trim[i], let a = inPiece, let b = outPiece {
                let p1 = a.p3, p2 = b.p0
                var first = BezierNode(point: p1, inHandle: a.isCurve ? a.c2 : nil)
                var second = BezierNode(point: p2, outHandle: b.isCurve ? b.c1 : nil)
                if style == .rounded,
                   let d1 = Self.unit(Self.endTangentForward(a)) ?? Self.unit(t.corner.point - p1),
                   let d2 = Self.unit(Self.startTangent(b)) ?? Self.unit(p2 - t.corner.point) {
                    // Circular arc from p1 (heading d1) to p2 (heading d2): r = chord / (2 sin(φ/2)), handle 4/3 tan(φ/4) r.
                    // With straight edges this is exactly r = d·tan(θ/2), φ = π − θ.
                    let phi = acos(max(-1, min(1, d1.x * d2.x + d1.y * d2.y)))
                    let chord = p1.distance(to: p2)
                    let k: Double
                    if phi > 1e-9, sin(phi / 2) > 1e-12 {
                        let r = chord / (2 * sin(phi / 2))
                        k = 4.0 / 3.0 * tan(phi / 4) * r
                    } else {
                        k = chord / 3
                    }
                    first.outHandle = p1 + d1 * k
                    second.inHandle = p2 - d2 * k
                }
                out.append(first)
                out.append(second)
            } else {
                var node = nodes[i]
                node.inHandle = inPiece.flatMap { $0.isCurve ? $0.c2 : nil }
                node.outHandle = outPiece.flatMap { $0.isCurve ? $0.c1 : nil }
                if !isClosed, i == 0 { node.inHandle = nodes[i].inHandle }
                if !isClosed, i == n - 1 { node.outHandle = nodes[i].outHandle }
                out.append(node)
            }
        }
        return Self.mergingCoincident(out, closed: isClosed)
    }

    /// Two roundings that each take half of the same edge meet in one point: those two nodes become one node
    /// (incoming handle of the first, outgoing handle of the second).
    private static func mergingCoincident(_ nodes: [BezierNode], closed: Bool) -> [BezierNode] {
        var out: [BezierNode] = []
        for n in nodes {
            if let last = out.last, last.point.distance(to: n.point) < 1e-9 {
                out[out.count - 1] = BezierNode(point: last.point, inHandle: last.inHandle, outHandle: n.outHandle)
            } else {
                out.append(n)
            }
        }
        if closed, out.count > 2, let first = out.first, let last = out.last, first.point.distance(to: last.point) < 1e-9 {
            out[0] = BezierNode(point: first.point, inHandle: last.inHandle, outHandle: first.outHandle)
            out.removeLast()
        }
        return out
    }

    // MARK: Segment helpers

    private static func unit(_ v: Point2D) -> Point2D? {
        let l = hypot(v.x, v.y)
        return l > 1e-12 ? v * (1 / l) : nil
    }

    /// Direction leaving the start of the segment (first control point that differs from p0).
    private static func startTangent(_ s: CubicSegment) -> Point2D {
        for q in [s.c1, s.c2, s.p3] where q.distance(to: s.p0) > 1e-12 { return q - s.p0 }
        return Point2D(x: 0, y: 0)
    }

    /// Direction of travel arriving at the end of the segment.
    private static func endTangentForward(_ s: CubicSegment) -> Point2D {
        for q in [s.c2, s.c1, s.p0] where q.distance(to: s.p3) > 1e-12 { return s.p3 - q }
        return Point2D(x: 0, y: 0)
    }

    /// Direction from the end of the segment back along it.
    private static func endTangentBackward(_ s: CubicSegment) -> Point2D { endTangentForward(s) * -1 }

    private static let lengthSteps = 64

    /// Length of the segment (exact for straight segments, a 64-step polyline for curves).
    static func arcLength(_ s: CubicSegment) -> Double {
        guard s.isCurve else { return s.p0.distance(to: s.p3) }
        var len = 0.0, prev = s.p0
        for k in 1...lengthSteps {
            let q = s.point(at: Double(k) / Double(lengthSteps))
            len += prev.distance(to: q)
            prev = q
        }
        return len
    }

    /// Parameter t at which the length along the segment from p0 is `length`.
    static func parameter(_ s: CubicSegment, atLength length: Double) -> Double {
        let total = arcLength(s)
        guard total > 1e-12 else { return 0 }
        if length <= 0 { return 0 }
        if length >= total { return 1 }
        guard s.isCurve else { return length / total }
        var acc = 0.0, prev = s.p0
        for k in 1...lengthSteps {
            let t = Double(k) / Double(lengthSteps)
            let q = s.point(at: t)
            let step = prev.distance(to: q)
            if acc + step >= length {
                let f = step > 0 ? (length - acc) / step : 0
                return t - (1 - f) / Double(lengthSteps)
            }
            acc += step
            prev = q
        }
        return 1
    }
}
