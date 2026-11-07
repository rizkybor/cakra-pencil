import Foundation

/// Rotasi presisi (Shift saat memutar): sudut menempel bila sisi lurus objek jadi sejajar/tegak lurus dengan
/// sisi lurus objek lain di dekatnya (atau utara grid); bila tidak ada yang dekat, ke kelipatan `step` derajat.
public enum RotationSnap {
    /// Sisi lurus sebuah objek: arah (derajat searah jarum jam dari utara grid, 0–180) dan ujungnya.
    public struct Edge: Sendable, Equatable {
        public var bearing: Double
        public var a: Point2D
        public var b: Point2D
    }

    public struct Result: Sendable, Equatable {
        /// Sudut rotasi absolut objek (derajat).
        public var degrees: Double
        /// Sisi acuan yang membuat objek lurus (nil = utara grid atau kelipatan sudut).
        public var reference: Edge?
        /// true = menempel ke kelipatan sudut (tidak ada sisi yang sejajar).
        public var isStep: Bool
    }

    /// Arah garis a→b sebagai bearing 0–180 (arah garis, bukan vektor).
    public static func bearing(_ a: Point2D, _ b: Point2D) -> Double {
        let d = atan2(b.x - a.x, b.y - a.y) * 180 / .pi
        let r = d.truncatingRemainder(dividingBy: 180)
        return r < 0 ? r + 180 : r
    }

    /// Selisih terkecil dua arah modulo `period` (hasil −period/2 … period/2).
    static func difference(_ a: Double, _ b: Double, period: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: period)
        if d > period / 2 { d -= period }
        if d < -period / 2 { d += period }
        return d
    }

    /// - Parameters:
    ///   - raw: sudut rotasi absolut yang ditunjuk jari/kursor.
    ///   - base: sudut rotasi objek saat mulai diputar (`edges` diukur pada sudut ini).
    ///   - edges: sisi lurus objek yang diputar; kosong (mis. simbol titik) = arah atas simbol (0°).
    ///   - references: sisi lurus objek lain di dekatnya.
    ///   - includeNorth: utara grid juga acuan.
    ///   - threshold: jarak menempel ke sisi acuan (derajat).
    ///   - step: kelipatan sudut bila tidak ada sisi acuan dalam jangkauan.
    public static func snap(raw: Double, base: Double, edges: [Edge], references: [Edge], includeNorth: Bool = true,
                            threshold: Double = 4, step: Double = 15) -> Result {
        let own = edges.isEmpty ? [0.0] : edges.map(\.bearing)
        var refs: [(Double, Edge?)] = references.map { ($0.bearing, $0) }
        if includeNorth { refs.append((0, nil)) }
        var best: (degrees: Double, gap: Double, ref: Edge?)?
        for e in own {
            // Bearing sisi setelah rotasi = e + (R − base); sejajar atau tegak lurus = selisih kelipatan 90°.
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
    /// Sisi lurus (segmen bukan kurva) yang panjangnya minimal `minLength` meter.
    public func straightEdges(minLength: Double) -> [RotationSnap.Edge] {
        guard kind != .point else { return [] }
        return segments.compactMap { s in
            guard !s.isCurve, s.p0.distance(to: s.p3) >= minLength else { return nil }
            return RotationSnap.Edge(bearing: RotationSnap.bearing(s.p0, s.p3), a: s.p0, b: s.p3)
        }
    }

    /// Atur sudut absolut tanpa pembulatan 0,1° (rotasi presisi agar sisi benar-benar sejajar).
    public mutating func setRotationExactly(_ degrees: Double) {
        let target = Feature.normalizedDegrees(degrees)
        let delta = target - rotationDegrees
        if kind != .point, delta != 0, let c = rotationPivot {
            nodes = nodes.map { n in
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
