import Foundation

/// Averages GPS fixes taken while standing still ("hold here" for 10–30 s) into one more accurate position.
///
/// Each fix is weighted by 1 / accuracy², fixes worse than `maxAccuracyM` are ignored, and fixes far from the running
/// median (multipath jumps) are dropped. The reported accuracy combines the weighted standard error with the scatter
/// of the fixes, and never claims better than 1 m (consumer GNSS).
public struct PositionAverager: Sendable {
    public struct Fix: Sendable {
        public var position: Point2D
        public var accuracyM: Double
        public var time: Date

        public init(position: Point2D, accuracyM: Double, time: Date = Date()) {
            self.position = position
            self.accuracyM = accuracyM
            self.time = time
        }
    }

    public struct Result: Equatable, Sendable {
        public var position: Point2D
        public var accuracyM: Double
        public var samples: Int
        public var durationS: Double
    }

    public var maxAccuracyM: Double
    /// Fixes farther than this many meters (or 3 × their accuracy) from the median are outliers.
    public var outlierM: Double
    public private(set) var fixes: [Fix] = []

    public init(maxAccuracyM: Double = 30, outlierM: Double = 15) {
        self.maxAccuracyM = maxAccuracyM
        self.outlierM = outlierM
    }

    /// Adds a fix; returns false if it was ignored (too inaccurate or invalid).
    @discardableResult
    public mutating func add(_ fix: Fix) -> Bool {
        guard fix.accuracyM > 0, fix.accuracyM <= maxAccuracyM, fix.position.x.isFinite, fix.position.y.isFinite else { return false }
        fixes.append(fix)
        return true
    }

    public mutating func reset() { fixes.removeAll() }

    /// Current average (nil until there is at least one fix).
    public var result: Result? {
        guard !fixes.isEmpty else { return nil }
        let xs = fixes.map(\.position.x).sorted(), ys = fixes.map(\.position.y).sorted()
        let median = Point2D(x: xs[xs.count / 2], y: ys[ys.count / 2])
        var used = fixes.filter { $0.position.distance(to: median) <= max(outlierM, 3 * $0.accuracyM) }
        if used.isEmpty { used = fixes }
        var sw = 0.0, sx = 0.0, sy = 0.0
        for f in used {
            let w = 1 / (f.accuracyM * f.accuracyM)
            sw += w; sx += w * f.position.x; sy += w * f.position.y
        }
        let mean = Point2D(x: sx / sw, y: sy / sw)
        // Standard error of the weighted mean, and the actual scatter of the fixes around it.
        let standardError = sqrt(1 / sw)
        let scatter = sqrt(used.reduce(0) { $0 + pow($1.position.distance(to: mean), 2) } / Double(used.count))
        let scatterError = used.count > 1 ? scatter / sqrt(Double(used.count)) : (used.first?.accuracyM ?? 0)
        let accuracy = max(1, max(standardError, scatterError) * 2)        // ~95 % radius
        let times = used.map(\.time)
        let duration = (times.max() ?? Date()).timeIntervalSince(times.min() ?? Date())
        return Result(position: mean, accuracyM: min(accuracy, used.map(\.accuracyM).min() ?? accuracy),
                      samples: used.count, durationS: duration)
    }
}
