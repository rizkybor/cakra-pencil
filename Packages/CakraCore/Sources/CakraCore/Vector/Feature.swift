import Foundation

/// Titik bezier: posisi + handle masuk/keluar (koordinat absolut UTM). Tanpa handle = titik sudut.
public struct BezierNode: Codable, Hashable, Sendable {
    public var point: Point2D
    public var inHandle: Point2D?
    public var outHandle: Point2D?

    public init(point: Point2D, inHandle: Point2D? = nil, outHandle: Point2D? = nil) {
        self.point = point
        self.inHandle = inHandle
        self.outHandle = outHandle
    }

    public var isSmooth: Bool { inHandle != nil || outHandle != nil }

    /// Geser titik beserta kedua handle-nya.
    public func moved(by d: Point2D) -> BezierNode {
        BezierNode(point: point + d, inHandle: inHandle.map { $0 + d }, outHandle: outHandle.map { $0 + d })
    }
}

/// Satu segmen kubik p0 → p3 dengan titik kontrol c1, c2. Segmen lurus: c1 = p0, c2 = p3.
public struct CubicSegment: Hashable, Sendable {
    public var p0: Point2D
    public var c1: Point2D
    public var c2: Point2D
    public var p3: Point2D
    public var isCurve: Bool

    public func point(at t: Double) -> Point2D {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return Point2D(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }
}

public enum FeatureKind: String, Codable, CaseIterable, Sendable {
    case point
    case line
    case area

    public var label: String {
        switch self {
        case .point: return "Titik"
        case .line: return "Garis"
        case .area: return "Area"
        }
    }
}

/// Objek vektor (FR-4): garis atau area dari titik bezier, di koordinat proyek (UTM).
public struct Feature: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: FeatureKind
    public var colorHex: String
    public var widthMM: Double
    public var nodes: [BezierNode]
    public var isVisible: Bool
    public var isLocked: Bool
    public var createdAt: Date
    /// Kode simbol ISOM/ISSprOM (mis. "101.0") dan namanya, bila objek digambar dengan simbol dari panel simbol
    /// atau diimpor dari OCAD. Ikut ke export .omap/DXF.
    public var symbolCode: String?
    public var symbolName: String?
    /// Bentuk simbol titik pada ukuran standar (mm kertas). Hanya untuk `kind == .point`.
    public var pointElements: [PointElement]?
    /// Pengali ukuran simbol titik (1 = ukuran standar IOF dari set simbol).
    public var sizeFactor: Double?
    /// Garis ganda: warna tepi dan lebar isi (mm); `widthMM` = lebar total tepi ke tepi.
    public var casingColorHex: String?
    public var innerWidthMM: Double?
    /// Tebal standar IOF dari simbolnya, untuk tombol "Standar" setelah tebal diubah.
    public var standardWidthMM: Double?

    public init(id: UUID = UUID(), name: String = "", kind: FeatureKind, colorHex: String, widthMM: Double,
                nodes: [BezierNode], isVisible: Bool = true, isLocked: Bool = false, createdAt: Date = Date(),
                symbolCode: String? = nil, symbolName: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.widthMM = widthMM
        self.nodes = nodes
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.createdAt = createdAt
        self.symbolCode = symbolCode
        self.symbolName = symbolName
    }

    /// Area selalu tertutup; garis terbuka.
    public var isClosed: Bool { kind == .area }

    public var segments: [CubicSegment] {
        guard nodes.count > 1 else { return [] }
        var out: [CubicSegment] = []
        let count = isClosed ? nodes.count : nodes.count - 1
        for i in 0..<count {
            let a = nodes[i], b = nodes[(i + 1) % nodes.count]
            out.append(CubicSegment(p0: a.point, c1: a.outHandle ?? a.point, c2: b.inHandle ?? b.point, p3: b.point,
                                    isCurve: a.outHandle != nil || b.inHandle != nil))
        }
        return out
    }

