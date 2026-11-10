import Foundation

/// A single map symbol (ISOM/ISSprOM/school) from an OCAD symbol set.
public struct MapSymbol: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case point, line, area, text

        public var label: String {
            switch self {
            case .point: return "Point"
            case .line: return "Line"
            case .area: return "Area"
            case .text: return "Text"
            }
        }
    }

    /// OCAD number ×1000 (101000 = 101.0); unique within a set.
    public var number: Int
    public var name: String
    public var kind: Kind
    public var colorHex: String
    /// Main line width on paper (mm); nil for areas/points and double-line symbols.
    public var lineWidthMM: Double?
    public var isEnabled: Bool
    /// Point symbol shape (set's standard size, paper mm); nil for lines/areas.
    public var pointElements: [PointElement]?
    /// IOF line style (single or double) for line symbols.
    public var lineStyle: LineStyle?
    /// Color Hierarchy: position of the symbol's main color in the OCAD color table (0 = topmost, drawn last).
    /// Points: color of the topmost element. Double lines: fill color; `casingPriority` = its edge color.
    public var colorPriority: Int?
    public var casingPriority: Int?
    /// Area hatch / dot / triangle patterns per the specification (stored for exchange; areas are drawn with
    /// `colorHex` as a solid fill for now).
    public var patterns: [AreaPattern]?
    /// Tags, dots, ticks, chevrons… along a line per the specification (drawn by `SymbolOrnaments`).
    public var decoration: LineDecoration?
    /// Text symbols: letter (cap) height on paper (mm), e.g. ISOM 102.1 / 603.1 1.5 mm, ISSprOM 102.1 1.52 mm.
    public var textSizeMM: Double?

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

    /// Lines (pen tool), areas (pen tool/rectangle/ellipse), and points that have a shape. Text not yet.
    public var isDrawable: Bool { kind == .line || kind == .area || (kind == .point && !(pointElements ?? []).isEmpty) }

    /// IOF standard width for drawing: single line width, total double-line width, or 0.1 mm for area outlines.
    public var drawingWidthMM: Double { lineStyle?.widthMM ?? lineWidthMM ?? (kind == .area ? 0.1 : 0.25) }

    /// ISOM group from the hundreds digit of the symbol number.
    public var category: SymbolCategory { SymbolCategory(rawValue: number / 100_000) ?? .other }
}

public enum SymbolCategory: Int, CaseIterable, Identifiable, Sendable {
    case landform = 1, rock, water, vegetation, manMade, technical, course
    /// ISInOM (indoor) groups 1100–1700; ISInOM symbols with ISOM codes (521, 516, 301, 417, 7xx…) keep their ISOM group.
    case indoorConstruction = 11, indoorFloor = 12, indoorWater = 13, indoorFurniture = 14, indoorDirections = 17
    case other = 0

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .landform: return "1 Landforms"
        case .rock: return "2 Rock & cliffs"
        case .water: return "3 Water & marsh"
        case .vegetation: return "4 Vegetation"
        case .manMade: return "5 Man-made"
        case .technical: return "6 Technical"
        case .course: return "7 Course"
        case .indoorConstruction: return "11 Construction"
        case .indoorFloor: return "12 Floors"
        case .indoorWater: return "13 Water"
        case .indoorFurniture: return "14 Furniture"
        case .indoorDirections: return "17 Directions"
        case .other: return "Other"
        }
    }
}

