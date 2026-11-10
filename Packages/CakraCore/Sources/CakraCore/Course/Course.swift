import Foundation

/// Course planner (like Purple Pen / OCAD Course Setting): controls are shared by many courses,
/// a course = a sequence of controls. Positions are in the project CRS (UTM, meters).

public enum ControlKind: String, Codable, CaseIterable, Sendable {
    case start, control, finish

    public var label: String {
        switch self {
        case .start: return "Start"
        case .control: return "Control"
        case .finish: return "Finish"
        }
    }
}

/// One control point (start, control, or finish) on the map.
public struct ControlPoint: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: ControlKind
    /// Control code (31–255 per SPORTident/Emit punching units); nil for start/finish.
    public var code: Int?
    public var position: Point2D
    public var description: ControlDescription
    /// Size multiplier for this control's symbol (nil = 100%, IOF standard size).
    public var sizeFactor: Double?

    public var effectiveSize: Double { sizeFactor ?? 1 }
    public static let sizeRange: ClosedRange<Double> = 0.5...2

    public init(id: UUID = UUID(), kind: ControlKind, code: Int? = nil, position: Point2D, description: ControlDescription = ControlDescription()) {
        self.id = id
        self.kind = kind
        self.code = code
        self.position = position
        self.description = description
    }

    /// Short label: "31", "S1", "F1".
    public func label(in set: CourseSet) -> String {
        switch kind {
        case .control: return code.map(String.init) ?? "?"
        case .start: return "S\((set.controls.filter { $0.kind == .start }.firstIndex { $0.id == id } ?? 0) + 1)"
        case .finish: return "F\((set.controls.filter { $0.kind == .finish }.firstIndex { $0.id == id } ?? 0) + 1)"
        }
    }

    /// Id for IOF XML (`<Id>`): the control code, or S1/F1.
    public func iofID(in set: CourseSet) -> String { label(in: set) }
}

public enum CourseKind: String, Codable, CaseIterable, Sendable {
    /// Fixed order: start → controls 1…n → finish.
    case normal
    /// Score/rogaining: free order, controls are numbered by their code.
    case score

    public var label: String { self == .normal ? "Normal" : "Score" }
}

/// Course: control sequence + competitor data.
public struct Course: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: CourseKind
    /// Ordered control ids, including start (first) and finish (last) if present.
    public var controlIDs: [UUID]
    /// Estimated number of competitors (for computing control load, like "Competitor load" in Purple Pen).
    public var competitors: Int
    /// Total climb (m), entered manually as in Purple Pen.
    public var climbM: Int?
    /// Gaps cut into the course line (Purple Pen "Add gap"), e.g. so a leg doesn't cover an important map detail.
    public var legGaps: [LegGap]?
    /// Classes running this course (optional heading line of the description sheet, e.g. "M45 M50 W21").
    public var classes: String?
    /// IOF 14.1: distance from the timed start to the start triangle (m); nil = no line.
    public var startDistanceM: Int?
    /// IOF 15.x special instruction rows between the controls.
    public var specialInstructions: [SpecialInstruction]?
    /// IOF 16.x route from the last control to the finish; nil = 16.3 (navigate, no tapes).
    public var finishRoute: FinishRoute?

    public var effectiveFinishRoute: FinishRoute { finishRoute ?? .navigate }
    public var allSpecialInstructions: [SpecialInstruction] { specialInstructions ?? [] }

    public init(id: UUID = UUID(), name: String, kind: CourseKind = .normal, controlIDs: [UUID] = [], competitors: Int = 0, climbM: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.controlIDs = controlIDs
        self.competitors = competitors
        self.climbM = climbM
    }
}

