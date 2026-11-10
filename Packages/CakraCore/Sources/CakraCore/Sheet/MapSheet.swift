import Foundation

public enum SheetOrientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape

    public var toggled: SheetOrientation { self == .portrait ? .landscape : .portrait }
}

/// Paper size in mm, always stored as short side × long side.
public struct PaperSize: Codable, Hashable, Sendable {
    public var name: String
    public var shortMM: Double
    public var longMM: Double

    public static let a4 = PaperSize(name: "A4", shortMM: 210, longMM: 297)
}

/// Scale and dpi options from FR-1.1 and FR-3.1.
public enum MapPresets {
    /// 1:1000 to 1:15000, in steps of 500.
    public static let scales = Array(stride(from: 1000, through: 15000, by: 500))
    public static let dpis = [300, 600, 900]
    public static let marginsMM: [Double] = [0, 5, 10]
    public static let snapStepsM = [0, 10, 50, 100]
    /// Indoor maps (ISInOM 6.7.3 §3.1): base scale 1:700; larger scales (1:500, 1:350 …) enlarge all symbols, smaller
    /// scales (1:1000 … 1:2000) keep the 1:700 sizes. The map is scaled to fit the paper, prioritising legibility.
    public static let indoorScales = [250, 300, 350, 400, 500, 600, 700, 800, 900, 1000, 1250, 1500, 2000]

    /// The scales offered for a map of `standard` (indoor or outdoor).
    public static func scales(indoor: Bool) -> [Int] { indoor ? indoorScales : scales }
}

/// Stored in a project's sheet when the user picks the standard instead of the automatic choice from the scale.
extension MapStandard: Codable {}

/// Map sheet: paper + orientation + margin + scale. All derived sizes are computed from this.
public struct SheetSpec: Codable, Hashable, Sendable {
    public var paper: PaperSize
    public var orientation: SheetOrientation
    public var marginMM: Double
    public var scaleDenominator: Int
    /// The IOF map specification chosen by the user ("Indoor map (ISInOM)" = `.isinom`); nil = automatic from the
    /// scale (ISOM / ISSprOM). Optional in the file, so projects saved before it existed still open.
    public var standardOverride: MapStandard?

    public init(paper: PaperSize = .a4, orientation: SheetOrientation = .portrait, marginMM: Double = 0, scaleDenominator: Int = 4000,
                standardOverride: MapStandard? = nil) {
        self.paper = paper
        self.orientation = orientation
        self.marginMM = marginMM
        self.scaleDenominator = scaleDenominator
        self.standardOverride = standardOverride
    }

    /// The IOF standard the map follows: the user's choice, else ISSprOM for sprint scales and ISOM for forest scales.
    /// Drives course symbol sizes, the preferred symbol set and symbol lookup, north lines and contours.
    public var mapStandard: MapStandard { standardOverride ?? MapStandard.for(scale: scaleDenominator) }

    /// Indoor orienteering map (ISInOM): no contours, north orientation not required.
    public var isIndoor: Bool { mapStandard == .isinom }

    /// IOF enlargement of the map's symbols at its scale (e.g. ISInOM 1:500 = 1.4, 1:1000 = 1).
    public var symbolEnlargement: Double { mapStandard.enlargement(scale: scaleDenominator) }

    /// Mapping area on paper (mm) = paper minus the margin on all four sides (FR-1.6).
    public var mappingWidthMM: Double {
        (orientation == .portrait ? paper.shortMM : paper.longMM) - 2 * marginMM
    }

    public var mappingHeightMM: Double {
        (orientation == .portrait ? paper.longMM : paper.shortMM) - 2 * marginMM
    }

    /// Ground size (m) of the mapping area at this scale.
    public var groundWidthM: Double { mappingWidthMM / 1000 * Double(scaleDenominator) }
    public var groundHeightM: Double { mappingHeightMM / 1000 * Double(scaleDenominator) }

    /// Pixel size on the ground (m) = scale × 0.0254 / dpi.
    public func pixelSizeM(dpi: Int) -> Double {
        Double(scaleDenominator) * 0.0254 / Double(dpi)
    }

    /// Raster dimensions of the mapping area at a given dpi.
    public func pixelDimensions(dpi: Int) -> (width: Int, height: Int) {
        (Int((mappingWidthMM / 25.4 * Double(dpi)).rounded()),
         Int((mappingHeightMM / 25.4 * Double(dpi)).rounded()))
    }

    /// Ground meters for a size in paper mm.
    public func groundMeters(forPaperMM mm: Double) -> Double {
        mm / 1000 * Double(scaleDenominator)
    }
}

/// North-up frame relative to the UTM grid. origin = lower-left corner (minX, minY).
public struct MapFrame: Codable, Hashable, Sendable {
    public var origin: Point2D
    public var widthM: Double
    public var heightM: Double

    public init(origin: Point2D, widthM: Double, heightM: Double) {
        self.origin = origin
        self.widthM = widthM
        self.heightM = heightM
    }

    public init(center: Point2D, sheet: SheetSpec) {
        self.init(origin: Point2D(x: center.x - sheet.groundWidthM / 2, y: center.y - sheet.groundHeightM / 2),
                  widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
    }

    public var extent: Rect2D { Rect2D(minX: origin.x, minY: origin.y, maxX: origin.x + widthM, maxY: origin.y + heightM) }
    public var center: Point2D { extent.center }

    /// Corners clockwise from upper-left: UL, UR, LR, LL.
    public var corners: [Point2D] {
        let e = extent
        return [Point2D(x: e.minX, y: e.maxY), Point2D(x: e.maxX, y: e.maxY),
                Point2D(x: e.maxX, y: e.minY), Point2D(x: e.minX, y: e.minY)]
    }

    /// Snap the lower-left corner to the nearest multiple of `stepM` (FR-1.7). Size is unchanged.
    public func snapped(toStep stepM: Int) -> MapFrame {
        guard stepM > 0 else { return self }
        let s = Double(stepM)
        var f = self
        f.origin = Point2D(x: (origin.x / s).rounded() * s, y: (origin.y / s).rounded() * s)
        return f
    }

    /// New frame with the size from `sheet` and the same center (change of scale/orientation, FR-1.4/1.5).
    public func resized(to sheet: SheetSpec) -> MapFrame {
        MapFrame(center: center, sheet: sheet)
    }
}
