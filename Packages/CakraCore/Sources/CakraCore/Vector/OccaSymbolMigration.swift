import Foundation

/// Brings objects drawn with an older version of OCCA's ISOM / ISSprOM sets up to date. Objects store their own colours,
/// line style and point shape (copied from the symbol when drawn), so a change to the sets — e.g. the Rev 4 colours of
/// "IOF Printing and Colour Definitions" (brown 25/75/100/0, green 80/0/100/0, olive 38/27/100/0…), renamed symbols, or
/// corrected shapes and dashes — does not reach them by itself. Run when a map is opened (idempotent: a second run
/// changes nothing).
///
/// Only objects whose symbol (same code and name) is one of OCCA's own symbols are touched, and only:
/// - colours that are OCCA's pre-Rev 4 colours (`OccaStandardSymbols.legacyHexes`) — custom colours stay;
/// - renamed symbols (old OCCA name → new name, per standard);
/// - line styles of symbols whose style changed (dashes, transparent double lines…), when the object still has its
///   symbol's standard width;
/// - point shapes, when all of the object's point colours are OCCA colours.
public enum OccaSymbolMigration {
    /// OCCA symbol names before the 2026-11 review → (code, name) now, per standard.
    static let renames: [MapStandard: [String: (code: String, name: String)]] = [
        .isom: [
            "526.0|Cairn, memorial or boundary stone": ("526.0", "Cairn"),
            "529.0|Prominent impassable line feature": ("529.0", "Prominent uncrossable line feature"),
            "511.0|Major power line, cableway or skilift": ("511.0", "Major power line"),
        ],
        .issprom: [
            "105.2|Retaining earth wall": ("105.2", "Retaining earth wall seen only from one side"),
            "506.0|Small unpaved footpath": ("506.0", "Small unpaved footpath or track"),
            // 104.1 is not an ISSprOM symbol (the 1.65 in the PDF is hidden text): such objects become 104 Earth bank.
            "104.1|Earth bank, very high": ("104.0", "Earth bank"),
        ],
    ]

    /// Line symbols whose stored style (width, dashes, double line) changed in the review.
    static let restyledLines: [MapStandard: Set<String>] = [
        .isom: ["106.0", "202.0", "215.0", "507.0", "511.0", "514.0", "517.0", "532.0"],
        .issprom: ["104.0", "507.0", "509.2", "511.0", "512.1", "532.0"],
    ]

    /// Code + name of every symbol in OCCA's own sets.
    static let occaSymbols: Set<String> = {
        Set((OccaStandardSymbols.isomFile().symbols + OccaStandardSymbols.issprFile().symbols + OccaStandardSymbols.isinomFile().symbols)
            .map { "\($0.code)|\($0.name)" })
    }()

    /// Updated objects, or nil when nothing changed. `lookup` = the map's symbol lookup (code, name → symbol, sized
    /// for the map), `standard` = the map's standard.
    public static func refreshed(_ features: [Feature], standard: MapStandard, lookup: (String, String?) -> MapSymbol?) -> [Feature]? {
        var changed = false
        let out = features.map { f -> Feature in
            guard let g = refreshed(f, standard: standard, lookup: lookup), g != f else { return f }
            changed = true
            return g
        }
        return changed ? out : nil
    }

    static func refreshed(_ f: Feature, standard: MapStandard, lookup: (String, String?) -> MapSymbol?) -> Feature? {
        guard var code = f.symbolCode else { return nil }
        var g = f
        // Renamed symbols.
        if let name = f.symbolName, let to = renames[standard]?["\(code)|\(name)"] {
            let oldPrefix = "\(code) \(name)"
            g.symbolCode = to.code
            g.symbolName = to.name
            if g.name.hasPrefix(oldPrefix) { g.name = "\(to.code) \(to.name)" + g.name.dropFirst(oldPrefix.count) }
            code = to.code
        }
        guard let s = lookup(code, g.symbolName), s.name == g.symbolName, occaSymbols.contains("\(s.code)|\(s.name)") else {
            return g == f ? nil : g
        }
        let legacy = OccaStandardSymbols.legacyHexes, occa = OccaStandardSymbols.occaHexes
        switch (f.kind, s.kind) {
        case (.line, .line):
            if let st = s.lineStyle {
                let standardWidth = g.standardWidthMM.map { abs($0 - g.widthMM) < 1e-6 } ?? true
                if restyledLines[standard]?.contains(s.code) == true, standardWidth,
                   g.dashMM != st.dashMM || g.innerDashMM != st.innerDashMM || g.casingColorHex != st.casing?.colorHex
                    || g.innerWidthMM != st.casing?.innerWidthMM || abs(g.widthMM - st.widthMM) > 1e-6 || g.roundCaps != st.roundCaps {
                    g.apply(st)
                }
                if legacy.contains(g.colorHex.uppercased()) { g.colorHex = st.colorHex }
                if let c = g.casingColorHex, legacy.contains(c.uppercased()) { g.casingColorHex = st.casing?.colorHex ?? c }
            }
        case (.area, .area), (.line, .area), (.area, .line):
            if legacy.contains(g.colorHex.uppercased()) { g.colorHex = s.lineStyle?.colorHex ?? s.colorHex }
        case (.point, .point):
            if let se = s.pointElements, let fe = g.pointElements, !se.isEmpty, fe != se,
               fe.allSatisfy({ occa.contains($0.colorHex.uppercased()) }) {
                g.pointElements = se
                g.colorHex = se.drawingOrder.last?.colorHex ?? g.colorHex
                g.widthMM = se.diameterMM * g.effectiveSizeFactor
            }
        default:
            break
        }
        return g == f ? nil : g
    }
}
