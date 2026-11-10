import Foundation

/// OCCA's own ISOM 2017-2 and ISSprOM 2019-2 symbol sets, written from the IOF specifications (Revision 6,
/// January 2024): symbol codes, names, sizes (paper mm at the base scale), colors, and color order. Saved as the
/// built-in `.occasym` files (see `OccaSymbolFile`); regenerate them with the `OccaStandardSymbolsTests` generator.
///
/// Sources (2026-11 review): ISOM 2017-2 Rev 6 (precise definitions p.39–40), ISSprOM 2019-2 Rev 6 (p.30–31) and "IOF
/// Printing and Colour Definitions" Rev 4 (colour table p.6). Drawn by `SymbolOrnaments` (patterns, decorations),
/// `PointSymbolRenderer` and the exporters. Values that the PDFs only show in figures are marked "figure-based":
/// 511 bars, 532 step spacing, 710.2 turned-out ends, ISSprOM 208 density (ISOM's at 120 %), 509.2 "0.3" taken as CC.
/// Re-check these first when the IOF publishes a new revision, then regenerate the `.occasym` files and bump
/// `OccaSymbolMigration` if names or styles change.
public enum OccaStandardSymbols {
    public static let author = "OCCA — Rizky Ajie Kurniawan"
    public static let license = "© 2026 Rizky Ajie Kurniawan. Part of OCCA. Symbol definitions follow the IOF specifications ISOM 2017-2 and ISSprOM 2019-2."

    // MARK: Colors (top → bottom = drawing order)

    /// A row of the IOF colour table ("IOF Printing and Colour Definitions", Revision 4, Sept 2024, p.6): name, CMYK
    /// (0–100) and the standards using it. The table is one list for all IOF standards, each standard using a subset
    /// in the same order, so ISOM and ISSprOM objects can share one numbering: a symbol's `colorPriority` is its
    /// colour's row here (0 = topmost). `match` = the symbol kinds a colour of another set (OCAD, OOM) is matched to by
    /// `ColorHierarchy.iofPriority` when several rows share its RGB.
    public struct IOFColorRow: Sendable {
        public let id: String
        public let name: String
        public let cmyk: [Double]
        public let isom: Bool
        public let sprint: Bool
        let match: Set<MapSymbol.Kind>
        /// Rows matched only as double-line edges (road outline).
        let edge: Bool

        init(_ id: String, _ name: String, _ cmyk: [Double], _ standards: String, match: Set<MapSymbol.Kind>, edge: Bool = false) {
            self.id = id
            self.name = name
            self.cmyk = cmyk
            self.isom = standards.contains("I")
            self.sprint = standards.contains("S")
            self.match = match
            self.edge = edge
        }

        /// CMYK 0–1.
        public var cmyk01: [Double] { cmyk.map { $0 / 100 } }
        public var hex: String { OccaSymbolFile.Color(id: id, name: name, cmyk: cmyk01).hex }
        public func uses(_ standard: MapStandard) -> Bool { standard == .isom ? isom : sprint }
    }

    /// The Rev 4 table rows for ISOM 2017-2 (I) and ISSprOM 2019-2 (S), top → bottom. Rows marked "OCCA" are not in
    /// the table: white for point symbols (418's centre dot, 203.2's centre; ISInOM has the same row), yellow 75 % in
    /// ISSprOM (401.1 is allowed by ISSprOM 401 but the table omits it) and paper white for 405 forest.
    public static let colorRows: [IOFColorRow] = {
        typealias R = IOFColorRow
        let P: Set<MapSymbol.Kind> = [.point], L: Set<MapSymbol.Kind> = [.line], A: Set<MapSymbol.Kind> = [.area]
        let all: Set<MapSymbol.Kind> = [.point, .line, .area, .text]
        return [
            R("purpleUpper", "Upper purple for course overprint", [35, 85, 0, 0], "IS", match: A),
            R("whiteCourse", "White for course overprint", [0, 0, 0, 0], "S", match: []),
            R("purple50", "Purple 50% area symbol", [18, 43, 0, 0], "S", match: all),
            R("whiteRailroad", "White for railroad", [0, 0, 0, 0], "IS", match: L),
            R("black", "Black 100%", [0, 0, 0, 100], "IS", match: all),
            R("bluePoint", "Blue 100% point symbols", [100, 0, 0, 0], "I", match: P),
            R("brownPoint", "Brown 100% point symbols", [25, 75, 100, 0], "I", match: P),
            R("whitePoint", "White for point symbols (OCCA)", [0, 0, 0, 0], "IS", match: []),
            R("greenPoint", "Green 100% point symbols", [80, 0, 100, 0], "IS", match: [.point, .line]),
            R("blueLine", "Blue 100% line symbols", [100, 0, 0, 0], "I", match: L),
            R("darkGreenEdge", "Dark green for forest edges", [100, 0, 80, 30], "I", match: all),
            R("brownLine", "Brown 100% line symbols", [25, 75, 100, 0], "I", match: [.line, .area, .text]),
            R("purpleLower", "Lower purple for course overprint", [35, 85, 0, 0], "IS", match: [.point, .line, .text]),
            R("darkGreenLine", "Dark green line symbols", [100, 0, 80, 30], "S", match: [.point, .line]),
            R("bluePointLine", "Blue 100% point and line symbols", [100, 0, 0, 0], "S", match: [.point, .line]),
            R("brown", "Brown 100%", [25, 75, 100, 0], "S", match: all),
            R("whiteStripes", "White stripes for area passable at two levels", [0, 0, 0, 0], "S", match: []),
            R("brown50Road", "Brown 50% for road infill", [10, 35, 50, 0], "IS", match: L),
            R("brown30Road", "Brown 30% for road infill", [6, 23, 33, 0], "S", match: L),
            R("blackRoadOutline", "Black 100% for road outline", [0, 0, 0, 100], "IS", match: [], edge: true),
            R("black50", "Black 50% for large buildings", [0, 0, 0, 50], "IS", match: all),
            R("black20", "Black 20% for canopy", [0, 0, 0, 20], "IS", match: all),
            R("blue", "Blue 100% area symbols", [100, 0, 0, 0], "IS", match: A),
            R("blue70", "Blue 70% area symbols", [70, 0, 0, 0], "IS", match: all),
            R("blue50", "Blue 50% area symbols", [50, 0, 0, 0], "IS", match: all),
            R("blue30", "Blue 30% area symbols", [30, 0, 0, 0], "S", match: all),
            R("whiteOverGreen", "White over green and brown", [0, 0, 0, 0], "IS", match: P),
            R("brown50Paved", "Brown 50% for paved area", [10, 35, 50, 0], "IS", match: A),
            R("brown30Paved", "Brown 30% for paved area", [6, 23, 33, 0], "S", match: A),
            R("olive", "Olive green", [38, 27, 100, 0], "IS", match: all),
            R("darkGreenArea", "Dark green area symbols", [100, 0, 80, 30], "S", match: A),
            R("green100", "Green 100% area symbols", [80, 0, 100, 0], "IS", match: A),
            R("green60", "Green 60% area symbols", [48, 0, 60, 0], "IS", match: all),
            R("green30", "Green 30% area symbols", [24, 0, 30, 0], "IS", match: all),
            R("black35", "Black 35% area symbols", [0, 0, 0, 35], "IS", match: all),
            R("whiteOverYellow", "White over yellow", [0, 0, 0, 0], "IS", match: []),
            R("blackCultivated", "Black for cultivated land and sandy ground", [0, 0, 0, 100], "IS", match: []),
            R("yellow100", "Yellow 100% area symbols", [0, 27, 79, 0], "IS", match: all),
            R("yellow75", "Yellow 75% area symbols", [0, 20, 59, 0], "IS", match: all),
            R("yellow50", "Yellow 50% area symbols", [0, 14, 40, 0], "IS", match: all),
            R("white", "White (paper, forest; OCCA)", [0, 0, 0, 0], "IS", match: A),
        ]
    }()

