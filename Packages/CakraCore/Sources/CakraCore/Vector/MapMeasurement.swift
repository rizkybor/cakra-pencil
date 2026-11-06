import Foundation

/// Hasil alat Ukur: garis lurus dari `start` ke `end` (UTM, meter).
public struct MapMeasurement: Equatable, Sendable {
    public var start: Point2D
    public var end: Point2D

    public init(start: Point2D, end: Point2D) {
        self.start = start
        self.end = end
    }

    /// Jarak di lapangan (meter).
    public var meters: Double { start.distance(to: end) }

    /// Panjang di kertas (mm) pada skala peta 1:`scaleDenominator`.
    public func paperMM(scaleDenominator: Int) -> Double {
        meters * 1000 / Double(max(scaleDenominator, 1))
    }

    /// Azimut grid (derajat 0–360, searah jarum jam dari utara grid UTM).
    public var gridBearing: Double {
        let d = atan2(end.x - start.x, end.y - start.y) * 180 / .pi
        return d < 0 ? d + 360 : d
    }
}
