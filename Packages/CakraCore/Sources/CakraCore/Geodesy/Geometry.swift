import Foundation

/// Titik di CRS proyeksi meter (UTM). x = easting, y = northing.
public struct Point2D: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static func + (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x + b.x, y: a.y + b.y) }
    public static func - (a: Point2D, b: Point2D) -> Point2D { Point2D(x: a.x - b.x, y: a.y - b.y) }

    public func distance(to other: Point2D) -> Double {
        hypot(x - other.x, y - other.y)
    }

    /// Jarak terdekat dari titik ini ke segmen a–b.
    public func distance(toSegment a: Point2D, _ b: Point2D) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return distance(to: a) }
        let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / len2))
        return distance(to: Point2D(x: a.x + t * dx, y: a.y + t * dy))
    }
}

/// Bounding box sumbu-sejajar dalam meter.
public struct Rect2D: Codable, Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init?(points: [Point2D]) {
        guard let first = points.first else { return nil }
        var r = Rect2D(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in points.dropFirst() {
            r.minX = min(r.minX, p.x); r.maxX = max(r.maxX, p.x)
            r.minY = min(r.minY, p.y); r.maxY = max(r.maxY, p.y)
        }
        self = r
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var center: Point2D { Point2D(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }

    public func intersects(_ o: Rect2D) -> Bool {
        minX <= o.maxX && maxX >= o.minX && minY <= o.maxY && maxY >= o.minY
    }

    public func contains(_ o: Rect2D) -> Bool {
        o.minX >= minX && o.maxX <= maxX && o.minY >= minY && o.maxY <= maxY
    }

    public func insetBy(_ d: Double) -> Rect2D {
        Rect2D(minX: minX + d, minY: minY + d, maxX: maxX - d, maxY: maxY - d)
    }
}

/// Koordinat geografis WGS84 dalam derajat.
public struct LatLon: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}
