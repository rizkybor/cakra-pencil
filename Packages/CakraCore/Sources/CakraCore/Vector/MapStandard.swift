import Foundation

/// The IOF map specification a map follows, chosen from its scale, with the standard sizes OCCA applies.
///
/// - ISOM 2017-2 (forest): base scale 1:15000; 1:10000 maps are enlarged to 150% (§2.9.1).
/// - ISSprOM 2019-2 (sprint): base scale 1:4000; 1:3000 maps are enlarged to 133% (§3.1).
/// - ISInOM 6.7.3 (indoor): base scale 1:700; larger scales are enlarged proportionally, smaller scales (e.g.
///   1:1500) keep the 1:700 sizes (§3.1). Never chosen from the scale alone — indoor maps are large-scale like sprint
///   maps, so `for(scale:)` stays ISOM / ISSprOM; ISInOM applies when the sheet's "Indoor map" option is on
///   (`SheetSpec.standardOverride`, read through `SheetSpec.mapStandard`).
///
/// All sizes are paper mm at the base scale; multiply by `enlargement(scale:)` for the map's own scale.
public enum MapStandard: String, CaseIterable, Sendable {
    case isom, issprom, isinom

    /// Sprint maps (1:5000 and larger scales) follow ISSprOM; forest maps (1:7500–1:15000) ISOM.
    public static func `for`(scale: Int) -> MapStandard { scale <= 5000 ? .issprom : .isom }

    public var label: String {
        switch self {
        case .isom: return "ISOM 2017-2"
        case .issprom: return "ISSprOM 2019-2"
        case .isinom: return "ISInOM 6.7.3"
        }
    }

    public var baseScale: Int {
        switch self {
        case .isom: return 15000
        case .issprom: return 4000
        case .isinom: return 700
        }
    }

    /// When a map is enlarged, all lines, symbols and screens are enlarged proportionally (never reduced).
    public func enlargement(scale: Int) -> Double {
        guard scale > 0 else { return 1 }
        return max(1, Double(baseScale) / Double(scale))
    }

    /// 101 Contour and 102 Index contour line widths. ISInOM has no contours (§3.2: level differences are 1201 steps);
    /// the sprint widths are used if contours are drawn on an indoor map.
    public var contourWidthMM: Double { self == .isom ? 0.14 : 0.21 }
    public var indexContourWidthMM: Double { self == .isom ? 0.25 : 0.30 }

    /// 103 Form line: ISOM 0.1 mm (dash 2.0 / gap 0.2), ISSprOM 0.15 mm (dash 3.0 / gap 0.3) — in both the width is
    /// ≈ 0.71 × the contour width and the dash/gap are 20× / 2× the form line width.
    public static let formLineWidthRatio = 0.1 / 0.14
    public static let formLineDashPerWidth = 20.0
    public static let formLineGapPerWidth = 2.0

    /// 601 Magnetic north lines: 20 mm apart at 1:15000 (300 m), 30 mm at 1:4000 (120 m). Enlarged maps keep the
    /// ground distance. Blue line width (black: ISOM 0.1, ISSprOM 0.14). Indoor maps need not be north-oriented
    /// (ISInOM §3.4); if north lines are shown they use the sprint width, 20 m apart (≈ 29 mm on paper at 1:700).
    public var northLineSpacingM: Double {
        switch self {
        case .isom: return 300
        case .issprom: return 120
        case .isinom: return 20
        }
    }
    public var northLineBlueWidthMM: Double { self == .isom ? 0.12 : 0.18 }
}

extension MapStandard {
    /// Factor for symbol sizes when a map changes scale: the ratio of the enlargements (e.g. ISOM 1:15000 → 1:10000 =
    /// 1.5, ISSprOM 1:4000 → 1:3000 = 1.333). 1 when the IOF standard changes (sprint ↔ forest symbols differ) or the
    /// enlargement stays the same.
    public static func symbolSizeFactor(fromScale old: Int, toScale new: Int) -> Double {
        let a = MapStandard.for(scale: old), b = MapStandard.for(scale: new)
        guard a == b else { return 1 }
        return b.enlargement(scale: new) / a.enlargement(scale: old)
    }

    /// Factor for symbol sizes when a sheet changes scale or standard (e.g. "Indoor map (ISInOM)" switched on or off).
    /// Same standard: the ratio of the enlargements (as `symbolSizeFactor(fromScale:toScale:)`). To or from ISInOM, the
    /// ratio too, since ISInOM's 1:700 sizes are about ISSprOM's 1:4000 sizes: ISSprOM at 1:700 (× 5.71) → ISInOM at
    /// 1:700 (× 1) = 0.175, and back = 5.71. ISOM ↔ ISSprOM: 1 (the symbols differ).
    public static func symbolSizeFactor(from old: SheetSpec, to new: SheetSpec) -> Double {
        let a = old.mapStandard, b = new.mapStandard
        guard a == b || a == .isinom || b == .isinom else { return 1 }
        return b.enlargement(scale: new.scaleDenominator) / a.enlargement(scale: old.scaleDenominator)
    }
}

extension Feature {
    /// This object with its symbol size × `k` (line width, double-line inner width, dashes, point shape); objects
    /// without a symbol (sketch lines, areas) are unchanged. Used when the map scale changes enlargement.
    public func withSymbolSize(scaledBy k: Double) -> Feature {
        guard symbolCode != nil, abs(k - 1) > 1e-9 else { return self }
        func r(_ v: Double) -> Double { (v * k * 1000).rounded() / 1000 }
        var f = self
        if kind == .area { return f }                 // area outlines are not part of the symbol size
        f.widthMM = r(widthMM)
        f.standardWidthMM = standardWidthMM.map(r)
        f.innerWidthMM = innerWidthMM.map(r)
        f.dashMM = dashMM?.map(r)
        f.innerDashMM = innerDashMM?.map(r)
        f.pointElements = pointElements?.map { e in
            PointElement(kind: e.kind, colorHex: e.colorHex, priority: e.priority, lineWidthMM: r(e.lineWidthMM),
                         diameterMM: r(e.diameterMM), points: e.points.map { Point2D(x: $0.x * k, y: $0.y * k) }, flatEnds: e.flatEnds)
        }
        return f
    }
}