    /// Kotak yang pasti memuat kurva (kurva bezier selalu di dalam hull titik kontrolnya).
    /// Untuk titik: kotak sebesar 1 m; ukuran gambar sebenarnya bergantung skala (lihat `pointRadiusM`).
    public var bounds: Rect2D? {
        if kind == .point, let p = nodes.first?.point {
            return Rect2D(minX: p.x - 1, minY: p.y - 1, maxX: p.x + 1, maxY: p.y + 1)
        }
        return Rect2D(points: nodes.flatMap { [$0.point] + [$0.inHandle, $0.outHandle].compactMap { $0 } })
    }

    public var effectiveSizeFactor: Double { sizeFactor ?? 1 }

    /// Jari-jari simbol titik di tanah (m) pada skala lembar.
    public func pointRadiusM(sheet: SheetSpec) -> Double {
        sheet.groundMeters(forPaperMM: (pointElements ?? []).diameterMM / 2 * effectiveSizeFactor)
    }

    /// Elemen titik yang sudah diskalakan `sizeFactor` (koordinat + diameter + tebal).
    public var scaledPointElements: [PointElement] {
        let k = effectiveSizeFactor
        return (pointElements ?? []).map { e in
            var e = e
            e.points = e.points.map { Point2D(x: $0.x * k, y: $0.y * k) }
            e.diameterMM *= k
            e.lineWidthMM *= k
            return e
        }
    }

    /// Objek simbol titik di posisi `p` dengan ukuran standar × `sizeFactor`.
    public static func point(at p: Point2D, elements: [PointElement], sizeFactor: Double = 1, name: String = "",
                             symbolCode: String? = nil, symbolName: String? = nil) -> Feature {
        var f = Feature(name: name, kind: .point, colorHex: elements.drawingOrder.last?.colorHex ?? "#000000",
                        widthMM: elements.diameterMM * sizeFactor, nodes: [BezierNode(point: p)],
                        symbolCode: symbolCode, symbolName: symbolName)
        f.pointElements = elements
        f.sizeFactor = sizeFactor == 1 ? nil : sizeFactor
        return f
    }

    /// Polyline pendekatan kurva; simpangan maksimum ≤ `tolerance` meter.
    public func flattened(tolerance: Double) -> [Point2D] {
        guard let first = nodes.first else { return [] }
        var pts = [first.point]
        for s in segments {
            if !s.isCurve {
                pts.append(s.p3)
                continue
            }
            // Jumlah langkah dari panjang poligon kontrol: cukup untuk toleransi di skala peta.
            let hull = s.p0.distance(to: s.c1) + s.c1.distance(to: s.c2) + s.c2.distance(to: s.p3)
            let steps = max(4, min(256, Int((hull / max(tolerance, 1e-6)).squareRoot().rounded(.up)) * 2))
            for k in 1...steps { pts.append(s.point(at: Double(k) / Double(steps))) }
        }
        return pts
    }

    public func distance(to p: Point2D, tolerance: Double) -> Double {
        let pts = flattened(tolerance: tolerance)
        guard pts.count > 1 else { return pts.first.map(p.distance) ?? .infinity }
        var best = Double.infinity
        for i in 1..<pts.count { best = min(best, p.distance(toSegment: pts[i - 1], pts[i])) }
        return best
    }

    /// Nama tampilan di panel: nama user, atau jenis + nomor pendek.
    public var displayName: String {
        name.isEmpty ? "\(kind.label) \(id.uuidString.prefix(4))" : name
    }
}

// MARK: - Bentuk dasar

extension Feature {
    /// Konstanta kubik untuk seperempat lingkaran (selisih radius maks ≈ 0,03%).
    public static let ellipseKappa = 0.5522847498

    /// Persegi panjang dari 4 pojok searah jarum jam mulai kiri atas (boleh miring bila peta diputar).
    public static func rectangle(corners c: [Point2D], colorHex: String, widthMM: Double) -> Feature {
        Feature(name: "", kind: .area, colorHex: colorHex, widthMM: widthMM, nodes: c.prefix(4).map { BezierNode(point: $0) })
    }