    /// Row of a colour id in `colorRows` (the colour priority of OCCA's ISOM / ISSprOM symbols).
    public static func colorRow(_ id: String) -> Int { colorRows.firstIndex { $0.id == id }! }

    /// The colour table of one standard (Rev 4 rows with its tick, top → bottom).
    public static func colors(for standard: MapStandard) -> [OccaSymbolFile.Color] {
        colorRows.filter { $0.uses(standard == .isinom ? .issprom : standard) }
            .map { OccaSymbolFile.Color(id: $0.id, name: $0.name, cmyk: $0.cmyk01) }
    }

    /// All rows (both standards), for code that needs any OCCA ISOM / ISSprOM colour by id.
    static func colors() -> [OccaSymbolFile.Color] { colorRows.map { OccaSymbolFile.Color(id: $0.id, name: $0.name, cmyk: $0.cmyk01) } }

    /// Spec CMYK (0–1, screens included) of a colour OCCA's sets draw with, by its screen hex: the Rev 4 table and the
    /// ISInOM table. nil = not an OCCA colour (sketch, custom or another set's colour).
    public static func cmyk(forHex hex: String) -> [Double]? { cmykByHex[hex.uppercased()] }

    private static let cmykByHex: [String: [Double]] = {
        var map: [String: [Double]] = [:]
        for c in colors() + isinomColors() where map[c.hex] == nil { map[c.hex] = c.cmyk.map { $0 * c.tint } }
        return map
    }()

    /// Screen hexes of OCCA's colour tables before Rev 4 (old brown 0/56/100/18 and its 50 / 30 % screens, green
    /// 76/0/91/0 with 60 / 30 % screens, olive 38/27/85/0, purple 50 % and yellow 75 % as screens), that no current OCCA
    /// colour has: objects still carrying one of these get their symbol's new colour (see `OccaSymbolMigration`).
    public static let legacyHexes: Set<String> = {
        let old: [([Double], Double)] = [([0, 0.56, 1, 0.18], 1), ([0, 0.56, 1, 0.18], 0.5), ([0, 0.56, 1, 0.18], 0.3),
                                         ([0.76, 0, 0.91, 0], 1), ([0.76, 0, 0.91, 0], 0.6), ([0.76, 0, 0.91, 0], 0.3),
                                         ([0.38, 0.27, 0.85, 0], 1), ([0.35, 0.85, 0, 0], 0.5), ([0, 0.27, 0.79, 0], 0.75),
                                         ([0, 0.27, 0.79, 0], 0.5)]
        let current = Set(cmykByHex.keys)
        return Set(old.map { OccaSymbolFile.Color(id: "", name: "", cmyk: $0.0, tint: $0.1).hex }).subtracting(current)
    }()

    /// Every hex an OCCA ISOM / ISSprOM / ISInOM symbol uses now or used before Rev 4.
    public static var occaHexes: Set<String> { legacyHexes.union(cmykByHex.keys) }

    // MARK: Files

    public static func isomFile() -> OccaSymbolFile {
        var b = Builder(colors: colors(for: .isom), priorities: colorRow)
        isom(&b)
        return OccaSymbolFile(name: "ISOM 2017-2 · OCCA", standard: "ISOM 2017-2",
                              specification: "IOF International Specification for Orienteering Maps ISOM 2017-2, Revision 6, January 2024",
                              scale: 15000, author: author, license: license,
                              notes: "Sizes at 1:15000; OCCA enlarges them to 150 % on 1:10000 maps.",
                              colors: b.colors, symbols: b.symbols.sorted { $0.number < $1.number })
    }

    public static func issprFile() -> OccaSymbolFile {
        var b = Builder(colors: colors(for: .issprom), priorities: colorRow)
        issprom(&b)
        return OccaSymbolFile(name: "ISSprOM 2019-2 · OCCA", standard: "ISSprOM 2019-2",
                              specification: "IOF International Specification for Sprint Orienteering Maps ISSprOM 2019-2, Revision 6, January 2024",
                              scale: 4000, author: author, license: license,
                              notes: "Sizes at 1:4000; OCCA enlarges them to 133 % on 1:3000 maps.",
                              colors: b.colors, symbols: b.symbols.sorted { $0.number < $1.number })
    }

    /// Bundle file names of the built-in sets.
    public static let isomFileName = "OCCA ISOM 2017-2.occasym"
    public static let issprFileName = "OCCA ISSprOM 2019-2.occasym"

    // MARK: Builder

    struct Builder {
        let colors: [OccaSymbolFile.Color]
        var symbols: [MapSymbol] = []
        /// Colour priority of a colour id; nil = its index in `colors` (ISInOM).
        let priorities: ((String) -> Int)?

        init(colors: [OccaSymbolFile.Color], priorities: ((String) -> Int)? = nil) {
            self.colors = colors
            self.priorities = priorities
        }

        func hex(_ id: String) -> String {
            guard let c = colors.first(where: { $0.id == id }) else { preconditionFailure("colour \(id) not in this standard's table") }
            return c.hex
        }
        func prio(_ id: String) -> Int {
            precondition(colors.contains { $0.id == id }, "colour \(id) not in this standard's table")
            return priorities?(id) ?? colors.firstIndex { $0.id == id }!
        }

        static func number(_ code: String) -> Int {
            let p = code.split(separator: ".")
            return Int(p[0])! * 1000 + (p.count > 1 ? Int(p[1])! : 0)
        }

        private mutating func add(_ s: MapSymbol) {
            precondition(!symbols.contains { $0.number == s.number }, "duplicate \(s.code)")
            symbols.append(s)
        }

        mutating func line(_ code: String, _ name: String, _ color: String, _ w: Double, dash: [Double]? = nil,
                           round: Bool = false, deco: LineDecoration? = nil) {
            var s = MapSymbol(number: Self.number(code), name: name, kind: .line, colorHex: hex(color), lineWidthMM: w, isEnabled: true,
                              lineStyle: LineStyle(colorHex: hex(color), widthMM: w, casing: nil, dashMM: dash, roundCaps: round))
            s.colorPriority = prio(color)
            s.decoration = deco
            add(s)
        }

        /// Dotted line: dots of `d` every `cc` (round-capped tiny dashes).
        mutating func dotted(_ code: String, _ name: String, _ color: String, _ d: Double, _ cc: Double) {
            line(code, name, color, d, dash: [0.01, ((cc - 0.01) * 1000).rounded() / 1000], round: true)
        }

        /// Double line: two `edge`-wide edges with `inner` (inside measure) between them, filled with `fill`. The edges
        /// get their own colour level (`edgeColor`, e.g. "Black 100 % for road outline" below the road infill).
        mutating func double(_ code: String, _ name: String, edgeColor: String, edge: Double, inner: Double,
                             fill: String, edgeDash: [Double]? = nil, innerDash: [Double]? = nil) {
            let total = ((inner + 2 * edge) * 1000).rounded() / 1000
            var s = MapSymbol(number: Self.number(code), name: name, kind: .line, colorHex: hex(fill), lineWidthMM: nil, isEnabled: true,
                              lineStyle: LineStyle(colorHex: hex(fill), widthMM: total,
                                                   casing: LineStyle.Casing(colorHex: hex(edgeColor), innerWidthMM: inner),
                                                   dashMM: edgeDash, innerDashMM: innerDash, roundCaps: false))
            s.colorPriority = prio(fill)
            s.casingPriority = prio(edgeColor)
            add(s)
        }

        /// Double line with a transparent inside (215, 509.2, 511, 532, 710.2): two `edge`-wide lines `cc` apart centre
        /// to centre, drawn as a decoration (the main line, `cc + edge` wide for selection, is not stroked).
        mutating func edges(_ code: String, _ name: String, _ color: String, edge: Double, cc: Double, more: [LineDecoration]? = nil) {
            let total = ((cc + edge) * 1000).rounded() / 1000
            line(code, name, color, total, deco: LineDecoration(kind: .edges, sizeMM: cc, widthMM: edge, spacingMM: 0, hidesLine: true, more: more))
        }

