import Foundation

/// IOF control description (International Specification for Control Descriptions 2024), columns C–H.
/// A = sequence number and B = code are filled from the course. Values are stored as IOF symbol ids (e.g. "2.4" Boulder).
/// Directional symbols carry their direction in the id: "0.1NE" (column C), "12.4NE" (column G: north east corner, inside).
public struct ControlDescription: Codable, Hashable, Sendable {
    /// C: which of several similar features (e.g. "0.1N" = northern).
    public var which: String?
    /// D: control feature (required for controls).
    public var feature: String?
    /// E: appearance / feature detail.
    public var appearance: String?
    /// F: dimensions ("2.5", "8x4", "0.5/3"), combination (10.1 crossing, 10.2 junction) or 11.1 bend.
    public var dimension: String?
    /// G: flag location relative to the feature.
    public var location: String?
    /// H: other information (first aid, refreshments, manned control).
    public var other: String?

    public init(which: String? = nil, feature: String? = nil, appearance: String? = nil, dimension: String? = nil,
                location: String? = nil, other: String? = nil) {
        self.which = which
        self.feature = feature
        self.appearance = appearance
        self.dimension = dimension
        self.location = location
        self.other = other
    }

    public var isEmpty: Bool { [which, feature, appearance, dimension, location, other].allSatisfy { ($0 ?? "").isEmpty } }

    /// English text description, e.g. "Northern boulder, 1.5 m, north east side".
    public var text: String {
        // English word order: which + appearance + feature ("Northern low boulder"), first letter capitalized.
        let words = [IOFSymbols.textName(which), IOFSymbols.textName(appearance), IOFSymbols.textName(feature)]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        let head = words.prefix(1).uppercased() + words.dropFirst()
        var parts = head.isEmpty ? [] : [head]
        if let d = dimension?.trimmingCharacters(in: .whitespaces), !d.isEmpty {
            // Numbers like "1.5" are dimensions (m), not the column D symbol id 1.5.
            if let sym = IOFSymbols.symbol(d), sym.column == .f { parts.append(sym.textName) } else {
                parts.append(Self.dimensionText(d))
            }
        }
        if let g = IOFSymbols.textName(location) { parts.append(g) }
        if let h = IOFSymbols.textName(other) { parts.append(h) }
        return parts.joined(separator: ", ")
    }

    /// Column F dimensions as text: "2.5" → "2.5 m", "8x4" → "8 m x 4 m", "0.5/3" → "0.5 m / 3 m".
    static func dimensionText(_ d: String) -> String {
        let slash = d.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if slash.count == 2 { return "\(slash[0]) m / \(slash[1]) m" }
        let by = d.lowercased().split(separator: "x").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if by.count == 2, by.allSatisfy({ Double($0) != nil }) { return "\(by[0]) m x \(by[1]) m" }
        return "\(d) m"
    }

    // MARK: Migration from the 2018 symbol numbering

    /// Converts a description saved with the IOF 2018 numbering to the 2024 numbering, field by field
    /// (column G 11.x → 12.x and column H 12.x → 13.x, so the two "12.x" ranges never collide).
    /// Symbols whose meaning was dropped or reused in 2024 move to hidden legacy ids that keep their old
    /// pictogram and name ("x.barrier", "x.rubbishBin", "x.topEdge", "x.beginning", "x.bend", "x.radio").
    /// Corner/tip/end/part had no stored direction in 2018 and get `IOFSymbols.defaultDirection` (north).
    public func migratedFrom2018() -> ControlDescription {
        var d = self
        switch feature {
        case "5.23": d.feature = IOFSymbols.Legacy.barrier
        case "5.24": d.feature = IOFSymbols.Legacy.rubbishBin
        default: break
        }
        if let g = location {
            let dir = IOFSymbols.defaultDirection
            switch g {
            case "11.2": d.location = IOFSymbols.Legacy.topEdge
            case "11.3": d.location = "12.8"
            case "11.4": d.location = "12.9"
            case "11.5": d.location = "12.10"
            case "11.6": d.location = "12.13"
            case "11.7": d.location = "12.11"
            case "11.8": d.location = "12.4" + dir
            case "11.9": d.location = "12.5" + dir
            case "11.10": d.location = "12.6" + dir
            case "11.12": d.location = "12.7" + dir
            case "11.13": d.location = "12.3" + dir
            case "11.14": d.location = IOFSymbols.Legacy.beginning
            case "11.15": d.location = "12.14"
            case "11.11":
                // Bend moved to column F in 2024; keep it in G (legacy) when F already holds something.
                if (dimension ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    d.dimension = IOFSymbols.bend
                    d.location = nil
                } else {
                    d.location = IOFSymbols.Legacy.bend
                }
            default:
                if g.hasPrefix("11.1"), let dir = IOFSymbols.direction(of: String(g.dropFirst(4))) { d.location = "12.1" + dir }
            }
        }
        switch other {
        case "12.1": d.other = "13.1"
        case "12.2": d.other = "13.2"
        case "12.3": d.other = IOFSymbols.Legacy.radio
        case "12.4": d.other = "13.3"
        default: break
        }
        return d
    }
}

