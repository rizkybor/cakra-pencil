import Foundation

/// Course planner (seperti Purple Pen / OCAD Course Setting): kontrol dipakai bersama oleh banyak lintasan,
/// lintasan = urutan kontrol. Posisi dalam CRS proyek (UTM, meter).

public enum ControlKind: String, Codable, CaseIterable, Sendable {
    case start, control, finish

    public var label: String {
        switch self {
        case .start: return "Start"
        case .control: return "Kontrol"
        case .finish: return "Finish"
        }
    }
}

/// Satu titik kontrol (start, kontrol, atau finish) di peta.
public struct ControlPoint: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: ControlKind
    /// Kode kontrol (31–255 sesuai unit punching SPORTident/Emit); nil untuk start/finish.
    public var code: Int?
    public var position: Point2D
    public var description: ControlDescription

    public init(id: UUID = UUID(), kind: ControlKind, code: Int? = nil, position: Point2D, description: ControlDescription = ControlDescription()) {
        self.id = id
        self.kind = kind
        self.code = code
        self.position = position
        self.description = description
    }

    /// Label singkat: "31", "S1", "F1".
    public func label(in set: CourseSet) -> String {
        switch kind {
        case .control: return code.map(String.init) ?? "?"
        case .start: return "S\((set.controls.filter { $0.kind == .start }.firstIndex { $0.id == id } ?? 0) + 1)"
        case .finish: return "F\((set.controls.filter { $0.kind == .finish }.firstIndex { $0.id == id } ?? 0) + 1)"
        }
    }

    /// Id untuk IOF XML (`<Id>`): kode kontrol, atau S1/F1.
    public func iofID(in set: CourseSet) -> String { label(in: set) }
}

public enum CourseKind: String, Codable, CaseIterable, Sendable {
    /// Urutan tetap: start → kontrol 1…n → finish.
    case normal
    /// Score/rogaining: urutan bebas, kontrol diberi nomor kodenya.
    case score

    public var label: String { self == .normal ? "Urutan" : "Score" }
}

/// Lintasan: urutan kontrol + data peserta.
public struct Course: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: CourseKind
    /// Urutan id kontrol, termasuk start (awal) dan finish (akhir) bila ada.
    public var controlIDs: [UUID]
    /// Perkiraan jumlah peserta (untuk hitung beban kontrol, seperti "Competitor load" di Purple Pen).
    public var competitors: Int
    /// Total tanjakan (m), diisi manual seperti di Purple Pen.
    public var climbM: Int?

    public init(id: UUID = UUID(), name: String, kind: CourseKind = .normal, controlIDs: [UUID] = [], competitors: Int = 0, climbM: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.controlIDs = controlIDs
        self.competitors = competitors
        self.climbM = climbM
    }
}

/// Semua kontrol + lintasan dalam satu proyek (disimpan di courses.json).
public struct CourseSet: Codable, Hashable, Sendable {
    public var eventTitle: String
    public var controls: [ControlPoint]
    public var courses: [Course]
    /// Kode pertama untuk penomoran otomatis.
    public var firstCode: Int
    /// Lewati kode yang terbaca lain bila kartu/peta terbalik (mis. 66 ↔ 99, 68 ↔ 89).
    public var avoidAmbiguousCodes: Bool

    public init(eventTitle: String = "", controls: [ControlPoint] = [], courses: [Course] = [], firstCode: Int = 31, avoidAmbiguousCodes: Bool = true) {
        self.eventTitle = eventTitle
        self.controls = controls
        self.courses = courses
        self.firstCode = firstCode
        self.avoidAmbiguousCodes = avoidAmbiguousCodes
    }

    public static let codeRange = 31...255

    public var isEmpty: Bool { controls.isEmpty && courses.isEmpty }

    public func control(_ id: UUID) -> ControlPoint? { controls.first { $0.id == id } }

    public func course(_ id: UUID) -> Course? { courses.first { $0.id == id } }

    /// Kontrol lintasan sesuai urutan (id yang hilang dilewati).
    public func controls(of course: Course) -> [ControlPoint] {
        let byID = Dictionary(uniqueKeysWithValues: controls.map { ($0.id, $0) })
        return course.controlIDs.compactMap { byID[$0] }
    }

    // MARK: Kode kontrol

