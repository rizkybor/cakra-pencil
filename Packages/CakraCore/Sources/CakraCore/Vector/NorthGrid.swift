import Foundation

/// Garis utara (grid vertikal) di dalam frame, seperti simbol ISOM 601 "magnetic north line".
///
/// - Utara grid: garis pada easting kelipatan `spacingM`, jadi selaras dengan grid UTM peta lain.
/// - Utara magnetik: garis diputar searah jarum jam sebesar deklinasi (positif = timur), tetap berjarak
///   `spacingM` dan berjangkar pada kelipatan jarak dari titik asal UTM.
public struct NorthGrid: Codable, Hashable, Sendable {
    public enum Reference: String, Codable, CaseIterable, Sendable {
        case grid, magnetic

        public var label: String { self == .grid ? "Utara grid" : "Utara magnetik" }
    }

    public var isEnabled: Bool
    public var reference: Reference
    public var declinationDeg: Double
    public var spacingM: Double
    public var colorHex: String
    public var opacity: Double
    public var lineWidthMM: Double
    public var includeInExport: Bool

    public init(isEnabled: Bool = false, reference: Reference = .grid, declinationDeg: Double = 0, spacingM: Double = 250,
                colorHex: String = "#00A0E6", opacity: Double = 0.8, lineWidthMM: Double = 0.18, includeInExport: Bool = true) {
        self.isEnabled = isEnabled
        self.reference = reference
        self.declinationDeg = declinationDeg
        self.spacingM = spacingM
        self.colorHex = colorHex
        self.opacity = opacity
        self.lineWidthMM = lineWidthMM
        self.includeInExport = includeInExport
    }

    public static let spacingPresetsM: [Double] = [50, 100, 125, 200, 250, 300, 400, 500, 1000]
    public static let spacingRangeM: ClosedRange<Double> = 10...5000

    /// Sudut garis dari utara grid (derajat, searah jarum jam).
    public var angleDeg: Double { reference == .magnetic ? declinationDeg : 0 }

    /// Jarak antar garis di kertas pada skala tertentu (mm).
    public func spacingPaperMM(scale: Int) -> Double { spacingM / Double(scale) * 1000 }

    /// Segmen garis yang terpotong tepi frame, urut dari barat ke timur.
    public func lines(in frame: MapFrame) -> [(Point2D, Point2D)] {
        guard spacingM > 0 else { return [] }
        let e = frame.extent
        let a = angleDeg * .pi / 180
        let d = Point2D(x: sin(a), y: cos(a))        // arah garis
        let n = Point2D(x: cos(a), y: -sin(a))       // normal (jarak antar garis diukur sepanjang ini)
        let offsets = frame.corners.map { $0.x * n.x + $0.y * n.y }
        let lo = Int((offsets.min()! / spacingM).rounded(.up)), hi = Int((offsets.max()! / spacingM).rounded(.down))
        guard lo <= hi, hi - lo < 10_000 else { return [] }

        var out: [(Point2D, Point2D)] = []
        for k in lo...hi {
            let o = Double(k) * spacingM
            let base = Point2D(x: n.x * o, y: n.y * o)
            // Potong garis base + t·d dengan kotak frame (metode slab).
            var t0 = -Double.infinity, t1 = Double.infinity
            for (p, dir, lo, hi) in [(base.x, d.x, e.minX, e.maxX), (base.y, d.y, e.minY, e.maxY)] {
                if abs(dir) < 1e-12 {
                    if p < lo - 1e-9 || p > hi + 1e-9 { t0 = 1; t1 = 0 }
                } else {
                    let ta = (lo - p) / dir, tb = (hi - p) / dir
                    t0 = max(t0, min(ta, tb))
                    t1 = min(t1, max(ta, tb))
                }
            }
            guard t1 - t0 > 1e-6 else { continue }
            out.append((Point2D(x: base.x + d.x * t0, y: base.y + d.y * t0), Point2D(x: base.x + d.x * t1, y: base.y + d.y * t1)))
        }
        return out
    }

    /// Garis grid sebagai objek vektor bersimbol ISOM 601 untuk export .omap/DXF.
    public func features(in frame: MapFrame) -> [Feature] {
        lines(in: frame).enumerated().map { i, seg in
            Feature(name: "Garis utara \(i + 1)", kind: .line, colorHex: colorHex, widthMM: lineWidthMM,
                    nodes: [BezierNode(point: seg.0), BezierNode(point: seg.1)],
                    symbolCode: "601.0", symbolName: "Magnetic north line")
        }
    }
}
