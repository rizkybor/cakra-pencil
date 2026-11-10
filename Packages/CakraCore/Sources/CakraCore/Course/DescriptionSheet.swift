import Foundation

/// Control description sheet for one course (IOF Control Descriptions 2024; text mode like Purple Pen's):
/// title, organizer, optional classes, course name + length + climb, optional 14.1 distance to the start triangle,
/// start row, control rows (A number, B code, C–H symbols or IOF text) with 15.x special instructions between them,
/// and the 16.x finish row (distance from the last control).
public struct DescriptionSheet: Hashable, Sendable {
    /// A full-width row that is not a control: 14.1 or a 15.x special instruction.
    public enum Special: Hashable, Sendable {
        /// 14.1: distance from the timed start to the start triangle (m).
        case startDistance(Int)
        /// 15.1–15.6 special instruction.
        case instruction(SpecialInstruction.Kind, meters: Int?)

        public var text: String {
            switch self {
            case let .startDistance(m): return "Distance to start triangle: \(m) m"
            case let .instruction(kind, meters): return kind.text(meters: meters)
            }
        }

        public var isInstruction: Bool { if case .instruction = self { return true } else { return false } }
    }

    public struct Row: Hashable, Sendable {
        /// Start/finish are drawn with their symbol (triangle / double circle) in column A.
        public var kind: ControlKind
        public var number: String
        public var code: String
        public var text: String
        /// Columns C–H for symbol descriptions.
        public var description = ControlDescription()
        /// Finish: navigation distance from the last control (m).
        public var finishMeters: Int?
        /// Finish: 16.1 taped, 16.2 funnel, 16.3 navigate.
        public var finishRoute = FinishRoute.navigate
        /// 14.1 / 15.x row (drawn full width); nil = start, control, or finish row.
        public var special: Special?
        /// Index of the row's control in the course's control list (or the "All controls" order), for editing.
        public var controlIndex: Int?
        /// Thick line below this row: after every 3rd control and on both sides of a special instruction.
        public var thickBelow = false

        /// A 14.1 / 15.x row on its own (e.g. a preview in the editor).
        public static func special(_ special: Special) -> Row {
            Row(kind: special.isInstruction ? .control : .start, number: "", code: "", text: special.text, special: special)
        }

        /// Drawn as one full-width row (finish only in symbol mode).
        public func isFullWidth(symbols: Bool) -> Bool { special != nil || (symbols && kind == .finish) }
    }

    public var title: String
    /// Organizer name (row below the event title); empty = not printed.
    public var organizer = ""
    /// Classes line (optional, below the title/organizer), e.g. "M45 M50 W21"; empty = not printed.
    public var classes = ""
    public var courseName: String
    public var lengthText: String
    public var climbText: String
    public var rows: [Row]
    /// Continuation column (no title or course name row), used when rows exceed the per-column limit.
    public var isContinuation = false

    /// Heading rows above the course line (title, organizer, classes); 0 for a continuation column.
    public var headingRowCount: Int {
        isContinuation ? 0 : [title, organizer, classes].filter { !$0.isEmpty }.count
    }

    /// Split into columns of at most `maxRows` rows; the first column carries the title + course name.
    /// Special rows count as rows; thick lines travel with their rows.
    public func columns(maxRows: Int?) -> [DescriptionSheet] {
        guard let maxRows, maxRows > 0, rows.count > maxRows else { return [self] }
        return stride(from: 0, to: rows.count, by: maxRows).map { start in
            var col = self
            col.rows = Array(rows[start..<min(start + maxRows, rows.count)])
            col.isContinuation = start > 0
            return col
        }
    }

    /// Row order for "All controls": start, controls by code, then finish.
    public static func allControlsOrder(_ set: CourseSet) -> [ControlPoint] {
        set.controls.filter { $0.kind == .start }
            + set.controls.filter { $0.kind == .control }.sorted { ($0.code ?? .max) < ($1.code ?? .max) }
            + set.controls.filter { $0.kind == .finish }
    }

