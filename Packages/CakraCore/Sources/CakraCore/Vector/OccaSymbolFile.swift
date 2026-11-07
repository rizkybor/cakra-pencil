import Foundation

/// OCCA symbol set file (`.occasym`): JSON with the set's metadata, its color table (CMYK + screen tint, top → bottom =
/// drawing order), and its symbols (`MapSymbol`, including each symbol's enabled state). Written by OCCA for the
/// built-in ISOM 2017-2 / ISSprOM 2019-2 sets and when a user exports a set; read on import.
public struct OccaSymbolFile: Codable, Sendable {
    public static let fileExtension = "occasym"
    public static let formatName = "OCCA symbol set"
    public static let currentVersion = 1

    /// A printing color: CMYK (0–1) of the full color and the screen percentage (1 = 100 %).
    public struct Color: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var cmyk: [Double]
        public var tint: Double

        public init(id: String, name: String, cmyk: [Double], tint: Double = 1) {
            self.id = id
            self.name = name
            self.cmyk = cmyk
            self.tint = tint
        }

        /// Screen color: CMYK → RGB, then the tint mixed with white paper.
        public var hex: String {
            let c = cmyk + [0, 0, 0, 0]
            func ch(_ x: Double) -> Int {
                let full = (1 - min(max(x, 0), 1)) * (1 - min(max(c[3], 0), 1))
                return Int(((1 - tint) + tint * full) * 255 + 0.5)
            }
            return String(format: "#%02X%02X%02X", ch(c[0]), ch(c[1]), ch(c[2]))
        }
    }

    public var format: String
    public var formatVersion: Int
    public var name: String
    /// "ISOM 2017-2", "ISSprOM 2019-2", or free text for custom sets.
    public var standard: String
    public var specification: String
    /// Scale the sizes are for (paper mm at 1:scale).
    public var scale: Int
    public var author: String
    public var license: String
    public var notes: String
    public var colors: [Color]
    public var symbols: [MapSymbol]

    public init(name: String, standard: String, specification: String, scale: Int, author: String, license: String,
                notes: String = "", colors: [Color], symbols: [MapSymbol]) {
        self.format = Self.formatName
        self.formatVersion = Self.currentVersion
        self.name = name
        self.standard = standard
        self.specification = specification
        self.scale = scale
        self.author = author
        self.license = license
        self.notes = notes
        self.colors = colors
        self.symbols = symbols
    }

    public enum ReadError: LocalizedError {
        case notASymbolFile, newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .notASymbolFile: return "This is not an OCCA symbol set (.occasym) file."
            case let .newerVersion(v): return "This symbol set was made with a newer OCCA (format \(v)). Update OCCA to open it."
            }
        }
    }

    public static func read(_ data: Data) throws -> OccaSymbolFile {
        guard let file = try? JSONDecoder().decode(OccaSymbolFile.self, from: data), file.format == formatName else {
            throw ReadError.notASymbolFile
        }
        guard file.formatVersion <= currentVersion else { throw ReadError.newerVersion(file.formatVersion) }
        return file
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    /// The set for the library (each symbol keeps its enabled state).
    public func symbolSet(sourceFile: String, name: String? = nil) -> SymbolSet {
        SymbolSet(name: name ?? self.name, sourceFile: sourceFile, scale: scale, symbols: symbols)
    }
}

extension SymbolSet {
    /// Export as an `.occasym` file. The color table is rebuilt from the symbols' colors in color order (sets read
    /// from OCAD / OOM files don't keep CMYK, so those colors are stored as RGB-derived CMYK).
    public func occaSymbolFile(author: String, license: String, notes: String = "") -> OccaSymbolFile {
        var seen: [String: Int] = [:]
        for s in symbols {
            let p = s.colorPriority ?? Int.max
            if seen[s.colorHex].map({ p < $0 }) ?? true { seen[s.colorHex] = p }
        }
        let colors = seen.sorted { $0.value < $1.value }.enumerated().map { i, entry -> OccaSymbolFile.Color in
            OccaSymbolFile.Color(id: "c\(i)", name: entry.key, cmyk: Self.cmyk(fromHex: entry.key))
        }
        return OccaSymbolFile(name: name, standard: standard?.label ?? "", specification: "", scale: scale,
                              author: author, license: license, notes: notes, colors: colors, symbols: symbols)
    }

    static func cmyk(fromHex hex: String) -> [Double] {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = Int(h, radix: 16) else { return [0, 0, 0, 1] }
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        let k = 1 - max(r, g, b)
        guard k < 1 else { return [0, 0, 0, 1] }
        func r3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
        return [r3((1 - r - k) / (1 - k)), r3((1 - g - k) / (1 - k)), r3((1 - b - k) / (1 - k)), r3(k)]
    }
}
