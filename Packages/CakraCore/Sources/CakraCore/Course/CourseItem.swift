import Foundation

/// Extra object on the course map (like Purple Pen / OCAD Course Setting "special items"): text,
/// shapes (rectangle, ellipse, line), and JPG/PNG images (logos, sponsors, notes). Positioned in UTM, so it moves with
/// the map; text/image size in paper mm.
public struct CourseItem: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case text, rectangle, ellipse, line, image
        /// IOF course symbols (ISOM 2017-2 §3.7 / ISSprOM 2019-2 §4.7), drawn like OCCA's course symbol set.
        case mapIssue, markedRoute, outOfBoundsBoundary, outOfBoundsArea, crossingPoint, outOfBoundsRoute, firstAid,
             refreshment, mapExchange

        public enum Placement: Sendable { case tap, line, area }

        /// The IOF course symbols, in code order (for menus).
        public static let iofSymbols: [Kind] = [.mapIssue, .markedRoute, .outOfBoundsBoundary, .outOfBoundsArea, .crossingPoint,
                                                .outOfBoundsRoute, .firstAid, .refreshment, .mapExchange]

        public var label: String {
            switch self {
            case .text: return "Text"
            case .rectangle: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .line: return "Line"
            case .image: return "Image"
            case .mapIssue: return "702 Map issue point"
            case .markedRoute: return "707 Marked route"
            case .outOfBoundsBoundary: return "708 Out-of-bounds boundary"
            case .outOfBoundsArea: return "709 Out-of-bounds area"
            case .crossingPoint: return "710 Crossing point"
            case .outOfBoundsRoute: return "711 Out-of-bounds route"
            case .firstAid: return "712 First aid post"
            case .refreshment: return "713 Refreshment point"
            case .mapExchange: return "715 Map exchange"
            }
        }

        public var systemImage: String {
            switch self {
            case .text: return "textformat"
            case .rectangle: return "rectangle"
            case .ellipse: return "circle"
            case .line: return "line.diagonal"
            case .image: return "photo"
            case .mapIssue: return "flag"
            case .markedRoute: return "line.diagonal.arrow"
            case .outOfBoundsBoundary: return "minus"
            case .outOfBoundsArea: return "square.slash"
            case .crossingPoint: return "equal"
            case .outOfBoundsRoute: return "xmark"
            case .firstAid: return "cross"
            case .refreshment: return "cup.and.saucer"
            case .mapExchange: return "arrow.triangle.2.circlepath"
            }
        }

        /// How a new object is placed: tap (point symbols), drag a line, drag a rectangle.
        public var placement: Placement {
            switch self {
            case .text, .image, .mapIssue, .crossingPoint, .firstAid, .refreshment, .mapExchange: return .tap
            case .line, .markedRoute, .outOfBoundsBoundary, .outOfBoundsRoute: return .line
            case .rectangle, .ellipse, .outOfBoundsArea: return .area
            }
        }

        public var isIOFSymbol: Bool { Self.iofSymbols.contains(self) }
    }

    public var id: UUID
    public var kind: Kind
    /// Text/image: [center]. Rectangle/ellipse: [corner, opposite corner]. Line: points (≥ 2).
    public var points: [Point2D]
    public var text: String?
    /// Letter height on paper (mm).
    public var textHeightMM: Double?
    /// Rectangle/ellipse filled with transparent purple (e.g. out-of-bounds area).
    public var filled: Bool?
    /// File name in the project package's image folder.
    public var imageName: String?
    /// Image height / width.
    public var imageAspect: Double?
    /// Image width on paper (mm).
    public var widthMM: Double?
    /// Old version: a single course. Used when `courseIDs` is empty.
    public var courseID: UUID?
    /// Shown only on these courses; nil (and `courseID` nil) = all courses.
    public var courseIDs: [UUID]?
    /// Object color "#RRGGBB"; nil = course color (purple).
    public var colorHex: String?
    /// Text: bold / italic (nil = regular).
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
    /// Content of new text before the user types.
    public static let placeholderText = "Text"
    public static let textHeightRangeMM: ClosedRange<Double> = 1.5...20
    public static let defaultImageWidthMM = 30.0
    public static let imageWidthRangeMM: ClosedRange<Double> = 5...200

    public var effectiveTextHeightMM: Double { textHeightMM ?? Self.defaultTextHeightMM }

    /// Font size (pt) for letter height `mm` (cap height ≈ 0.72 em, 1 pt = 0.3528 mm).
    public static func points(forTextHeightMM mm: Double) -> Double { mm / 0.72 / (25.4 / 72) }

    /// Courses on which the object is shown; nil = all courses.
    public var scope: [UUID]? {
        if let ids = courseIDs, !ids.isEmpty { return ids }
        return courseID.map { [$0] }
    }

    /// Set the courses on which the object is shown (nil or empty = all courses).
    public mutating func setScope(_ ids: [UUID]?) {
        courseID = nil
        courseIDs = (ids?.isEmpty ?? true) ? nil : ids
    }

    /// Shown on `course`? (nil = the all-controls view: all objects are shown.)
    public func shows(in course: Course?) -> Bool {
        guard let course, let scope else { return true }
        return scope.contains(course.id)
    }

    /// Quick colors for layout design (besides the free color picker).
    public static let swatches = ["#A626FF", "#000000", "#E8202A", "#0072CE", "#00A651", "#F7941D", "#FFFFFF"]
    public var isFilled: Bool { filled ?? false }

    public var displayName: String {
        switch kind {
        case .text: return (text?.isEmpty == false ? text! : "Text")
        default: return kind.label
        }
    }

    public func moved(by d: Point2D) -> CourseItem {
        var c = self
        c.points = points.map { $0 + d }
        return c
    }

    /// Text/image box size on the ground (m): (width, height).
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

    /// Outline points of a rectangle/ellipse/line (ellipse: 72 points).
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
        case .line, .markedRoute, .outOfBoundsBoundary, .outOfBoundsRoute:
            return points
        case .outOfBoundsArea:
            guard points.count >= 2 else { return [] }
            let a = points[0], b = points[1]
            return [a, Point2D(x: b.x, y: a.y), b, Point2D(x: a.x, y: b.y)]
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
        case .mapIssue, .crossingPoint, .firstAid, .refreshment, .mapExchange:
            guard let c = points.first else { return nil }
            let r = iofSymbolRadiusM(sheet: sheet)
            return Rect2D(minX: c.x - r, minY: c.y - r, maxX: c.x + r, maxY: c.y + r)
        default:
            return Rect2D(points: outline)
        }
    }

    /// Hit distance (m): 0 inside text/images/filled shapes, otherwise the distance to the outline.
    public func hitDistance(to p: Point2D, sheet: SheetSpec) -> Double {
        switch kind {
        case .text, .image:
            guard let b = bounds(sheet: sheet) else { return .infinity }
            let dx = max(b.minX - p.x, 0, p.x - b.maxX), dy = max(b.minY - p.y, 0, p.y - b.maxY)
            return hypot(dx, dy)
        case .mapIssue, .crossingPoint, .firstAid, .refreshment, .mapExchange:
            guard let c = points.first else { return .infinity }
            return max(0, p.distance(to: c) - iofSymbolRadiusM(sheet: sheet))
        case .rectangle, .ellipse, .line, .markedRoute, .outOfBoundsBoundary, .outOfBoundsRoute, .outOfBoundsArea:
            let pts = outline
            guard pts.count >= 2 else { return .infinity }
            let closed = kind.placement == .area
            if closed, isFilled || kind == .outOfBoundsArea, Self.contains(pts, p) { return 0 }
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

    /// Overprint shapes of this object (with its own color if set).
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
            // Lines spaced 1.25 × letter height, block centered on the point.
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
        case .mapIssue, .markedRoute, .outOfBoundsBoundary, .outOfBoundsArea, .crossingPoint, .outOfBoundsRoute, .firstAid,
             .refreshment, .mapExchange:
            return iofMarks(sheet: sheet)
        }
    }
}
