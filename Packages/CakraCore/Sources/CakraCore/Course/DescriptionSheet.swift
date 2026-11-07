import Foundation

/// Control description sheet for one course (like Purple Pen's description sheet in text mode):
/// title, course name + length + climb, start row, control rows (A number, B code, IOF text description),
/// and finish row (distance from the last control). Columns C–H are carried per row for IOF symbol descriptions.
public struct DescriptionSheet: Hashable, Sendable {
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
    }

    public var title: String
    /// Organizer name (row below the event title); empty = not printed.
    public var organizer = ""
    public var courseName: String
    public var lengthText: String
    public var climbText: String
    public var rows: [Row]
    /// Continuation column (no title or course name row), used when rows exceed the per-column limit.
    public var isContinuation = false

    /// Split into columns of at most `maxRows` rows; the first column carries the title + course name.
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

    /// Description sheet for `course`; nil = "All controls" (master): column A empty, code in column B, sorted by code,
    /// without course length and finish distance.
    public init(_ set: CourseSet, course: Course?) {
        guard let course else {
            title = set.eventTitle
            organizer = set.organizer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            courseName = "All controls"
            lengthText = ""
            climbText = ""
            rows = Self.allControlsOrder(set).map { c in
                let d = c.description.text
                switch c.kind {
                case .start: return Row(kind: .start, number: "", code: "", text: d.isEmpty ? "Start" : "Start: \(d)", description: c.description)
                case .control: return Row(kind: .control, number: "", code: c.code.map(String.init) ?? "", text: d, description: c.description)
                case .finish: return Row(kind: .finish, number: "", code: "", text: "Finish")
                }
            }
            return
        }
        title = set.eventTitle
        organizer = set.organizer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        courseName = course.name
        let km = set.length(of: course) / 1000
        lengthText = course.kind == .score ? "Score" : String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), km)
        climbText = course.climbM.map { "\($0) m" } ?? ""
        let list = set.controls(of: course)
        var rows: [Row] = []
        var n = 0
        for (i, c) in list.enumerated() {
            switch c.kind {
            case .start:
                let d = c.description.text
                rows.append(Row(kind: .start, number: "", code: "", text: d.isEmpty ? "Start" : "Start: \(d)", description: c.description))
            case .control:
                n += 1
                let d = c.description.text
                rows.append(Row(kind: .control, number: course.kind == .score ? "" : "\(n)", code: c.code.map(String.init) ?? "",
                                text: d.isEmpty ? "(no description yet)" : d, description: c.description))
            case .finish:
                let prev = i > 0 ? list[i - 1] : nil
                let dist = prev.map { Int(($0.position.distance(to: c.position) / 10).rounded() * 10) }
                rows.append(Row(kind: .finish, number: "", code: "", text: dist.map { "Navigate \($0) m to finish" } ?? "Finish",
                                finishMeters: dist))
            }
        }
        self.rows = rows
    }
}
