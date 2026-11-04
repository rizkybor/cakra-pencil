import Foundation

/// Ukuran simbol lintasan (ungu) di kertas, sesuai ISOM 2017-2 (forest) atau ISSprOM 2019-2 (sprint).
public struct CourseStyle: Codable, Hashable, Sendable {
    public var colorHex: String
    public var lineWidthMM: Double
    public var controlDiameterMM: Double
    public var startSideMM: Double
    public var finishInnerMM: Double
    public var finishOuterMM: Double
    public var numberHeightMM: Double

    /// ISOM 2017-2: lingkaran 5 mm, start 6 mm, finish 5/7 mm, garis 0,35 mm, nomor 4 mm.
    public static let isom = CourseStyle(colorHex: "#A626FF", lineWidthMM: 0.35, controlDiameterMM: 5, startSideMM: 6,
                                         finishInnerMM: 5, finishOuterMM: 7, numberHeightMM: 4)
    /// ISSprOM 2019-2: lingkaran 6 mm, start 7 mm, finish 6/8 mm.
    public static let issprom = CourseStyle(colorHex: "#A626FF", lineWidthMM: 0.35, controlDiameterMM: 6, startSideMM: 7,
                                            finishInnerMM: 6, finishOuterMM: 8, numberHeightMM: 4)

    /// Skala sprint (≤ 1:5000) memakai ISSprOM.
    public static func standard(scale: Int) -> CourseStyle { scale <= 5000 ? .issprom : .isom }
}

/// Bentuk overprint dalam meter tanah (UTM), siap digambar di peta, PDF, atau raster.
public enum CourseMark: Hashable, Sendable {
    case circle(center: Point2D, radiusM: Double)
    case polyline([Point2D], closed: Bool)
    /// Teks berpusat di `center`, tinggi huruf dalam meter tanah.
    case text(String, center: Point2D, heightM: Double)
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

    /// Kotak pembatas semua bentuk (untuk zoom/dirty rect).
    public var bounds: Rect2D? {
        Rect2D(points: marks.flatMap { m -> [Point2D] in
            switch m {
            case let .circle(c, r): return [Point2D(x: c.x - r, y: c.y - r), Point2D(x: c.x + r, y: c.y + r)]
            case let .polyline(pts, _): return pts
            case let .text(_, c, h): return [Point2D(x: c.x - h, y: c.y - h), Point2D(x: c.x + h, y: c.y + h)]
            }
        })
    }

    /// Overprint satu lintasan; `course == nil` = semua kontrol (label = kode, tanpa leg), seperti "All controls".
    public static func make(_ set: CourseSet, course: Course?, sheet: SheetSpec, style: CourseStyle? = nil) -> CourseOverprint {
        var st = style ?? .standard(scale: sheet.scaleDenominator)
        // Ukuran pilihan user (global) di atas standar IOF; per kontrol dikalikan lagi `sizeFactor`.
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
                // Kontrol yang dikunjungi lebih dari sekali: "3/7".
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

        /// Jari-jari tempat leg berhenti.
        func trim(_ c: ControlPoint) -> Double {
            let k = c.effectiveSize
            switch c.kind {
            case .control: return m(st.controlDiameterMM / 2 * k)
            case .start: return m(st.startSideMM / sqrt(3) * k)
            case .finish: return m(st.finishOuterMM / 2 * k)
            }
        }

        // Arah leg masuk/keluar per kontrol (untuk arah segitiga start dan posisi nomor).
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
                // Segitiga sama sisi, satu sudut menunjuk ke kontrol pertama (IOF); tanpa leg: ke utara.
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

        // Nomor: di luar lingkaran, pada arah yang paling jauh dari leg (mulai timur laut).
        let h = m(st.numberHeightMM)
        for c in set.controls where labels[c.id] != nil {
            let text = labels[c.id]!
            let used = directions[c.id] ?? []
            let candidates = (0..<8).map { Double.pi / 4 - Double($0) * .pi / 4 }
            func clearance(_ a: Double) -> Double {
                used.map { abs(atan2(sin($0 - a), cos($0 - a))) }.min() ?? .pi
            }
            let best = candidates.max { clearance($0) < clearance($1) } ?? .pi / 4
            // Lebar teks ± 0,6 × tinggi per digit; jarak agar tidak menyentuh lingkaran.
            let halfW = Double(text.count) * h * 0.3
            let reach = trim(c) + h * 0.25 + max(abs(cos(best)) * halfW, abs(sin(best)) * h / 2)
            marks.append(.text(text, center: Point2D(x: c.position.x + reach * cos(best), y: c.position.y + reach * sin(best)), heightM: h))
        }

        return CourseOverprint(marks: marks, lineWidthM: m(st.lineWidthMM), colorHex: st.colorHex)
    }
}