/// Symbol set imported from an OCAD file; stored in the app library and shared across projects.
public struct SymbolSet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var sourceFile: String
    public var scale: Int
    public var isEnabled: Bool
    public var symbols: [MapSymbol]
    /// Version of the OCAD reader that created this set; older sets are updated/re-imported to get the latest data.
    public var readerVersion: Int?

    /// 1 = basic symbols, 2 = point symbol shapes, 3 = IOF line widths + double lines, 4 = dashes + line caps,
    /// 5 = Color Hierarchy (color table order), 6 = main line + double-line fill (railway), 7 = area patterns (hatch,
    /// dot structures).
    public static let currentReaderVersion = 7

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
    /// This file's symbol list as a symbol set, sorted by number. All symbols are enabled by default.
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
                // Area patterns: OCAD hatch (angle 0 = east–west lines) and dot structures → OCCA patterns (0° = north–south).
                var patterns: [AreaPattern] = []
                if kind == .area {
                    func occaAngle(_ ocad: Double) -> Double { ((90 - ocad).truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180) }
                    for h in s.rawHatch {
                        if let hex = colors[h.color] {
                            patterns.append(AreaPattern(kind: .lines, colorHex: hex, sizeMM: h.lw, spacingMM: h.dist, angleDeg: occaAngle(h.angle)))
                        }
                    }
                    if let st = s.rawStructure, let hex = colors[st.color] {
                        patterns.append(AreaPattern(kind: hex.uppercased() == "#FFFFFF" ? .holes : .dots, colorHex: hex, sizeMM: st.diam,
                                                    spacingMM: (st.width * st.height).squareRoot(), angleDeg: st.angle))
                    }
                }
                let patternOnly = kind == .area && !patterns.isEmpty && s.areaFill == .some(nil)
                let areaFillHex = s.areaFill.flatMap { $0 }.flatMap { colors[$0] }
                let color = patternOnly ? "#FFFFFF"
                    : (elements.drawingOrder.last?.colorHex ?? style?.colorHex ?? areaFillHex ?? colors[s.colorNumber] ?? "#000000")
                var m = MapSymbol(number: s.number, name: s.name.trimmingCharacters(in: .whitespaces), kind: kind,
                                  colorHex: color, lineWidthMM: s.lineWidthMM, isEnabled: true,
                                  pointElements: elements.isEmpty ? nil : elements, lineStyle: style)
                m.patterns = patterns.isEmpty ? nil : patterns
                // Color Hierarchy from this file's color table.
                if kind == .point, let top = elements.map(\.priority).min() {
                    m.colorPriority = top
                } else if kind == .line, let bg = s.background, style?.casing != nil {
                    m.colorPriority = colorOrder[s.colorNumber]
                    m.casingPriority = colorOrder[bg.color]
                } else if kind == .line, let d = s.doubleLine, style?.casing != nil {
                    m.colorPriority = d.fillColor.flatMap { colorOrder[$0] } ?? colorOrder[d.edgeColor]
                    m.casingPriority = colorOrder[d.edgeColor]
                } else if patternOnly, let first = s.rawHatch.first?.color ?? s.rawStructure?.color {
                    m.colorPriority = colorOrder[first]
                } else if kind == .area, let fill = s.areaFill.flatMap({ $0 }) {
                    m.colorPriority = colorOrder[fill]
                } else {
                    m.colorPriority = colorOrder[s.colorNumber]
                }
                return m
            }
        return SymbolSet(name: name, sourceFile: sourceFile, scale: Int(scale), symbols: symbols)
    }
}

/// IOF line style. Double line (road, path, railway): edge `casing.colorHex` `widthMM` wide underneath,
/// fill `colorHex` `casing.innerWidthMM` wide on top, so it appears as two edge lines with fill in between.
public struct LineStyle: Codable, Hashable, Sendable {
    public struct Casing: Codable, Hashable, Sendable {
        public var colorHex: String
        public var innerWidthMM: Double
    }

    public var colorHex: String
    public var widthMM: Double
    public var casing: Casing?
    /// Dash pattern [dash, gap] in paper mm (nil = solid line). For double lines it applies to the edges.
    public var dashMM: [Double]?
    /// Dash pattern of the inner line (fill) on a layered line, e.g. the dashed white of a railway; nil = solid.
    public var innerDashMM: [Double]?
    /// Round caps (contours, footpaths) or flat/sharp (walls, fences, buildings), as in OCAD.
    public var roundCaps: Bool?

