import Foundation

// MARK: - Gabung objek (OCAD "Merge" / OOM "Unify areas" + "Connect paths")

/// Hasil penggabungan dua objek.
public struct MergeResult: Hashable, Sendable {
    public var feature: Feature
    /// Area digabung lewat poligon (tumpang tindih): kurva bezier menjadi titik-titik lurus.
    public var flattenedCurves: Bool
    /// Area gabungan punya lubang di tengah; lubang tidak disimpan (objek area belum mendukung lubang).
    public var droppedHoles: Bool
}

extension BezierNode {
    /// Titik yang sama dengan arah dibalik (handle masuk ↔ keluar).
    public var reversed: BezierNode { BezierNode(point: point, inHandle: outHandle, outHandle: inHandle) }
}

extension Feature {
    /// Boleh digabung: jenis sama (garis–garis atau area–area) dan simbol sama; objek tanpa simbol
    /// cocok bila warnanya sama.
    public func canMerge(with o: Feature) -> Bool {
        guard id != o.id, kind == o.kind, kind != .point else { return false }
        if let a = symbolCode { return a == o.symbolCode }
        return o.symbolCode == nil && colorHex.lowercased() == o.colorHex.lowercased()
    }

    /// Urutan titik dibalik (bentuk sama).
    public var reversedNodes: [BezierNode] { nodes.reversed().map(\.reversed) }

    // MARK: Garis

    /// Jarak terdekat antar ujung dua garis (m).
    public func endpointGap(to o: Feature) -> Double {
        guard kind == .line, o.kind == .line, let a0 = nodes.first, let a1 = nodes.last,
              let b0 = o.nodes.first, let b1 = o.nodes.last else { return .infinity }
        return [a0.point.distance(to: b0.point), a0.point.distance(to: b1.point),
                a1.point.distance(to: b0.point), a1.point.distance(to: b1.point)].min()!
    }

    /// Sambung dua garis di pasangan ujung terdekat (≤ `tolerance` m). Ujung yang berjauhan bertemu di
    /// titik tengahnya; handle kurva di sambungan dipertahankan. Hasil memakai identitas dan gaya `self`.
    public func joiningLine(_ o: Feature, tolerance: Double) -> Feature? {
        guard canMerge(with: o), kind == .line, nodes.count >= 2, o.nodes.count >= 2 else { return nil }
        let a0 = nodes.first!.point, a1 = nodes.last!.point, b0 = o.nodes.first!.point, b1 = o.nodes.last!.point
        // (jarak, bagian depan, bagian belakang): ujung akhir depan bertemu ujung awal belakang.
        let options: [(Double, [BezierNode], [BezierNode])] = [
            (a1.distance(to: b0), nodes, o.nodes),
            (a1.distance(to: b1), nodes, o.reversedNodes),
            (a0.distance(to: b0), reversedNodes, o.nodes),
            (a0.distance(to: b1), o.nodes, nodes),
        ]
        guard let best = options.min(by: { $0.0 < $1.0 }), best.0 <= tolerance else { return nil }
        var head = best.1, tail = best.2
        let end = head.removeLast(), start = tail.removeFirst()
        let meet = Point2D(x: (end.point.x + start.point.x) / 2, y: (end.point.y + start.point.y) / 2)
        let joint = BezierNode(point: meet, inHandle: end.inHandle.map { $0 + (meet - end.point) },
                               outHandle: start.outHandle.map { $0 + (meet - start.point) })
        var f = self
        f.nodes = head + [joint] + tail
        return f
    }

    // MARK: Area

    /// Satukan dua area. Area yang ditempelkan (berbagi sisi lewat titik yang di-snap) disambung tanpa
    /// mengubah kurvanya; area yang tumpang tindih disatukan lewat poligon. nil = tidak bersentuhan.
    /// `vertexTolerance`: jarak titik yang dianggap sama (m); `flattenTolerance`: kerapatan perataan kurva (m).
    public func unitingArea(_ o: Feature, vertexTolerance: Double, flattenTolerance: Double,
                            allowOverlap: Bool = true) -> MergeResult? {
        guard canMerge(with: o), kind == .area, nodes.count >= 3, o.nodes.count >= 3 else { return nil }
        if let f = stitchingArea(o, tolerance: vertexTolerance) {
            return MergeResult(feature: f, flattenedCurves: false, droppedHoles: false)
        }
        guard allowOverlap, let ba = bounds, let bb = o.bounds,
              ba.insetBy(-vertexTolerance).intersects(bb) else { return nil }
        let pa = PolygonUnion.ring(flattened(tolerance: flattenTolerance))
        let pb = PolygonUnion.ring(o.flattened(tolerance: flattenTolerance))
        guard let u = PolygonUnion.union(pa, pb, eps: max(vertexTolerance, 1e-6)) else { return nil }
        var f = self
        f.nodes = u.outer.map { BezierNode(point: $0) }
        f.rotationDeg = rotationDeg
        let curved = nodes.contains(where: \.isSmooth) || o.nodes.contains(where: \.isSmooth)
        return MergeResult(feature: f, flattenedCurves: curved, droppedHoles: u.holes > 0)
    }