    /// Kode yang dibaca terbalik (diputar 180°) menjadi kode lain yang sah, mis. 66 → 99, 68 → 89, 61 → 19.
    public static func isAmbiguous(_ code: Int) -> Bool {
        let flip: [Character: Character] = ["0": "0", "1": "1", "6": "9", "8": "8", "9": "6"]
        let digits = Array(String(code))
        guard digits.allSatisfy({ flip[$0] != nil }) else { return false }
        let rotated = String(digits.reversed().map { flip[$0]! })
        guard rotated.first != "0", let other = Int(rotated) else { return false }
        return other != code && codeRange.contains(other)
    }

    /// Kode bebas berikutnya mulai `firstCode`.
    public func nextFreeCode() -> Int? {
        let used = Set(controls.compactMap(\.code))
        for c in max(firstCode, Self.codeRange.lowerBound)...Self.codeRange.upperBound where !used.contains(c) {
            if avoidAmbiguousCodes && Self.isAmbiguous(c) { continue }
            return c
        }
        return nil
    }

    /// Kode yang dipakai lebih dari satu kontrol.
    public var duplicateCodes: Set<Int> {
        var seen = Set<Int>(), dup = Set<Int>()
        for c in controls.compactMap(\.code) where !seen.insert(c).inserted { dup.insert(c) }
        return dup
    }

    // MARK: Panjang & beban

    /// Panjang leg (m, garis lurus) antar kontrol berurutan.
    public func legLengths(of course: Course) -> [Double] {
        let pts = controls(of: course).map(\.position)
        guard pts.count >= 2 else { return [] }
        return zip(pts, pts.dropFirst()).map { $0.distance(to: $1) }
    }

    /// Panjang lintasan (m): jumlah leg garis lurus start → … → finish (aturan IOF/Purple Pen).
    /// Score: tidak ada urutan, jadi 0.
    public func length(of course: Course) -> Double {
        course.kind == .score ? 0 : legLengths(of: course).reduce(0, +)
    }

    /// Nomor urut kontrol (1…n) dalam lintasan; start/finish tidak bernomor.
    public func sequenceNumbers(of course: Course) -> [UUID: Int] {
        var n = 0
        var out: [UUID: Int] = [:]
        for c in controls(of: course) where c.kind == .control {
            n += 1
            if out[c.id] == nil { out[c.id] = n }
        }
        return out
    }

    /// Beban kontrol: jumlah lintasan + peserta yang mengunjungi tiap kontrol.
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

    /// Beban leg yang dipakai lebih dari satu lintasan (arah tidak dibedakan), urut dari yang terberat.
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

    // MARK: Peringatan (seperti "Report: course check" di Purple Pen)

    public func warnings(minLegM: Double = 20) -> [String] {
        var out: [String] = []
        for code in duplicateCodes.sorted() { out.append("Kode \(code) dipakai lebih dari satu kontrol.") }
        for c in controls where c.kind == .control {
            if let code = c.code, Self.isAmbiguous(code) { out.append("Kode \(code) terbaca lain bila terbalik.") }
            if c.code == nil { out.append("Ada kontrol tanpa kode.") }
        }
        // Kontrol berdekatan dengan fitur sama (IOF: < 30 m, atau < 60 m bila fitur sama).
        let cs = controls.filter { $0.kind == .control }
        for i in cs.indices {
            for j in cs.indices where j > i {
                let d = cs[i].position.distance(to: cs[j].position)
                let sameFeature = cs[i].description.feature != nil && cs[i].description.feature == cs[j].description.feature
                if d < 30 || (sameFeature && d < 60) {
                    out.append("Kontrol \(cs[i].code ?? 0) dan \(cs[j].code ?? 0) hanya \(Int(d.rounded())) m\(sameFeature ? " dengan fitur sama" : "") (IOF: min. \(sameFeature ? 60 : 30) m).")
                }
            }
        }
        for course in courses {
            let list = controls(of: course)
            if course.kind == .normal {
                if list.first?.kind != .start { out.append("\(course.name): belum ada start.") }
                if list.last?.kind != .finish { out.append("\(course.name): belum ada finish.") }
                for (a, b) in zip(list, list.dropFirst()) where a.id == b.id {
                    out.append("\(course.name): kontrol \(a.label(in: self)) dua kali berturut-turut.")
                }
                for (a, b) in zip(list, list.dropFirst()) where a.id != b.id && a.position.distance(to: b.position) < minLegM {
                    out.append("\(course.name): leg \(a.label(in: self))–\(b.label(in: self)) sangat pendek.")
                }
            }
            if !list.contains(where: { $0.kind == .control }) { out.append("\(course.name): belum ada kontrol.") }
        }
        return out
    }
}
