import Foundation

/// Course symbol (purple) sizes on paper, per ISOM 2017-2 (forest) or ISSprOM 2019-2 (sprint).
public struct CourseStyle: Codable, Hashable, Sendable {
    public var colorHex: String
    public var lineWidthMM: Double
    public var controlDiameterMM: Double
    public var startSideMM: Double
    public var finishInnerMM: Double
    public var finishOuterMM: Double
    public var numberHeightMM: Double

    /// ISOM 2017-2 §3.7 at 1:15000: control circle ø5.0, start triangle side 6.0, finish ø4.0 / ø6.0, line 0.35,
    /// control number Arial 4.0 mm.
    public static let isom = CourseStyle(colorHex: "#A626FF", lineWidthMM: 0.35, controlDiameterMM: 5, startSideMM: 6,
                                         finishInnerMM: 4, finishOuterMM: 6, numberHeightMM: 4)
    /// ISSprOM 2019-2 §4.7 at 1:4000: control circle ø6.0, start 7.0, finish ø5.0 / ø7.0, line 0.35, number 4.0 mm.
    public static let issprom = CourseStyle(colorHex: "#A626FF", lineWidthMM: 0.35, controlDiameterMM: 6, startSideMM: 7,
                                            finishInnerMM: 5, finishOuterMM: 7, numberHeightMM: 4)

    /// Sprint scales (≤ 1:5000) use ISSprOM, others ISOM; enlarged maps (1:10000 = 150%, 1:3000 = 133%) enlarge
    /// the course symbols proportionally (ISOM §2.9.1, ISSprOM §3.1).
    public static func standard(scale: Int) -> CourseStyle {
        let standard = MapStandard.for(scale: scale)
        return (standard == .isom ? CourseStyle.isom : .issprom).scaled(by: standard.enlargement(scale: scale))
    }

    /// All sizes × `k` (color unchanged).
    public func scaled(by k: Double) -> CourseStyle {
        CourseStyle(colorHex: colorHex, lineWidthMM: lineWidthMM * k, controlDiameterMM: controlDiameterMM * k,
                    startSideMM: startSideMM * k, finishInnerMM: finishInnerMM * k, finishOuterMM: finishOuterMM * k,
                    numberHeightMM: numberHeightMM * k)
    }

    /// The control number size is a font size (Arial 4.0 mm); digits are ≈ 0.716 of it tall.
    public static let digitHeightPerFontSize = 0.716
}

/// Overprint shapes in ground meters (UTM), ready to draw on the map, PDF, or raster.
public enum CourseMark: Hashable, Sendable {
    case circle(center: Point2D, radiusM: Double)
    case polyline([Point2D], closed: Bool)
    /// Text centered at `center`, letter height in ground meters.
    case text(String, center: Point2D, heightM: Double)
    /// Polygon filled with the overprint color at `opacity` (out-of-bounds areas etc.).
    case fill([Point2D], opacity: Double)
    /// Image (file name in the project package) centered at `center`, size on the ground. Not rotated (grid north up).
    case image(String, center: Point2D, widthM: Double, heightM: Double)
    /// Change color for the following shapes ("#RRGGBB"); nil = back to the overprint color.
    case color(String?)
    /// Font style for the following text (Helvetica / Bold / Oblique / BoldOblique).
    case font(bold: Bool, italic: Bool)
    /// Line width for the following shapes in ground meters (IOF symbols: 708 boundary, 712 cross…); nil = the course line.
    case width(Double?)
}

public struct CourseOverprint: Hashable, Sendable {
    public var marks: [CourseMark]
    public var lineWidthM: Double
    public var colorHex: String

    public init(marks: [CourseMark], lineWidthM: Double, colorHex: String) {
        self.marks = marks
        self.lineWidthM = lineWidthM
        self.colorHex = colorHex
    }

    public var isEmpty: Bool { marks.isEmpty }

    /// Gap between a course line and the control circles (paper mm, at the standard 0.35 mm line).
    public static let legGapMM = 0.3

    /// Bounding box of all shapes (for zoom/dirty rect).
    public var bounds: Rect2D? {
        Rect2D(points: marks.flatMap { m -> [Point2D] in
            switch m {
            case let .circle(c, r): return [Point2D(x: c.x - r, y: c.y - r), Point2D(x: c.x + r, y: c.y + r)]
            case let .polyline(pts, _): return pts
            case let .text(t, c, h):
                let w = max(Double(t.count) * h * 0.35, h)
                return [Point2D(x: c.x - w, y: c.y - h), Point2D(x: c.x + w, y: c.y + h)]
            case let .fill(pts, _): return pts
            case let .image(_, c, w, h): return [Point2D(x: c.x - w / 2, y: c.y - h / 2), Point2D(x: c.x + w / 2, y: c.y + h / 2)]
            case .color, .font, .width: return []
            }
        })
    }