        /// Area with a solid fill (`color`), optional patterns. Areas defined only by a pattern (`patternOnly`, white
        /// "fill") draw just the pattern, so what lies below stays visible; they are drawn at the colour level of their
        /// pattern (`level`, e.g. marsh at "Blue 100 % area symbols"), not at the paper white at the bottom.
        mutating func area(_ code: String, _ name: String, _ color: String, patterns: [AreaPattern]? = nil, patternOnly: Bool = false,
                           level: String? = nil) {
            precondition(!patternOnly || level != nil, "\(code): pattern-only areas need the level of their pattern colour")
            var s = MapSymbol(number: Self.number(code), name: name, kind: .area, colorHex: hex(color), lineWidthMM: nil, isEnabled: true)
            s.colorPriority = prio(level ?? color)
            s.patterns = patterns
            add(s)
        }

        func pattern(_ kind: AreaPattern.Kind, _ color: String, size: Double, cc: Double, angle: Double = 0, dash: [Double]? = nil,
                     staggered: Bool? = nil, random: Bool? = nil, sides: [Double]? = nil, jitter: Double? = nil) -> AreaPattern {
            AreaPattern(kind: kind, colorHex: hex(color), sizeMM: size, spacingMM: cc, angleDeg: angle, dashMM: dash, staggered: staggered,
                        random: random, sidesMM: sides, jitterMM: jitter)
        }

        /// Random dots / triangles: cell size for `perMM2` marks per mm².
        static func cell(perMM2 d: Double) -> Double { ((1 / d.squareRoot()) * 1000).rounded() / 1000 }

        mutating func point(_ code: String, _ name: String, _ elements: [PointElement]) {
            let top = elements.drawingOrder.last!
            var s = MapSymbol(number: Self.number(code), name: name, kind: .point, colorHex: top.colorHex, lineWidthMM: nil,
                              isEnabled: true, pointElements: elements)
            s.colorPriority = elements.map(\.priority).min()
            add(s)
        }

        mutating func text(_ code: String, _ name: String, _ color: String, height: Double? = nil) {
            var s = MapSymbol(number: Self.number(code), name: name, kind: .text, colorHex: hex(color), lineWidthMM: nil, isEnabled: true)
            s.colorPriority = prio(color)
            s.textSizeMM = height
            add(s)
        }

        // Point elements (paper mm, y up, centred on the symbol position = its centre of gravity).

        func dot(_ d: Double, _ color: String, at p: Point2D = Point2D(x: 0, y: 0)) -> PointElement {
            PointElement(kind: .dot, colorHex: hex(color), priority: prio(color), lineWidthMM: 0, diameterMM: d, points: [p])
        }

        /// Ring of outside measure `om` and line width `lw`.
        func ring(_ om: Double, _ lw: Double, _ color: String, at p: Point2D = Point2D(x: 0, y: 0)) -> PointElement {
            PointElement(kind: .circle, colorHex: hex(color), priority: prio(color), lineWidthMM: lw, diameterMM: om - lw, points: [p])
        }

        /// Circle with centre-line diameter `cc`.
        func circleCC(_ cc: Double, _ lw: Double, _ color: String) -> PointElement {
            PointElement(kind: .circle, colorHex: hex(color), priority: prio(color), lineWidthMM: lw, diameterMM: cc, points: [Point2D(x: 0, y: 0)])
        }

        /// Polyline; `flat`: flat ends and mitred corners (as drawn in the IOF precise definitions).
        func lines(_ pts: [(Double, Double)], _ lw: Double, _ color: String, flat: Bool = false) -> PointElement {
            PointElement(kind: .line, colorHex: hex(color), priority: prio(color), lineWidthMM: lw, diameterMM: 0,
                         points: pts.map { Point2D(x: $0.0, y: $0.1) }, flatEnds: flat ? true : nil)
        }

        func fill(_ pts: [(Double, Double)], _ color: String) -> PointElement {
            PointElement(kind: .area, colorHex: hex(color), priority: prio(color), lineWidthMM: 0, diameterMM: 0,
                         points: pts.map { Point2D(x: $0.0, y: $0.1) })
        }

        /// "V" of outside measure w × h (pit, waterhole, rocky pit), the position `cog` above the tip (outside measure).
        func vee(_ w: Double, _ h: Double, _ lw: Double, _ color: String, cog: Double) -> PointElement {
            // Flat top ends, mitred tip: the arms' outer edges meet `cog` below the position, their outer corners reach
            // ± w / 2 and the top (solved for the arm angle φ from the vertical in a few steps).
            var phi = atan2((w - lw) / 2, h), x = 0.0, top = 0.0, tip = 0.0
            for _ in 0..<8 {
                tip = -cog + lw / 2 / sin(phi)
                x = w / 2 - lw / 2 * cos(phi)
                top = -cog + h - lw / 2 * sin(phi)
                phi = atan2(x, top - tip)
            }
            return lines([(-x, top), (0, tip), (x, top)], lw, color, flat: true)
        }

        /// Half ring "U" (semicircle) of outside width w (small depression, spring), the position `cog` above its bottom
        /// (outside measure). The outside height is w / 2 + lw / 2.
        func cup(_ w: Double, _ lw: Double, _ color: String, cog: Double) -> PointElement {
            let r = (w - lw) / 2, yc = -cog + lw / 2 + r
            let pts = (0...32).map { i -> (Double, Double) in
                let t = Double.pi + Double(i) / 32 * Double.pi
                return (r * cos(t), yc + r * sin(t))
            }
            return lines(pts, lw, color, flat: true)
        }

        /// "x" of outside measure `om`.
        func cross(_ om: Double, _ lw: Double, _ color: String) -> [PointElement] {
            let a = (om - lw) / 2
            return [lines([(-a, -a), (a, a)], lw, color), lines([(-a, a), (a, -a)], lw, color)]
        }

        /// "+" of outside measure `om` and width `lw` with flat ends (registration mark, tower cross).
        func plus(_ om: Double, _ lw: Double, _ color: String) -> [PointElement] {
            let a = om / 2
            return [lines([(-a, 0), (a, 0)], lw, color, flat: true), lines([(0, -a), (0, a)], lw, color, flat: true)]
        }

        func ellipse(_ w: Double, _ h: Double, _ color: String) -> PointElement {
            fill((0..<24).map { i in
                let t = Double(i) / 24 * 2 * Double.pi
                return (w / 2 * cos(t), h / 2 * sin(t))
            }, color)
        }

        /// Equilateral triangle with side `s`, pointing up (north), centred on its centroid.
        func triangle(_ s: Double, _ color: String, outline lw: Double? = nil) -> PointElement {
            let h = s * sqrt(3) / 2
            let pts = [(0, 2 * h / 3), (-s / 2, -h / 3), (s / 2, -h / 3)]
            if let lw { return lines(pts + [pts[0]], lw, color) }
            return fill(pts, color)
        }

        /// Outlined equilateral triangle whose outside sides (mitred) are `om` long (115).
        func outlinedTriangle(_ om: Double, _ lw: Double, _ color: String) -> PointElement {
            let s = om - lw * sqrt(3), h = s * sqrt(3) / 2
            let pts = [(0, 2 * h / 3), (-s / 2, -h / 3), (s / 2, -h / 3)]
            // Once around plus one side, so every corner is a mitred join.
            return lines(pts + [pts[0], pts[1]], lw, color, flat: true)
        }

        /// Square outline of outside measure `om` (311), mitred corners.
        func square(_ om: Double, _ lw: Double, _ color: String) -> PointElement {
            let a = (om - lw) / 2
            return lines([(-a, -a), (-a, a), (a, a), (a, -a), (-a, -a), (-a, a)], lw, color, flat: true)
        }