/// One IOF description symbol.
public struct IOFSymbol: Hashable, Sendable, Identifiable {
    public enum Column: String, CaseIterable, Sendable {
        case c = "C", d = "D", e = "E", f = "F", g = "G", h = "H"

        public var title: String {
            switch self {
            case .c: return "Which"
            case .d: return "Feature"
            case .e: return "Appearance"
            case .f: return "Dimensions / combination / bend"
            case .g: return "Flag location"
            case .h: return "Other information"
            }
        }
    }

    public var id: String
    public var column: Column
    /// Name as in the specification (lower case for C, E, F, G, H so it reads inside a sentence).
    public var name: String
    /// Official English name (capitalized).
    public var english: String
    /// Group for column D: Landforms, Rock and boulders, Water and marsh, Vegetation, Man-made features, Special items,
    /// Indoor (ISInOM).
    public var group: String?
    /// Old (IOF 2018) symbol kept so existing descriptions still render; not offered in the picker.
    public var isLegacy = false
    /// Short name for text descriptions when the official name lists alternatives ("Cliff, crag" → "Cliff").
    public var shortName: String?

    /// Name used in English text descriptions.
    public var textName: String { shortName ?? name }
}

/// IOF 2024 description symbol catalog (numbers as in the specification; display name + official English name).
public enum IOFSymbols {
    /// Every known id, including the 8 directions of directional symbols and the hidden legacy symbols.
    public static let all: [IOFSymbol] = which + features + indoorFeatures + appearance + combinations + locations + other + legacy

    /// All ids of a column (with every direction and legacy symbols).
    public static func symbols(in column: IOFSymbol.Column) -> [IOFSymbol] { all.filter { $0.column == column } }

    /// Symbols offered in the picker: no legacy symbols; column G lists each directional symbol once
    /// (its base id, e.g. "12.4") — the direction is chosen separately.
    public static func pickerSymbols(in column: IOFSymbol.Column) -> [IOFSymbol] {
        column == .g ? locationChoices : all.filter { $0.column == column && !$0.isLegacy }
    }

    /// As `pickerSymbols(in:)`; on an indoor map (ISInOM) column D starts with the indoor features, otherwise they come last.
    public static func pickerSymbols(in column: IOFSymbol.Column, indoor: Bool) -> [IOFSymbol] {
        let list = pickerSymbols(in: column)
        guard column == .d, indoor else { return list }
        return list.filter { $0.group == indoorGroup } + list.filter { $0.group != indoorGroup }
    }

    private static let byID: [String: IOFSymbol] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func symbol(_ id: String?) -> IOFSymbol? { id.flatMap { byID[$0] } }

    public static func name(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return byID[id]?.name
    }

    /// Name for text descriptions (short form of names with alternatives).
    public static func textName(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return byID[id]?.textName
    }

    private static func s(_ id: String, _ c: IOFSymbol.Column, _ name: String, _ en: String, _ group: String? = nil,
                          short: String? = nil) -> IOFSymbol {
        IOFSymbol(id: id, column: c, name: name, english: en, group: group, shortName: short)
    }

    // MARK: Directions

    /// The 8 directions, clockwise from north.
    public static let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// Direction for 2018 corner/tip/end/part symbols, which had no stored direction.
    public static let defaultDirection = "N"

