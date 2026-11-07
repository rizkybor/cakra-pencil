import Foundation

/// Result of the Measure tool: a straight line from `start` to `end` (UTM, meters).
public struct MapMeasurement: Equatable, Sendable {
    public var start: Point2D
    public var end: Point2D

    public init(start: Point2D, end: Point2D) {
        self.start = start
        self.end = end
    }

    /// Distance on the ground (meters).
    public var meters: Double { start.distance(to: end) }

    /// Length on paper (mm) at map scale 1:`scaleDenominator`.
    public func paperMM(scaleDenominator: Int) -> Double {
        meters * 1000 / Double(max(scaleDenominator, 1))
    }

    /// Grid azimuth (degrees 0–360, clockwise from UTM grid north).
    public var gridBearing: Double {
        let d = atan2(end.x - start.x, end.y - start.y) * 180 / .pi
        return d < 0 ? d + 360 : d
    }
}