        /// Five-armed star (arms 72° apart, one pointing north) inside a circle of diameter `om` (313); flat arm ends
        /// touching the circle.
        func star(_ om: Double, _ lw: Double, _ color: String) -> [PointElement] {
            let r = ((om / 2) * (om / 2) - (lw / 2) * (lw / 2)).squareRoot()
            return (0..<5).map { i in
                let a = Double(i) * 72 * .pi / 180
                return lines([(0, 0), (r * sin(a), r * cos(a))], lw, color, flat: true)
            }
        }

        /// "T" of outside measure w × h, the position `cog` below its top (525 small tower), flat ends.
        func tee(_ w: Double, _ h: Double, _ lw: Double, _ color: String, cog: Double) -> [PointElement] {
            let top = cog - lw / 2, x = w / 2, bottom = cog - h
            return [lines([(-x, top), (x, top)], lw, color, flat: true), lines([(0, top + lw / 2), (0, bottom)], lw, color, flat: true)]
        }

        /// Stem with a roof "Λ" (arms 60° from the stem) of outside measure w × h, the position `cog` below its top
        /// (527 fodder rack), flat ends.
        func rack(_ w: Double, _ h: Double, _ lw: Double, _ color: String, cog: Double) -> [PointElement] {
            let a = 60 * Double.pi / 180
            // The mitred apex reaches the top; the arm ends' outer corners reach ± w / 2.
            let apex = cog - lw / 2 / sin(a), x = w / 2 - lw / 2 * cos(a), drop = x / tan(a)
            return [lines([(-x, apex - drop), (0, apex), (x, apex - drop)], lw, color, flat: true),
                    lines([(0, apex), (0, cog - h)], lw, color, flat: true)]
        }

        /// Filled rectangle w × h centred on the position.
        func rect(_ w: Double, _ h: Double, _ color: String) -> PointElement {
            fill([(-w / 2, -h / 2), (-w / 2, h / 2), (w / 2, h / 2), (w / 2, -h / 2)], color)
        }

        /// Two lines curving outward, `length` long, `gap` apart inside (crossing points).
        func crossing(_ length: Double, _ gap: Double, _ lw: Double, _ color: String) -> [PointElement] {
            let x0 = gap / 2 + lw / 2, bend = length * 0.12
            let left = (0...10).map { i -> (Double, Double) in
                let t = Double(i) / 5 - 1
                return (-x0 - bend * t * t, t * length / 2)
            }
            return [lines(left, lw, color), lines(left.map { (-$0.0, $0.1) }, lw, color)]
        }

        /// 713 refreshment point: a pail 3.5 OM wide and high, elliptical rim 3.5 × 1.1 OM, bottom 2.1 OM wide curving
        /// 0.5 (OM) down, line 0.4; the position 1.879 above the bottom (ISOM 2017-2 p.40).
        func pail(_ color: String) -> [PointElement] {
            let lw = 0.4, top = 3.5 - 1.879, bottom = -1.879
            let rx = (3.5 - lw) / 2, ry = (1.1 - lw) / 2, rimY = top - 1.1 / 2
            let rim = (0...32).map { i -> (Double, Double) in
                let t = Double(i) / 32 * 2 * .pi
                return (rx * cos(t), rimY + ry * sin(t))
            }
            let bx = (2.1 - lw) / 2, low = bottom + lw / 2, sag = 0.5 - lw, corner = low + sag
            var body: [(Double, Double)] = [(-rx, rimY), (-bx, corner)]
            for i in 1..<8 {
                let x = -bx + 2 * bx * Double(i) / 8, f = x / bx
                body.append((x, corner - sag * (1 - f * f)))
            }
            body += [(bx, corner), (rx, rimY)]
            return [lines(rim, lw, color), lines(body, lw, color)]
        }
    }

    // MARK: ISOM 2017-2 (1:15000)