    public init(colorHex: String, widthMM: Double, casing: Casing?, dashMM: [Double]? = nil, innerDashMM: [Double]? = nil,
                roundCaps: Bool? = nil) {
        self.colorHex = colorHex
        self.widthMM = widthMM
        self.casing = casing
        self.dashMM = dashMM
        self.innerDashMM = innerDashMM
        self.roundCaps = roundCaps
    }
}

/// A repeating area pattern (ISOM/ISSprOM): parallel lines (solid or dashed), a dot or triangle grid (regular, jittered or
/// random), or holes (white/tinted dots).
public struct AreaPattern: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case lines, dots, triangles, holes }

    public var kind: Kind
    public var colorHex: String
    /// Line or dot/triangle size (paper mm). Triangles: the side of an equilateral triangle, or the longest side when
    /// `sidesMM` is set.
    public var sizeMM: Double
    /// Centre-to-centre spacing (paper mm). Random patterns: the side of the square cell holding one mark
    /// (density = 1 / spacing² marks per mm²).
    public var spacingMM: Double
    /// Direction of the lines / grid, degrees from map north (0 = north–south lines).
    public var angleDeg: Double
    /// Lines: dash pattern along each line [dash, gap, …] (paper mm); nil = solid lines (310, 414).
    public var dashMM: [Double]?
    /// Alternate rows shifted by half a period (dashed lines: half the dash pattern; dots: half the spacing).
    public var staggered: Bool?
    /// Triangles / dots: one mark per cell at a random position (triangles also at a random rotation), the same on
    /// every redraw (seeded by the object and the cell), e.g. 208 / 209 boulder fields.
    public var random: Bool?
    /// Triangles: the three sides of a scalene triangle (paper mm), e.g. ISOM 208: 0.8 : 0.6 : 0.5.
    public var sidesMM: [Double]?
    /// Dots: random displacement of each dot from its grid position, up to this distance (paper mm).
    public var jitterMM: Double?

    public init(kind: Kind, colorHex: String, sizeMM: Double, spacingMM: Double, angleDeg: Double = 0, dashMM: [Double]? = nil,
                staggered: Bool? = nil, random: Bool? = nil, sidesMM: [Double]? = nil, jitterMM: Double? = nil) {
        self.kind = kind
        self.colorHex = colorHex
        self.sizeMM = sizeMM
        self.spacingMM = spacingMM
        self.angleDeg = angleDeg
        self.dashMM = dashMM
        self.staggered = staggered
        self.random = random
        self.sidesMM = sidesMM
        self.jitterMM = jitterMM
    }

    /// The pattern with all its sizes × `k` (map enlargement); angles and flags unchanged.
    public func scaled(by k: Double) -> AreaPattern {
        func r(_ v: Double) -> Double { (v * k * 1000).rounded() / 1000 }
        var p = self
        p.sizeMM = r(sizeMM); p.spacingMM = r(spacingMM)
        p.dashMM = dashMM?.map(r); p.sidesMM = sidesMM?.map(r); p.jitterMM = jitterMM.map(r)
        return p
    }
}