    public static func direction(of s: String) -> String? { directions.contains(s) ? s : nil }

    /// "NE" → "north east".
    public static func directionName(_ dir: String) -> String {
        ["N": "north", "NE": "north east", "E": "east", "SE": "south east", "S": "south", "SW": "south west",
         "W": "west", "NW": "north west"][dir] ?? dir
    }

    /// Column G symbols that take one of the 8 directions (12.1–12.7, 12.12).
    public static let directionalLocations = ["12.1", "12.2", "12.3", "12.4", "12.5", "12.6", "12.7", "12.12"]

    /// Splits a column G id into its base and direction: "12.4NE" → ("12.4", "NE"); "12.8" → ("12.8", nil).
    public static func splitDirection(_ id: String) -> (base: String, direction: String?) {
        let letters = id.reversed().prefix { $0.isLetter }
        guard !letters.isEmpty, !id.hasPrefix("x.") else { return (id, nil) }
        let dir = String(letters.reversed())
        let base = String(id.dropLast(dir.count))
        return direction(of: dir) != nil ? (base, dir) : (id, nil)
    }

    public static func isDirectional(_ base: String) -> Bool { directionalLocations.contains(base) }

    /// Column F id of the bend symbol (in column G until 2018).
    public static let bend = "11.1"

    /// Hidden ids for 2018 symbols that were dropped or whose number got another meaning in 2024.
    public enum Legacy {
        public static let barrier = "x.barrier"
        public static let rubbishBin = "x.rubbishBin"
        public static let topEdge = "x.topEdge"
        public static let beginning = "x.beginning"
        public static let bend = "x.bend"
        public static let radio = "x.radio"
    }

    // MARK: Columns

    // Column C: which of several similar features.
    static let which: [IOFSymbol] = [
        s("0.1N", .c, "northern", "Northern"), s("0.1NE", .c, "north-eastern", "North-eastern"),
        s("0.1E", .c, "eastern", "Eastern"), s("0.1SE", .c, "south-eastern", "South-eastern"),
        s("0.1S", .c, "southern", "Southern"), s("0.1SW", .c, "south-western", "South-western"),
        s("0.1W", .c, "western", "Western"), s("0.1NW", .c, "north-western", "North-western"),
        s("0.2", .c, "upper", "Upper"), s("0.3", .c, "lower", "Lower"), s("0.4", .c, "middle", "Middle"),
    ]

