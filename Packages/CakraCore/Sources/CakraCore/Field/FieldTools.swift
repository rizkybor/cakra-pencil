import Foundation

// MARK: - Bearing / distance offset

/// A note placed away from where the surveyor stood (a boulder across a ravine, a cliff top): compass bearing and
/// distance from the standing position. Kept with the note so it can be checked later.
public struct FieldOffset: Codable, Hashable, Sendable {
    /// Where the surveyor stood (UTM, the project's zone).
    public var from: Point2D
    /// True bearing in degrees (0 = north, clockwise), as the compass gives it.
    public var bearingDeg: Double
    public var distanceM: Double
    /// Paces counted, when the distance came from pacing.
    public var paces: Double?

    public init(from: Point2D, bearingDeg: Double, distanceM: Double, paces: Double? = nil) {
        self.from = from
        self.bearingDeg = bearingDeg
        self.distanceM = distanceM
        self.paces = paces
    }

    /// The target position. The bearing is true north; UTM grid north differs by the grid convergence (up to ~2° at
    /// the zone edges), so the target is computed on the ellipsoid surface and projected back.
    public func target(zone: UTMZone) -> Point2D {
        FieldOffset.destination(from: from, bearingDeg: bearingDeg, distanceM: distanceM, zone: zone)
    }

    public static func destination(from p: Point2D, bearingDeg: Double, distanceM: Double, zone: UTMZone) -> Point2D {
        let start = zone.unproject(p)
        let r = 6_371_008.8
        let d = distanceM / r, b = bearingDeg * .pi / 180
        let lat1 = start.lat * .pi / 180, lon1 = start.lon * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
        let lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        let end = zone.project(LatLon(lat: lat2 * 180 / .pi, lon: lon2 * 180 / .pi))
        // Spherical vs. ellipsoid distance differs by up to 0.5 %: scale to the exact distance on the grid (the UTM
        // scale factor near the central meridian is within 0.04 % of 1, below pacing accuracy).
        let dx = end.x - p.x, dy = end.y - p.y, len = hypot(dx, dy)
        guard len > 0 else { return p }
        let k = distanceM / len
        return Point2D(x: p.x + dx * k, y: p.y + dy * k)
    }
}

/// Pace counting: one pace = two steps (orienteering habit). Calibrate by walking a known distance (e.g. 100 m).
public enum PaceCount {
    /// A typical pace length in forest (m per two steps).
    public static let defaultPaceM = 1.5

    public static func paceLength(knownDistanceM: Double, paces: Double) -> Double? {
        guard knownDistanceM > 0, paces > 0 else { return nil }
        let l = knownDistanceM / paces
        return (0.5...3).contains(l) ? l : nil
    }
}

// MARK: - Vegetation (runnability) classes

/// Quick vegetation classification in the field: the ISOM 2017-2 / ISSprOM 2019-2 runnability classes 401–410,
/// recorded as draft notes and drawn as areas at the desk.
public enum VegetationClass: String, Codable, CaseIterable, Sendable {
    case openLand = "401", openScattered = "402", roughOpen = "403", roughOpenScattered = "404", forest = "405"
    case slow = "406", slowGoodVisibility = "407", walk = "408", walkGoodVisibility = "409", fight = "410"

    public var code: String { rawValue }

    public var label: String {
        switch self {
        case .openLand: return "Open land"
        case .openScattered: return "Open land, scattered trees"
        case .roughOpen: return "Rough open land"
        case .roughOpenScattered: return "Rough open, scattered trees"
        case .forest: return "Forest (easy running)"
        case .slow: return "Slow running"
        case .slowGoodVisibility: return "Slow running, good visibility"
        case .walk: return "Walk"
        case .walkGoodVisibility: return "Walk, good visibility"
        case .fight: return "Fight"
        }
    }

    /// Short run speed hint for the button.
    public var speed: String {
        switch self {
        case .openLand, .openScattered, .forest: return "100 %"
        case .roughOpen, .roughOpenScattered: return "rough"
        case .slow, .slowGoodVisibility: return "60–80 %"
        case .walk, .walkGoodVisibility: return "20–60 %"
        case .fight: return "0–20 %"
        }
    }

