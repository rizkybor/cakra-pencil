import Foundation

/// IOF control description (International Specification for Control Descriptions 2018), columns C–H.
/// A = sequence number and B = code are filled from the course. Values are stored as IOF symbol ids (e.g. "2.4" Boulder).
public struct ControlDescription: Codable, Hashable, Sendable {
    /// C: which of several similar features (e.g. "0.1N" = northern).
    public var which: String?
    /// D: control feature (required for controls).
    public var feature: String?
    /// E: appearance / feature detail.
    public var appearance: String?
    /// F: dimensions ("2.5", "8x4") or combination (crossing/junction).
    public var dimension: String?
    /// G: flag location relative to the feature.
    public var location: String?
    /// H: other information (first aid, refreshments, radio, …).
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

    /// English text description, e.g. "Northern boulder, 1.5 m, east side".
    public var text: String {
        // English word order: which + appearance + feature ("Northern low boulder"), first letter capitalized.
        let words = [IOFSymbols.name(which), IOFSymbols.name(appearance), IOFSymbols.name(feature)].compactMap { $0 }.joined(separator: " ").lowercased()
        let head = words.prefix(1).uppercased() + words.dropFirst()
        var parts = head.isEmpty ? [] : [head]
        if let d = dimension?.trimmingCharacters(in: .whitespaces), !d.isEmpty {
            // Numbers like "1.5" are dimensions (m), not the column D symbol id 1.5.
            if let sym = IOFSymbols.symbol(d), sym.column == .f { parts.append(sym.name) } else {
                parts.append("\(d) m")
            }
        }
        if let g = IOFSymbols.name(location) { parts.append(g) }
        if let h = IOFSymbols.name(other) { parts.append(h) }
        return parts.joined(separator: ", ")
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
            case .f: return "Dimensions / combination"
            case .g: return "Flag location"
            case .h: return "Other information"
            }
        }
    }

    public var id: String
    public var column: Column
    public var name: String
    public var english: String
    /// Group for column D: Landforms, Rock and boulders, Water and marsh, Vegetation, Man-made features, Special items.
    public var group: String?
}

/// IOF 2018 description symbol catalog (numbers as in the specification; display name + official English name).
public enum IOFSymbols {
    public static let all: [IOFSymbol] = which + features + appearance + combinations + locations + other

    public static func symbols(in column: IOFSymbol.Column) -> [IOFSymbol] { all.filter { $0.column == column } }

    private static let byID: [String: IOFSymbol] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func symbol(_ id: String?) -> IOFSymbol? { id.flatMap { byID[$0] } }

    public static func name(_ id: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        return byID[id]?.name
    }

