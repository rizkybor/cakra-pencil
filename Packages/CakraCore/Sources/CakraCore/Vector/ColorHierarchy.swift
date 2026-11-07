import Foundation

/// Color Hierarchy (OCAD Color Table / OOM color priority): warna yang lebih atas di tabel warna digambar
/// di atas warna di bawahnya, apa pun urutan objeknya. Mis. di ISSprOM 2019-2: hitam (bangunan, jalan) di atas
/// biru, biru di atas cokelat, cokelat di atas hijau, hijau di atas kuning; tepi hitam jalan di bawah isi
/// putih/cokelat 40%-nya. Objek dengan warna yang sama mengikuti urutan objek (panel Layer).
public enum ColorHierarchy {
    /// Bagian objek yang digambar: utuh, atau tepi/isi garis ganda yang punya lapisan warna sendiri.
    public enum Part: Sendable, Equatable {
        case whole, casing, main
    }

    public struct Paint: Sendable, Equatable {
        public var index: Int
        public var part: Part
        public var priority: Int
    }

    /// Objek tanpa simbol (sketsa) di atas semua warna peta; simbol yang tidak dikenal di bawah semuanya
    /// (area paling bawah, lalu garis, lalu titik) agar tidak menutupi warna yang sudah jelas urutannya.
    static let sketchPriority = -1

    static func fallbackPriority(_ f: Feature) -> Int {
        if f.symbolCode == nil { return sketchPriority }
        switch f.kind {
        case .area: return 30_000
        case .line: return 20_000
        case .point: return 10_000
        }
    }

    /// Prioritas warna utama objek (0 = paling atas). Titik tanpa data set simbol memakai prioritas
    /// elemennya sendiri (dari file OCAD).
    public static func priority(of f: Feature) -> Int {
        if let p = f.colorPriority { return p }
        if f.kind == .point, f.symbolCode != nil, let top = f.pointElements?.map(\.priority).min() { return top }
        return fallbackPriority(f)
    }

    /// Urutan menggambar (bawah → atas): prioritas besar dulu; sama prioritas = urutan objek.
    /// Garis ganda dengan warna tepi berbeda lapisan dipecah jadi tepi dan isi.
    public static func paintOrder(_ features: [Feature]) -> [Paint] {
        var paints: [Paint] = []
        paints.reserveCapacity(features.count)
        for (i, f) in features.enumerated() {
            let main = priority(of: f)
            if f.kind == .line, f.casingColorHex != nil, let casing = f.casingPriority, casing != main {
                paints.append(Paint(index: i, part: .casing, priority: casing))
                paints.append(Paint(index: i, part: .main, priority: main))
            } else {
                paints.append(Paint(index: i, part: .whole, priority: main))
            }
        }
        // Stabil: urutan objek dipertahankan untuk prioritas yang sama.
        return paints.enumerated()
            .sorted { a, b in a.element.priority != b.element.priority ? a.element.priority > b.element.priority : a.offset < b.offset }
            .map(\.element)
    }

    /// Indeks objek dari paling atas ke paling bawah (untuk memilih objek yang terlihat di atas).
    public static func topDownIndices(_ features: [Feature]) -> [Int] {
        var seen = Set<Int>()
        return paintOrder(features).reversed().compactMap { seen.insert($0.index).inserted ? $0.index : nil }
    }
}

extension Array where Element == Feature {
    /// Salinan objek dengan prioritas warna dari set simbol (`lookup` kode → simbol).
    public func withColorPriorities(_ lookup: (String) -> MapSymbol?) -> [Feature] {
        var cache: [String: MapSymbol?] = [:]
        return map { f in
            guard let code = f.symbolCode else { return f }
            let s: MapSymbol?
            if let hit = cache[code] { s = hit } else { s = lookup(code); cache[code] = s }
            guard let s, s.colorPriority != nil else { return f }
            var g = f
            g.colorPriority = s.colorPriority
            g.casingPriority = s.casingPriority
            return g
        }
    }
}