    /// Climb as printed: rounded to the nearest 5 m (IOF 2024 heading).
    public static func climbText(_ climbM: Int?) -> String {
        guard let climbM, climbM > 0 else { return "" }
        return "\(Int((Double(climbM) / 5).rounded()) * 5) m"
    }

    /// IOF rule: a thick line after every 3rd control and on both sides of every special instruction.
    static func markThickLines(_ rows: inout [Row]) {
        var n = 0
        for i in rows.indices {
            rows[i].thickBelow = false
        }
        for i in rows.indices {
            if let sp = rows[i].special {
                if sp.isInstruction {
                    rows[i].thickBelow = true
                    if i > 0 { rows[i - 1].thickBelow = true }
                }
            } else if rows[i].kind == .control {
                n += 1
                if n % 3 == 0 { rows[i].thickBelow = true }
            }
        }
    }

    /// Description sheet for `course`; nil = "All controls" (master): column A empty, code in column B, sorted by code,
    /// without course length and finish distance.
    public init(_ set: CourseSet, course: Course?) {
        title = set.eventTitle
        organizer = set.organizer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let course else {
            courseName = "All controls"
            lengthText = ""
            climbText = ""
            var rows: [Row] = Self.allControlsOrder(set).enumerated().map { i, c in
                let d = c.description.text
                switch c.kind {
                case .start: return Row(kind: .start, number: "", code: "", text: d.isEmpty ? "Start" : "Start: \(d)", description: c.description,
                                        controlIndex: i)
                case .control: return Row(kind: .control, number: "", code: c.code.map(String.init) ?? "", text: d, description: c.description,
                                          controlIndex: i)
                case .finish: return Row(kind: .finish, number: "", code: "", text: "Finish", controlIndex: i)
                }
            }
            Self.markThickLines(&rows)
            self.rows = rows
            return
        }
        classes = course.classes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        courseName = course.name
        let km = set.length(of: course) / 1000
        lengthText = course.kind == .score ? "Score" : String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), km)
        climbText = Self.climbText(course.climbM)
        let list = set.controls(of: course)
        var rows: [Row] = []
        if let m = course.startDistanceM, m > 0 {
            rows.append(.special(.startDistance(m)))
        }
        // Special instructions by position: after the n-th control (0 = after the start).
        let specials = course.allSpecialInstructions
        let controlCount = list.filter { $0.kind == .control }.count
        func specialRows(after n: Int) -> [Row] {
            specials.filter { min(max($0.afterControl, 0), controlCount) == n }.map { s in
                let meters = s.kind.hasLength ? s.lengthM : nil
                return Row.special(.instruction(s.kind, meters: meters))
            }
        }
        var placedFirst = !list.contains { $0.kind == .start }
        if placedFirst { rows += specialRows(after: 0) }
        var n = 0
        for (i, c) in list.enumerated() {
            switch c.kind {
            case .start:
                let d = c.description.text
                rows.append(Row(kind: .start, number: "", code: "", text: d.isEmpty ? "Start" : "Start: \(d)", description: c.description,
                                controlIndex: i))
                if !placedFirst { rows += specialRows(after: 0); placedFirst = true }
            case .control:
                n += 1
                let d = c.description.text
                rows.append(Row(kind: .control, number: course.kind == .score ? "" : "\(n)", code: c.code.map(String.init) ?? "",
                                text: d.isEmpty ? "(no description yet)" : d, description: c.description, controlIndex: i))
                rows += specialRows(after: n)
            case .finish:
                let prev = i > 0 ? list[i - 1] : nil
                let dist = prev.map { Int(($0.position.distance(to: c.position) / 10).rounded() * 10) }
                let route = course.effectiveFinishRoute
                rows.append(Row(kind: .finish, number: "", code: "", text: route.text(meters: dist), finishMeters: dist, finishRoute: route,
                                controlIndex: i))
            }
        }
        Self.markThickLines(&rows)
        self.rows = rows
    }
}