    private static func s(_ id: String, _ c: IOFSymbol.Column, _ name: String, _ en: String, _ group: String? = nil) -> IOFSymbol {
        IOFSymbol(id: id, column: c, name: name, english: en, group: group)
    }

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
            s("1.15", .d, "Broken ground", "Broken ground", land), s("1.16", .d, "Ant hill", "Ant hill", land),
            s("2.1", .d, "Cliff", "Cliff", rock), s("2.2", .d, "Rock pillar", "Rock pillar", rock),
            s("2.3", .d, "Cave", "Cave", rock), s("2.4", .d, "Boulder", "Boulder", rock),
            s("2.5", .d, "Boulder field", "Boulder field", rock), s("2.6", .d, "Boulder cluster", "Boulder cluster", rock),
            s("2.7", .d, "Stony ground", "Stony ground", rock), s("2.8", .d, "Bare rock", "Bare rock", rock),
            s("2.9", .d, "Narrow passage", "Narrow passage", rock), s("2.10", .d, "Trench", "Trench", rock),
            s("3.1", .d, "Lake", "Lake", water), s("3.2", .d, "Pond", "Pond", water),
            s("3.3", .d, "Waterhole", "Waterhole", water), s("3.4", .d, "River / stream", "River / stream", water),
            s("3.5", .d, "Minor water channel", "Minor water channel", water), s("3.6", .d, "Narrow marsh", "Narrow marsh", water),
            s("3.7", .d, "Marsh", "Marsh", water), s("3.8", .d, "Firm ground in marsh", "Firm ground in marsh", water),
            s("3.9", .d, "Well", "Well", water), s("3.10", .d, "Spring", "Spring", water),
            s("3.11", .d, "Water tank", "Water tank", water),
            s("4.1", .d, "Open land", "Open land", veg), s("4.2", .d, "Semi-open land", "Semi-open land", veg),
            s("4.3", .d, "Forest corner", "Forest corner", veg), s("4.4", .d, "Clearing", "Clearing", veg),
            s("4.5", .d, "Thicket", "Thicket", veg), s("4.6", .d, "Linear thicket", "Linear thicket", veg),
            s("4.7", .d, "Vegetation boundary", "Vegetation boundary", veg), s("4.8", .d, "Copse", "Copse", veg),
            s("4.9", .d, "Distinct tree", "Distinct tree", veg), s("4.10", .d, "Tree stump / root stock", "Tree stump / root stock", veg),
            s("5.1", .d, "Road", "Road", man), s("5.2", .d, "Track / path", "Track / path", man),
            s("5.3", .d, "Ride", "Ride", man), s("5.4", .d, "Bridge", "Bridge", man),
            s("5.5", .d, "Power line", "Power line", man), s("5.6", .d, "Power line pylon", "Power line pylon", man),
            s("5.7", .d, "Tunnel", "Tunnel", man), s("5.8", .d, "Stone wall", "Stone wall", man),
            s("5.9", .d, "Fence", "Fence", man), s("5.10", .d, "Crossing point", "Crossing point", man),
            s("5.11", .d, "Building", "Building", man), s("5.12", .d, "Paved area", "Paved area", man),
            s("5.13", .d, "Ruin", "Ruin", man), s("5.14", .d, "Pipeline", "Pipeline", man),
            s("5.15", .d, "Tower", "Tower", man), s("5.16", .d, "Shooting platform", "Shooting platform", man),
            s("5.17", .d, "Boundary stone / cairn", "Boundary stone / cairn", man), s("5.18", .d, "Fodder rack", "Fodder rack", man),
            s("5.19", .d, "Charcoal burning ground", "Charcoal burning ground", man), s("5.20", .d, "Monument / statue", "Monument / statue", man),
            s("5.21", .d, "Building pass through", "Building pass through", man), s("5.22", .d, "Stairway", "Stairway", man),
            s("5.23", .d, "Barrier", "Barrier", man), s("5.24", .d, "Rubbish bin", "Rubbish bin", man),
            s("6.1", .d, "Special item (x)", "Special item (x)", special), s("6.2", .d, "Special item (o)", "Special item (o)", special),
        ]
    }()

    // Column E: appearance.
    static let appearance: [IOFSymbol] = [
        s("8.1", .e, "low", "Low"), s("8.2", .e, "shallow", "Shallow"), s("8.3", .e, "deep", "Deep"),
        s("8.4", .e, "overgrown", "Overgrown"), s("8.5", .e, "open", "Open"),
        s("8.6", .e, "rocky / stony", "Rocky / stony"), s("8.7", .e, "marshy", "Marshy"), s("8.8", .e, "sandy", "Sandy"),
        s("8.9", .e, "needle leaved", "Needle leaved"), s("8.10", .e, "broad leaved", "Broad leaved"),
        s("8.11", .e, "ruined / collapsed", "Ruined / collapsed"),
    ]

    // Column F: combinations (dimensions are typed freely).
    static let combinations: [IOFSymbol] = [
        s("10.1", .f, "crossing", "Crossing"), s("10.2", .f, "junction", "Junction"),
    ]

    // Column G: flag location.
    static let locations: [IOFSymbol] = [
        s("11.1N", .g, "north side", "North side"), s("11.1NE", .g, "north-east side", "North-east side"),
        s("11.1E", .g, "east side", "East side"), s("11.1SE", .g, "south-east side", "South-east side"),
        s("11.1S", .g, "south side", "South side"), s("11.1SW", .g, "south-west side", "South-west side"),
        s("11.1W", .g, "west side", "West side"), s("11.1NW", .g, "north-west side", "North-west side"),
        s("11.2", .g, "top edge", "Top edge"), s("11.3", .g, "upper part", "Upper part"),
        s("11.4", .g, "lower part", "Lower part"), s("11.5", .g, "top", "Top"),
        s("11.6", .g, "beneath", "Beneath"), s("11.7", .g, "foot", "Foot"),
        s("11.8", .g, "corner (inside)", "Corner (inside)"), s("11.9", .g, "corner (outside)", "Corner (outside)"),
        s("11.10", .g, "tip", "Tip"), s("11.11", .g, "bend", "Bend"),
        s("11.12", .g, "end", "End"), s("11.13", .g, "part", "Part"),
        s("11.14", .g, "beginning", "Beginning"), s("11.15", .g, "between", "Between"),
    ]

    // Column H: other information.
    static let other: [IOFSymbol] = [
        s("12.1", .h, "first aid post", "First aid post"), s("12.2", .h, "refreshment point", "Refreshment point"),
        s("12.3", .h, "radio / TV control", "Radio / TV control"), s("12.4", .h, "manned control", "Manned control"),
    ]
}