/// Repeated marks along a line (ISOM/ISSprOM): tags (cliff, earth bank, fence), dots, pairs of dots or half dots (walls),
/// ticks, chevrons, triangles, pylon bars, the two edges and steps of a transparent double line, or a tapered line.
public struct LineDecoration: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Tags from the line edge, `sizeMM` long (cliffs, earth banks, fences).
        case tags, doubleTags
        /// Dots of `sizeMM` on the line; with `pairMM`, pairs of dots (515).
        case dots
        /// Half dots on the right side, flat side `offsetMM` from the centre line towards the dot (105.2, 513.2).
        case halfDots
        /// Ticks crossing the line, `sizeMM` long; spacing 0 = at both ends, splayed outward on both sides.
        case ticks, doubleTicks
        /// Pylon bars across the line, `sizeMM` long in total; spacing 0 = at every vertex (510, 511).
        case bars
        /// ">" chevrons: two arms `sizeMM` long from a vertex on the centre line, one on each side, at `angleDeg` to the
        /// line; with `pairMM`, pairs of chevrons (528, 529).
        case chevrons
        /// Solid equilateral triangles of side `sizeMM`, base on the line, peaks on the right (ISSprOM 512.1).
        case triangles
        /// One-sided ticks at both ends of the line pointing outward on the right side (ISOM 512 bridge edge).
        case endTicks
        /// Steps across the line, `sizeMM` long (532 stairway).
        case rungs
        /// The two edge lines of a double line with a transparent inside: `widthMM` wide, `sizeMM` apart centre to
        /// centre (215, 509.2, 511, 532).
        case edges
        /// The line drawn as a polygon with pointed ends: full width in the middle, narrowing to `widthMM` over
        /// `sizeMM` at each end (107 erosion gully).
        case taper
    }

    public var kind: Kind
    /// Tag/tick/arm length, dot diameter, triangle side, bar/rung length, edge distance or taper length (paper mm).
    public var sizeMM: Double
    /// Line width of tags/ticks/bars/rungs/edges (0 for dots); taper: the width at the tips.
    public var widthMM: Double
    /// Centre-to-centre spacing along the line (paper mm).
    public var spacingMM: Double
    /// Angle to the line (degrees; 90 = perpendicular).
    public var angleDeg: Double
    /// Pairs (tags, ticks, chevrons, dots): centre-to-centre distance between the two marks of a pair (paper mm); nil =
    /// 0.5 mm for double tags/ticks, single marks otherwise.
    public var pairMM: Double?
    /// Half dots: distance of the flat side from the centre line, towards the dot side (paper mm; Rev 6: 105.2 0.07,
    /// 513.2 0.05).
    public var offsetMM: Double?
    /// Marks centred on each dash of the line's dash pattern (106, 514, 517) instead of evenly spaced.
    public var onDashes: Bool?
    /// The main line is not drawn: the decoration is the whole symbol (transparent double lines, triangles, taper).
    public var hidesLine: Bool?
    /// Further decorations drawn with this one (e.g. 532: edges + steps; 511: edges + bars).
    public var more: [LineDecoration]?

    public init(kind: Kind, sizeMM: Double, widthMM: Double = 0, spacingMM: Double, angleDeg: Double = 90, pairMM: Double? = nil,
                offsetMM: Double? = nil, onDashes: Bool? = nil, hidesLine: Bool? = nil, more: [LineDecoration]? = nil) {
        self.kind = kind
        self.sizeMM = sizeMM
        self.widthMM = widthMM
        self.spacingMM = spacingMM
        self.angleDeg = angleDeg
        self.pairMM = pairMM
        self.offsetMM = offsetMM
        self.onDashes = onDashes
        self.hidesLine = hidesLine
        self.more = more
    }

    /// This decoration and its `more` decorations, in drawing order.
    public var all: [LineDecoration] {
        var head = self
        head.more = nil
        return [head] + (more ?? []).flatMap(\.all)
    }

    /// True when this decoration (or one of its `more`) replaces the main line.
    public var replacesLine: Bool { all.contains { $0.hidesLine == true } }

    /// The decoration with all its sizes × `k` (map enlargement); angles and flags unchanged.
    public func scaled(by k: Double) -> LineDecoration {
        func r(_ v: Double) -> Double { (v * k * 1000).rounded() / 1000 }
        var d = self
        d.sizeMM = r(sizeMM); d.widthMM = r(widthMM); d.spacingMM = r(spacingMM)
        d.pairMM = pairMM.map(r); d.offsetMM = offsetMM.map(r)
        d.more = more?.map { $0.scaled(by: k) }
        return d
    }
}
