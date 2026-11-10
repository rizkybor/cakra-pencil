import Foundation

// MARK: - Areas with holes (OCAD / OOM "hole" parts of an area object)

/// An area is its outer ring (`nodes`) plus optional holes (`holes`), each a closed ring of bezier nodes.
///
/// Winding convention: holes always run opposite to the outer ring (outer counterclockwise → holes clockwise, and the
/// other way round), so the area interior is on the same side of every ring. The outer ring keeps the user's drawing
/// direction. Renderers fill with the even-odd rule, which needs no particular winding, but the cut/merge engine and
/// the parallel offset rely on the convention; `normalizeHoles()` restores it after any edit that may break it.
///
/// Node Tool indices: hole nodes continue after the outer ring's nodes (`allNodes`), so index `nodes.count` is the
/// first node of the first hole.
extension Feature {
    /// The holes of an area (empty for lines and points, even if a value is stored).
    public var holeRings: [[BezierNode]] { kind == .area ? (holes ?? []) : [] }

    public var hasHoles: Bool { !holeRings.isEmpty }

    /// Outer ring first, then the holes.
    public var rings: [[BezierNode]] { [nodes] + holeRings }

    /// The ring `k` (0 = outer, 1… = holes) as a plain object of its own: same id and style, no holes.
    public func ringFeature(_ k: Int) -> Feature {
        var f = self
        f.holes = nil
        if k > 0, holeRings.indices.contains(k - 1) { f.nodes = holeRings[k - 1] }
        return f
    }

    /// Every ring as its own object (snap and follow targets: hole edges count like outer edges).
    public var ringFeatures: [Feature] { (0..<rings.count).map(ringFeature) }

    /// Outline segments of every ring (closed rings for areas).
    public var allSegments: [CubicSegment] { ringFeatures.flatMap(\.segments) }

    /// All nodes, outer ring first then each hole (Node Tool indices). Setting keeps the ring sizes.
    public var allNodes: [BezierNode] {
        get { holeRings.isEmpty ? nodes : nodes + holeRings.flatMap { $0 } }
        set {
            guard hasHoles else { nodes = newValue; return }
            var rest = newValue[...]
            nodes = Array(rest.prefix(nodes.count))
            rest = rest.dropFirst(nodes.count)
            holes = holeRings.map { h in
                let ring = Array(rest.prefix(h.count))
                rest = rest.dropFirst(h.count)
                return ring
            }
        }
    }

    /// Ring and index within that ring of Node Tool index `i`.
    public func ringLocation(ofNode i: Int) -> (ring: Int, index: Int)? {
        guard i >= 0 else { return nil }
        var start = 0
        for (k, r) in rings.enumerated() {
            if i < start + r.count { return (k, i - start) }
            start += r.count
        }
        return nil
    }

    /// Node Tool index of node `index` in ring `ring`.
    public func nodeIndex(ring: Int, index: Int) -> Int {
        rings.prefix(ring).reduce(0) { $0 + $1.count } + index
    }

    /// Node Tool indices of ring `k`.
    public func nodeIndices(ofRing k: Int) -> Range<Int> {
        let start = nodeIndex(ring: k, index: 0)
        return start..<(start + (rings.indices.contains(k) ? rings[k].count : 0))
    }

    /// Replace ring `k` with `nodes` (outer ring or a hole).
    public mutating func setRing(_ k: Int, _ ring: [BezierNode]) {
        if k == 0 { nodes = ring; return }
        guard var h = holes, h.indices.contains(k - 1) else { return }
        h[k - 1] = ring
        holes = h
    }

    /// This object with ring `k` replaced by what `transform` makes of it (as a plain object without holes).
    public func replacingRing(_ k: Int, _ transform: (Feature) -> Feature) -> Feature {
        var f = self
        f.setRing(k, transform(ringFeature(k)).nodes)
        return f
    }

