import Foundation

/// Symbol guide: the IOF map specification pages on the omapwiki, opened next to the map as a drawing hint.
/// The page is searched for the symbol code (no per-symbol URLs are assumed, so it keeps working if the site changes).
public enum SymbolGuide {
    public enum Spec: String, CaseIterable, Identifiable, Sendable {
        case isom, issprom

        public var id: String { rawValue }
        public var label: String { self == .isom ? "ISOM 2017-2" : "ISSprOM 2019-2" }
        public var url: URL {
            URL(string: "https://omapwiki.orienteering.sport/specifications/\(rawValue)/")!
        }

        /// Sprint maps (1:5000 and larger scales, e.g. 1:4000) use ISSprOM; forest maps (1:7500, 1:10000, 1:15000) ISOM.
        public static func `for`(scaleDenominator: Int) -> Spec {
            scaleDenominator <= 5000 ? .issprom : .isom
        }
    }

    /// Texts to look for on the page, most specific first: "101.0" → ["101.0", "101"], "509.1" → ["509.1", "509"],
    /// "512.100" (OCAD numbering of the spec's 512.1) → ["512.100", "512.1", "512"]. The bare main number comes last,
    /// so OCCA's helper parts that have no entry of their own (101.1 slope line, 521.1 building outline, 709.1 boundary…)
    /// still open their main symbol.
    public static func searchTerms(for code: String) -> [String] {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return [] }
        var terms = [c]
        let parts = c.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 2, parts[1].count > 1, parts[1].allSatisfy(\.isNumber) {
            var frac = String(parts[1])
            while frac.count > 1, frac.hasSuffix("0") { frac.removeLast() }
            let short = "\(parts[0]).\(frac)"
            if short != c { terms.append(short) }
        }
        if let last = terms.last, last.hasSuffix(".0") { terms.append(String(last.dropLast(2))) }
        if parts.count == 2, let main = parts.first, !main.isEmpty, !terms.contains(String(main)) { terms.append(String(main)) }
        return terms
    }
}