    static func isom(_ b: inout Builder) {
        typealias D = LineDecoration
        // 1 Landforms
        b.line("101", "Contour", "brownLine", 0.14, round: true)
        b.point("101.1", "Slope line, contour", [b.lines([(0, 0), (0, -0.4)], 0.14, "brownLine")])
        b.line("102", "Index contour", "brownLine", 0.25, round: true)
        b.text("102.1", "Index contour value", "brownLine", height: 1.5)
        b.line("103", "Form line", "brownLine", 0.1, dash: [2.0, 0.2])
        b.point("103.1", "Slope line, form line", [b.lines([(0, 0), (0, -0.4)], 0.1, "brownLine")])
        // Tags 0.40 below the line edge, 0.14 wide, every 0.50 (p.39).
        b.line("104", "Earth bank", "brownLine", 0.25, deco: D(kind: .tags, sizeMM: 0.4, widthMM: 0.14, spacingMM: 0.5))
        b.line("105.1", "Earth wall", "brownLine", 0.18, deco: D(kind: .dots, sizeMM: 0.45, spacingMM: 2.0))
        // Half dots ø0.45 every 1.0, flat side 0.07 from the centre line (Rev 6, p.39).
        b.line("105.2", "Retaining earth wall", "brownLine", 0.18, deco: D(kind: .halfDots, sizeMM: 0.45, spacingMM: 1.0, offsetMM: 0.07))
        // Dashes 1.65 / gaps 0.35 (2.0 CC), a dot centred on each dash.
        b.line("106", "Ruined earth wall", "brownLine", 0.18, dash: [1.65, 0.35], deco: D(kind: .dots, sizeMM: 0.45, spacingMM: 2.0, onDashes: true))
        // 0.25 line with pointed ends, narrowing over 0.75 at each end (p.39).
        b.line("107", "Erosion gully", "brownLine", 0.25, deco: D(kind: .taper, sizeMM: 0.75, widthMM: 0, spacingMM: 0, hidesLine: true))
        b.dotted("108", "Small erosion gully", "brownLine", 0.25, 0.45)
        b.point("109", "Small knoll", [b.dot(0.5, "brownPoint")])
        b.point("110", "Small elongated knoll", [b.ellipse(0.8, 0.4, "brownPoint")])
        b.point("111", "Small depression", [b.cup(0.8, 0.18, "brownPoint", cog: 0.197)])
        b.point("112", "Pit", [b.vee(0.7, 0.8, 0.18, "brownPoint", cog: 0.498)])
        b.area("113", "Broken ground", "white", patterns: [b.pattern(.dots, "brownLine", size: 0.2, cc: 0.55, jitter: 0.12)],
               patternOnly: true, level: "brownLine")
        // 7–9 dots per mm² (8 → 0.354 CC).
        b.area("114", "Very broken ground", "white", patterns: [b.pattern(.dots, "brownLine", size: 0.2, cc: Builder.cell(perMM2: 8), jitter: 0.08)],
               patternOnly: true, level: "brownLine")
        b.point("115", "Prominent landform feature", [b.outlinedTriangle(0.9, 0.18, "brownPoint")])
        // 2 Rock and boulders
        b.line("201", "Impassable cliff", "black", 0.35, deco: D(kind: .tags, sizeMM: 0.4, widthMM: 0.12, spacingMM: 0.5))
        b.line("202", "Cliff", "black", 0.25, round: true)
        b.line("202.1", "Cliff with tags", "black", 0.25, deco: D(kind: .tags, sizeMM: 0.4, widthMM: 0.12, spacingMM: 0.5))
        b.point("203.1", "Rocky pit or cave", [b.vee(0.7, 0.8, 0.16, "black", cog: 0.489)])
        b.point("203.2", "Dangerous pit", [b.ring(0.9, 0.35, "black"), b.dot(0.9 - 2 * 0.35, "whitePoint")])
        b.point("204", "Boulder", [b.dot(0.4, "black")])
        b.point("205", "Large boulder", [b.dot(0.6, "black")])
        b.area("206", "Gigantic boulder or rock pillar", "black")
        b.point("207", "Boulder cluster", [b.triangle(0.8, "black")])
        // Scalene triangles 0.8 : 0.6 : 0.5 at random positions and rotations; 208 0.8–1 per mm², 209 2–3 per mm² (p.39).
        b.area("208", "Boulder field", "white", patterns: [b.pattern(.triangles, "black", size: 0.8, cc: Builder.cell(perMM2: 0.9),
                                                                     random: true, sides: [0.8, 0.6, 0.5])], patternOnly: true, level: "black")
        b.area("209", "Dense boulder field", "white", patterns: [b.pattern(.triangles, "black", size: 0.8, cc: Builder.cell(perMM2: 2.5),
                                                                           random: true, sides: [0.8, 0.6, 0.5])], patternOnly: true, level: "black")
        b.area("210", "Stony ground, slow running", "white", patterns: [b.pattern(.dots, "black", size: 0.2, cc: 0.52, jitter: 0.1)],
               patternOnly: true, level: "black")
        b.area("211", "Stony ground, walk", "white", patterns: [b.pattern(.dots, "black", size: 0.2, cc: 0.36, jitter: 0.07)],
               patternOnly: true, level: "black")
        // 10–12 dots per mm² (11 → 0.302 CC).
        b.area("212", "Stony ground, fight", "white", patterns: [b.pattern(.dots, "black", size: 0.2, cc: Builder.cell(perMM2: 11), jitter: 0.05)],
               patternOnly: true, level: "black")
        b.area("213", "Sandy ground", "yellow50", patterns: [b.pattern(.dots, "blackCultivated", size: 0.16, cc: 0.45, angle: 45)])
        b.area("214", "Bare rock", "black35")
        // Two 0.10 lines with a 0.10 gap (0.30 in total), transparent inside.
        b.edges("215", "Trench", "black", edge: 0.1, cc: 0.2)
        // 3 Water and marsh
        b.area("301", "Uncrossable body of water", "blue")
        b.area("301.1", "Uncrossable body of water, dominant (70 %)", "blue70")
        b.line("301.2", "Uncrossable body of water, bank line", "black", 0.12)
        b.area("302", "Shallow body of water", "blue50")
        b.line("302.1", "Shallow body of water, outline", "blueLine", 0.1)
        b.line("302.2", "Shallow body of water, seasonal outline", "blueLine", 0.1, dash: [1.25, 0.25])
        b.point("303", "Waterhole", [b.vee(0.7, 0.8, 0.18, "bluePoint", cog: 0.498)])
        b.line("304", "Crossable watercourse", "blueLine", 0.3)
        b.line("305", "Small crossable watercourse", "blueLine", 0.18)
        b.line("306", "Minor/seasonal water channel", "blueLine", 0.18, dash: [1.25, 0.25])
        b.area("307", "Uncrossable marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.25, cc: 0.5, angle: 90)], patternOnly: true, level: "blue")
        b.line("307.1", "Uncrossable marsh, outline", "black", 0.12)
        b.area("308", "Marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.1, cc: 0.3, angle: 90)], patternOnly: true, level: "blue")
        b.dotted("309", "Narrow marsh", "blueLine", 0.25, 0.45)
        // Staggered dashed lines 0.1 @ 0.3, dash 0.9 / gap 0.25.
        b.area("310", "Indistinct marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.1, cc: 0.3, angle: 90, dash: [0.9, 0.25], staggered: true)],
               patternOnly: true, level: "blue")
        b.point("311", "Well, fountain or water tank", [b.square(0.8, 0.18, "bluePoint")])
        b.point("312", "Spring", [b.cup(0.9, 0.18, "bluePoint", cog: 0.216)])
        b.point("313", "Prominent water feature", b.star(0.9, 0.16, "bluePoint"))
        // 4 Vegetation
        b.area("401", "Open land", "yellow100")
        b.area("401.1", "Open land, dominant (75 %)", "yellow75")
        b.area("402", "Open land with scattered trees", "yellow100", patterns: [b.pattern(.holes, "whiteOverYellow", size: 0.4, cc: 0.7, angle: 45)])
        b.area("403", "Rough open land", "yellow50")
        b.area("404", "Rough open land with scattered trees", "yellow50", patterns: [b.pattern(.holes, "whiteOverYellow", size: 0.5, cc: 0.8, angle: 45)])
        b.area("405", "Forest", "white")
        b.area("406", "Vegetation: slow running", "green30")
        b.area("407", "Vegetation: slow running, good visibility", "white", patterns: [b.pattern(.lines, "green100", size: 0.12, cc: 0.84)],
               patternOnly: true, level: "green100")
        b.area("408", "Vegetation: walk", "green60")
        b.area("409", "Vegetation: walk, good visibility", "white", patterns: [b.pattern(.lines, "green100", size: 0.14, cc: 0.42)],
               patternOnly: true, level: "green100")
        b.area("410", "Vegetation: fight", "green100")
        b.area("412", "Cultivated land", "yellow100", patterns: [b.pattern(.dots, "blackCultivated", size: 0.2, cc: 0.8)])
        b.area("413", "Orchard", "yellow100", patterns: [b.pattern(.dots, "green100", size: 0.45, cc: 0.8)])
        // Dashed green lines 0.2 @ 0.85, dash 1.3 / gap 0.6, rows offset.
        b.area("414", "Vineyard or similar", "yellow100", patterns: [b.pattern(.lines, "green100", size: 0.2, cc: 0.85, dash: [1.3, 0.6], staggered: true)])
        b.line("415", "Distinct cultivation boundary", "black", 0.1)
        b.dotted("416", "Distinct vegetation boundary", "black", 0.22, 0.45)
        b.line("416.1", "Distinct vegetation boundary, green dashed line", "darkGreenEdge", 0.14, dash: [0.3, 0.2])
        b.point("417", "Prominent large tree", [b.dot(1.1, "whiteOverGreen"), b.ring(0.9, 0.18, "greenPoint")])
        b.point("418", "Prominent bush or tree", [b.dot(0.6, "greenPoint"), b.dot(0.2, "whitePoint")])
        b.point("419", "Prominent vegetation feature",
                b.cross(0.9 + 0.36, 0.36, "whiteOverGreen") + b.cross(0.9, 0.18, "greenPoint"))
        // 5 Man-made features
        b.area("501", "Paved area", "brown50Paved")
        b.line("501.1", "Paved area, bounding line", "black", 0.1)
        b.double("502", "Wide road", edgeColor: "blackRoadOutline", edge: 0.14, inner: 0.3, fill: "brown50Road")
        b.line("503", "Road", "black", 0.35)
        b.line("504", "Vehicle track", "black", 0.35, dash: [3.0, 0.25])
        b.line("505", "Footpath", "black", 0.25, dash: [2.0, 0.25])
        b.line("506", "Small footpath", "black", 0.18, dash: [1.0, 0.25])
        // Pairs of dashes: dash 1.0, gap 0.25, dash 1.0, gap 0.8.
        b.line("507", "Less distinct small footpath", "black", 0.18, dash: [1.0, 0.25, 1.0, 0.8])
        b.line("508", "Narrow ride or linear trace through the terrain", "black", 0.14, dash: [2.0, 0.25])
        // Black body (edges 0.1 at 0.35 CC) with white dashes 1.0 every 2.5 on top ("White for railroad" above black).
        b.double("509", "Railway", edgeColor: "black", edge: 0.1, inner: 0.25, fill: "whiteRailroad", innerDash: [1.0, 1.5])
        // Pylon bars 0.3 long in total, 0.14 wide, at every vertex.
        b.line("510", "Power line, cableway or skilift", "black", 0.14, deco: D(kind: .bars, sizeMM: 0.3, widthMM: 0.14, spacingMM: 0))
        // Two 0.14 lines ≥ 0.4 apart (CC), bars 0.2 wide across both at the masts (vertices).
        b.edges("511", "Major power line", "black", edge: 0.14, cc: 0.4,
                more: [D(kind: .bars, sizeMM: 0.4 + 0.3, widthMM: 0.2, spacingMM: 0)])
        // Bridge edge: 0.18 line, ticks 0.4 at 60° at both ends pointing outward on one side.
        b.line("512", "Bridge / tunnel", "black", 0.18, deco: D(kind: .endTicks, sizeMM: 0.4, widthMM: 0.18, spacingMM: 0, angleDeg: 60))
        b.point("512.1", "Footbridge", [b.lines([(-0.6, 0), (0.6, 0)], 0.18, "black")])
        b.line("513.1", "Wall", "black", 0.14, deco: D(kind: .dots, sizeMM: 0.4, spacingMM: 2.0))
        b.line("513.2", "Retaining wall", "black", 0.14, deco: D(kind: .halfDots, sizeMM: 0.4, spacingMM: 1.0, offsetMM: 0.05))
        b.line("514", "Ruined wall", "black", 0.14, dash: [1.65, 0.35], deco: D(kind: .dots, sizeMM: 0.4, spacingMM: 2.0, onDashes: true))
        // Pairs of dots ø0.6, 0.8 apart within a pair, a pair every 3.0.
        b.line("515", "Impassable wall", "black", 0.25, deco: D(kind: .dots, sizeMM: 0.6, spacingMM: 3.0, pairMM: 0.8))
        // Fence tags reach 0.40 from the centre line (p.40): 0.40 − half the line beyond its edge.
        b.line("516", "Fence", "black", 0.14, deco: D(kind: .tags, sizeMM: 0.4 - 0.07, widthMM: 0.14, spacingMM: 2.0, angleDeg: 60))
        b.line("517", "Ruined fence", "black", 0.14, dash: [1.65, 0.35],
               deco: D(kind: .tags, sizeMM: 0.4 - 0.07, widthMM: 0.14, spacingMM: 2.0, angleDeg: 60, onDashes: true))
        b.line("518", "Impassable fence", "black", 0.25,
               deco: D(kind: .doubleTags, sizeMM: 0.4 - 0.125, widthMM: 0.14, spacingMM: 2.5, angleDeg: 60, pairMM: 0.6))
        b.point("519", "Crossing point", [b.lines([(-0.3, -0.5), (-0.3, 0.5)], 0.18, "black"), b.lines([(0.3, -0.5), (0.3, 0.5)], 0.18, "black")])
        // Rev 6: a solid olive green (yellow 100 % + green 50 %), no stripes.
        b.area("520", "Area that shall not be entered", "olive")
        b.line("520.1", "Area that shall not be entered, bounding line", "black", 0.18)
        b.area("521", "Building", "black")
        b.area("521.1", "Large building", "black50")
        b.line("521.2", "Large building, outline", "black", 0.2)
        b.area("522", "Canopy", "black20")
        b.line("522.1", "Canopy, outline", "black", 0.1)
        b.line("523", "Ruin", "black", 0.16, dash: [0.5, 0.25])
        b.point("524", "High tower", [b.dot(0.8, "black")] + b.plus(1.4, 0.16, "black"))
        b.point("525", "Small tower", b.tee(1.0, 1.0, 0.16, "black", cog: 0.308))
        b.point("526", "Cairn", [b.ring(0.8, 0.16, "black"), b.dot(0.14, "black")])
        b.point("527", "Fodder rack", b.rack(0.9, 0.9, 0.16, "black", cog: 0.354))
        // Chevrons: arms 0.4 from the centre line, 0.14 wide, 45°, on both sides, every 2.0.
        b.line("528", "Prominent line feature", "black", 0.14, deco: D(kind: .chevrons, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2.0, angleDeg: 45))
        b.line("529", "Prominent uncrossable line feature", "black", 0.25,
               deco: D(kind: .chevrons, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2.0, angleDeg: 45, pairMM: 0.6))
        b.point("530", "Prominent man-made feature – ring", [b.ring(0.8, 0.16, "black")])
        b.point("531", "Prominent man-made feature – x", b.cross(0.8, 0.16, "black"))
        // Border lines 0.1, ≥ 0.4 apart inside (0.5 CC), steps 0.1 across every 0.4; transparent inside.
        b.edges("532", "Stairway", "black", edge: 0.1, cc: 0.5, more: [D(kind: .rungs, sizeMM: 0.5, widthMM: 0.1, spacingMM: 0.4)])
        // 6 Technical symbols
        b.line("601", "Magnetic north line", "black", 0.1)
        b.line("601.1", "Magnetic north line, blue", "blueLine", 0.12)
        b.point("602", "Registration mark", b.plus(4.0, 0.1, "black"))
        b.point("603", "Spot height", [b.dot(0.3, "black")])
        b.text("603.1", "Spot height, value", "black", height: 1.5)
        // 7 Course planning (1:15000)
        course(&b, start: 6.0, control: 5.0, finish: (4.0, 6.0), boundary: 0.7, oobLine: 0.25, sprint: false)
    }

    // MARK: ISSprOM 2019-2 (1:4000)

    static func issprom(_ b: inout Builder) {
        typealias D = LineDecoration
        // 1 Landforms
        b.line("101", "Contour", "brown", 0.21, round: true)
        b.point("101.1", "Slope line, contour", [b.lines([(0, 0), (0, -0.75)], 0.21, "brown")])
        b.line("102", "Index contour", "brown", 0.3, round: true)
        b.text("102.1", "Index contour value", "brown", height: 1.52)
        b.line("103", "Form line", "brown", 0.15, dash: [3.0, 0.3])
        b.point("103.1", "Slope line, form line", [b.lines([(0, 0), (0, -0.6)], 0.15, "brown")])
        // Tags 0.75 OM including the 0.27 line (p.30), 0.21 wide, every 0.75.
        b.line("104", "Earth bank", "brown", 0.27, deco: D(kind: .tags, sizeMM: 0.75 - 0.27, widthMM: 0.21, spacingMM: 0.75))
        b.line("105.1", "Small earth wall", "brown", 0.27, deco: D(kind: .dots, sizeMM: 0.7, spacingMM: 3.75))
        // Half dots ø0.7 every 1.9, flat side 0.11 from the centre line.
        b.line("105.2", "Retaining earth wall seen only from one side", "brown", 0.27,
               deco: D(kind: .halfDots, sizeMM: 0.7, spacingMM: 1.9, offsetMM: 0.11))
        // 0.37 line with pointed ends, narrowing over 0.75 at each end.
        b.line("107", "Erosion gully", "brown", 0.37, deco: D(kind: .taper, sizeMM: 0.75, widthMM: 0, spacingMM: 0, hidesLine: true))
        b.dotted("108", "Small erosion gully", "brown", 0.37, 0.6)
        b.point("109", "Small knoll", [b.dot(0.75, "brown")])
        b.point("110", "Small elongated knoll", [b.ellipse(1.2, 0.6, "brown")])
        // Semicircle 1.2 × 0.6, the position 0.296 below the top (p.30).
        b.point("111", "Small depression", [b.cup(1.2, 0.25, "brown", cog: 0.6 - 0.296)])
        b.point("112", "Pit or hole", [b.vee(1.1, 1.25, 0.25, "brown", cog: 0.778)])
        b.area("113", "Broken ground", "white", patterns: [b.pattern(.dots, "brown", size: 0.3, cc: 0.75, jitter: 0.15)],
               patternOnly: true, level: "brown")
        b.point("115", "Prominent landform feature", [b.outlinedTriangle(1.35, 0.25, "brown")])
        // 2 Rock and boulders
        // Tags 0.75 OM from the top of the 0.50 line (p.30), 0.18 wide, every 0.75.
        b.line("201", "Uncrossable cliff", "black", 0.5, deco: D(kind: .tags, sizeMM: 0.75 - 0.5, widthMM: 0.18, spacingMM: 0.75))
        b.line("202", "Passable rock face", "black", 0.3, round: true)
        b.line("202.1", "Passable rock face with tags", "black", 0.3, deco: D(kind: .tags, sizeMM: 0.75 - 0.3, widthMM: 0.18, spacingMM: 0.75))
        b.point("203", "Rocky pit or cave", [b.vee(1.1, 1.25, 0.25, "black", cog: 0.778)])
        b.point("204", "Boulder", [b.dot(0.6, "black")])
        b.point("205", "Large boulder", [b.dot(0.9, "black")])
        b.area("206", "Gigantic boulder or rock pillar", "black")
        b.point("207", "Boulder cluster", [b.triangle(1.2, "black")])
        // Scalene triangles 0.96 / 0.72 / 0.6 at random positions and rotations (ISOM's density at 120 %).
        b.area("208", "Boulder field", "white", patterns: [b.pattern(.triangles, "black", size: 0.96, cc: Builder.cell(perMM2: 0.9 / 1.44),
                                                                     random: true, sides: [0.96, 0.72, 0.6])], patternOnly: true, level: "black")
        b.area("210", "Stony ground", "white", patterns: [b.pattern(.dots, "black", size: 0.25, cc: 0.6, jitter: 0.12)], patternOnly: true, level: "black")
        b.area("213", "Open sandy ground", "yellow50", patterns: [b.pattern(.dots, "blackCultivated", size: 0.18, cc: 0.5, angle: 45)])
        b.area("214", "Bare rock", "black35")
        // 3 Water and marsh
        b.area("301", "Uncrossable body of water", "blue")
        b.area("301.1", "Uncrossable body of water, dominant (70 %)", "blue70")
        b.line("301.2", "Uncrossable body of water, outline", "black", 0.18)
        b.area("302", "Shallow body of water", "blue30")
        b.line("302.1", "Shallow body of water, outline", "bluePointLine", 0.18)
        b.point("303", "Waterhole", [b.vee(1.1, 1.25, 0.25, "bluePointLine", cog: 0.778)])
        b.line("305", "Small crossable watercourse", "bluePointLine", 0.21)
        b.line("306", "Minor/seasonal watercourse", "bluePointLine", 0.21, dash: [1.87, 0.37])
        b.area("307", "Uncrossable marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.25, cc: 0.5, angle: 90)], patternOnly: true, level: "blue")
        b.line("307.1", "Uncrossable marsh, outline", "black", 0.18)
        b.area("308", "Marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.12, cc: 0.38, angle: 90)], patternOnly: true, level: "blue")
        b.dotted("309", "Narrow marsh", "bluePointLine", 0.37, 0.6)
        // Staggered dashed lines 0.12 @ 0.38, dash 1.0 / gap 0.35.
        b.area("310", "Indistinct marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.12, cc: 0.38, angle: 90, dash: [1.0, 0.35], staggered: true)],
               patternOnly: true, level: "blue")
        b.point("311", "Small fountain or well", [b.square(0.9, 0.25, "bluePointLine")])
        b.point("312", "Spring", [b.cup(1.2, 0.25, "bluePointLine", cog: 0.6 - 0.296)])
        b.point("313", "Prominent water feature", b.star(1.2, 0.25, "bluePointLine"))
        // 4 Vegetation
        b.area("401", "Open land", "yellow100")
        b.area("401.1", "Open land, dominant (75 %)", "yellow75")
        b.area("402", "Open land with scattered trees", "yellow100", patterns: [b.pattern(.holes, "whiteOverYellow", size: 0.6, cc: 0.75, angle: 45)])
        b.area("403", "Rough open land", "yellow50")
        b.area("404", "Rough open land with scattered trees", "yellow50", patterns: [b.pattern(.holes, "whiteOverYellow", size: 0.7, cc: 1.0, angle: 45)])
        b.area("405", "Forest", "white")
        b.area("406", "Vegetation: slow running", "green30")
        b.area("407", "Vegetation: slow running, good visibility", "white", patterns: [b.pattern(.lines, "green100", size: 0.12, cc: 0.84)],
               patternOnly: true, level: "green100")
        b.area("408", "Vegetation: walk", "green60")
        b.area("409", "Vegetation: walk, good visibility", "white", patterns: [b.pattern(.lines, "green100", size: 0.14, cc: 0.42)],
               patternOnly: true, level: "green100")
        b.area("410", "Vegetation: fight", "green100")
        b.area("411", "Uncrossable vegetation", "darkGreenArea")
        b.area("412", "Cultivated land", "yellow100", patterns: [b.pattern(.dots, "blackCultivated", size: 0.2, cc: 0.8)])
        b.area("413", "Orchard", "yellow100", patterns: [b.pattern(.dots, "green100", size: 0.68, cc: 1.2)])
        // Dashed green lines 0.3 @ 1.3, dash 2.0 / gap 0.9, rows offset.
        b.area("414", "Vineyard or similar", "yellow100", patterns: [b.pattern(.lines, "green100", size: 0.3, cc: 1.3, dash: [2.0, 0.9], staggered: true)])
        b.line("415", "Distinct cultivation boundary", "black", 0.15)
        b.dotted("416", "Distinct vegetation boundary", "black", 0.25, 0.6)
        b.point("417", "Prominent large tree", [b.dot(1.4, "whiteOverGreen"), b.ring(1.2, 0.25, "greenPoint")])
        b.point("418", "Prominent bush or small tree", [b.dot(0.8, "greenPoint"), b.dot(0.2, "whitePoint")])
        b.point("419", "Prominent vegetation feature",
                b.cross(1.2 + 0.5, 0.5, "whiteOverGreen") + b.cross(1.2, 0.25, "greenPoint"))
        // 5 Man-made features
        b.area("501", "Paved area", "brown30Paved")
        b.line("501.1", "Step or edge of paved area", "black", 0.1)
        b.line("501.2", "Step or edge of paved area at lower level", "black", 0.1, dash: [0.7, 0.2])
        b.area("501.3", "Paved area with scattered trees", "brown30Paved", patterns: [b.pattern(.holes, "whiteOverGreen", size: 0.6, cc: 0.75, angle: 45)])
        b.area("501.4", "Paved area, heavy traffic", "brown50Paved")
        b.double("505", "Unpaved footpath or track", edgeColor: "blackRoadOutline", edge: 0.12, inner: 0.35, fill: "brown30Road", edgeDash: [2.0, 0.25])
        b.line("506", "Small unpaved footpath or track", "black", 0.27, dash: [1.5, 0.37])
        // Pairs of dashes: dash 1.5, gap 0.37, dash 1.5, then a gap of 1.5.
        b.line("507", "Less distinct small path", "black", 0.27, dash: [1.5, 0.37, 1.5, 1.5])
        b.line("508", "Narrow ride", "black", 0.21, dash: [4.5, 0.75])
        b.double("509.1", "Railway", edgeColor: "black", edge: 0.1, inner: 0.25, fill: "whiteRailroad", innerDash: [1.0, 1.5])
        // Two 0.08 lines 0.3 apart (taken as centre to centre), no white fill.
        b.edges("509.2", "Tramway", "black", edge: 0.08, cc: 0.3)
        b.line("510", "Power line, cableway or ski lift", "black", 0.14, deco: D(kind: .bars, sizeMM: 0.3, widthMM: 0.14, spacingMM: 0))
        // Two 0.14 lines ≥ 1.5 apart, bars 0.2 wide across both at the masts (vertices).
        b.edges("511", "Major power line", "black", edge: 0.14, cc: 1.5, more: [D(kind: .bars, sizeMM: 1.5 + 0.3, widthMM: 0.2, spacingMM: 0)])
        // Since 2022: a row of solid equilateral triangles (side 0.7), peaks outward, no main line.
        b.line("512.1", "Bridge or tunnel entrance", "black", 0.7,
               deco: D(kind: .triangles, sizeMM: 0.7, spacingMM: 0.7, hidesLine: true))
        b.line("512.2", "Underpass or tunnel", "black", 0.2, dash: [0.25, 0.2])
        b.area("512.3", "Area runnable at lower level", "white", patterns: [b.pattern(.lines, "whiteStripes", size: 0.3, cc: 0.6, angle: 45)],
               patternOnly: true, level: "whiteStripes")
        b.line("513.1", "Passable wall", "black", 0.21, deco: D(kind: .dots, sizeMM: 0.6, spacingMM: 3.75))
        b.line("513.2", "Passable retaining wall", "black", 0.21, deco: D(kind: .halfDots, sizeMM: 0.6, spacingMM: 1.9, offsetMM: 0.09))
        b.line("515", "Uncrossable wall", "black", 0.4)
        // Tags reach 0.75 from the centre line, 0.14 wide, 60°, every 3.75.
        b.line("516", "Passable fence or railing", "black", 0.21,
               deco: D(kind: .tags, sizeMM: 0.75 - 0.105, widthMM: 0.14, spacingMM: 3.75, angleDeg: 60))
        // Pairs of tags (0.9 apart), reaching 0.75 from the centre line, 0.14 wide, 60°, a pair every 3.75.
        b.line("518", "Uncrossable fence or railing", "black", 0.4,
               deco: D(kind: .doubleTags, sizeMM: 0.75 - 0.2, widthMM: 0.14, spacingMM: 3.75, angleDeg: 60, pairMM: 0.9))
        // Straight bars 1.4 long, 0.25 wide, 1.0 apart inside.
        b.point("519", "Crossing point", [b.lines([(-0.625, -0.7), (-0.625, 0.7)], 0.25, "black", flat: true),
                                          b.lines([(0.625, -0.7), (0.625, 0.7)], 0.25, "black", flat: true)])
        b.area("520", "Area that shall not be entered", "olive")
        b.line("520.1", "Area that shall not be entered, bounding line", "black", 0.1)
        b.area("521", "Building", "black50")
        b.line("521.1", "Building, outline", "black", 0.14)
        b.area("522", "Canopy", "black20")
        b.point("522.1", "Pillar", [b.fill([(-0.25, -0.25), (-0.25, 0.25), (0.25, 0.25), (0.25, -0.25)], "black")])
        b.line("522.2", "Canopy, outline", "black", 0.1)
        b.point("524", "High tower", [b.dot(1.2, "black")] + b.plus(2.1, 0.25, "black"))
        b.point("525", "Small tower", b.tee(1.5, 1.5, 0.22, "black", cog: 0.462))
        b.point("526", "Cairn, memorial, sculpture, small monument or boundary stone", [b.ring(1.0, 0.22, "black"), b.dot(0.2, "black")])
        b.point("527", "Fodder rack", b.rack(1.5, 1.5, 0.22, "black", cog: 0.59))
        // Chevrons reaching 0.75 from the centre line, 0.14 wide, 45°, every 3.75.
        b.line("528", "Prominent line feature", "black", 0.21,
               deco: D(kind: .chevrons, sizeMM: 0.75, widthMM: 0.14, spacingMM: 3.75, angleDeg: 45))
        b.line("529", "Prominent uncrossable line feature", "black", 0.4,
               deco: D(kind: .chevrons, sizeMM: 0.75, widthMM: 0.14, spacingMM: 3.75, angleDeg: 45, pairMM: 0.9))
        b.point("530", "Prominent man-made feature – ring", [b.ring(1.0, 0.22, "black")])
        b.point("531", "Prominent man-made feature – x", b.cross(1.2, 0.22, "black"))
        b.edges("532", "Stairway", "black", edge: 0.1, cc: 0.5, more: [D(kind: .rungs, sizeMM: 0.5, widthMM: 0.1, spacingMM: 0.4)])
        // Black 50 % dots ø0.55 @ 0.75 at 45°, transparent between them.
        b.area("533", "Area with obstacles", "white", patterns: [b.pattern(.dots, "black50", size: 0.55, cc: 0.75, angle: 45)],
               patternOnly: true, level: "black50")
        // 6 Technical symbols
        b.line("601", "Magnetic north line", "black", 0.14)
        b.line("601.1", "Magnetic north line, blue", "bluePointLine", 0.18)
        b.point("602", "Registration mark", b.plus(4.0, 0.1, "black"))
        // 7 Course planning (1:4000)
        course(&b, start: 7.0, control: 6.0, finish: (5.0, 7.0), boundary: 1.0, oobLine: 0.4, sprint: true)
    }

    // MARK: Course planning (both standards; purple)

    /// Upper / lower purple per symbol as ISOM 2017-2 §3.7 and ISSprOM 2019-2 §4.7 state (ISSprOM: 704 control
    /// numbers and the 714 screen are upper purple).
    static func course(_ b: inout Builder, start: Double, control: Double, finish: (Double, Double), boundary: Double,
                       oobLine: Double, sprint: Bool) {
        let lw = 0.35
        b.point("701", "Start", [b.triangle(start, "purpleLower", outline: lw)])
        // A bar 2.5 × 0.6 across the route.
        b.point("702", "Map issue point", [b.rect(0.6, 2.5, "purpleUpper")])
        b.point("703", "Control point", [b.circleCC(control, lw, "purpleLower")])
        b.text("704", "Control number", sprint ? "purpleUpper" : "purpleLower", height: 4.0)
        b.line("705", "Course line", "purpleLower", lw)
        b.point("706", "Finish", [b.circleCC(finish.0, lw, "purpleLower"), b.circleCC(finish.1, lw, "purpleLower")])
        b.line("707", "Marked route", "purpleUpper", lw, dash: [2.0, 0.5])
        b.line("708", "Out-of-bounds boundary", "purpleLower", boundary)
        // Cross-hatched 0.2 @ 1.2 at ±45°.
        b.area("709", "Out-of-bounds area", "white", patterns: [b.pattern(.lines, "purpleUpper", size: 0.2, cc: 1.2, angle: 45),
                                                                b.pattern(.lines, "purpleUpper", size: 0.2, cc: 1.2, angle: 135)],
               patternOnly: true, level: "purpleUpper")
        b.line("709.1", "Out-of-bounds area, solid boundary", "purpleUpper", oobLine)
        b.line("709.2", "Out-of-bounds area, dashed boundary", "purpleUpper", oobLine, dash: [3.0, 0.5])
        if sprint {
            b.point("710.1", "Crossing point", b.crossing(4.5, 1.0, 0.5, "purpleLower"))
            // Two parallel 0.35 lines 1.5 apart with their ends turned outward.
            b.edges("710.2", "Crossing section", "purpleUpper", edge: lw, cc: 1.5,
                    more: [LineDecoration(kind: .endTicks, sizeMM: 0.5, widthMM: lw, spacingMM: 0, angleDeg: 35, pairMM: 1.5)])
            b.area("714", "Temporary construction or closed area", "purple50")
            b.line("714.1", "Temporary construction or closed area, outline", "purpleUpper", 0.1)
        } else {
            b.point("710", "Crossing point", b.crossing(3.0, 0.6, lw, "purpleLower"))
            b.point("711", "Out-of-bounds route", b.cross(3.0, lw, "purpleUpper"))
            // A cross 4.0 × 4.0 of 1.33 wide bars (flat ends).
            b.point("712", "First aid post", [b.rect(4.0, 1.33, "purpleLower"), b.rect(1.33, 4.0, "purpleLower")])
            b.point("713", "Refreshment point", b.pail("purpleLower"))
        }
        let r = control / 2
        b.point("715", "Continuing point after map exchange",
                [b.circleCC(control, lw, "purpleLower"), b.triangle(r * 1.2, "purpleLower", outline: lw)])
    }
}