    /// Area yang berbagi rantai titik berurutan (minimal satu sisi): rantai bersama dibuang, sisanya disambung.
    func stitchingArea(_ o: Feature, tolerance: Double) -> Feature? {
        // Samakan arah (berlawanan jarum jam) agar rantai bersama berjalan berlawanan di kedua area.
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
        /// Sisi a[i]→a[i+1] juga sisi b (dibalik).
        func shared(_ i: Int) -> Bool {
            guard let p = match[i], let q = match[(i + 1) % n] else { return false }
            return q == (p - 1 + m) % m
        }
        let edges = (0..<n).filter(shared)
        guard !edges.isEmpty, edges.count < n else { return nil }
        // Tepat satu rantai berurutan; lebih dari satu = akan ada lubang → pakai jalur poligon.
        let starts = edges.filter { !shared(($0 - 1 + n) % n) }
        guard starts.count == 1, let s = starts.first else { return nil }
        var e = s
        while shared((e + 1) % n) { e = (e + 1) % n }
        let i = s, j = (e + 1) % n            // rantai a[i] … a[j]
        guard let bi = match[i], let bj = match[j] else { return nil }
        // Bagian a di luar rantai: a[j] … a[i]; lalu bagian b di luar rantai: b[bi+1] … b[bj-1].
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

    /// Luas bertanda dari titik-titiknya (positif = berlawanan jarum jam, y ke utara).
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

// MARK: - Union poligon sederhana

/// Union dua poligon sederhana dengan klasifikasi sisi: semua sisi dipotong di titik perpotongan, sisi yang
/// berada di luar poligon lain (atau sisi bersama yang searah) dipertahankan, lalu dirangkai jadi cincin.
/// Tahan terhadap titik/sisi yang berimpit (kasus area yang di-snap), yang sering membuat algoritme lain gagal.
enum PolygonUnion {
    /// Cincin tanpa titik ganda, berlawanan jarum jam.
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

    /// nil bila keduanya tidak bersentuhan (hasil lebih dari satu bagian).
    static func union(_ a: [Point2D], _ b: [Point2D], eps: Double) -> (outer: [Point2D], holes: Int)? {
        guard a.count >= 3, b.count >= 3 else { return nil }
        let sa = split(a, by: b, eps: eps), sb = split(b, by: a, eps: eps)
        var kept: [(Point2D, Point2D)] = []
        for (p, q) in sa {
            let mid = Point2D(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            switch locate(mid, in: b, eps: eps) {
            case .outside: kept.append((p, q))
            case .inside: break
            case .boundary:
                // Sisi bersama: simpan sekali bila searah (bagian dari tepi luar); berlawanan = sisi dalam.
                if sb.contains(where: { $0.0.distance(to: p) <= eps && $0.1.distance(to: q) <= eps }) { kept.append((p, q)) }
            }
        }
        for (p, q) in sb {
            let mid = Point2D(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            if case .outside = locate(mid, in: a, eps: eps) { kept.append((p, q)) }
        }
        let rings = trace(kept, eps: eps)
        let outers = rings.filter { area($0) > 0 }
        // Tidak bersentuhan sama sekali = dua cincin luar; menempel di satu titik juga ditolak.
        guard outers.count == 1, let outer = outers.first else { return nil }
        let holes = rings.filter { area($0) < -eps * eps }.count
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

    /// Potong sisi-sisi `poly` di setiap perpotongan dan titik `other` yang terletak di atasnya.
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

    /// Perpotongan dua segmen yang tidak sejajar (di dalam keduanya).
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

    /// Rangkai sisi berarah menjadi cincin. Di titik bercabang, ambil belokan paling kanan.
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

    /// Sudut belok ke kiri (0…2π) dari arah masuk; nilai kecil = belok kanan.
    private static func turn(_ inDir: Double, _ e: (Point2D, Point2D)) -> Double {
        let out = atan2(e.1.y - e.0.y, e.1.x - e.0.x)
        var a = out - inDir + .pi   // 0 = balik arah
        while a <= 0 { a += 2 * .pi }
        while a > 2 * .pi { a -= 2 * .pi }
        return a
    }

    /// Hapus titik yang segaris dengan tetangganya (sisa pemotongan sisi).
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

// MARK: - Isi garis dengan area (OCAD "Fill / make border")

extension Feature {
    /// Garis yang bisa diisi area: minimal 3 titik.
    public var canFillWithArea: Bool { kind == .line && nodes.count >= 3 }

    /// Ujung garis bertemu (garis tertutup) dalam `tolerance` m.
    public func isClosedLine(tolerance: Double) -> Bool {
        guard kind == .line, let a = nodes.first, let b = nodes.last, nodes.count >= 3 else { return false }
        return a.point.distance(to: b.point) <= tolerance
    }

    /// Objek area baru dengan bentuk garis ini dan simbol area `s`; garisnya sendiri tidak berubah.
    /// Titik akhir yang berimpit dengan titik awal digabung (area menutup sendiri); garis terbuka ditutup lurus.
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
