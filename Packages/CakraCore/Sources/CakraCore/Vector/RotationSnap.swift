import Foundation

/// Precision rotation (Shift while rotating): the angle snaps when a straight side of the object becomes parallel/perpendicular
/// to a straight side of a nearby object (or grid north); if none is close, to multiples of `step` degrees.
public enum RotationSnap {
    /// Straight side of an object: direction (degrees clockwise from grid north, 0–180) and its endpoints.
    public struct Edge: Sendable, Equatable {
        public var bearing: Double
        public var a: Point2D
        public var b: Point2D
    }

    public struct Result: Sendable, Equatable {
        /// Absolute rotation angle of the object (degrees).
        public var degrees: Double
        /// Reference side the object was aligned to (nil = grid north or angle multiple).
        public var reference: Edge?
        /// true = snapped to an angle multiple (no parallel side).
        public var isStep: Bool
    }

    /// Direction of line a→b as a bearing 0–180 (line direction, not a vector).
    public static func bearing(_ a: Point2D, _ b: Point2D) -> Double {
        let d = atan2(b.x - a.x, b.y - a.y) * 180 / .pi
        let r = d.truncatingRemainder(dividingBy: 180)
        return r < 0 ? r + 180 : r
    }

    /// Smallest difference between two directions modulo `period` (result −period/2 … period/2).
    static func difference(_ a: Double, _ b: Double, period: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: period)
        if d > period / 2 { d -= period }
        if d < -period / 2 { d += period }
        return d
    }

    /// - Parameters:
    ///   - raw: absolute rotation angle indicated by the finger/cursor.
    ///   - base: object's rotation angle when rotation began (`edges` are measured at this angle).
    ///   - edges: straight sides of the rotated object; empty (e.g. point symbol) = the symbol's up direction (0°).
    ///   - references: straight sides of other nearby objects.
    ///   - includeNorth: grid north is also a reference.
    ///   - threshold: snap distance to a reference side (degrees).
    ///   - step: angle multiple when no reference side is within range.
    public static func snap(raw: Double, base: Double, edges: [Edge], references: [Edge], includeNorth: Bool = true,
                            threshold: Double = 4, step: Double = 15) -> Result {
        let own = edges.isEmpty ? [0.0] : edges.map(\.bearing)
        var refs: [(Double, Edge?)] = references.map { ($0.bearing, $0) }
        if includeNorth { refs.append((0, nil)) }
        var best: (degrees: Double, gap: Double, ref: Edge?)?
        for e in own {
            // Side bearing after rotation = e + (R − base); parallel or perpendicular = difference is a multiple of 90°.
            let current = e + (raw - base)
            for (r, edge) in refs {
                let d = difference(r, current, period: 90)
                guard abs(d) <= threshold else { continue }
                if best == nil || abs(d) < best!.gap - 1e-9 {
                    best = (raw + d, abs(d), edge)
                }
            }
        }
        if let best {
            return Result(degrees: Feature.normalizedDegrees(best.degrees), reference: best.ref, isStep: false)
        }
        let stepped = (raw / step).rounded() * step
        return Result(degrees: Feature.normalizedDegrees(stepped), reference: nil, isStep: true)
    }
}

extension Feature {
    /// Straight sides (non-curved segments) at least `minLength` meters long.
    public func straightEdges(minLength: Double) -> [RotationSnap.Edge] {
        guard kind != .point else { return [] }
        return allSegments.compactMap { s in
            guard !s.isCurve, s.p0.distance(to: s.p3) >= minLength else { return nil }
            return RotationSnap.Edge(bearing: RotationSnap.bearing(s.p0, s.p3), a: s.p0, b: s.p3)
        }
    }

    /// Set the absolute angle without 0.1° rounding (precision rotation so sides are truly parallel).
    public mutating func setRotationExactly(_ degrees: Double) {
        let target = Feature.normalizedDegrees(degrees)
        let delta = target - rotationDegrees
        if kind != .point, delta != 0, let c = rotationPivot {
            self = mappingAllNodes { n in
                var m = n
                m.point = Feature.rotate(n.point, around: c, degrees: delta)
                m.inHandle = n.inHandle.map { Feature.rotate($0, around: c, degrees: delta) }
                m.outHandle = n.outHandle.map { Feature.rotate($0, around: c, degrees: delta) }
                return m
            }
        }
        rotationDeg = abs(target) < 1e-9 ? nil : target
    }
}
