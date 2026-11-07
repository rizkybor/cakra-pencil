import Foundation

/// Deskripsi kontrol IOF (International Specification for Control Descriptions 2018), kolom C–H.
/// A = nomor urut dan B = kode diisi dari lintasan. Nilai disimpan sebagai id simbol IOF (mis. "2.4" Boulder).
public struct ControlDescription: Codable, Hashable, Sendable {
    /// C: yang mana dari fitur serupa (mis. "0.1N" = paling utara).
    public var which: String?
    /// D: fitur kontrol (wajib untuk kontrol).
    public var feature: String?
    /// E: penampakan / detail fitur.
    public var appearance: String?
    /// F: dimensi ("2.5", "8x4") atau kombinasi (persimpangan/pertemuan).
    public var dimension: String?
    /// G: posisi bendera terhadap fitur.
    public var location: String?
    /// H: info lain (P3K, minum, radio, …).
    public var other: String?

    public init(which: String? = nil, feature: String? = nil, appearance: String? = nil, dimension: String? = nil,
                location: String? = nil, other: String? = nil) {
        self.which = which
        self.feature = feature
        self.appearance = appearance
        self.dimension = dimension
        self.location = location
        self.other = other
    }

    public var isEmpty: Bool { [which, feature, appearance, dimension, location, other].allSatisfy { ($0 ?? "").isEmpty } }

    /// Deskripsi teks bahasa Indonesia, mis. "Batu besar paling utara, 1,5 m, sisi timur".
    public var text: String {
        var head = [IOFSymbols.name(feature), IOFSymbols.name(appearance)].compactMap { $0 }.joined(separator: " ")
        if let w = IOFSymbols.name(which) { head = head.isEmpty ? w : "\(head) \(w)" }
        var parts = head.isEmpty ? [] : [head]
        if let d = dimension?.trimmingCharacters(in: .whitespaces), !d.isEmpty {
            // Angka seperti "1.5" adalah dimensi (m), bukan id simbol 1.5 kolom D.
            if let sym = IOFSymbols.symbol(d), sym.column == .f { parts.append(sym.name) } else {
                parts.append("\(d.replacingOccurrences(of: ".", with: ",")) m")
            }
        }
        if let g = IOFSymbols.name(location) { parts.append(g) }
        if let h = IOFSymbols.name(other) { parts.append(h) }
        return parts.joined(separator: ", ")
    }
}

/// Satu simbol deskripsi IOF.
public struct IOFSymbol: Hashable, Sendable, Identifiable {
    public enum Column: String, CaseIterable, Sendable {
        case c = "C", d = "D", e = "E", f = "F", g = "G", h = "H"

        public var title: String {
            switch self {
            case .c: return "Yang mana"
            case .d: return "Fitur"
            case .e: return "Penampakan"
            case .f: return "Dimensi / kombinasi"
            case .g: return "Posisi bendera"
            case .h: return "Info lain"
            }
        }
    }

    public var id: String
    public var column: Column
    public var name: String
    public var english: String
    /// Kelompok untuk kolom D: Bentuk lahan, Batuan, Air, Vegetasi, Buatan manusia, Khusus.
    public var group: String?
}

/// Katalog simbol deskripsi IOF 2018 (nomor sesuai spesifikasi; nama dalam bahasa Indonesia + Inggris).
public enum IOFSymbols {
    public static let all: [IOFSymbol] = which + features + appearance + combinations + locations + other

    public static func symbols(in column: IOFSymbol.Column) -> [IOFSymbol] { all.filter { $0.column == column } }

    private static let byID: [String: IOFSymbol] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func symbol(_ id: String?) -> IOFSymbol? { id.flatMap { byID[$0] } }

    public static func name(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return byID[id]?.name
    }

    private static func s(_ id: String, _ c: IOFSymbol.Column, _ name: String, _ en: String, _ group: String? = nil) -> IOFSymbol {
        IOFSymbol(id: id, column: c, name: name, english: en, group: group)
    }