/// IOF special instruction (15.1–15.6): a full-width row between control descriptions.
public struct SpecialInstruction: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case tapedAway = "15.1", tapedBetween = "15.2", crossingPoint = "15.3", outOfBoundsPassage = "15.4",
             tapedToMapExchange = "15.5", mapFlip = "15.6"

        /// Short label for menus.
        public var label: String {
            switch self {
            case .tapedAway: return "Taped route away from control"
            case .tapedBetween: return "Taped route between controls"
            case .crossingPoint: return "Mandatory crossing point"
            case .outOfBoundsPassage: return "Passage through out of bounds area"
            case .tapedToMapExchange: return "Taped route to map exchange"
            case .mapFlip: return "Map flip"
            }
        }

        /// Whether the symbol carries a route length.
        public var hasLength: Bool { self == .tapedAway || self == .tapedBetween || self == .tapedToMapExchange }

        /// English text as in the specification.
        public func text(meters: Int?) -> String {
            let m = meters.map { " \($0) m" } ?? ""
            switch self {
            case .tapedAway: return "Follow taped route\(m) away from control"
            case .tapedBetween: return "Follow taped route\(m) between controls"
            case .crossingPoint: return "Mandatory crossing point"
            case .outOfBoundsPassage: return "Mandatory passage through out of bounds area"
            case .tapedToMapExchange: return "Follow taped route\(m) to map exchange"
            case .mapFlip: return "Map flip (turn the map over)"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Position in the course: after the n-th control (0 = right after the start).
    public var afterControl: Int
    /// Route length (m) for 15.1, 15.2, 15.5.
    public var lengthM: Int?

    public init(id: UUID = UUID(), kind: Kind, afterControl: Int, lengthM: Int? = nil) {
        self.id = id
        self.kind = kind
        self.afterControl = afterControl
        self.lengthM = lengthM
    }
}

/// IOF 16.x: nature of the route from the last control to the finish.
public enum FinishRoute: String, Codable, CaseIterable, Sendable {
    case taped = "16.1", funnel = "16.2", navigate = "16.3"

    public var label: String {
        switch self {
        case .taped: return "Taped route to finish"
        case .funnel: return "Navigate to funnel, then tapes"
        case .navigate: return "Navigate to finish (no tapes)"
        }
    }

    /// English text, e.g. "400 m from last control to finish, follow taped route".
    public func text(meters: Int?) -> String {
        switch self {
        case .taped: return meters.map { "\($0) m from last control to finish, follow taped route" } ?? "Follow taped route to finish"
        case .funnel: return meters.map { "\($0) m from last control to finish, navigate to finish funnel, then follow tapes" }
            ?? "Navigate to finish funnel, then follow tapes"
        case .navigate: return meters.map { "Navigate \($0) m to finish" } ?? "Finish"
        }
    }
}

/// A gap in the course line of the leg `from` → `to`: centred at fraction `at` of the control-to-control distance,
/// `lengthMM` long on paper.
public struct LegGap: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var from: UUID
    public var to: UUID
    public var at: Double
    public var lengthMM: Double

    /// Default gap length on paper (mm).
    public static let defaultLengthMM = 2.5

    public init(id: UUID = UUID(), from: UUID, to: UUID, at: Double, lengthMM: Double = LegGap.defaultLengthMM) {
        self.id = id
        self.from = from
        self.to = to
        self.at = at
        self.lengthMM = lengthMM
    }
}

/// Single-page race map layout: full map + overprint, control descriptions in a map corner, north arrow,
/// and title box (event, course, scale, contour interval, scale bar) like a printed orienteering map.
public struct CoursePrintLayout: Codable, Hashable, Sendable {
    public enum Corner: String, Codable, CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight

        public var label: String {
            switch self {
            case .topLeft: return "Top left"
            case .topRight: return "Top right"
            case .bottomLeft: return "Bottom left"
            case .bottomRight: return "Bottom right"
            }
        }

