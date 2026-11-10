import Foundation

/// Color Hierarchy (OCAD Color Table / OOM color priority): colors higher in the color table are drawn
/// above colors below them, regardless of object order. E.g. in ISSprOM 2019-2: black (buildings, roads) above
/// blue, blue above brown, brown above green, green above yellow; a road's black edges below its white/40% brown
/// fill. Objects of the same color follow the object order (Layers panel).
public enum ColorHierarchy {
    /// Part of an object being drawn: the whole object, or a double line's edges/fill when they have their own color layers.
    public enum Part: Sendable, Equatable {
        case whole, casing, main
        /// The elements of a point symbol with this color priority (e.g. 417: the green ring at "green 100 % point
        /// symbols", its white mask at "white over green and brown"), so a mask only covers the colors below its own.
        case elements(Int)
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
            } else if f.kind == .point, f.colorPriority != nil, let levels = f.pointElements.map({ Set($0.map(\.priority)) }), levels.count > 1 {
                // Point symbols painted per element at each element's own color level (its set's color table).
                for p in levels.sorted(by: >) { paints.append(Paint(index: i, part: .elements(p), priority: p)) }
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
            // Point elements: the color levels of the symbol's elements (same shape), so each element is painted at its
            // own level in the same color table as the other objects.
            if f.kind == .point, let se = s.pointElements, var fe = g.pointElements, se.count == fe.count {
                for k in fe.indices { fe[k].priority = se[k].priority }
                g.pointElements = fe
            }
            return g
        }
    }
}

// MARK: - One color order for all symbol sets

extension ColorHierarchy {
    private struct OrderEntry {
        let priority: Int
        let rgb: (r: Double, g: Double, b: Double)
        let match: Set<MapSymbol.Kind>
        let edge: Bool
    }

    /// The IOF color order (Rev 4 table) of a standard; nil = ISOM and ISSprOM together. ISInOM: its own table.
    private static func order(_ standard: MapStandard?) -> [OrderEntry] {
        switch standard {
        case .isinom?: return isinomOrder
        case .isom?: return isomOrder
        case .issprom?: return sprintOrder
        case nil: return bothOrder
        }
    }

    private static func rows(_ keep: (OccaStandardSymbols.IOFColorRow) -> Bool) -> [OrderEntry] {
        OccaStandardSymbols.colorRows.enumerated().filter { keep($0.element) }.map {
            OrderEntry(priority: $0.offset, rgb: rgb($0.element.hex), match: $0.element.match, edge: $0.element.edge)
        }
    }

    private static let isomOrder = rows { $0.isom }
    private static let sprintOrder = rows { $0.sprint }
    private static let bothOrder = rows { _ in true }
    private static let isinomOrder: [OrderEntry] = OccaStandardSymbols.isinomColors().enumerated().map {
        OrderEntry(priority: $0.offset, rgb: rgb($0.element.hex), match: [.point, .line, .area, .text], edge: false)
    }

    private static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = Int(h, radix: 16) ?? 0
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    /// Position of a color in the IOF order of `standard` (nil = ISOM + ISSprOM): the nearest OCCA color. Colors with
    /// several roles (blue point / line / area, brown point / line, the whites, purple upper / lower…) resolve by symbol
    /// kind — e.g. a blue area takes "Blue 100 % area symbols", a white area the paper white at the bottom, a white point
    /// element "White over green and brown" (masks). `edge`: a double line's edge color (black → "Black 100 % for road
    /// outline", above the screens). Colors only used for patterns or special whites (cultivated black, white over
    /// yellow, white stripes) are not matched. ISInOM: its own table, equal colors → areas the lowest, others the highest.
    public static func iofPriority(hex: String, kind: MapSymbol.Kind, standard: MapStandard? = nil, edge: Bool = false) -> Int {
        let c = rgb(hex)
        let table = order(standard)
        func dist(_ o: OrderEntry) -> Double { (c.r - o.rgb.r) * (c.r - o.rgb.r) + (c.g - o.rgb.g) * (c.g - o.rgb.g) + (c.b - o.rgb.b) * (c.b - o.rgb.b) }
        if standard == .isinom {
            var best = Int.max, bestD = Double.infinity
            for o in table {
                let d = dist(o)
                if d < bestD - 0.5 || (abs(d - bestD) <= 0.5 && kind == .area) { best = o.priority; bestD = d }
            }
            return best
        }
        let candidates = table.filter { edge ? ($0.edge || !$0.match.isEmpty) : !$0.match.isEmpty }
        guard let bestD = candidates.map(dist).min() else { return Int.max }
        let near = candidates.filter { dist($0) <= bestD + 0.5 }
        if edge, let e = near.first(where: \.edge) { return e.priority }
        return (near.first { $0.match.contains(kind) } ?? near[0]).priority
    }

    /// Color levels of the course overprint in the color order: upper purple on top, lower purple below black, blue and
    /// brown 100 % ("IOF Printing and Colour Definitions" Rev 4 §4 and p.6). ISOM and ISSprOM share the numbering.
    public static func lowerPurplePriority(for standard: MapStandard = .isom) -> Int {
        standard == .isinom ? OccaStandardSymbols.isinomColors().firstIndex { $0.id == "n52" }! : OccaStandardSymbols.colorRow("purpleLower")
    }

    public static func upperPurplePriority(for standard: MapStandard = .isom) -> Int {
        standard == .isinom ? OccaStandardSymbols.isinomColors().firstIndex { $0.id == "n50" }! : OccaStandardSymbols.colorRow("purpleUpper")
    }
}

extension MapSymbol {
    /// This symbol with its color priorities in the IOF order of OCCA's sets, so symbols from different sets (OCCA,
    /// OCAD, OOM) can be layered on one map: each set's own color table numbers can't be compared with another's.
    /// `standard` = the map's standard (nil: ISOM and ISSprOM rows together). Areas drawn only by a pattern take the
    /// level of their pattern color (marsh lines at blue, boulder fields at black…), not white at the bottom; point
    /// elements each get their own level.
    public func withIOFColorOrder(standard: MapStandard? = nil) -> MapSymbol {
        var s = self
        let kind: MapSymbol.Kind = lineStyle?.casing != nil ? .line : self.kind
        if self.kind == .area, SymbolOrnaments.isPatternOnly(fillHex: colorHex, patterns: patterns), let p = patterns?.first {
            // A white pattern (holes, stripes) has no level of its own: keep the area level.
            let white = p.colorHex.uppercased() == "#FFFFFF"
            s.colorPriority = ColorHierarchy.iofPriority(hex: white ? colorHex : p.colorHex, kind: .area, standard: standard)
        } else {
            s.colorPriority = ColorHierarchy.iofPriority(hex: lineStyle?.colorHex ?? colorHex, kind: kind, standard: standard)
        }
        // Double-line edges: the road outline color (above the screens, below the road infill), so the fill shows
        // between them.
        if let casing = lineStyle?.casing { s.casingPriority = ColorHierarchy.iofPriority(hex: casing.colorHex, kind: .line, standard: standard, edge: true) }
        s.pointElements = pointElements?.map { e in
            var e = e
            e.priority = ColorHierarchy.iofPriority(hex: e.colorHex, kind: .point, standard: standard)
            return e
        }
        if self.kind == .point, let top = s.pointElements?.map(\.priority).min() { s.colorPriority = top }
        return s
    }
}
