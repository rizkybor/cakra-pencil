import Foundation

// MARK: - OCAD-like edit tools: add node, cut, scale, parallel, reverse

extension Feature {
    /// Add a node at a path position without changing the shape (curve split via de Casteljau). Returns the new node's index.
    @discardableResult
    public mutating func insertNode(at pos: PathPosition) -> Int? {
        let segs = segments
        guard kind != .point, segs.indices.contains(pos.segment), pos.t > 1e-6, pos.t < 1 - 1e-6 else { return nil }
        let s = segs[pos.segment]
        let i = pos.segment, j = (i + 1) % nodes.count
        if s.isCurve {
            let (l, r) = s.split(at: pos.t)
            nodes[i].outHandle = l.c1
            nodes[j].inHandle = r.c2
            nodes.insert(BezierNode(point: l.p3, inHandle: l.c2, outHandle: r.c1), at: i + 1)
        } else {
            nodes.insert(BezierNode(point: s.point(at: pos.t)), at: i + 1)
        }
        return i + 1
    }

    /// Add a node on ring `ring` (0 = outer, 1… = holes) without changing the shape. Returns its Node Tool index.
    @discardableResult
    public mutating func insertNode(ring: Int, at pos: PathPosition) -> Int? {
        guard ring > 0 else { return insertNode(at: pos) }
        var f = ringFeature(ring)
        guard let local = f.insertNode(at: pos) else { return nil }
        setRing(ring, f.nodes)
        return nodeIndex(ring: ring, index: local)
    }

    /// Drag a segment (Node Tool, as in Affinity/Illustrator): the point at position `t` on segment `index` is moved
    /// by `d` by changing that segment's two handles. A straight segment becomes curved. The segment's end nodes
    /// do not move; smooth nodes stay smooth (the opposite handle rotates along), corners stay corners.
    public func bendingSegment(_ index: Int, at t: Double, by d: Point2D) -> Feature {
        let segs = segments
        guard segs.indices.contains(index) else { return self }
        let s = segs[index]
        let t = min(max(t, 0.05), 0.95)
        let c1 = s.isCurve ? s.c1 : s.p0 + (s.p3 - s.p0) * (1.0 / 3)
        let c2 = s.isCurve ? s.c2 : s.p0 + (s.p3 - s.p0) * (2.0 / 3)
        // B(t) = … + 3(1−t)²t·c1 + 3(1−t)t²·c2 + …; c1 moves by (1−t)·k·d and c2 by t·k·d so B(t) moves by exactly d.
        let b1 = 3 * (1 - t) * (1 - t) * t, b2 = 3 * (1 - t) * t * t
        let k = 1 / (b1 * (1 - t) + b2 * t)
        var f = self
        f.moveHandle(node: index, isIn: false, to: c1 + d * ((1 - t) * k))
        f.moveHandle(node: (index + 1) % nodes.count, isIn: true, to: c2 + d * (t * k))
        return f
    }

    /// Cut a line at one position into two lines (OCAD Cut). The second part gets a new id and an empty name.
    public func splitLine(at pos: PathPosition) -> (Feature, Feature)? {
        guard kind == .line, nodes.count >= 2 else { return nil }
        let end = PathPosition(segment: segments.count - 1, t: 1)
        let start = PathPosition(segment: 0, t: 0)
        guard pos.order > 1e-6, pos.order < end.order - 1e-6 else { return nil }
        let a = forwardNodes(from: start, to: pos), b = forwardNodes(from: pos, to: end)
        guard a.count >= 2, b.count >= 2 else { return nil }
        var first = self, second = self
        first.nodes = a
        second.id = UUID()
        second.name = ""
        second.createdAt = Date()
        second.nodes = b
        return (first, second)
    }

    /// Split an area into two areas with a straight line between two points on its outline (OCAD Cut area).
    public func splitArea(from a: PathPosition, to b: PathPosition) -> (Feature, Feature)? {
        guard kind == .area, let pa = point(at: a), let pb = point(at: b), pa.distance(to: pb) > 1e-6 else { return nil }
        let one = forwardNodes(from: a, to: b), two = forwardNodes(from: b, to: a)
        // Each part's end point = the other part's start point; the area closes straight back to its start point.
        guard one.count >= 3, two.count >= 3 else { return nil }
        var first = self, second = self
        first.nodes = one
        second.id = UUID()
        second.name = ""
        second.createdAt = Date()
        second.nodes = two
        return (first, second)
    }