    /// Edit the ring that holds Node Tool index `i`; `body` gets that ring as a plain object and the index within it.
    public mutating func editRing<R>(containingNode i: Int, _ body: (inout Feature, Int) -> R) -> R? {
        guard let (k, local) = ringLocation(ofNode: i) else { return nil }
        var ring = ringFeature(k)
        let r = body(&ring, local)
        setRing(k, ring.nodes)
        return r
    }

    /// Every node of every ring through `transform`.
    public func mappingAllNodes(_ transform: (BezierNode) -> BezierNode) -> Feature {
        var f = self
        f.nodes = nodes.map(transform)
        if let h = holes { f.holes = h.map { $0.map(transform) } }
        return f
    }

    /// Moved by `d` (all rings, with their handles).
    public func moved(by d: Point2D) -> Feature { mappingAllNodes { $0.moved(by: d) } }

    /// Remove hole `k` (0-based index into `holes`).
    public mutating func removeHole(_ k: Int) {
        guard var h = holes, h.indices.contains(k) else { return }
        h.remove(at: k)
        holes = h.isEmpty ? nil : h
    }

    /// Restore the winding convention (holes opposite to the outer ring), drop holes with fewer than 3 nodes or no area,
    /// and store `nil` when nothing is left.
    public mutating func normalizeHoles() {
        guard kind == .area, let h = holes else { holes = nil; return }
        let outer = Feature.signedArea(of: nodes)
        let kept = h.compactMap { ring -> [BezierNode]? in
            guard ring.count >= 3 else { return nil }
            let a = Feature.signedArea(of: ring)
            guard abs(a) > 1e-12 else { return nil }
            return (a > 0) == (outer > 0) ? ring.reversed().map(\.reversed) : ring
        }
        holes = kept.isEmpty ? nil : kept
    }

    /// Signed area of a ring's node points (positive = counterclockwise, y north).
    public static func signedArea(of ring: [BezierNode]) -> Double {
        let p = ring.map(\.point)
        guard p.count >= 3 else { return 0 }
        var s = 0.0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    /// Polylines of every ring (curves flattened within `tolerance` m).
    public func flattenedRings(tolerance: Double) -> [[Point2D]] {
        ringFeatures.map { $0.flattened(tolerance: tolerance) }
    }

    /// Point inside the filled part of the area: inside the outer ring and not inside a hole (even-odd over all rings).
    public func containsPoint(_ p: Point2D, tolerance: Double) -> Bool {
        guard kind == .area else { return false }
        var inside = false
        for pts in flattenedRings(tolerance: tolerance) where pts.count >= 3 {
            var j = pts.count - 1
            for i in 0..<pts.count {
                let a = pts[i], b = pts[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                j = i
            }
        }
        return inside
    }

    /// Index into `holes` of the hole containing `p` (nil = not in a hole).
    public func holeIndex(containing p: Point2D, tolerance: Double) -> Int? {
        holeRings.indices.first { k in
            ringFeature(k + 1).containsPoint(p, tolerance: tolerance)
        }
    }

    /// Filled ground area (m²): the outer ring minus its holes.
    public func filledArea(tolerance: Double) -> Double {
        let rings = flattenedRings(tolerance: tolerance).map { abs(ShapeCut.signedArea($0)) }
        guard let outer = rings.first else { return 0 }
        return max(0, outer - rings.dropFirst().reduce(0, +))
    }

    /// Nearest point on any ring: ring number (0 = outer), position on that ring, point, distance.
    public func nearestRingPosition(to p: Point2D) -> (ring: Int, position: PathPosition, point: Point2D, distance: Double)? {
        var best: (Int, PathPosition, Point2D, Double)?
        for (k, f) in ringFeatures.enumerated() {
            guard let r = f.nearestPathPosition(to: p), r.distance < (best?.3 ?? .infinity) else { continue }
            best = (k, r.position, r.point, r.distance)
        }
        return best.map { (ring: $0.0, position: $0.1, point: $0.2, distance: $0.3) }
    }
}