    // Kolom C: yang mana dari beberapa fitur serupa.
    static let which: [IOFSymbol] = [
        s("0.1N", .c, "paling utara", "Northern"), s("0.1NE", .c, "paling timur laut", "North-eastern"),
        s("0.1E", .c, "paling timur", "Eastern"), s("0.1SE", .c, "paling tenggara", "South-eastern"),
        s("0.1S", .c, "paling selatan", "Southern"), s("0.1SW", .c, "paling barat daya", "South-western"),
        s("0.1W", .c, "paling barat", "Western"), s("0.1NW", .c, "paling barat laut", "North-western"),
        s("0.2", .c, "atas", "Upper"), s("0.3", .c, "bawah", "Lower"), s("0.4", .c, "tengah", "Middle"),
    ]

    // Kolom D: fitur.
    static let features: [IOFSymbol] = {
        let land = "Bentuk lahan", rock = "Batuan", water = "Air", veg = "Vegetasi", man = "Buatan manusia", special = "Khusus"
        return [
            s("1.1", .d, "Teras", "Terrace", land), s("1.2", .d, "Punggungan (spur)", "Spur", land),
            s("1.3", .d, "Lembah kecil (re-entrant)", "Re-entrant", land), s("1.4", .d, "Tebing tanah", "Earth bank", land),
            s("1.5", .d, "Galian / tambang", "Quarry", land), s("1.6", .d, "Tanggul tanah", "Earth wall", land),
            s("1.7", .d, "Parit erosi", "Erosion gully", land), s("1.8", .d, "Parit erosi kecil", "Small erosion gully", land),
            s("1.9", .d, "Bukit", "Hill", land), s("1.10", .d, "Bukit kecil (knoll)", "Knoll", land),
            s("1.11", .d, "Pelana (saddle)", "Saddle", land), s("1.12", .d, "Cekungan", "Depression", land),
            s("1.13", .d, "Cekungan kecil", "Small depression", land), s("1.14", .d, "Lubang", "Pit", land),
            s("1.15", .d, "Tanah tak rata", "Broken ground", land), s("1.16", .d, "Sarang semut", "Ant hill", land),
            s("2.1", .d, "Tebing batu", "Cliff", rock), s("2.2", .d, "Pilar batu", "Rock pillar", rock),
            s("2.3", .d, "Gua", "Cave", rock), s("2.4", .d, "Batu besar", "Boulder", rock),
            s("2.5", .d, "Medan batu besar", "Boulder field", rock), s("2.6", .d, "Kelompok batu besar", "Boulder cluster", rock),
            s("2.7", .d, "Tanah berbatu", "Stony ground", rock), s("2.8", .d, "Batu gundul", "Bare rock", rock),
            s("2.9", .d, "Celah sempit", "Narrow passage", rock), s("2.10", .d, "Parit", "Trench", rock),
            s("3.1", .d, "Danau", "Lake", water), s("3.2", .d, "Kolam", "Pond", water),
            s("3.3", .d, "Lubang air", "Waterhole", water), s("3.4", .d, "Sungai / kali", "River / stream", water),
            s("3.5", .d, "Saluran air kecil", "Minor water channel", water), s("3.6", .d, "Rawa sempit", "Narrow marsh", water),
            s("3.7", .d, "Rawa", "Marsh", water), s("3.8", .d, "Tanah keras di rawa", "Firm ground in marsh", water),
            s("3.9", .d, "Sumur", "Well", water), s("3.10", .d, "Mata air", "Spring", water),
            s("3.11", .d, "Bak / tangki air", "Water tank", water),
            s("4.1", .d, "Lahan terbuka", "Open land", veg), s("4.2", .d, "Lahan semi terbuka", "Semi-open land", veg),
            s("4.3", .d, "Sudut hutan", "Forest corner", veg), s("4.4", .d, "Area terbuka di hutan", "Clearing", veg),
            s("4.5", .d, "Semak lebat", "Thicket", veg), s("4.6", .d, "Semak memanjang", "Linear thicket", veg),
            s("4.7", .d, "Batas vegetasi", "Vegetation boundary", veg), s("4.8", .d, "Rumpun pohon", "Copse", veg),
            s("4.9", .d, "Pohon menonjol", "Distinct tree", veg), s("4.10", .d, "Tunggul pohon", "Tree stump / root stock", veg),
            s("5.1", .d, "Jalan", "Road", man), s("5.2", .d, "Jalan setapak", "Track / path", man),
            s("5.3", .d, "Jalur hutan (ride)", "Ride", man), s("5.4", .d, "Jembatan", "Bridge", man),
            s("5.5", .d, "Kabel listrik", "Power line", man), s("5.6", .d, "Tiang listrik", "Power line pylon", man),
            s("5.7", .d, "Terowongan", "Tunnel", man), s("5.8", .d, "Tembok batu", "Stone wall", man),
            s("5.9", .d, "Pagar", "Fence", man), s("5.10", .d, "Titik penyeberangan", "Crossing point", man),
            s("5.11", .d, "Bangunan", "Building", man), s("5.12", .d, "Area perkerasan", "Paved area", man),
            s("5.13", .d, "Reruntuhan", "Ruin", man), s("5.14", .d, "Pipa", "Pipeline", man),
            s("5.15", .d, "Menara", "Tower", man), s("5.16", .d, "Platform tembak", "Shooting platform", man),
            s("5.17", .d, "Tugu batas / cairn", "Boundary stone / cairn", man), s("5.18", .d, "Rak pakan", "Fodder rack", man),
            s("5.19", .d, "Bekas pembakaran arang", "Charcoal burning ground", man), s("5.20", .d, "Monumen / patung", "Monument / statue", man),
            s("5.21", .d, "Lorong bangunan", "Building pass through", man), s("5.22", .d, "Tangga", "Stairway", man),
            s("5.23", .d, "Tanggul / pembatas", "Barrier", man), s("5.24", .d, "Tempat sampah", "Rubbish bin", man),
            s("6.1", .d, "Objek khusus (x)", "Special item (x)", special), s("6.2", .d, "Objek khusus (o)", "Special item (o)", special),
        ]
    }()