    /// Scale line/area geometry proportionally about `center` (line width unchanged, like OCAD Scale).
    /// Every node and handle through `transform` (e.g. a non-uniform scale done on screen); smart flags are kept.
    /// Holes go through the same transform.
    public func mapped(_ transform: (Point2D) -> Point2D) -> Feature {
        var f = mappingAllNodes { BezierNode(point: transform($0.point), inHandle: $0.inHandle.map(transform),
                                             outHandle: $0.outHandle.map(transform), smart: $0.smart) }
        f.normalizeHoles()   // a mirroring transform flips every ring; keep holes opposite to the outer ring
        return f
    }

    public func scaled(by k: Double, around center: Point2D) -> Feature {
        guard kind != .point, k > 0 else { return self }
        func s(_ p: Point2D) -> Point2D { Point2D(x: center.x + (p.x - center.x) * k, y: center.y + (p.y - center.y) * k) }
        return mappingAllNodes { BezierNode(point: s($0.point), inHandle: $0.inHandle.map(s), outHandle: $0.outHandle.map(s)) }
    }

    /// Parallel line/area at `distance` m (positive = left of the line direction; counterclockwise area: inward).
    /// Nodes move along the angle bisector (miter); handles move together with their node.
    /// Holes run opposite to the outer ring, so the same offset moves them the other way: an area made smaller
    /// (inward) gets larger holes, an area made larger gets smaller holes; a hole that shrinks away is dropped.
    public func parallel(offset distance: Double) -> Feature {
        guard kind != .point, nodes.count >= 2, distance != 0 else { return self }
        if hasHoles {
            var out = ringFeature(0).parallel(offset: distance)
            out.holes = holeRings.compactMap { ring -> [BezierNode]? in
                var h = ringFeature(0)
                h.nodes = ring
                let moved = h.parallel(offset: distance).nodes
                // Shrunk past its size, the ring folds over itself: its nodes end up closer to the original ring than
                // the offset distance.
                let tolerance = abs(distance) / 50
                let folded = moved.contains { h.distance(to: $0.point, tolerance: tolerance) < abs(distance) * 0.9 }
                return folded || abs(Feature.signedArea(of: moved)) < 1e-9 ? nil : moved
            }
            out.normalizeHoles()
            return out
        }
        let n = nodes.count
        func unit(_ v: Point2D) -> Point2D? {
            let l = hypot(v.x, v.y)
            return l > 1e-12 ? Point2D(x: v.x / l, y: v.y / l) : nil
        }
        func left(_ t: Point2D) -> Point2D { Point2D(x: -t.y, y: t.x) }
        var out = self
        for i in 0..<n {
            let p = nodes[i].point
            let hasPrev = i > 0 || isClosed, hasNext = i < n - 1 || isClosed
            let prev = nodes[(i - 1 + n) % n], next = nodes[(i + 1) % n]
            // In/out directions use the handles if present (curve tangent).
            let tin = hasPrev ? unit(p - (nodes[i].inHandle ?? prev.outHandle ?? prev.point)) ?? unit(p - prev.point) : nil
            let tout = hasNext ? unit((nodes[i].outHandle ?? next.inHandle ?? next.point) - p) ?? unit(next.point - p) : nil
            let normals = [tin, tout].compactMap { $0 }.map(left)
            guard let n0 = normals.first else { continue }
            var dir = n0
            var factor = 1.0
            if normals.count == 2, let avg = unit(normals[0] + normals[1]) {
                dir = avg
                // Miter limited to 3× so very sharp corners do not extend infinitely.
                factor = 1 / max(1.0 / 3, dir.x * normals[0].x + dir.y * normals[0].y)
            }
            let v = Point2D(x: dir.x * distance * factor, y: dir.y * distance * factor)
            out.nodes[i] = nodes[i].moved(by: v)
        }
        return out
    }

    /// Reverse the line direction (OCAD Reverse): important for directional symbols such as cliffs and fences.
    public mutating func reverse() {
        nodes = reversedNodes
        holes = holes.map { $0.map { $0.reversed().map(\.reversed) } }   // holes stay opposite to the outer ring
    }
}
