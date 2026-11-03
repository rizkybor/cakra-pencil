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

    public init(number: Int, name: String, kind: Kind, colorHex: String, lineWidthMM: Double?, isEnabled: Bool,
                pointElements: [PointElement]? = nil) {
        self.number = number
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.lineWidthMM = lineWidthMM
        self.isEnabled = isEnabled
        self.pointElements = pointElements
    }

    public var id: Int { number }
    public var code: String { "\(number / 1000).\(number % 1000)" }

    /// Garis (pen tool), area (pen tool/rectangle/ellipse), dan titik yang punya bentuk. Teks belum.
    public var isDrawable: Bool { kind == .line || kind == .area || (kind == .point && !(pointElements ?? []).isEmpty) }

    /// Tebal untuk menggambar: tebal simbol, atau 0,25 mm untuk simbol garis ganda / area.
    public var drawingWidthMM: Double { lineWidthMM ?? (kind == .area ? 0.1 : 0.25) }

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

    public init(id: UUID = UUID(), name: String, sourceFile: String, scale: Int, isEnabled: Bool = true, symbols: [MapSymbol]) {
        self.id = id
        self.name = name
        self.sourceFile = sourceFile
        self.scale = scale
        self.isEnabled = isEnabled
        self.symbols = symbols
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
                let color = elements.drawingOrder.last?.colorHex ?? colors[s.colorNumber] ?? "#000000"
                return MapSymbol(number: s.number, name: s.name.trimmingCharacters(in: .whitespaces), kind: kind,
                                 colorHex: color, lineWidthMM: s.lineWidthMM, isEnabled: true,
                                 pointElements: elements.isEmpty ? nil : elements)
            }
        return SymbolSet(name: name, sourceFile: sourceFile, scale: Int(scale), symbols: symbols)
    }
}
