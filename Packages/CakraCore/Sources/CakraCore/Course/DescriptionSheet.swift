import Foundation

/// Lembar deskripsi kontrol satu lintasan (seperti lembar deskripsi Purple Pen dalam mode teks):
/// judul, nama lintasan + panjang + tanjakan, baris start, baris kontrol (A nomor, B kode, deskripsi IOF teks),
/// dan baris finish (jarak dari kontrol terakhir).
public struct DescriptionSheet: Hashable, Sendable {
    public struct Row: Hashable, Sendable {
        /// Start/finish digambar dengan simbolnya (segitiga / lingkaran ganda) di kolom A.
        public var kind: ControlKind
        public var number: String
        public var code: String
        public var text: String
    }

    public var title: String
    public var courseName: String
    public var lengthText: String
    public var climbText: String
    public var rows: [Row]

    public init(_ set: CourseSet, course: Course) {
        title = set.eventTitle
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
                rows.append(Row(kind: .start, number: "", code: "", text: d.isEmpty ? "Start" : "Start: \(d)"))
            case .control:
                n += 1
                let d = c.description.text
                rows.append(Row(kind: .control, number: course.kind == .score ? "" : "\(n)", code: c.code.map(String.init) ?? "",
                                text: d.isEmpty ? "(belum ada deskripsi)" : d))
            case .finish:
                let prev = i > 0 ? list[i - 1] : nil
                let dist = prev.map { Int(($0.position.distance(to: c.position) / 10).rounded() * 10) }
                rows.append(Row(kind: .finish, number: "", code: "", text: dist.map { "Navigasi \($0) m ke finish" } ?? "Finish"))
            }
        }
        self.rows = rows
    }
}
