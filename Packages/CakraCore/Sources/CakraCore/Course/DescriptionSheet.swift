import Foundation

/// Lembar deskripsi kontrol satu lintasan (seperti lembar deskripsi Purple Pen dalam mode teks):
/// judul, nama lintasan + panjang + tanjakan, baris start, baris kontrol (A nomor, B kode, deskripsi IOF teks),
/// dan baris finish (jarak dari kontrol terakhir). Kolom C–H dibawa per baris untuk deskripsi bergambar IOF.
public struct DescriptionSheet: Hashable, Sendable {
    public struct Row: Hashable, Sendable {
        /// Start/finish digambar dengan simbolnya (segitiga / lingkaran ganda) di kolom A.
        public var kind: ControlKind
        public var number: String
        public var code: String
        public var text: String
        /// Kolom C–H untuk deskripsi bergambar.
        public var description = ControlDescription()
        /// Finish: jarak navigasi dari kontrol terakhir (m).
        public var finishMeters: Int?
    }

    public var title: String
    /// Nama penyelenggara (baris di bawah judul acara); kosong = tidak dicetak.
    public var organizer = ""
    public var courseName: String
    public var lengthText: String
    public var climbText: String
    public var rows: [Row]
    /// Kolom lanjutan (tanpa judul dan baris nama lintasan), dipakai bila baris melebihi batas per kolom.
    public var isContinuation = false

    /// Bagi jadi kolom berisi maksimal `maxRows` baris; kolom pertama membawa judul + nama lintasan.
    public func columns(maxRows: Int?) -> [DescriptionSheet] {
        guard let maxRows, maxRows > 0, rows.count > maxRows else { return [self] }
        return stride(from: 0, to: rows.count, by: maxRows).map { start in
            var col = self
            col.rows = Array(rows[start..<min(start + maxRows, rows.count)])
            col.isContinuation = start > 0
            return col
        }
    }

    public init(_ set: CourseSet, course: Course) {
        title = set.eventTitle
        organizer = set.organizer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        courseName = course.name
        let km = set.length(of: course) / 1000
        lengthText = course.kind == .score ? "Score" : String(format: "%.1f km", locale: Locale(identifier: "id_ID"), km)
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
                                text: d.isEmpty ? "(belum ada deskripsi)" : d, description: c.description))
            case .finish:
                let prev = i > 0 ? list[i - 1] : nil
                let dist = prev.map { Int(($0.position.distance(to: c.position) / 10).rounded() * 10) }
                rows.append(Row(kind: .finish, number: "", code: "", text: dist.map { "Navigasi \($0) m ke finish" } ?? "Finish",
                                finishMeters: dist))
            }
        }
        self.rows = rows
    }
}
