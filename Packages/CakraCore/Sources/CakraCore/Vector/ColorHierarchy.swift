import Foundation

/// Color Hierarchy (OCAD Color Table / OOM color priority): colors higher in the color table are drawn
/// above colors below them, regardless of object order. E.g. in ISSprOM 2019-2: black (buildings, roads) above
/// blue, blue above brown, brown above green, green above yellow; a road's black edges below its white/40% brown
/// fill. Objects of the same color follow the object order (Layers panel).
public enum ColorHierarchy {
    /// Part of an object being drawn: the whole object, or a double line's edges/fill when they have their own color layers.
    public enum Part: Sendable, Equatable {
        case whole, casing, main
    }

    public struct Paint: Sendable, Equatable {
        public var index: Int
        public var part: Part
        public var priority: Int
    }

    /// Objects without a symbol (sketches) above all map colors; unknown symbols below everything
    /// (areas lowest, then lines, then points) so they don't cover colors whose order is known.
    static let sketchPriority = -1

    static func fallbackPriority(_ f: Feature) -> Int {
        if f.symbolCode == nil { return sketchPriority }
        switch f.kind {
        case .area: return 30_000
        case .line: return 20_000
        case .point: return 10_000
        }
    }

    /// Priority of the object's main color (0 = topmost). Points without symbol set data use their
    /// own elements' priority (from the OCAD file).
    public static func priority(of f: Feature) -> Int {
        if let p = f.colorPriority { return p }
        if f.kind == .point, f.symbolCode != nil, let top = f.pointElements?.map(\.priority).min() { return top }
        return fallbackPriority(f)
    }

    /// Drawing order (bottom → top): higher priority values first; equal priority = object order.
    /// Double lines whose edge color is on a different layer are split into edges and fill.
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
        // Stable: object order is preserved for equal priorities.
        return paints.enumerated()
            .sorted { a, b in a.element.priority != b.element.priority ? a.element.priority > b.element.priority : a.offset < b.offset }
            .map(\.element)
    }

    /// Object indices from topmost to bottommost (for selecting the object visible on top).
    public static func topDownIndices(_ features: [Feature]) -> [Int] {
        var seen = Set<Int>()
        return paintOrder(features).reversed().compactMap { seen.insert($0.index).inserted ? $0.index : nil }
    }
}

extension Array where Element == Feature {
    /// Copies of the objects with color priorities from the symbol set (`lookup` code + symbol name → symbol).
    public func withColorPriorities(_ lookup: (String, String?) -> MapSymbol?) -> [Feature] {
        var cache: [String: MapSymbol?] = [:]
        return map { f in
            guard let code = f.symbolCode else { return f }
            let key = code + "\u{1}" + (f.symbolName ?? "")
            let s: MapSymbol?
            if let hit = cache[key] { s = hit } else { s = lookup(code, f.symbolName); cache[key] = s }
            guard let s else { return f }
            var g = f
            if s.colorPriority != nil {
                g.colorPriority = s.colorPriority
                g.casingPriority = s.casingPriority
            }
            // Patterns / decorations belong to the symbol's standard look: areas get the pattern, lines the decoration.
            if f.kind == .area { g.patterns = s.kind == .area ? s.patterns : nil }
            if f.kind == .line { g.decoration = s.kind == .line ? s.decoration : nil }
            return g
        }
    }
}

// MARK: - One color order for all symbol sets

extension ColorHierarchy {
    /// The IOF color order of OCCA's own sets (index 0 = topmost), with each color's RGB.
    private static let iofOrder: [(r: Double, g: Double, b: Double)] = OccaStandardSymbols.colors().map { rgb($0.hex) }

    private static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = Int(h, radix: 16) ?? 0
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    /// Position of a color in the IOF order: the nearest OCCA color. Equal colors (white, green, purple appear more
    /// than once) resolve by symbol kind — areas take the lowest one (forest white, green screens), points and lines the
    /// highest (white masks, green point symbols).
    public static func iofPriority(hex: String, kind: MapSymbol.Kind) -> Int {
        let c = rgb(hex)
        var best = Int.max, bestD = Double.infinity
        for (i, o) in iofOrder.enumerated() {
            let d = (c.r - o.r) * (c.r - o.r) + (c.g - o.g) * (c.g - o.g) + (c.b - o.b) * (c.b - o.b)
            if d < bestD - 0.5 || (abs(d - bestD) <= 0.5 && kind == .area) { best = i; bestD = d }
        }
        return best
    }
}

extension MapSymbol {
    /// This symbol with its color priorities in the IOF order of OCCA's sets, so symbols from different sets (OCCA,
    /// OCAD, OOM) can be layered on one map: each set's own color table numbers can't be compared with another's.
    public func withIOFColorOrder() -> MapSymbol {
        var s = self
        let kind: MapSymbol.Kind = lineStyle?.casing != nil ? .line : self.kind
        s.colorPriority = ColorHierarchy.iofPriority(hex: lineStyle?.colorHex ?? colorHex, kind: kind)
        // Double-line edges take the lowest matching color (e.g. "Black (double-line edges)" below the fill colors),
        // so the fill shows between them.
        if let casing = lineStyle?.casing { s.casingPriority = ColorHierarchy.iofPriority(hex: casing.colorHex, kind: .area) }
        return s
    }
}
