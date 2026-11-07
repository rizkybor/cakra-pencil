import Foundation

/// The IOF map specification a map follows, chosen from its scale, with the standard sizes OCCA applies.
///
/// - ISOM 2017-2 (forest): base scale 1:15000; 1:10000 maps are enlarged to 150% (§2.9.1).
/// - ISSprOM 2019-2 (sprint): base scale 1:4000; 1:3000 maps are enlarged to 133% (§3.1).
///
/// All sizes are paper mm at the base scale; multiply by `enlargement(scale:)` for the map's own scale.
public enum MapStandard: String, CaseIterable, Sendable {
    case isom, issprom

    /// Sprint maps (1:5000 and larger scales) follow ISSprOM; forest maps (1:7500–1:15000) ISOM.
    public static func `for`(scale: Int) -> MapStandard { scale <= 5000 ? .issprom : .isom }

    public var label: String { self == .isom ? "ISOM 2017-2" : "ISSprOM 2019-2" }

    public var baseScale: Int { self == .isom ? 15000 : 4000 }

    /// When a map is enlarged, all lines, symbols and screens are enlarged proportionally (never reduced).
    public func enlargement(scale: Int) -> Double {
        guard scale > 0 else { return 1 }
        return max(1, Double(baseScale) / Double(scale))
    }

    /// 101 Contour and 102 Index contour line widths.
    public var contourWidthMM: Double { self == .isom ? 0.14 : 0.21 }
    public var indexContourWidthMM: Double { self == .isom ? 0.25 : 0.30 }

    /// 103 Form line: ISOM 0.1 mm (dash 2.0 / gap 0.2), ISSprOM 0.15 mm (dash 3.0 / gap 0.3) — in both the width is
    /// ≈ 0.71 × the contour width and the dash/gap are 20× / 2× the form line width.
    public static let formLineWidthRatio = 0.1 / 0.14
    public static let formLineDashPerWidth = 20.0
    public static let formLineGapPerWidth = 2.0

    /// 601 Magnetic north lines: 20 mm apart at 1:15000 (300 m), 30 mm at 1:4000 (120 m). Enlarged maps keep the
    /// ground distance. Blue line width (black: ISOM 0.1, ISSprOM 0.14).
    public var northLineSpacingM: Double { self == .isom ? 300 : 120 }
    public var northLineBlueWidthMM: Double { self == .isom ? 0.12 : 0.18 }
}
