import Foundation

/// Which symbol set a map prefers (the Symbols panel's default set and the set an object's symbol is looked up in), for
/// the map's scale and IOF standard (`SheetSpec.mapStandard`). On an indoor map (ISInOM) OCCA's ISInOM set comes first,
/// so symbols that ISInOM shares with ISSprOM by code and name (301, 302, 516, 518, 520, 701–715) draw with the ISInOM
/// definitions instead of ISSprOM's enlarged × 5.7 at 1:700.
public enum SymbolSetPreference {
    /// Rank of a set (lower = preferred): OCCA's own set of the map's standard, then sets of the same scale, then sets of
    /// the same standard, then others; course design sets after map sets.
    public static func tier(_ set: SymbolSet, isOcca: Bool, scale: Int, standard: MapStandard) -> Int {
        let base = isOcca && set.standard == standard ? 0 : set.scale == scale ? 1 : (set.standard == standard ? 2 : 3)
        return base + (set.isCourseDesign ? 4 : 0)
    }

    /// `sets` best first (stable within a tier), each sized for the map scale.
    public static func ordered(_ sets: [SymbolSet], isOcca: (SymbolSet) -> Bool, scale: Int, standard: MapStandard) -> [SymbolSet] {
        let tiers = sets.map { tier($0, isOcca: isOcca($0), scale: scale, standard: standard) }
        return sets.indices
            .sorted { tiers[$0] != tiers[$1] ? tiers[$0] < tiers[$1] : $0 < $1 }
            .map { sets[$0].scaled(by: sets[$0].sizeFactor(forMapScale: scale)) }
    }

    public static func ordered(_ sets: [SymbolSet], isOcca: (SymbolSet) -> Bool, sheet: SheetSpec) -> [SymbolSet] {
        ordered(sets, isOcca: isOcca, scale: sheet.scaleDenominator, standard: sheet.mapStandard)
    }

    /// An object's symbol among `ordered` sets: same code and name first (an object drawn with another set whose code
    /// means something else keeps its own symbol), else the best set's symbol with that code.
    public static func symbol(code: String, name: String?, in ordered: [SymbolSet]) -> MapSymbol? {
        let candidates = ordered.flatMap { $0.symbols.filter { $0.code == code } }
        if let name, let hit = candidates.first(where: { $0.name == name }) { return hit }
        return candidates.first
    }
}