    /// Overprint of one course; `course == nil` = all controls (label = code, no legs), like "All controls".
    public static func make(_ set: CourseSet, course: Course?, sheet: SheetSpec, style: CourseStyle? = nil) -> CourseOverprint {
        var st = style ?? .standard(scale: sheet.scaleDenominator)
        // User-chosen sizes (global) on top of the IOF standard; per control multiplied again by `sizeFactor`.
        let look = set.effectiveAppearance
        st.controlDiameterMM *= look.controlScale
        st.startSideMM *= look.controlScale
        st.finishInnerMM *= look.controlScale
        st.finishOuterMM *= look.controlScale
        st.numberHeightMM *= look.numberScale
        st.lineWidthMM *= look.lineScale
        let m = { (mm: Double) in sheet.groundMeters(forPaperMM: mm) }
        var marks: [CourseMark] = []

        let list: [ControlPoint]
        let legs: Bool
        var labels: [UUID: String] = [:]
        if let course {
            list = set.controls(of: course)
            legs = course.kind == .normal
            if course.kind == .normal {
                // Controls visited more than once: "3/7".
                var n = 0
                for c in list where c.kind == .control {
                    n += 1
                    labels[c.id] = labels[c.id].map { "\($0)/\(n)" } ?? "\(n)"
                }
            } else {
                for c in list where c.kind == .control { labels[c.id] = c.code.map(String.init) ?? "?" }
            }
        } else {
            list = set.controls
            legs = false
            for c in list where c.kind == .control { labels[c.id] = c.code.map(String.init) ?? "?" }
        }

        /// Radius at which legs stop.
        // ISOM 705 / ISSprOM: a small gap between the course line and the circles (0.3 mm on paper, enlarged with the map).
        let legGap = m(Self.legGapMM * st.lineWidthMM / 0.35)
        func trim(_ c: ControlPoint) -> Double {
            let k = c.effectiveSize
            switch c.kind {
            case .control: return m(st.controlDiameterMM / 2 * k) + legGap
            case .start: return m(st.startSideMM / sqrt(3) * k) + legGap
            case .finish: return m(st.finishOuterMM / 2 * k) + legGap
            }
        }

        // Incoming/outgoing leg directions per control (for start triangle direction and number placement).
        var directions: [UUID: [Double]] = [:]
        if legs {
            for (a, b) in zip(list, list.dropFirst()) where a.id != b.id {
                let ang = atan2(b.position.y - a.position.y, b.position.x - a.position.x)
                directions[a.id, default: []].append(ang)
                directions[b.id, default: []].append(ang + .pi)
            }
        }

        var drawn = Set<UUID>()
        for c in list where drawn.insert(c.id).inserted {
            let p = c.position
            let k = c.effectiveSize
            switch c.kind {
            case .control:
                marks.append(.circle(center: p, radiusM: m(st.controlDiameterMM / 2 * k)))
            case .finish:
                marks.append(.circle(center: p, radiusM: m(st.finishInnerMM / 2 * k)))
                marks.append(.circle(center: p, radiusM: m(st.finishOuterMM / 2 * k)))
            case .start:
                // Equilateral triangle, one corner pointing to the first control (IOF); without legs: north.
                let heading = directions[c.id]?.first ?? .pi / 2
                let r = m(st.startSideMM / sqrt(3) * k)
                let pts = (0..<3).map { i -> Point2D in
                    let a = heading + Double(i) * 2 * .pi / 3
                    return Point2D(x: p.x + r * cos(a), y: p.y + r * sin(a))
                }
                marks.append(.polyline(pts, closed: true))
            }
        }

        if legs {
            for (a, b) in zip(list, list.dropFirst()) where a.id != b.id {
                let d = a.position.distance(to: b.position)
                let ra = trim(a), rb = trim(b)
                guard d > ra + rb else { continue }
                let ux = (b.position.x - a.position.x) / d, uy = (b.position.y - a.position.y) / d
                marks.append(.polyline([Point2D(x: a.position.x + ux * ra, y: a.position.y + uy * ra),
                                        Point2D(x: b.position.x - ux * rb, y: b.position.y - uy * rb)], closed: false))
            }
        }

        // Number: outside the circle, in the direction farthest from the legs (starting north-east).
        // `numberHeightMM` is the font size; text marks carry the digit height.
        let h = m(st.numberHeightMM * CourseStyle.digitHeightPerFontSize)
        for c in set.controls where labels[c.id] != nil {
            let text = labels[c.id]!
            let used = directions[c.id] ?? []
            let candidates = (0..<8).map { Double.pi / 4 - Double($0) * .pi / 4 }
            func clearance(_ a: Double) -> Double {
                used.map { abs(atan2(sin($0 - a), cos($0 - a))) }.min() ?? .pi
            }
            let best = candidates.max { clearance($0) < clearance($1) } ?? .pi / 4
            // Text width ≈ 0.6 × height per digit; offset so it does not touch the circle.
            let halfW = Double(text.count) * h * 0.3
            let reach = trim(c) + h * 0.25 + max(abs(cos(best)) * halfW, abs(sin(best)) * h / 2)
            marks.append(.text(text, center: Point2D(x: c.position.x + reach * cos(best), y: c.position.y + reach * sin(best)), heightM: h))
        }

        // Extra objects (text, shapes, images): images at the bottom so the course lines stay visible on top.
        let extra = set.items(for: course).flatMap { $0.marks(sheet: sheet) }
        let images = extra.filter { if case .image = $0 { return true } else { return false } }
        let others = extra.filter { if case .image = $0 { return false } else { return true } }
        return CourseOverprint(marks: images + marks + others, lineWidthM: m(st.lineWidthMM), colorHex: st.colorHex)
    }
}