        public var isTop: Bool { self == .topLeft || self == .topRight }
        public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    }

    public var descriptionOnMap = true
    public var descriptionCorner = Corner.topRight
    /// Description cell side (mm); IOF 2024: 5–7 mm, usually 6 mm on the map.
    public var descriptionCellMM = 6.0
    /// Second page with descriptions only (to hand out / attach to the arm).
    public var separateDescriptionPage = false
    /// Maximum rows (start, controls, finish) per column; the rest moves to the next column. nil = one column.
    public var descriptionMaxRows: Int?
    /// Free position: top-left corner of the description block from the top-left of the map area (mm, x right, y down).
    /// nil = at `descriptionCorner`.
    public var descriptionOffsetMM: Point2D?
    /// IOF symbol descriptions (columns A–H, pictograms); false = text descriptions (A, B, then text).
    public var descriptionSymbols = true
    /// Description ink color: black (standard) or course purple like the controls.
    public var descriptionColor = DescriptionColor.black

    public enum DescriptionColor: String, Codable, CaseIterable, Sendable {
        case black, purple

        public var label: String { self == .black ? "Black" : "Purple (like controls)" }
        /// Hex color; purple = the course overprint color.
        public var hex: String { self == .black ? "#000000" : CourseStyle.isom.colorHex }
    }

    public init() {}

    /// Unknown keys (title box/north arrow from older versions) are ignored; missing keys = defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        descriptionOnMap = try c.decodeIfPresent(Bool.self, forKey: .descriptionOnMap) ?? true
        descriptionCorner = try c.decodeIfPresent(Corner.self, forKey: .descriptionCorner) ?? .topRight
        // Older projects allowed up to 8 mm; IOF 2024 boxes are 5–7 mm.
        descriptionCellMM = min(max(try c.decodeIfPresent(Double.self, forKey: .descriptionCellMM) ?? 6, Self.cellRangeMM.lowerBound),
                                Self.cellRangeMM.upperBound)
        separateDescriptionPage = try c.decodeIfPresent(Bool.self, forKey: .separateDescriptionPage) ?? false
        descriptionMaxRows = try c.decodeIfPresent(Int.self, forKey: .descriptionMaxRows)
        descriptionOffsetMM = try c.decodeIfPresent(Point2D.self, forKey: .descriptionOffsetMM)
        descriptionSymbols = try c.decodeIfPresent(Bool.self, forKey: .descriptionSymbols) ?? true
        descriptionColor = try c.decodeIfPresent(DescriptionColor.self, forKey: .descriptionColor) ?? .black
    }

    public static let maxRowsRange = 3...40

    /// IOF 2024: description boxes 5–7 mm.
    public static let cellRangeMM: ClosedRange<Double> = 5...7
}

/// Overprint size multipliers relative to the IOF standard (1 = 100%).
public struct CourseAppearance: Codable, Hashable, Sendable {
    /// Control circle, start triangle, finish circles.
    public var controlScale: Double
    /// Control number height.
    public var numberScale: Double
    /// Line width (circles, legs).
    public var lineScale: Double

    public init(controlScale: Double = 1, numberScale: Double = 1, lineScale: Double = 1) {
        self.controlScale = controlScale
        self.numberScale = numberScale
        self.lineScale = lineScale
    }

    public static let range: ClosedRange<Double> = 0.5...2
    public var isStandard: Bool { self == CourseAppearance() }
}

/// All controls + courses in a project (stored in courses.json).
public struct CourseSet: Codable, Hashable, Sendable {
    public var eventTitle: String
    /// Organizer name, printed below the event name on the description sheet (nil in older packages).
    public var organizer: String?
    public var controls: [ControlPoint]
    public var courses: [Course]
    /// First code for automatic numbering.
    public var firstCode: Int
    /// Skip codes that read differently when the card/map is upside down (e.g. 66 ↔ 99, 68 ↔ 89).
    public var avoidAmbiguousCodes: Bool
    /// Course symbol size for all controls (nil = IOF standard), like Purple Pen's "Course appearance".
    public var appearance: CourseAppearance?

    public var effectiveAppearance: CourseAppearance { appearance ?? CourseAppearance() }
    /// Print layout of the course map (position and columns of the control descriptions).
    public var printLayout: CoursePrintLayout?
    /// Extra text, shapes, and images on the course map (nil in older packages).
    public var items: [CourseItem]?
    /// Numbering of the stored control description symbols: `descriptionFormatCurrent` (IOF 2024).
    /// Missing in data saved before the 2024 update, which is migrated once when decoded.
    public var descriptionFormat: Int? = CourseSet.descriptionFormatCurrent

    /// IOF Control Descriptions edition used by the stored symbol ids.
    public static let descriptionFormatCurrent = 2024

    public var allItems: [CourseItem] { items ?? [] }

    public var effectivePrintLayout: CoursePrintLayout { printLayout ?? CoursePrintLayout() }

    public init(eventTitle: String = "", controls: [ControlPoint] = [], courses: [Course] = [], firstCode: Int = 31, avoidAmbiguousCodes: Bool = true) {
        self.eventTitle = eventTitle
        self.controls = controls
        self.courses = courses
        self.firstCode = firstCode
        self.avoidAmbiguousCodes = avoidAmbiguousCodes
    }