    /// Approximate print color (ISOM yellow / green screens on white), for buttons and pins.
    public var colorHex: String {
        switch self {
        case .openLand: return "#FFBA35"
        case .openScattered: return "#FFC85E"
        case .roughOpen: return "#FFDC9A"
        case .roughOpenScattered: return "#FFE3AE"
        case .forest: return "#FFFFFF"
        case .slow, .slowGoodVisibility: return "#C5E8BC"
        case .walk, .walkGoodVisibility: return "#8AD07B"
        case .fight: return "#3DB54A"
        }
    }
}

// MARK: - Survey coverage

/// How much of the map area has been walked: every point within `radiusM` of a track (what a mapper sees while
/// walking, e.g. 25 m in forest) counts as covered. Counted on a grid of `cellM` cells.
public enum FieldCoverage {
    public static func fraction(of area: Rect2D, tracks: [FieldTrack], radiusM: Double, cellM: Double = 5) -> Double {
        let w = area.maxX - area.minX, h = area.maxY - area.minY
        guard w > 0, h > 0, radiusM > 0 else { return 0 }
        // Keep the grid at most ~250 000 cells.
        let cell = max(cellM, sqrt(w * h / 250_000))
        let nx = max(1, Int((w / cell).rounded(.up))), ny = max(1, Int((h / cell).rounded(.up)))
        var covered = [Bool](repeating: false, count: nx * ny)
        let r2 = radiusM * radiusM
        for t in tracks {
            for seg in t.segments {
                let pts = seg.map(\.position)
                let pairs = pts.count == 1 ? [(pts[0], pts[0])] : Array(zip(pts, pts.dropFirst()))
                for (a, b) in pairs {
                    let minX = min(a.x, b.x) - radiusM, maxX = max(a.x, b.x) + radiusM
                    let minY = min(a.y, b.y) - radiusM, maxY = max(a.y, b.y) + radiusM
                    let i0 = max(0, Int((minX - area.minX) / cell)), i1 = min(nx - 1, Int((maxX - area.minX) / cell))
                    let j0 = max(0, Int((minY - area.minY) / cell)), j1 = min(ny - 1, Int((maxY - area.minY) / cell))
                    guard i0 <= i1, j0 <= j1 else { continue }
                    for j in j0...j1 {
                        for i in i0...i1 where !covered[j * nx + i] {
                            let c = Point2D(x: area.minX + (Double(i) + 0.5) * cell, y: area.minY + (Double(j) + 0.5) * cell)
                            if distanceSquared(c, a, b) <= r2 { covered[j * nx + i] = true }
                        }
                    }
                }
            }
        }
        return Double(covered.lazy.filter { $0 }.count) / Double(nx * ny)
    }

    static func distanceSquared(_ p: Point2D, _ a: Point2D, _ b: Point2D) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
        t = min(max(t, 0), 1)
        let qx = a.x + t * dx - p.x, qy = a.y + t * dy - p.y
        return qx * qx + qy * qy
    }
}

// MARK: - Track → line

extension FieldTrack {
    /// The part of the track between two fractions of its recorded length (0…1), split at pause gaps, each part
    /// simplified (Douglas–Peucker, `toleranceM`; 0 = keep every point). Parts with fewer than 2 points are dropped.
    public func lineParts(from start: Double = 0, to end: Double = 1, toleranceM: Double = 0) -> [[Point2D]] {
        let total = lengthM
        let a = min(max(start, 0), 1) * total, b = min(max(end, 0), 1) * total
        guard b > a else { return [] }
        var parts: [[Point2D]] = []
        var walked = 0.0
        for seg in segments {
            var part: [Point2D] = []
            let pts = seg.map(\.position)
            if pts.count == 1, walked >= a, walked <= b { continue }
            for (p, q) in zip(pts, pts.dropFirst()) {
                let d = p.distance(to: q)
                let s0 = walked, s1 = walked + d
                walked = s1
                guard s1 >= a, s0 <= b, d > 0 else { continue }
                let t0 = max(0, (a - s0) / d), t1 = min(1, (b - s0) / d)
                let p0 = Point2D(x: p.x + (q.x - p.x) * t0, y: p.y + (q.y - p.y) * t0)
                let p1 = Point2D(x: p.x + (q.x - p.x) * t1, y: p.y + (q.y - p.y) * t1)
                if part.isEmpty || part.last! != p0 { part.append(p0) }
                part.append(p1)
            }
            if part.count >= 2 { parts.append(part) }
        }
        guard toleranceM > 0 else { return parts }
        return parts.map { ContourGenerator.simplify($0, tolerance: toleranceM) }.filter { $0.count >= 2 }
    }
}
