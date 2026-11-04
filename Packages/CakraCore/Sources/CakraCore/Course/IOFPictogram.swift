import CoreGraphics
import Foundation

/// Piktogram deskripsi kontrol IOF (kolom C–H) sebagai gambar vektor sederhana di kotak satuan
/// (0…1, y ke atas). Satu definisi dipakai untuk PDF dan pratinjau di layar, jadi tampilannya sama.
///
/// Bentuknya disederhanakan dari spesifikasi IOF 2018 agar tetap terbaca pada kotak 5–7 mm.
public enum IOFPictogram {
    public enum Shape: Hashable, Sendable {
        /// Garis patah (tidak tertutup).
        case line([Point2D])
        /// Poligon tertutup; `fill` = diisi penuh.
        case poly([Point2D], fill: Bool)
        case circle(Point2D, r: Double, fill: Bool)
        /// Busur dari sudut a0 ke a1 (radian, berlawanan jarum jam).
        case arc(Point2D, r: Double, a0: Double, a1: Double)
        /// Titik-titik kecil terisi.
        case dots([Point2D], r: Double)
        /// Teks di tengah kotak (dimensi kolom F), `size` relatif tinggi kotak.
        case text(String, at: Point2D, size: Double)
    }

    /// Tebal garis relatif sisi kotak.
    public static let lineWidth = 0.055

    // MARK: Bentuk per simbol

    /// Bentuk satu simbol; nil bila id tidak dikenal.
    public static func shapes(_ id: String?) -> [Shape]? {
        guard let id, !id.isEmpty else { return nil }
        if let s = table[id] { return s }
        if id.hasPrefix("0.1"), let a = angle(String(id.dropFirst(3))) { return arrow(a) }
        if id.hasPrefix("11.1"), let a = angle(String(id.dropFirst(4))) {
            let d = P(0.5 + 0.34 * cos(a), 0.5 + 0.34 * sin(a))
            return [.circle(P(0.5, 0.5), r: 0.2, fill: false), .dots([d], r: 0.07)]
        }
        return nil
    }

    /// Dimensi kolom F yang diketik ("1.5", "8x4", "1.0/2.5") sebagai teks; simbol 10.x sebagai gambar.
    public static func dimensionShapes(_ value: String?) -> [Shape]? {
        guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        if let s = shapes(v), IOFSymbols.symbol(v)?.column == .f { return s }
        let parts = v.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2 {
            return [.text(parts[0], at: P(0.42, 0.68), size: 0.32), .line([P(0.15, 0.15), P(0.85, 0.85)]),
                    .text(parts[1], at: P(0.62, 0.22), size: 0.32)]
        }
        let t = v.replacingOccurrences(of: "x", with: "×").replacingOccurrences(of: "X", with: "×")
        return [.text(t, at: P(0.5, 0.5), size: t.count > 4 ? 0.3 : 0.4)]
    }

    private static func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    private static func angle(_ dir: String) -> Double? {
        let d: [String: Double] = ["E": 0, "NE": 45, "N": 90, "NW": 135, "W": 180, "SW": 225, "S": 270, "SE": 315]
        return d[dir].map { $0 * .pi / 180 }
    }

    /// Panah dari tengah ke arah `a` (kolom C: paling utara, dst.).
    private static func arrow(_ a: Double) -> [Shape] {
        let tip = P(0.5 + 0.36 * cos(a), 0.5 + 0.36 * sin(a)), tail = P(0.5 - 0.36 * cos(a), 0.5 - 0.36 * sin(a))
        let l = P(tip.x - 0.2 * cos(a - 0.5), tip.y - 0.2 * sin(a - 0.5)), r = P(tip.x - 0.2 * cos(a + 0.5), tip.y - 0.2 * sin(a + 0.5))
        return [.line([tail, tip]), .line([l, tip, r])]
    }