    // Column D: features.
    static let features: [IOFSymbol] = {
        let land = "Landforms", rock = "Rock and boulders", water = "Water and marsh", veg = "Vegetation", man = "Man-made features", special = "Special items"
        return [
            s("1.1", .d, "Terrace", "Terrace", land), s("1.2", .d, "Spur", "Spur", land),
            s("1.3", .d, "Re-entrant", "Re-entrant", land), s("1.4", .d, "Earth bank", "Earth bank", land),
            s("1.5", .d, "Quarry", "Quarry", land), s("1.6", .d, "Earth wall", "Earth wall", land),
            s("1.7", .d, "Erosion gully", "Erosion gully", land), s("1.8", .d, "Small erosion gully", "Small erosion gully", land),
            s("1.9", .d, "Hill", "Hill", land), s("1.10", .d, "Knoll", "Knoll", land),
            s("1.11", .d, "Saddle", "Saddle", land), s("1.12", .d, "Depression", "Depression", land),
            s("1.13", .d, "Small depression", "Small depression", land), s("1.14", .d, "Pit", "Pit", land),
            s("1.15", .d, "Broken ground", "Broken ground", land),
            s("1.16", .d, "Ant hill (termite mound)", "Ant hill (termite mound)", land, short: "Ant hill"),
            s("2.1", .d, "Cliff, crag", "Cliff, crag", rock, short: "Cliff"), s("2.2", .d, "Rock pillar", "Rock pillar", rock),
            s("2.3", .d, "Cave", "Cave", rock), s("2.4", .d, "Boulder", "Boulder", rock),
            s("2.5", .d, "Boulder field", "Boulder field", rock), s("2.6", .d, "Boulder cluster", "Boulder cluster", rock),
            s("2.7", .d, "Stony ground", "Stony ground", rock), s("2.8", .d, "Bare rock", "Bare rock", rock),
            s("2.9", .d, "Narrow passage", "Narrow passage", rock), s("2.10", .d, "Trench", "Trench", rock),
            s("3.1", .d, "Lake", "Lake", water), s("3.2", .d, "Pond", "Pond", water),
            s("3.3", .d, "Waterhole", "Waterhole", water),
            s("3.4", .d, "River, stream, watercourse", "River, stream, watercourse", water, short: "Stream"),
            s("3.5", .d, "Minor water channel, ditch", "Minor water channel, ditch", water, short: "Ditch"),
            s("3.6", .d, "Narrow marsh", "Narrow marsh", water),
            s("3.7", .d, "Marsh", "Marsh", water), s("3.8", .d, "Firm ground in marsh", "Firm ground in marsh", water),
            s("3.9", .d, "Well", "Well", water), s("3.10", .d, "Spring", "Spring", water),
            s("3.11", .d, "Water tank, water trough", "Water tank, water trough", water, short: "Water tank"),
            s("4.1", .d, "Open land", "Open land", veg), s("4.2", .d, "Semi-open land", "Semi-open land", veg),
            s("4.3", .d, "Forest corner", "Forest corner", veg), s("4.4", .d, "Clearing", "Clearing", veg),
            s("4.5", .d, "Thicket", "Thicket", veg), s("4.6", .d, "Linear thicket", "Linear thicket", veg),
            s("4.7", .d, "Vegetation boundary", "Vegetation boundary", veg), s("4.8", .d, "Copse", "Copse", veg),
            s("4.9", .d, "Prominent tree", "Prominent tree", veg),
            s("4.10", .d, "Prominent vegetation feature (e.g. root stock, tree stump)", "Prominent vegetation feature", veg,
              short: "Prominent vegetation feature"),
            s("5.1", .d, "Road", "Road", man), s("5.2", .d, "Track / path", "Track / path", man),
            s("5.3", .d, "Ride", "Ride", man), s("5.4", .d, "Bridge", "Bridge", man),
            s("5.5", .d, "Power line", "Power line", man), s("5.6", .d, "Pylon", "Pylon", man),
            s("5.7", .d, "Tunnel", "Tunnel", man), s("5.8", .d, "Wall", "Wall", man),
            s("5.9", .d, "Fence", "Fence", man), s("5.10", .d, "Crossing point", "Crossing point", man),
            s("5.11", .d, "Building", "Building", man), s("5.12", .d, "Paved area", "Paved area", man),
            s("5.13", .d, "Ruin", "Ruin", man),
            s("5.14", .d, "Prominent man-made line feature (e.g. pipeline, bobsleigh track)", "Prominent man-made line feature", man,
              short: "Prominent man-made line feature"),
            s("5.15", .d, "Tower / pylon", "Tower / pylon", man, short: "Tower"),
            s("5.16", .d, "Shooting platform", "Shooting platform", man),
            s("5.17", .d, "Boundary stone, cairn", "Boundary stone, cairn", man, short: "Boundary stone"),
            s("5.18", .d, "Fodder rack", "Fodder rack", man),
            s("5.19", .d, "Charcoal burning ground, platform", "Charcoal burning ground, platform", man, short: "Charcoal burning ground"),
            s("5.20", .d, "Monument / statue", "Monument / statue", man),
            s("5.21", .d, "Canopy", "Canopy", man), s("5.22", .d, "Stairway", "Stairway", man),
            s("5.23", .d, "Out of bounds area", "Out of bounds area", man), s("5.24", .d, "Railway", "Railway", man),
            s("6.1", .d, "Prominent feature / special item", "Prominent feature / special item", special, short: "Special item (x)"),
            s("6.2", .d, "Prominent feature / special item", "Prominent feature / special item", special, short: "Special item (o)"),
        ]
    }()

    /// Group of the indoor column D features.
    public static let indoorGroup = "Indoor"