    public static let codeRange = 31...255

    /// Decodes all fields (missing optional ones = nil); descriptions saved with the 2018 numbering are converted to 2024.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventTitle = try c.decode(String.self, forKey: .eventTitle)
        organizer = try c.decodeIfPresent(String.self, forKey: .organizer)
        controls = try c.decode([ControlPoint].self, forKey: .controls)
        courses = try c.decode([Course].self, forKey: .courses)
        firstCode = try c.decode(Int.self, forKey: .firstCode)
        avoidAmbiguousCodes = try c.decode(Bool.self, forKey: .avoidAmbiguousCodes)
        appearance = try c.decodeIfPresent(CourseAppearance.self, forKey: .appearance)
        printLayout = try c.decodeIfPresent(CoursePrintLayout.self, forKey: .printLayout)
        items = try c.decodeIfPresent([CourseItem].self, forKey: .items)
        let format = try c.decodeIfPresent(Int.self, forKey: .descriptionFormat) ?? 2018
        if format < 2024 {
            for i in controls.indices { controls[i].description = controls[i].description.migratedFrom2018() }
        }
        descriptionFormat = Self.descriptionFormatCurrent
    }

    public var isEmpty: Bool { controls.isEmpty && courses.isEmpty && allItems.isEmpty }

    /// Extra objects shown on course `course` (nil = the "All controls" view: all objects).
    public func items(for course: Course?) -> [CourseItem] {
        allItems.filter { $0.shows(in: course) }
    }

    public func control(_ id: UUID) -> ControlPoint? { controls.first { $0.id == id } }

    public func course(_ id: UUID) -> Course? { courses.first { $0.id == id } }

    /// The course's controls in order (missing ids are skipped).
    public func controls(of course: Course) -> [ControlPoint] {
        let byID = Dictionary(uniqueKeysWithValues: controls.map { ($0.id, $0) })
        return course.controlIDs.compactMap { byID[$0] }
    }

    // MARK: Control codes

    /// Codes that, read upside down (rotated 180°), become another valid code, e.g. 66 → 99, 68 → 89, 61 → 19.
    public static func isAmbiguous(_ code: Int) -> Bool {
        let flip: [Character: Character] = ["0": "0", "1": "1", "6": "9", "8": "8", "9": "6"]
        let digits = Array(String(code))
        guard digits.allSatisfy({ flip[$0] != nil }) else { return false }
        let rotated = String(digits.reversed().map { flip[$0]! })
        guard rotated.first != "0", let other = Int(rotated) else { return false }
        return other != code && codeRange.contains(other)
    }

    /// Next free code starting at `firstCode`.
    public func nextFreeCode() -> Int? {
        let used = Set(controls.compactMap(\.code))
        for c in max(firstCode, Self.codeRange.lowerBound)...Self.codeRange.upperBound where !used.contains(c) {
            if avoidAmbiguousCodes && Self.isAmbiguous(c) { continue }
            return c
        }
        return nil
    }

    /// Renumber all control codes starting at `firstCode`: in order of appearance in courses (first course first),
    /// then unused controls. Ambiguous codes are skipped when `avoidAmbiguousCodes`.
    public func renumbered() -> CourseSet {
        var order: [UUID] = []
        var seen = Set<UUID>()
        for id in courses.flatMap(\.controlIDs) + controls.map(\.id) where seen.insert(id).inserted {
            if control(id)?.kind == .control { order.append(id) }
        }
        var next = self
        var code = max(firstCode, Self.codeRange.lowerBound)
        for id in order {
            while avoidAmbiguousCodes && Self.isAmbiguous(code) { code += 1 }
            guard Self.codeRange.contains(code), let i = next.controls.firstIndex(where: { $0.id == id }) else { break }
            next.controls[i].code = code
            code += 1
        }
        return next
    }

    /// Codes used by more than one control.
    public var duplicateCodes: Set<Int> {
        var seen = Set<Int>(), dup = Set<Int>()
        for c in controls.compactMap(\.code) where !seen.insert(c).inserted { dup.insert(c) }
        return dup
    }

    // MARK: Length & load

    /// Leg lengths (m, straight line) between consecutive controls.
    public func legLengths(of course: Course) -> [Double] {
        let pts = controls(of: course).map(\.position)
        guard pts.count >= 2 else { return [] }
        return zip(pts, pts.dropFirst()).map { $0.distance(to: $1) }
    }

    /// Course length (m): sum of straight-line legs start → … → finish (IOF/Purple Pen rule).
    /// Score: no order, so 0.
    public func length(of course: Course) -> Double {
        course.kind == .score ? 0 : legLengths(of: course).reduce(0, +)
    }

    /// Control sequence numbers (1…n) within the course; start/finish are not numbered.
    public func sequenceNumbers(of course: Course) -> [UUID: Int] {
        var n = 0
        var out: [UUID: Int] = [:]
        for c in controls(of: course) where c.kind == .control {
            n += 1
            if out[c.id] == nil { out[c.id] = n }
        }
        return out
    }

    /// Control load: number of courses + competitors visiting each control.
    public struct ControlLoad: Hashable, Sendable {
        public var controlID: UUID
        public var courseCount: Int
        public var visits: Int
    }

    public func controlLoads() -> [ControlLoad] {
        controls.map { c in
            let using = courses.filter { $0.controlIDs.contains(c.id) }
            return ControlLoad(controlID: c.id, courseCount: using.count, visits: using.reduce(0) { $0 + $1.competitors })
        }
    }

    /// Load of legs used by more than one course (direction ignored), heaviest first.
    public struct LegLoad: Hashable, Sendable {
        public var from: UUID
        public var to: UUID
        public var courseCount: Int
        public var visits: Int
    }

    public func sharedLegLoads() -> [LegLoad] {
        var table: [String: LegLoad] = [:]
        for course in courses where course.kind == .normal {
            let ids = course.controlIDs
            guard ids.count >= 2 else { continue }
            var seenInCourse = Set<String>()
            for (a, b) in zip(ids, ids.dropFirst()) {
                let key = [a.uuidString, b.uuidString].sorted().joined(separator: "|")
                guard seenInCourse.insert(key).inserted else { continue }
                var l = table[key] ?? LegLoad(from: a, to: b, courseCount: 0, visits: 0)
                l.courseCount += 1
                l.visits += course.competitors
                table[key] = l
            }
        }
        return table.values.filter { $0.courseCount > 1 }.sorted { ($0.visits, $0.courseCount) > ($1.visits, $1.courseCount) }
    }

    // MARK: Warnings (like "Report: course check" in Purple Pen)

    public func warnings(minLegM: Double = 20) -> [String] {
        var out: [String] = []
        for code in duplicateCodes.sorted() { out.append("Code \(code) is used by more than one control.") }
        for c in controls where c.kind == .control {
            if let code = c.code, Self.isAmbiguous(code) { out.append("Code \(code) reads differently upside down.") }
            if c.code == nil { out.append("A control has no code.") }
        }
        // Controls close together or on the same feature (IOF: < 30 m, or < 60 m if the feature is the same).
        let cs = controls.filter { $0.kind == .control }
        for i in cs.indices {
            for j in cs.indices where j > i {
                let d = cs[i].position.distance(to: cs[j].position)
                let sameFeature = cs[i].description.feature != nil && cs[i].description.feature == cs[j].description.feature
                if d < 30 || (sameFeature && d < 60) {
                    out.append("Controls \(cs[i].code ?? 0) and \(cs[j].code ?? 0) are only \(Int(d.rounded())) m apart\(sameFeature ? " on the same feature" : "") (IOF: min. \(sameFeature ? 60 : 30) m).")
                }
            }
        }
        for course in courses {
            let list = controls(of: course)
            if course.kind == .normal {
                if list.first?.kind != .start { out.append("\(course.name): no start yet.") }
                if list.last?.kind != .finish { out.append("\(course.name): no finish yet.") }
                for (a, b) in zip(list, list.dropFirst()) where a.id == b.id {
                    out.append("\(course.name): control \(a.label(in: self)) appears twice in a row.")
                }
                for (a, b) in zip(list, list.dropFirst()) where a.id != b.id && a.position.distance(to: b.position) < minLegM {
                    out.append("\(course.name): leg \(a.label(in: self))–\(b.label(in: self)) is very short.")
                }
            }
            if !list.contains(where: { $0.kind == .control }) { out.append("\(course.name): no controls yet.") }
        }
        return out
    }
}