    private static func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, fill: Bool = false) -> Shape {
        .poly([P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)], fill: fill)
    }

    private static func triangle(_ cx: Double, _ cy: Double, _ s: Double) -> Shape {
        .poly([P(cx - s, cy - s * 0.8), P(cx + s, cy - s * 0.8), P(cx, cy + s * 0.9)], fill: true)
    }

    private static func dashes(_ y: Double, from x0: Double = 0.15, to x1: Double = 0.85, count: Int = 3) -> [Shape] {
        let step = (x1 - x0) / Double(count * 2 - 1)
        return (0..<count).map { i in .line([P(x0 + Double(i * 2) * step, y), P(x0 + Double(i * 2 + 1) * step, y)]) }
    }

    private static func grid(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, n: Int = 4) -> [Shape] {
        (0...n).flatMap { i -> [Shape] in
            let t = Double(i) / Double(n)
            return [.line([P(x0 + (x1 - x0) * t, y0), P(x0 + (x1 - x0) * t, y1)]), .line([P(x0, y0 + (y1 - y0) * t), P(x1, y0 + (y1 - y0) * t)])]
        }
    }

    private static func scatter(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, n: Int) -> [Point2D] {
        (0..<n).flatMap { i in (0..<n).map { j in
            P(x0 + (x1 - x0) * (Double(i) + (j % 2 == 0 ? 0.25 : 0.75)) / Double(n), y0 + (y1 - y0) * (Double(j) + 0.5) / Double(n))
        } }
    }

    private static func tree(_ cx: Double, _ cy: Double, _ r: Double) -> [Shape] {
        [.circle(P(cx, cy + r * 0.4), r: r, fill: false), .line([P(cx, cy - r * 0.6), P(cx, cy - r * 1.8)])]
    }

    // swiftlint:disable:next function_body_length
    private static let table: [String: [Shape]] = {
        var t: [String: [Shape]] = [:]
        let c = P(0.5, 0.5)

        // C: yang mana
        t["0.2"] = [.line([P(0.15, 0.68), P(0.85, 0.68)]), .line([P(0.15, 0.32), P(0.85, 0.32)]), .dots([P(0.5, 0.68)], r: 0.09)]
        t["0.3"] = [.line([P(0.15, 0.68), P(0.85, 0.68)]), .line([P(0.15, 0.32), P(0.85, 0.32)]), .dots([P(0.5, 0.32)], r: 0.09)]
        t["0.4"] = [.line([P(0.15, 0.78), P(0.85, 0.78)]), .line([P(0.15, 0.5), P(0.85, 0.5)]), .line([P(0.15, 0.22), P(0.85, 0.22)]),
                    .dots([P(0.5, 0.5)], r: 0.09)]

        // D: bentuk lahan
        t["1.1"] = [.line([P(0.12, 0.3), P(0.42, 0.3), P(0.58, 0.7), P(0.88, 0.7)])]
        t["1.2"] = [.arc(P(0.5, 0.3), r: 0.32, a0: 0, a1: .pi)]
        t["1.3"] = [.arc(P(0.5, 0.7), r: 0.32, a0: .pi, a1: 2 * .pi)]
        t["1.4"] = [.line([P(0.12, 0.65), P(0.88, 0.65)])] + [0.22, 0.42, 0.62, 0.82].map { .line([P($0, 0.65), P($0, 0.4)]) }
        t["1.5"] = [.arc(c, r: 0.32, a0: .pi * 0.15, a1: .pi * 0.85), .arc(c, r: 0.32, a0: .pi * 1.15, a1: .pi * 1.85)]
            + [0.3, 0.5, 0.7].map { .line([P($0, 0.82 - abs($0 - 0.5) * 0.4), P($0, 0.62)]) }
        t["1.6"] = [.line([P(0.12, 0.5), P(0.88, 0.5)])] + [0.25, 0.5, 0.75].flatMap { x -> [Shape] in
            [.line([P(x, 0.5), P(x, 0.72)]), .line([P(x, 0.5), P(x, 0.28)])]
        }
        t["1.7"] = [.line([P(0.15, 0.78), P(0.85, 0.5), P(0.15, 0.22)])]
        t["1.8"] = [.dots([0.18, 0.34, 0.5, 0.66, 0.82].map { P($0, 0.5) }, r: 0.05)]
        t["1.9"] = [.circle(c, r: 0.34, fill: false)]
        t["1.10"] = [.circle(c, r: 0.16, fill: true)]
        t["1.11"] = [.arc(P(0.05, 0.5), r: 0.3, a0: -.pi / 2.6, a1: .pi / 2.6), .arc(P(0.95, 0.5), r: 0.3, a0: .pi - .pi / 2.6, a1: .pi + .pi / 2.6)]
        t["1.12"] = [.circle(c, r: 0.32, fill: false)] + [0.0, 0.5, 1.0, 1.5].map { k in
            let a = k * .pi
            return .line([P(0.5 + 0.32 * cos(a), 0.5 + 0.32 * sin(a)), P(0.5 + 0.18 * cos(a), 0.5 + 0.18 * sin(a))])
        }
        t["1.13"] = [.arc(P(0.5, 0.62), r: 0.26, a0: .pi, a1: 2 * .pi)]
        t["1.14"] = [.line([P(0.25, 0.75), P(0.5, 0.25), P(0.75, 0.75)])]
        t["1.15"] = [.line([P(0.15, 0.7), P(0.25, 0.5), P(0.35, 0.7)]), .line([P(0.6, 0.45), P(0.7, 0.25), P(0.8, 0.45)]),
                     .dots([P(0.7, 0.75), P(0.25, 0.25), P(0.5, 0.5)], r: 0.06)]
        t["1.16"] = (0..<4).map { k in
            let a = Double(k) * .pi / 4
            return .line([P(0.5 - 0.28 * cos(a), 0.5 - 0.28 * sin(a)), P(0.5 + 0.28 * cos(a), 0.5 + 0.28 * sin(a))])
        }

        // D: batuan
        t["2.1"] = [.line([P(0.12, 0.7), P(0.88, 0.7)]), .poly([P(0.2, 0.7), P(0.3, 0.7), P(0.25, 0.32)], fill: true),
                    .poly([P(0.45, 0.7), P(0.55, 0.7), P(0.5, 0.32)], fill: true), .poly([P(0.7, 0.7), P(0.8, 0.7), P(0.75, 0.32)], fill: true)]
        t["2.2"] = [.poly([P(0.38, 0.15), P(0.62, 0.15), P(0.58, 0.85), P(0.42, 0.85)], fill: true)]
        t["2.3"] = [.poly([P(0.2, 0.5), P(0.8, 0.8), P(0.8, 0.2)], fill: true)]
        t["2.4"] = [triangle(0.5, 0.47, 0.3)]
        t["2.5"] = [triangle(0.3, 0.7, 0.15), triangle(0.7, 0.68, 0.13), triangle(0.32, 0.3, 0.13), triangle(0.72, 0.28, 0.15)]
        t["2.6"] = [triangle(0.35, 0.36, 0.17), triangle(0.65, 0.36, 0.17), triangle(0.5, 0.66, 0.17)]
        t["2.7"] = [triangle(0.25, 0.72, 0.08), triangle(0.7, 0.75, 0.08), triangle(0.48, 0.5, 0.08), triangle(0.25, 0.26, 0.08),
                    triangle(0.75, 0.3, 0.08)]
        t["2.8"] = [box(0.18, 0.18, 0.82, 0.82), .dots(scatter(0.18, 0.18, 0.82, 0.82, n: 3), r: 0.04)]
        t["2.9"] = [.line([P(0.3, 0.12), P(0.3, 0.88)]), .line([P(0.7, 0.12), P(0.7, 0.88)])]
            + [0.25, 0.5, 0.75].flatMap { y -> [Shape] in [.line([P(0.3, y), P(0.14, y)]), .line([P(0.7, y), P(0.86, y)])] }
        t["2.10"] = [.line([P(0.12, 0.6), P(0.88, 0.6)]), .line([P(0.12, 0.4), P(0.88, 0.4)]), .line([P(0.12, 0.6), P(0.12, 0.4)])]

        // D: air
        t["3.1"] = [.circle(c, r: 0.36, fill: false), .line([P(0.26, 0.56), P(0.74, 0.56)]), .line([P(0.26, 0.42), P(0.74, 0.42)])]
        t["3.2"] = [.circle(c, r: 0.26, fill: false), .line([P(0.36, 0.5), P(0.64, 0.5)])]
        t["3.3"] = [.arc(P(0.5, 0.6), r: 0.3, a0: .pi, a1: 2 * .pi), .line([P(0.3, 0.45), P(0.7, 0.45)])]
        t["3.4"] = [.line((0...12).map { i in P(0.12 + Double(i) * 0.76 / 12, 0.5 + 0.12 * sin(Double(i) * .pi / 3)) })]
        t["3.5"] = dashes(0.5, count: 4)
        t["3.6"] = dashes(0.5, count: 4) + [.dots([0.25, 0.5, 0.75].map { P($0, 0.32) }, r: 0.04)]
        t["3.7"] = dashes(0.72) + dashes(0.5, from: 0.25, to: 0.75, count: 2) + dashes(0.28)
        t["3.8"] = dashes(0.8) + dashes(0.2) + [.circle(c, r: 0.16, fill: false)]
        t["3.9"] = [.circle(c, r: 0.18, fill: false)] + [0.25, 0.75, 1.25, 1.75].map { k in
            let a = k * .pi
            return .line([P(0.5 + 0.18 * cos(a), 0.5 + 0.18 * sin(a)), P(0.5 + 0.36 * cos(a), 0.5 + 0.36 * sin(a))])
        }
        t["3.10"] = [.arc(P(0.38, 0.5), r: 0.18, a0: .pi / 2, a1: 1.5 * .pi), .line([P(0.38, 0.68), P(0.38, 0.32)]),
                     .line([P(0.38, 0.5), P(0.86, 0.5)])]
        t["3.11"] = [.line([P(0.22, 0.78), P(0.22, 0.25), P(0.78, 0.25), P(0.78, 0.78)]), .line([P(0.22, 0.6), P(0.78, 0.6)])]

        // D: vegetasi
        t["4.1"] = [.circle(c, r: 0.32, fill: false)]
        t["4.2"] = [.circle(c, r: 0.32, fill: false), .dots(scatter(0.32, 0.32, 0.68, 0.68, n: 2), r: 0.04)]
        t["4.3"] = [.line([P(0.18, 0.18), P(0.18, 0.82), P(0.82, 0.82)]), .dots(scatter(0.24, 0.24, 0.84, 0.76, n: 3), r: 0.04)]
        t["4.4"] = [.circle(c, r: 0.32, fill: false), .dots(scatter(0.14, 0.82, 0.86, 0.95, n: 3) + scatter(0.14, 0.05, 0.86, 0.18, n: 3), r: 0.03)]
        t["4.5"] = grid(0.2, 0.2, 0.8, 0.8)
        t["4.6"] = grid(0.12, 0.38, 0.88, 0.62, n: 3)
        t["4.7"] = [.dots([0.15, 0.29, 0.43, 0.57, 0.71, 0.85].map { P($0, 0.5) }, r: 0.045)]
        t["4.8"] = [.circle(P(0.36, 0.42), r: 0.18, fill: false), .circle(P(0.64, 0.42), r: 0.18, fill: false), .circle(P(0.5, 0.66), r: 0.18, fill: false)]
        t["4.9"] = tree(0.5, 0.6, 0.22)
        t["4.10"] = [.line([P(0.5, 0.75), P(0.5, 0.42)]), .line([P(0.25, 0.22), P(0.5, 0.42), P(0.75, 0.22)]), .line([P(0.5, 0.42), P(0.5, 0.2)])]

        // D: buatan manusia
        t["5.1"] = [.line([P(0.12, 0.62), P(0.88, 0.62)]), .line([P(0.12, 0.38), P(0.88, 0.38)])]
        t["5.2"] = dashes(0.5, count: 3)
        t["5.3"] = dashes(0.5, count: 5)
        t["5.4"] = [.line([P(0.15, 0.78), P(0.3, 0.64), P(0.7, 0.64), P(0.85, 0.78)]), .line([P(0.15, 0.22), P(0.3, 0.36), P(0.7, 0.36), P(0.85, 0.22)])]
        t["5.5"] = [.line([P(0.1, 0.5), P(0.9, 0.5)]), .line([P(0.3, 0.38), P(0.3, 0.62)]), .line([P(0.7, 0.38), P(0.7, 0.62)])]
        t["5.6"] = [.line([P(0.25, 0.15), P(0.5, 0.85), P(0.75, 0.15)]), .line([P(0.34, 0.4), P(0.66, 0.4)]), .line([P(0.2, 0.68), P(0.8, 0.68)])]
        t["5.7"] = [.arc(P(0.5, 0.3), r: 0.3, a0: 0, a1: .pi), .line([P(0.2, 0.3), P(0.2, 0.18)]), .line([P(0.8, 0.3), P(0.8, 0.18)]),
                    .line([P(0.1, 0.18), P(0.9, 0.18)])]
        t["5.8"] = [.line([P(0.12, 0.5), P(0.88, 0.5)]), .dots([0.25, 0.5, 0.75].map { P($0, 0.5) }, r: 0.08)]
        t["5.9"] = [.line([P(0.12, 0.5), P(0.88, 0.5)])] + [0.28, 0.5, 0.72].flatMap { x -> [Shape] in
            [.line([P(x - 0.07, 0.4), P(x + 0.07, 0.6)]), .line([P(x - 0.07, 0.6), P(x + 0.07, 0.4)])]
        }
        t["5.10"] = [.line([P(0.1, 0.5), P(0.38, 0.5)]), .line([P(0.62, 0.5), P(0.9, 0.5)]), .line([P(0.38, 0.32), P(0.38, 0.68)]),
                     .line([P(0.62, 0.32), P(0.62, 0.68)])]
        t["5.11"] = [box(0.22, 0.22, 0.78, 0.78, fill: true)]
        t["5.12"] = [box(0.18, 0.18, 0.82, 0.82)]
        t["5.13"] = dashes(0.2, from: 0.2, to: 0.8, count: 2) + dashes(0.8, from: 0.2, to: 0.8, count: 2)
            + [.line([P(0.2, 0.2), P(0.2, 0.4)]), .line([P(0.2, 0.6), P(0.2, 0.8)]), .line([P(0.8, 0.2), P(0.8, 0.4)]), .line([P(0.8, 0.6), P(0.8, 0.8)])]
        t["5.14"] = [.line([P(0.1, 0.5), P(0.9, 0.5)]), .circle(P(0.3, 0.5), r: 0.08, fill: false), .circle(P(0.7, 0.5), r: 0.08, fill: false)]
        t["5.15"] = [.line([P(0.3, 0.15), P(0.42, 0.7)]), .line([P(0.7, 0.15), P(0.58, 0.7)]), box(0.34, 0.7, 0.66, 0.85)]
        t["5.16"] = [.line([P(0.3, 0.15), P(0.3, 0.6), P(0.7, 0.6), P(0.7, 0.15)]), .line([P(0.3, 0.6), P(0.3, 0.85)])]
        t["5.17"] = [.circle(c, r: 0.2, fill: false), .dots([c], r: 0.06)]
        t["5.18"] = [.line([P(0.4, 0.15), P(0.4, 0.85)]), .line([P(0.4, 0.75), P(0.68, 0.6)]), .line([P(0.4, 0.55), P(0.68, 0.4)])]
        t["5.19"] = [.circle(c, r: 0.3, fill: false), .dots([c], r: 0.12)]
        t["5.20"] = [box(0.4, 0.3, 0.6, 0.8, fill: true), .line([P(0.2, 0.22), P(0.8, 0.22)])]
        t["5.21"] = [.line([P(0.2, 0.2), P(0.2, 0.8), P(0.8, 0.8), P(0.8, 0.2)]), .line([P(0.12, 0.2), P(0.88, 0.2)]),
                     .line([P(0.4, 0.5), P(0.6, 0.5)])]
        t["5.22"] = [.line([P(0.15, 0.2), P(0.15, 0.35), P(0.35, 0.35), P(0.35, 0.5), P(0.55, 0.5), P(0.55, 0.65), P(0.75, 0.65), P(0.75, 0.8)])]
        t["5.23"] = [.line([P(0.15, 0.5), P(0.85, 0.5)]), .line([P(0.15, 0.32), P(0.15, 0.68)]), .line([P(0.85, 0.32), P(0.85, 0.68)]),
                     box(0.42, 0.42, 0.58, 0.58, fill: true)]
        t["5.24"] = [.poly([P(0.3, 0.78), P(0.7, 0.78), P(0.64, 0.2), P(0.36, 0.2)], fill: false), .line([P(0.24, 0.78), P(0.76, 0.78)])]
        t["6.1"] = [.line([P(0.25, 0.25), P(0.75, 0.75)]), .line([P(0.25, 0.75), P(0.75, 0.25)])]
        t["6.2"] = [.circle(c, r: 0.26, fill: false)]

        // E: penampakan
        t["8.1"] = [.arc(P(0.5, 0.2), r: 0.42, a0: .pi * 0.22, a1: .pi * 0.78)]
        t["8.2"] = [.arc(P(0.5, 0.8), r: 0.42, a0: .pi * 1.22, a1: .pi * 1.78)]
        t["8.3"] = [.line([P(0.25, 0.85), P(0.25, 0.4)]), .arc(P(0.5, 0.4), r: 0.25, a0: .pi, a1: 2 * .pi), .line([P(0.75, 0.4), P(0.75, 0.85)])]
        t["8.4"] = grid(0.2, 0.2, 0.8, 0.8)
        t["8.5"] = [.dots((0..<16).map { i in
            let k = Double(i % 4) / 3, side = i / 4
            switch side {
            case 0: return P(0.2 + 0.6 * k, 0.2)
            case 1: return P(0.8, 0.2 + 0.6 * k)
            case 2: return P(0.8 - 0.6 * k, 0.8)
            default: return P(0.2, 0.8 - 0.6 * k)
            }
        }, r: 0.035)]
        t["8.6"] = [triangle(0.3, 0.68, 0.1), triangle(0.7, 0.68, 0.1), triangle(0.5, 0.3, 0.1)]
        t["8.7"] = dashes(0.72, count: 2) + dashes(0.5, count: 2) + dashes(0.28, count: 2)
        t["8.8"] = [.dots(scatter(0.18, 0.18, 0.82, 0.82, n: 4), r: 0.035)]
        t["8.9"] = [.poly([P(0.5, 0.88), P(0.28, 0.42), P(0.72, 0.42)], fill: false), .line([P(0.5, 0.42), P(0.5, 0.12)])]
        t["8.10"] = tree(0.5, 0.56, 0.24)
        t["8.11"] = [.line([P(0.25, 0.2), P(0.25, 0.6)]), .arc(P(0.5, 0.6), r: 0.25, a0: .pi * 0.45, a1: .pi),
                     .line([P(0.75, 0.2), P(0.75, 0.45)]), .line([P(0.62, 0.62), P(0.86, 0.2)])]

        // F: kombinasi
        t["10.1"] = [.line([P(0.2, 0.2), P(0.8, 0.8)]), .line([P(0.2, 0.8), P(0.8, 0.2)])]
        t["10.2"] = [.line([P(0.2, 0.82), P(0.5, 0.5), P(0.8, 0.82)]), .line([P(0.5, 0.5), P(0.5, 0.15)])]

        // G: posisi bendera (fitur = garis/bentuk, bendera = titik)
        t["11.2"] = [.arc(P(0.5, 0.25), r: 0.36, a0: .pi * 0.1, a1: .pi * 0.9), .dots([P(0.5, 0.61)], r: 0.07)]
        t["11.3"] = [.line([P(0.32, 0.12), P(0.32, 0.88)]), .line([P(0.68, 0.12), P(0.68, 0.88)]), .dots([P(0.5, 0.72)], r: 0.07)]
        t["11.4"] = [.line([P(0.32, 0.12), P(0.32, 0.88)]), .line([P(0.68, 0.12), P(0.68, 0.88)]), .dots([P(0.5, 0.28)], r: 0.07)]
        t["11.5"] = [.line([P(0.25, 0.15), P(0.25, 0.55)]), .arc(P(0.5, 0.55), r: 0.25, a0: 0, a1: .pi), .line([P(0.75, 0.55), P(0.75, 0.15)]),
                     .dots([P(0.5, 0.68)], r: 0.07)]
        t["11.6"] = [.line([P(0.2, 0.45), P(0.2, 0.8), P(0.8, 0.8), P(0.8, 0.45)]), .dots([P(0.5, 0.45)], r: 0.07)]
        t["11.7"] = [.line([P(0.35, 0.88), P(0.35, 0.2), P(0.8, 0.2)]), .dots([P(0.5, 0.32)], r: 0.07)]
        t["11.8"] = [.line([P(0.25, 0.88), P(0.25, 0.25), P(0.85, 0.25)]), .dots([P(0.4, 0.4)], r: 0.07)]
        t["11.9"] = [.line([P(0.2, 0.22), P(0.5, 0.6), P(0.8, 0.22)]), .dots([P(0.5, 0.8)], r: 0.07)]
        t["11.10"] = [.line([P(0.85, 0.85), P(0.35, 0.35)]), .line([P(0.6, 0.85), P(0.35, 0.35)]), .dots([P(0.22, 0.22)], r: 0.07)]
        t["11.11"] = [.line([P(0.75, 0.88), P(0.35, 0.5), P(0.75, 0.12)]), .dots([P(0.2, 0.5)], r: 0.07)]
        t["11.12"] = [.line([P(0.12, 0.88), P(0.65, 0.35)]), .dots([P(0.78, 0.22)], r: 0.07)]
        t["11.13"] = [.circle(c, r: 0.34, fill: false), .dots([P(0.68, 0.5)], r: 0.07)]
        t["11.14"] = [.line([P(0.35, 0.65), P(0.88, 0.12)]), .dots([P(0.22, 0.78)], r: 0.07)]
        t["11.15"] = [.line([P(0.15, 0.8), P(0.85, 0.8)]), .line([P(0.15, 0.2), P(0.85, 0.2)]), .dots([c], r: 0.07)]

        // H: info lain
        t["12.1"] = [box(0.4, 0.15, 0.6, 0.85, fill: true), box(0.15, 0.4, 0.85, 0.6, fill: true)]
        t["12.2"] = [.poly([P(0.25, 0.82), P(0.75, 0.82), P(0.65, 0.18), P(0.35, 0.18)], fill: false), .line([P(0.29, 0.6), P(0.71, 0.6)])]
        t["12.3"] = [.line([P(0.62, 0.9), P(0.38, 0.5), P(0.62, 0.5), P(0.38, 0.1)]), .line([P(0.3, 0.2), P(0.38, 0.1), P(0.46, 0.2)])]
        t["12.4"] = [.circle(P(0.5, 0.8), r: 0.08, fill: false), .line([P(0.5, 0.72), P(0.5, 0.4)]), .line([P(0.28, 0.58), P(0.72, 0.58)]),
                     .line([P(0.32, 0.12), P(0.5, 0.4), P(0.68, 0.12)])]
        return t
    }()

    // MARK: Gambar ke CGContext (layar, PNG)

    /// Gambar bentuk di `rect` (koordinat konteks). `flipped`: y konteks ke bawah (UIKit/SwiftUI).
    public static func draw(_ shapes: [Shape], in ctx: CGContext, rect: CGRect, flipped: Bool, color: CGColor) {
        let s = Double(min(rect.width, rect.height))
        func pt(_ p: Point2D) -> CGPoint {
            CGPoint(x: rect.minX + p.x * rect.width, y: flipped ? rect.maxY - p.y * rect.height : rect.minY + p.y * rect.height)
        }
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(lineWidth * s)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for shape in shapes {
            switch shape {
            case let .line(pts):
                guard let f = pts.first else { continue }
                ctx.move(to: pt(f))
                pts.dropFirst().forEach { ctx.addLine(to: pt($0)) }
                ctx.strokePath()
            case let .poly(pts, fill):
                guard let f = pts.first else { continue }
                ctx.move(to: pt(f))
                pts.dropFirst().forEach { ctx.addLine(to: pt($0)) }
                ctx.closePath()
                if fill { ctx.fillPath() } else { ctx.strokePath() }
            case let .circle(cc, r, fill):
                let p = pt(cc), rr = r * Double(rect.width)
                let e = CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr)
                if fill { ctx.fillEllipse(in: e) } else { ctx.strokeEllipse(in: e) }
            case let .arc(cc, r, a0, a1):
                let n = 24
                for i in 0...n {
                    let a = a0 + (a1 - a0) * Double(i) / Double(n)
                    let q = pt(P(cc.x + r * cos(a), cc.y + r * sin(a)))
                    if i == 0 { ctx.move(to: q) } else { ctx.addLine(to: q) }
                }
                ctx.strokePath()
            case let .dots(pts, r):
                for d in pts {
                    let p = pt(d), rr = r * Double(rect.width)
                    ctx.fillEllipse(in: CGRect(x: p.x - rr, y: p.y - rr, width: 2 * rr, height: 2 * rr))
                }
            case .text:
                break  // teks digambar oleh pemanggil (SwiftUI Text / PDF Tj)
            }
        }
        ctx.restoreGState()
    }

    // MARK: Operator PDF

    /// Operator PDF untuk bentuk di kotak (x0, y0, size) dalam pt (y ke atas). Warna mengikuti status grafis.
    static func pdf(_ shapes: [Shape], x0: Double, y0: Double, size: Double, textWidth: (String, Double) -> Double) -> String {
        func n(_ v: Double) -> String { GeoPDFExporter.n(v, 2) }
        func pt(_ p: Point2D) -> String { "\(n(x0 + p.x * size)) \(n(y0 + p.y * size))" }
        var c = "q \(n(lineWidth * size)) w 1 J 1 j\n"
        for shape in shapes {
            switch shape {
            case let .line(pts):
                guard let f = pts.first else { continue }
                c += "\(pt(f)) m " + pts.dropFirst().map { "\(pt($0)) l " }.joined() + "S\n"
            case let .poly(pts, fill):
                guard let f = pts.first else { continue }
                c += "\(pt(f)) m " + pts.dropFirst().map { "\(pt($0)) l " }.joined() + (fill ? "h f\n" : "h S\n")
            case let .circle(cc, r, fill):
                c += GeoPDFExporter.circlePath(center: Point2D(x: 0, y: 0), r: r * size, { "\(n(x0 + cc.x * size + $0.x)) \(n(y0 + cc.y * size + $0.y))" })
                    + (fill ? "f\n" : "S\n")
            case let .arc(cc, r, a0, a1):
                let steps = 16
                c += (0...steps).map { i -> String in
                    let a = a0 + (a1 - a0) * Double(i) / Double(steps)
                    return pt(P(cc.x + r * cos(a), cc.y + r * sin(a))) + (i == 0 ? " m " : " l ")
                }.joined() + "S\n"
            case let .dots(pts, r):
                for d in pts {
                    c += GeoPDFExporter.circlePath(center: Point2D(x: 0, y: 0), r: r * size, { "\(n(x0 + d.x * size + $0.x)) \(n(y0 + d.y * size + $0.y))" }) + "f\n"
                }
            case let .text(str, at, rel):
                let fs = rel * size
                let w = textWidth(str, fs)
                c += "BT /F1 \(n(fs)) Tf \(n(x0 + at.x * size - w / 2)) \(n(y0 + at.y * size - fs * 0.35)) Td (\(GeoPDFExporter.pdfString(str))) Tj ET\n"
            }
        }
        return c + "Q\n"
    }
}
