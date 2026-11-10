import Foundation

/// North lines (vertical grid) inside the frame, like ISOM symbol 601 "magnetic north line".
///
/// - Grid north: lines at eastings that are multiples of `spacingM`, so they align with other maps' UTM grids.
/// - Magnetic north: lines rotated clockwise by the declination (positive = east), still spaced
///   `spacingM` apart and anchored at multiples of that distance from the UTM origin.
public struct NorthGrid: Codable, Hashable, Sendable {
    public enum Reference: String, Codable, CaseIterable, Sendable {
        case grid, magnetic

        public var label: String { self == .grid ? "Grid north" : "Magnetic north" }
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

    public static let spacingPresetsM: [Double] = [10, 20, 25, 50, 100, 120, 125, 200, 250, 300, 400, 500, 1000]

    /// IOF 601 magnetic north lines for the scale: blue, ISOM 300 m apart and 0.12 mm wide, ISSprOM 120 m and
    /// 0.18 mm (enlarged maps: same ground spacing, wider lines). Off until the user shows them.
    public static func standard(scale: Int) -> NorthGrid { standard(scale: scale, standard: MapStandard.for(scale: scale)) }

    /// North lines of `standard` at `scale`. Indoor maps (ISInOM §3.4) need not be north-oriented: the sprint values
    /// are used and the grid stays off until the user shows it.
    public static func standard(scale: Int, standard s: MapStandard) -> NorthGrid {
        let w = (s.northLineBlueWidthMM * s.enlargement(scale: scale) * 1000).rounded() / 1000
        return NorthGrid(spacingM: s.northLineSpacingM, opacity: 1, lineWidthMM: w)
    }
    public static let spacingRangeM: ClosedRange<Double> = 10...5000

    /// Line angle from grid north (degrees, clockwise).
    public var angleDeg: Double { reference == .magnetic ? declinationDeg : 0 }

    /// Line spacing on paper at a given scale (mm).
    public func spacingPaperMM(scale: Int) -> Double { spacingM / Double(scale) * 1000 }

    /// Line segments clipped to the frame edges, ordered west to east.
    public func lines(in frame: MapFrame) -> [(Point2D, Point2D)] {
        guard spacingM > 0 else { return [] }
        let e = frame.extent
        let a = angleDeg * .pi / 180
        let d = Point2D(x: sin(a), y: cos(a))        // line direction
        let n = Point2D(x: cos(a), y: -sin(a))       // normal (line spacing is measured along this)
        let offsets = frame.corners.map { $0.x * n.x + $0.y * n.y }
        let lo = Int((offsets.min()! / spacingM).rounded(.up)), hi = Int((offsets.max()! / spacingM).rounded(.down))
        guard lo <= hi, hi - lo < 10_000 else { return [] }

        var out: [(Point2D, Point2D)] = []
        for k in lo...hi {
            let o = Double(k) * spacingM
            let base = Point2D(x: n.x * o, y: n.y * o)
            // Clip line base + t·d against the frame box (slab method).
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

    /// Grid lines as vector objects with ISOM symbol 601 for .omap/DXF export.
    public func features(in frame: MapFrame) -> [Feature] {
        lines(in: frame).enumerated().map { i, seg in
            Feature(name: "North line \(i + 1)", kind: .line, colorHex: colorHex, widthMM: lineWidthMM,
                    nodes: [BezierNode(point: seg.0), BezierNode(point: seg.1)],
                    symbolCode: "601.0", symbolName: "Magnetic north line")
        }
    }
}
