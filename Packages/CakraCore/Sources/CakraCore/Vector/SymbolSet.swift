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
    /// Tags, dots, or ticks along a line per the specification (stored; the main line is drawn).
    public var decoration: LineDecoration?

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

/// A repeating area pattern (ISOM/ISSprOM): parallel lines, a dot or triangle grid, or holes (white/tinted dots).
public struct AreaPattern: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case lines, dots, triangles, holes }

    public var kind: Kind
    public var colorHex: String
    /// Line or dot/triangle size (paper mm).
    public var sizeMM: Double
    /// Centre-to-centre spacing (paper mm).
    public var spacingMM: Double
    /// Direction of the lines / grid, degrees from map north (0 = north–south lines).
    public var angleDeg: Double

    public init(kind: Kind, colorHex: String, sizeMM: Double, spacingMM: Double, angleDeg: Double = 0) {
        self.kind = kind
        self.colorHex = colorHex
        self.sizeMM = sizeMM
        self.spacingMM = spacingMM
        self.angleDeg = angleDeg
    }
}

/// Repeated marks along a line (ISOM/ISSprOM): tags (cliff, earth bank, fence), dots or half dots (walls), ticks,
/// pylon bars.
public struct LineDecoration: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case tags, doubleTags, dots, halfDots, ticks, doubleTicks, bars }

    public var kind: Kind
    /// Tag/tick length or dot diameter (paper mm).
    public var sizeMM: Double
    /// Line width of tags/ticks (0 for dots).
    public var widthMM: Double
    /// Centre-to-centre spacing along the line (paper mm).
    public var spacingMM: Double
    /// Angle to the line (degrees; 90 = perpendicular).
    public var angleDeg: Double
    /// Double tags/ticks: centre-to-centre distance between the two marks of a pair (paper mm); nil = 0.5 mm.
    public var pairMM: Double?

    public init(kind: Kind, sizeMM: Double, widthMM: Double = 0, spacingMM: Double, angleDeg: Double = 90, pairMM: Double? = nil) {
        self.kind = kind
        self.sizeMM = sizeMM
        self.widthMM = widthMM
        self.spacingMM = spacingMM
        self.angleDeg = angleDeg
        self.pairMM = pairMM
    }
}
