import Foundation

/// A static HD image of the Apple Maps basemap (satellite, hybrid, or standard) captured for the locked map area.
/// Once the area is locked, the workspace shows this image instead of the live map, so the basemap no longer
/// changes with the zoom level (e.g. road widths on the Standard map).
///
/// The image is in Web Mercator, so it is placed exactly by its lat/lon bounds. It is stored in the project
/// package under `imagery/` as a local cache: it is not included in `.occa` files or exports, and another device
/// captures its own copy.
public struct ImagerySnapshot: Codable, Hashable, Sendable {
    /// Package folder for captured imagery.
    public static let folder = "imagery"
    /// Target ground resolution (m per pixel) and the largest image side (pixels).
    public static let targetMetersPerPixel = 0.25
    public static let maxPixelSide = 4096
    /// A snapshot much larger than the frame (e.g. after switching to a larger scale) is captured again for detail.
    static let maxSpanRatio = 1.6

    /// Map type id, e.g. "satellite", "hybrid", "standard".
    public var mapType: String
    /// JPEG file name relative to the project package.
    public var fileName: String
    public var north: Double
    public var south: Double
    public var west: Double
    public var east: Double
    public var width: Int
    public var height: Int
    public var capturedAt: Date

    public init(mapType: String, fileName: String, north: Double, south: Double, west: Double, east: Double,
                width: Int, height: Int, capturedAt: Date = Date()) {
        self.mapType = mapType
        self.fileName = fileName
        self.north = north
        self.south = south
        self.west = west
        self.east = east
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
    }

    /// Image and metadata paths (relative to the package) for a map type.
    public static func imagePath(for mapType: String) -> String { "\(folder)/\(mapType).jpg" }
    public static func metadataPath(for mapType: String) -> String { "\(folder)/\(mapType).json" }

    /// The image covers every given point and is not much larger than them (so it still has enough detail).
    public func fits(_ points: [LatLon]) -> Bool {
        guard !points.isEmpty else { return false }
        let lats = points.map(\.lat), lons = points.map(\.lon)
        guard lats.min()! >= south, lats.max()! <= north, lons.min()! >= west, lons.max()! <= east else { return false }
        let spanLat = lats.max()! - lats.min()!, spanLon = lons.max()! - lons.min()!
        guard spanLat > 0, spanLon > 0 else { return true }
        return (north - south) / spanLat <= Self.maxSpanRatio && (east - west) / spanLon <= Self.maxSpanRatio
    }

    /// Approximate ground resolution (m per pixel) along the image width.
    public var metersPerPixel: Double {
        let midLat = (north + south) / 2 * .pi / 180
        return (east - west) * 111_320 * cos(midLat) / Double(max(width, 1))
    }

    /// Image size in pixels for a ground area of `widthM` × `heightM`: `targetMetersPerPixel`, at most `maxPixelSide`.
    public static func pixelSize(widthM: Double, heightM: Double) -> (width: Int, height: Int) {
        guard widthM > 0, heightM > 0 else { return (1, 1) }
        var w = widthM / targetMetersPerPixel, h = heightM / targetMetersPerPixel
        let k = min(1, Double(maxPixelSide) / max(w, h))
        w *= k
        h *= k
        return (max(1, Int(w.rounded())), max(1, Int(h.rounded())))
    }
}