    /// ISInOM 6.7.3 indoor control description features (column D; Purple Pen 6.3–6.9). Offered in every picker, first on
    /// indoor maps (`pickerSymbols(in:indoor:)`).
    static let indoorFeatures: [IOFSymbol] = {
        let g = indoorGroup
        return [
            s("7.119", .d, "Pillar", "Pillar", g), s("7.132", .d, "Toilet", "Toilet", g),
            s("7.133", .d, "Shower", "Shower", g), s("7.134", .d, "Sink", "Sink", g),
            s("7.141", .d, "Table or bench", "Table or bench", g, short: "Table"),
            s("7.142", .d, "Cupboard / shelf", "Cupboard / shelf", g, short: "Cupboard"),
            s("7.143", .d, "Couch / sofa", "Couch / sofa", g, short: "Couch"),
        ]
    }()

    // Column E: appearance.
    static let appearance: [IOFSymbol] = [
        s("8.1", .e, "low", "Low"), s("8.2", .e, "shallow", "Shallow"), s("8.3", .e, "deep", "Deep"),
        s("8.4", .e, "overgrown", "Overgrown"), s("8.5", .e, "open", "Open"),
        s("8.6", .e, "rocky / stony", "Rocky / stony"), s("8.7", .e, "marshy", "Marshy"), s("8.8", .e, "sandy", "Sandy"),
        s("8.9", .e, "needle leaved", "Needle leaved"), s("8.10", .e, "broad leaved", "Broad leaved"),
        s("8.11", .e, "ruined", "Ruined"),
    ]

    // Column F: combinations and bend (dimensions are typed freely).
    static let combinations: [IOFSymbol] = [
        s("10.1", .f, "crossing", "Crossing"), s("10.2", .f, "junction", "Junction"), s(bend, .f, "bend", "Bend"),
    ]

    /// Column G base symbols (2024 numbering) in picker order.
    private static let locationBases: [(id: String, name: String)] = [
        ("12.1", "side"), ("12.2", "edge"), ("12.3", "part"), ("12.4", "corner (inside)"), ("12.5", "corner (outside)"),
        ("12.6", "tip"), ("12.7", "end"), ("12.8", "upper part"), ("12.9", "lower part"), ("12.10", "top"),
        ("12.11", "foot"), ("12.12", "foot (with direction)"), ("12.13", "beneath"), ("12.14", "between"),
    ]

    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    // Column G: flag location; directional symbols in all 8 directions ("12.4NE" north east corner (inside)).
    static let locations: [IOFSymbol] = locationBases.flatMap { base -> [IOFSymbol] in
        guard isDirectional(base.id) else { return [s(base.id, .g, base.name, capitalized(base.name))] }
        let noun = base.id == "12.12" ? "foot" : base.name
        return directions.map { dir in
            let n = "\(directionName(dir)) \(noun)"
            return s(base.id + dir, .g, n, capitalized(n))
        }
    }

    /// Picker entries for column G: one per base symbol (directional ones without a direction).
    static let locationChoices: [IOFSymbol] = locationBases.map { s($0.id, .g, $0.name, capitalized($0.name)) }

    // Column H: other information.
    static let other: [IOFSymbol] = [
        s("13.1", .h, "first aid post", "First aid post"), s("13.2", .h, "refreshment point", "Refreshment point"),
        s("13.3", .h, "manned control", "Manned control"),
    ]

    /// 2018 symbols kept for old projects (hidden from the picker).
    static let legacy: [IOFSymbol] = [
        IOFSymbol(id: Legacy.barrier, column: .d, name: "Barrier", english: "Barrier", group: "Man-made features", isLegacy: true),
        IOFSymbol(id: Legacy.rubbishBin, column: .d, name: "Rubbish bin", english: "Rubbish bin", group: "Man-made features", isLegacy: true),
        IOFSymbol(id: Legacy.topEdge, column: .g, name: "top edge", english: "Top edge", isLegacy: true),
        IOFSymbol(id: Legacy.beginning, column: .g, name: "beginning", english: "Beginning", isLegacy: true),
        IOFSymbol(id: Legacy.bend, column: .g, name: "bend", english: "Bend", isLegacy: true),
        IOFSymbol(id: Legacy.radio, column: .h, name: "radio / TV control", english: "Radio / TV control", isLegacy: true),
    ]
}
