import Foundation

/// Satu simbol peta (ISOM/ISSprOM/sekolah) dari set simbol OCAD.
public struct MapSymbol: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case point, line, area, text

        public var label: String {
            switch self {
            case .point: return "Titik"
            case .line: return "Garis"
            case .area: return "Area"
            case .text: return "Teks"
            }
        }
    }

    /// Nomor OCAD ×1000 (101000 = 101.0); unik dalam satu set.
    public var number: Int
    public var name: String
    public var kind: Kind
    public var colorHex: String
    /// Tebal garis utama di kertas (mm); nil untuk area/titik dan simbol garis ganda.
    public var lineWidthMM: Double?
    public var isEnabled: Bool
    /// Bentuk simbol titik (ukuran standar set, mm kertas); nil untuk garis/area.
    public var pointElements: [PointElement]?
    /// Gaya garis IOF (tunggal atau ganda) untuk simbol garis.
    public var lineStyle: LineStyle?

    public init(number: Int, name: String, kind: Kind, colorHex: String, lineWidthMM: Double?, isEnabled: Bool,
                pointElements: [PointElement]? = nil, lineStyle: LineStyle? = nil) {
        self.number = number
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.lineWidthMM = lineWidthMM
        self.isEnabled = isEnabled
        self.pointElements = pointElements
        self.lineStyle = lineStyle
    }

    public var id: Int { number }
    public var code: String { "\(number / 1000).\(number % 1000)" }

    /// Garis (pen tool), area (pen tool/rectangle/ellipse), dan titik yang punya bentuk. Teks belum.
    public var isDrawable: Bool { kind == .line || kind == .area || (kind == .point && !(pointElements ?? []).isEmpty) }

    /// Tebal standar IOF untuk menggambar: tebal garis tunggal, lebar total garis ganda, atau 0,1 mm untuk tepi area.
    public var drawingWidthMM: Double { lineStyle?.widthMM ?? lineWidthMM ?? (kind == .area ? 0.1 : 0.25) }

    /// Kelompok ISOM dari digit ratusan nomor simbol.
    public var category: SymbolCategory { SymbolCategory(rawValue: number / 100_000) ?? .other }
}

public enum SymbolCategory: Int, CaseIterable, Identifiable, Sendable {
    case landform = 1, rock, water, vegetation, manMade, technical, course
    case other = 0

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .landform: return "1 Bentuk lahan"
        case .rock: return "2 Batu & tebing"
        case .water: return "3 Air & rawa"
        case .vegetation: return "4 Vegetasi"
        case .manMade: return "5 Buatan manusia"
        case .technical: return "6 Teknis"
        case .course: return "7 Lintasan"
        case .other: return "Lainnya"
        }
    }
}

/// Set simbol yang diimpor dari file OCAD; disimpan di pustaka app dan dipakai lintas proyek.
public struct SymbolSet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var sourceFile: String
    public var scale: Int
    public var isEnabled: Bool
    public var symbols: [MapSymbol]
    /// Versi pembaca OCAD yang membuat set ini; set lama diperbarui/diimpor ulang agar dapat data terbaru.
    public var readerVersion: Int?

    /// 1 = simbol dasar, 2 = bentuk simbol titik, 3 = tebal garis IOF + garis ganda, 4 = putus-putus + ujung garis.
    public static let currentReaderVersion = 4

    public var isOutdated: Bool { (readerVersion ?? 0) < Self.currentReaderVersion }

    public init(id: UUID = UUID(), name: String, sourceFile: String, scale: Int, isEnabled: Bool = true, symbols: [MapSymbol]) {
        self.id = id
        self.name = name
        self.sourceFile = sourceFile
        self.scale = scale
        self.isEnabled = isEnabled
        self.symbols = symbols
        self.readerVersion = Self.currentReaderVersion
    }

    public var enabledCount: Int { symbols.filter(\.isEnabled).count }
}

extension OcadMap {
    /// Daftar simbol file ini sebagai set simbol, urut nomor. Semua simbol aktif secara default.
    public func symbolSet(name: String, sourceFile: String) -> SymbolSet {
        let symbols = self.symbols.values
            .sorted { $0.number < $1.number }
            .map { s -> MapSymbol in
                let kind: MapSymbol.Kind
                switch s.kind {
                case 1: kind = .point
                case 2: kind = .line
                case 3, 7: kind = .area
                default: kind = .text
                }
                let elements = kind == .point ? pointElements(of: s) : []
                let style = kind == .line ? lineStyle(of: s) : nil
                let color = elements.drawingOrder.last?.colorHex ?? style?.colorHex ?? colors[s.colorNumber] ?? "#000000"
                return MapSymbol(number: s.number, name: s.name.trimmingCharacters(in: .whitespaces), kind: kind,
                                 colorHex: color, lineWidthMM: s.lineWidthMM, isEnabled: true,
                                 pointElements: elements.isEmpty ? nil : elements, lineStyle: style)
            }
        return SymbolSet(name: name, sourceFile: sourceFile, scale: Int(scale), symbols: symbols)
    }
}

/// Gaya garis IOF. Garis ganda (jalan, setapak, rel): tepi `casing.colorHex` selebar `widthMM` di bawah,
/// isi `colorHex` selebar `casing.innerWidthMM` di atas, sehingga tampak dua garis tepi dengan isi di tengah.
public struct LineStyle: Codable, Hashable, Sendable {
    public struct Casing: Codable, Hashable, Sendable {
        public var colorHex: String
        public var innerWidthMM: Double
    }

    public var colorHex: String
    public var widthMM: Double
    public var casing: Casing?
    /// Pola putus-putus [garis, jeda] dalam mm kertas (nil = garis penuh). Untuk garis ganda berlaku pada tepinya.
    public var dashMM: [Double]?
    /// Ujung bulat (kontur, jalan setapak) atau rata/tajam (tembok, pagar, bangunan), seperti di OCAD.
    public var roundCaps: Bool?

    public init(colorHex: String, widthMM: Double, casing: Casing?, dashMM: [Double]? = nil, roundCaps: Bool? = nil) {
        self.colorHex = colorHex
        self.widthMM = widthMM
        self.casing = casing
        self.dashMM = dashMM
        self.roundCaps = roundCaps
    }
}