    /// Ellipse yang menyinggung jajaran genjang dari 4 pojok (kiri atas, kanan atas, kanan bawah, kiri bawah):
    /// 4 titik halus di tengah tiap sisi dengan handle kappa.
    public static func ellipse(corners c: [Point2D], colorHex: String, widthMM: Double) -> Feature {
        precondition(c.count >= 4)
        let center = Point2D(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        func half(_ a: Point2D, _ b: Point2D) -> Point2D { Point2D(x: (b.x - a.x) / 2, y: (b.y - a.y) / 2) }
        func scaled(_ p: Point2D, _ k: Double) -> Point2D { Point2D(x: p.x * k, y: p.y * k) }
        let u = half(c[0], c[1]) // setengah lebar, ke kanan
        let v = half(c[0], c[3]) // setengah tinggi, ke bawah
        let k = ellipseKappa
        let top = center - v, right = center + u, bottom = center + v, left = center - u
        return Feature(name: "", kind: .area, colorHex: colorHex, widthMM: widthMM, nodes: [
            BezierNode(point: top, inHandle: top - scaled(u, k), outHandle: top + scaled(u, k)),
            BezierNode(point: right, inHandle: right - scaled(v, k), outHandle: right + scaled(v, k)),
            BezierNode(point: bottom, inHandle: bottom + scaled(u, k), outHandle: bottom - scaled(u, k)),
            BezierNode(point: left, inHandle: left + scaled(v, k), outHandle: left - scaled(v, k)),
        ])
    }

    /// Ubah titik ke-i jadi sudut (tanpa handle) atau halus (handle searah tetangga, panjang ⅓ jarak terdekat).
    public mutating func toggleSmooth(at i: Int) {
        guard nodes.indices.contains(i) else { return }
        if nodes[i].isSmooth {
            nodes[i].inHandle = nil
            nodes[i].outHandle = nil
            return
        }
        let n = nodes.count
        let p = nodes[i].point
        let prev = (i > 0 || isClosed) ? nodes[(i - 1 + n) % n].point : p
        let next = (i < n - 1 || isClosed) ? nodes[(i + 1) % n].point : p
        var dir = next - prev
        let len = hypot(dir.x, dir.y)
        guard len > 0 else { return }
        dir = Point2D(x: dir.x / len, y: dir.y / len)
        let reach = min(p.distance(to: prev) == 0 ? .infinity : p.distance(to: prev),
                        p.distance(to: next) == 0 ? .infinity : p.distance(to: next)) / 3
        guard reach.isFinite else { return }
        nodes[i].inHandle = p - Point2D(x: dir.x * reach, y: dir.y * reach)
        nodes[i].outHandle = p + Point2D(x: dir.x * reach, y: dir.y * reach)
    }

    /// Pindahkan satu handle. Pada titik halus, handle seberangnya ikut berputar (segaris) dengan panjang tetap.
    public mutating func moveHandle(node i: Int, isIn: Bool, to h: Point2D) {
        guard nodes.indices.contains(i) else { return }
        let p = nodes[i].point
        if isIn { nodes[i].inHandle = h } else { nodes[i].outHandle = h }
        guard let other = isIn ? nodes[i].outHandle : nodes[i].inHandle else { return }
        let d = h - p
        let len = hypot(d.x, d.y)
        guard len > 0 else { return }
        let otherLen = other.distance(to: p)
        let mirrored = p - Point2D(x: d.x / len * otherLen, y: d.y / len * otherLen)
        if isIn { nodes[i].outHandle = mirrored } else { nodes[i].inHandle = mirrored }
    }
}

// MARK: - Gaya garis

extension Feature {
    /// Terapkan gaya garis IOF (tebal, warna, tepi garis ganda) dan simpan tebal standarnya.
    public mutating func apply(_ style: LineStyle) {
        colorHex = style.colorHex
        widthMM = style.widthMM
        casingColorHex = style.casing?.colorHex
        innerWidthMM = style.casing?.innerWidthMM
        standardWidthMM = style.widthMM
    }

    public var isDoubleLine: Bool { casingColorHex != nil && innerWidthMM != nil }

    /// Ubah lebar total; pada garis ganda lebar isi ikut berubah dengan perbandingan yang sama.
    public mutating func setWidth(_ mm: Double) {
        let next = PenPreset.clampWidth(mm)
        if let inner = innerWidthMM, widthMM > 0 { innerWidthMM = inner * next / widthMM }
        widthMM = next
    }
}
