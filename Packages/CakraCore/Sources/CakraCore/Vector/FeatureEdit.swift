import Foundation

// MARK: - Alat edit seperti OCAD: tambah titik, potong, skala, paralel, balik arah

extension Feature {
    /// Tambah titik di posisi path tanpa mengubah bentuk (kurva dibelah de Casteljau). Kembalikan indeks titik baru.
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

    /// Potong garis di satu posisi jadi dua garis (OCAD Cut). Bagian kedua mendapat id baru, nama kosong.
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

    /// Belah area dengan garis lurus antara dua titik di tepinya (OCAD Cut area) jadi dua area.
    public func splitArea(from a: PathPosition, to b: PathPosition) -> (Feature, Feature)? {
        guard kind == .area, let pa = point(at: a), let pb = point(at: b), pa.distance(to: pb) > 1e-6 else { return nil }
        let one = forwardNodes(from: a, to: b), two = forwardNodes(from: b, to: a)
        // Titik akhir tiap bagian = titik awal bagian lain; area menutup lurus kembali ke titik awalnya.
        guard one.count >= 3, two.count >= 3 else { return nil }
        var first = self, second = self
        first.nodes = one
        second.id = UUID()
        second.name = ""
        second.createdAt = Date()
        second.nodes = two
        return (first, second)
    }

    /// Ubah ukuran geometri garis/area sebanding terhadap `center` (tebal garis tetap, seperti OCAD Scale).
    public func scaled(by k: Double, around center: Point2D) -> Feature {
        guard kind != .point, k > 0 else { return self }
        func s(_ p: Point2D) -> Point2D { Point2D(x: center.x + (p.x - center.x) * k, y: center.y + (p.y - center.y) * k) }
        var f = self
        f.nodes = nodes.map { BezierNode(point: s($0.point), inHandle: $0.inHandle.map(s), outHandle: $0.outHandle.map(s)) }
        return f
    }

    /// Garis/area sejajar sejauh `distance` m (positif = sisi kiri arah garis; area berlawanan jarum jam: ke dalam).
    /// Titik digeser sepanjang garis bagi sudut (miter), handle ikut bergeser bersama titiknya.
    public func parallel(offset distance: Double) -> Feature {
        guard kind != .point, nodes.count >= 2, distance != 0 else { return self }
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
            // Arah masuk/keluar memakai handle bila ada (garis singgung kurva).
            let tin = hasPrev ? unit(p - (nodes[i].inHandle ?? prev.outHandle ?? prev.point)) ?? unit(p - prev.point) : nil
            let tout = hasNext ? unit((nodes[i].outHandle ?? next.inHandle ?? next.point) - p) ?? unit(next.point - p) : nil
            let normals = [tin, tout].compactMap { $0 }.map(left)
            guard let n0 = normals.first else { continue }
            var dir = n0
            var factor = 1.0
            if normals.count == 2, let avg = unit(normals[0] + normals[1]) {
                dir = avg
                // Miter dibatasi 3× agar sudut sangat tajam tidak memanjang tak terhingga.
                factor = 1 / max(1.0 / 3, dir.x * normals[0].x + dir.y * normals[0].y)
            }
            let v = Point2D(x: dir.x * distance * factor, y: dir.y * distance * factor)
            out.nodes[i] = nodes[i].moved(by: v)
        }
        return out
    }

    /// Balik arah garis (OCAD Reverse): penting untuk simbol berarah seperti tebing dan pagar.
    public mutating func reverse() {
        nodes = reversedNodes
    }
}
