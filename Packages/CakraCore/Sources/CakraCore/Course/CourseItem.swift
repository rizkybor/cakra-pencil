import Foundation

/// Objek tambahan di peta lintasan (seperti "special items" Purple Pen / OCAD Course Setting): teks,
/// bentuk (persegi, ellipse, garis), dan gambar JPG/PNG (logo, sponsor, keterangan). Posisi di UTM, jadi ikut
/// peta; ukuran teks/gambar dalam mm kertas.
public struct CourseItem: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case text, rectangle, ellipse, line, image

        public var label: String {
            switch self {
            case .text: return "Teks"
            case .rectangle: return "Persegi"
            case .ellipse: return "Ellipse"
            case .line: return "Garis"
            case .image: return "Gambar"
            }
        }

        public var systemImage: String {
            switch self {
            case .text: return "textformat"
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .line: return "line.diagonal"
            case .image: return "photo"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Teks/gambar: [pusat]. Persegi/ellipse: [pojok, pojok seberang]. Garis: titik-titik (≥ 2).
    public var points: [Point2D]
    public var text: String?
    /// Tinggi huruf di kertas (mm).
    public var textHeightMM: Double?
    /// Persegi/ellipse diisi ungu transparan (mis. area terlarang).
    public var filled: Bool?
    /// Nama file di folder gambar paket proyek.
    public var imageName: String?
    /// Tinggi / lebar gambar.
    public var imageAspect: Double?
    /// Lebar gambar di kertas (mm).
    public var widthMM: Double?
    /// Versi lama: satu lintasan. Dipakai bila `courseIDs` kosong.
    public var courseID: UUID?
    /// Tampil hanya di lintasan-lintasan ini; nil (dan `courseID` nil) = semua lintasan.
    public var courseIDs: [UUID]?
    /// Warna objek "#RRGGBB"; nil = warna lintasan (ungu).
    public var colorHex: String?
    /// Teks: huruf tebal / miring (nil = normal).
    public var bold: Bool?
    public var italic: Bool?

    public init(id: UUID = UUID(), kind: Kind, points: [Point2D], text: String? = nil, textHeightMM: Double? = nil,
                filled: Bool? = nil, imageName: String? = nil, imageAspect: Double? = nil, widthMM: Double? = nil, courseID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.points = points
        self.text = text
        self.textHeightMM = textHeightMM
        self.filled = filled
        self.imageName = imageName
        self.imageAspect = imageAspect
        self.widthMM = widthMM
        self.courseID = courseID
    }

    public static let defaultTextHeightMM = 4.0
    /// Isi teks baru sebelum diketik user.
    public static let placeholderText = "Teks"
    public static let textHeightRangeMM: ClosedRange<Double> = 1.5...20
    public static let defaultImageWidthMM = 30.0
    public static let imageWidthRangeMM: ClosedRange<Double> = 5...200

    public var effectiveTextHeightMM: Double { textHeightMM ?? Self.defaultTextHeightMM }

    /// Ukuran huruf (pt) untuk tinggi huruf `mm` (tinggi huruf kapital ≈ 0,72 em, 1 pt = 0,3528 mm).
    public static func points(forTextHeightMM mm: Double) -> Double { mm / 0.72 / (25.4 / 72) }

    /// Lintasan tempat objek tampil; nil = semua lintasan.
    public var scope: [UUID]? {
        if let ids = courseIDs, !ids.isEmpty { return ids }
        return courseID.map { [$0] }
    }

    /// Atur lintasan tempat objek tampil (nil atau kosong = semua lintasan).
    public mutating func setScope(_ ids: [UUID]?) {
        courseID = nil
        courseIDs = (ids?.isEmpty ?? true) ? nil : ids
    }

    /// Tampil di `course`? (nil = tampilan semua kontrol: semua objek tampil.)
    public func shows(in course: Course?) -> Bool {
        guard let course, let scope else { return true }
        return scope.contains(course.id)
    }

    /// Warna-warna cepat untuk desain tata letak (selain pemilih warna bebas).
    public static let swatches = ["#A626FF", "#000000", "#E8202A", "#0072CE", "#00A651", "#F7941D", "#FFFFFF"]
    public var isFilled: Bool { filled ?? false }

    public var displayName: String {
        switch kind {
        case .text: return (text?.isEmpty == false ? text! : "Teks")
        default: return kind.label
        }
    }

    public func moved(by d: Point2D) -> CourseItem {
        var c = self
        c.points = points.map { $0 + d }
        return c
    }

    /// Ukuran kotak teks/gambar di tanah (m): (lebar, tinggi).
    public func boxSizeM(sheet: SheetSpec) -> (w: Double, h: Double) {
        switch kind {
        case .text:
            let h = sheet.groundMeters(forPaperMM: effectiveTextHeightMM)
            let lines = (text ?? "").split(separator: "\n", omittingEmptySubsequences: false)
            let longest = lines.map(\.count).max() ?? 1
            return (Double(max(longest, 1)) * h * 0.6, h * 1.25 * Double(max(lines.count, 1)))
        case .image:
            let w = sheet.groundMeters(forPaperMM: widthMM ?? Self.defaultImageWidthMM)
            return (w, w * (imageAspect ?? 1))
        default:
            return (0, 0)
        }
    }

    /// Titik garis tepi persegi/ellipse/garis (ellipse: 72 titik).
    public var outline: [Point2D] {
        switch kind {
        case .rectangle:
            guard points.count >= 2 else { return [] }
            let a = points[0], b = points[1]
            return [a, Point2D(x: b.x, y: a.y), b, Point2D(x: a.x, y: b.y)]
        case .ellipse:
            guard points.count >= 2 else { return [] }
            let a = points[0], b = points[1]
            let c = Point2D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let rx = abs(b.x - a.x) / 2, ry = abs(b.y - a.y) / 2
            return (0..<72).map { i in
                let t = Double(i) / 72 * 2 * .pi
                return Point2D(x: c.x + rx * cos(t), y: c.y + ry * sin(t))
            }
        case .line:
            return points
        default:
            return []
        }
    }

    public func bounds(sheet: SheetSpec) -> Rect2D? {
        switch kind {
        case .text, .image:
            guard let c = points.first else { return nil }
            let s = boxSizeM(sheet: sheet)
            return Rect2D(minX: c.x - s.w / 2, minY: c.y - s.h / 2, maxX: c.x + s.w / 2, maxY: c.y + s.h / 2)
        default:
            return Rect2D(points: outline)
        }
    }

    /// Jarak sentuh (m): 0 di dalam teks/gambar/bentuk terisi, selain itu jarak ke garis.
    public func hitDistance(to p: Point2D, sheet: SheetSpec) -> Double {
        switch kind {
        case .text, .image:
            guard let b = bounds(sheet: sheet) else { return .infinity }
            let dx = max(b.minX - p.x, 0, p.x - b.maxX), dy = max(b.minY - p.y, 0, p.y - b.maxY)
            return hypot(dx, dy)
        case .rectangle, .ellipse, .line:
            let pts = outline
            guard pts.count >= 2 else { return .infinity }
            let closed = kind != .line
            if closed, isFilled, Self.contains(pts, p) { return 0 }
            var best = Double.infinity
            for i in 0..<(closed ? pts.count : pts.count - 1) {
                best = min(best, p.distance(toSegment: pts[i], pts[(i + 1) % pts.count]))
            }
            return best
        }
    }

    static func contains(_ poly: [Point2D], _ p: Point2D) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Bentuk overprint objek ini (dengan warna sendiri bila diatur).
    public func marks(sheet: SheetSpec) -> [CourseMark] {
        var body = shapeMarks(sheet: sheet)
        if kind == .text, !body.isEmpty, bold == true || italic == true {
            body = [.font(bold: bold == true, italic: italic == true)] + body + [.font(bold: false, italic: false)]
        }
        guard let colorHex, !body.isEmpty, kind != .image else { return body }
        return [.color(colorHex)] + body + [.color(nil)]
    }

    private func shapeMarks(sheet: SheetSpec) -> [CourseMark] {
        switch kind {
        case .text:
            guard let c = points.first, let t = text, !t.isEmpty else { return [] }
            let h = sheet.groundMeters(forPaperMM: effectiveTextHeightMM)
            let lines = t.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            // Baris berjarak 1,25 × tinggi huruf, blok berpusat di titik.
            let top = c.y + Double(lines.count - 1) * h * 1.25 / 2
            return lines.enumerated().compactMap { i, line in
                line.isEmpty ? nil : .text(line, center: Point2D(x: c.x, y: top - Double(i) * h * 1.25), heightM: h)
            }
        case .image:
            guard let c = points.first, let name = imageName else { return [] }
            let s = boxSizeM(sheet: sheet)
            return [.image(name, center: c, widthM: s.w, heightM: s.h)]
        case .rectangle, .ellipse:
            let pts = outline
            guard pts.count >= 3 else { return [] }
            return (isFilled ? [.fill(pts, opacity: 0.35)] : []) + [.polyline(pts, closed: true)]
        case .line:
            return points.count >= 2 ? [.polyline(points, closed: false)] : []
        }
    }
}