    // Kolom E: penampakan.
    static let appearance: [IOFSymbol] = [
        s("8.1", .e, "rendah", "Low"), s("8.2", .e, "dangkal", "Shallow"), s("8.3", .e, "dalam", "Deep"),
        s("8.4", .e, "berumput / tertutup", "Overgrown"), s("8.5", .e, "terbuka", "Open"),
        s("8.6", .e, "berbatu", "Rocky / stony"), s("8.7", .e, "berawa", "Marshy"), s("8.8", .e, "berpasir", "Sandy"),
        s("8.9", .e, "berdaun jarum", "Needle leaved"), s("8.10", .e, "berdaun lebar", "Broad leaved"),
        s("8.11", .e, "runtuh / rusak", "Ruined / collapsed"),
    ]

    // Kolom F: kombinasi (dimensi diketik bebas).
    static let combinations: [IOFSymbol] = [
        s("10.1", .f, "persilangan", "Crossing"), s("10.2", .f, "pertemuan", "Junction"),
    ]

    // Kolom G: posisi bendera.
    static let locations: [IOFSymbol] = [
        s("11.1N", .g, "sisi utara", "North side"), s("11.1NE", .g, "sisi timur laut", "North-east side"),
        s("11.1E", .g, "sisi timur", "East side"), s("11.1SE", .g, "sisi tenggara", "South-east side"),
        s("11.1S", .g, "sisi selatan", "South side"), s("11.1SW", .g, "sisi barat daya", "South-west side"),
        s("11.1W", .g, "sisi barat", "West side"), s("11.1NW", .g, "sisi barat laut", "North-west side"),
        s("11.2", .g, "tepi atas", "Top edge"), s("11.3", .g, "bagian atas", "Upper part"),
        s("11.4", .g, "bagian bawah", "Lower part"), s("11.5", .g, "puncak", "Top"),
        s("11.6", .g, "di bawah", "Beneath"), s("11.7", .g, "kaki", "Foot"),
        s("11.8", .g, "sudut (dalam)", "Corner (inside)"), s("11.9", .g, "sudut (luar)", "Corner (outside)"),
        s("11.10", .g, "ujung", "Tip"), s("11.11", .g, "belokan", "Bend"),
        s("11.12", .g, "ujung akhir", "End"), s("11.13", .g, "bagian tengah", "Part"),
        s("11.14", .g, "awal", "Beginning"), s("11.15", .g, "di antara", "Between"),
    ]

    // Kolom H: info lain.
    static let other: [IOFSymbol] = [
        s("12.1", .h, "P3K", "First aid post"), s("12.2", .h, "pos minum", "Refreshment point"),
        s("12.3", .h, "pos radio / TV", "Radio / TV control"), s("12.4", .h, "pos dijaga", "Manned control"),
    ]
}
