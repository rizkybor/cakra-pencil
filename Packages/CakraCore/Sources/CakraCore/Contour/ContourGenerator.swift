import Foundation

/// Per-project contour settings (FR-8.3 – FR-8.13). Default widths follow ISOM: contour 0.14 mm,
/// index 0.25 mm, form line 0.14 mm dashed.
public struct ContourSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var intervalM: Double
    public var indexEvery: Int
    public var baseOffsetM: Double
    public var smoothing: Int
    public var minLengthMM: Double
    public var showFormLines: Bool
    public var colorHex: String
    public var opacity: Double
    public var contourWidthMM: Double
    public var indexWidthMM: Double
    public var includeInExport: Bool

    public init(isEnabled: Bool = false, intervalM: Double = 5, indexEvery: Int = 5, baseOffsetM: Double = 0, smoothing: Int = 1,
                minLengthMM: Double = 1.5, showFormLines: Bool = false, colorHex: String = "#D15C00", opacity: Double = 1,
                contourWidthMM: Double = 0.14, indexWidthMM: Double = 0.25, includeInExport: Bool = true) {
        self.isEnabled = isEnabled
        self.intervalM = intervalM
        self.indexEvery = indexEvery
        self.baseOffsetM = baseOffsetM
        self.smoothing = smoothing
        self.minLengthMM = minLengthMM
        self.showFormLines = showFormLines
        self.colorHex = colorHex
        self.opacity = opacity
        self.contourWidthMM = contourWidthMM
        self.indexWidthMM = indexWidthMM
        self.includeInExport = includeInExport
    }

    /// The part of the settings that changes line geometry. Color, opacity, and width are drawing style only:
    /// changing them does not require recomputing the contours.
    public struct Geometry: Hashable, Sendable {
        var intervalM: Double, indexEvery: Int, baseOffsetM: Double, smoothing: Int, minLengthMM: Double, showFormLines: Bool
    }

    public var geometry: Geometry {
        Geometry(intervalM: intervalM, indexEvery: indexEvery, baseOffsetM: baseOffsetM, smoothing: smoothing,
                 minLengthMM: minLengthMM, showFormLines: showFormLines)
    }

    public static let opacityRange: ClosedRange<Double> = 0.05...1

    public static let intervalPresetsM: [Double] = [1, 2, 2.5, 5, 10]
    public static let intervalRangeM: ClosedRange<Double> = 0.5...50

    /// FR-8.4: 1:3000–1:5000 = 2 m, 1:7500–1:15000 = 5 m.
    public static func defaultInterval(scale: Int) -> Double { scale <= 5000 ? 2 : 5 }

    public static func defaults(scale: Int) -> ContourSettings { ContourSettings(intervalM: defaultInterval(scale: scale)) }

    /// FR-8.11: an interval below ±1/4 of the DEM's horizontal resolution usually just draws noise.
    public func intervalWarning(nativeResolutionM: Double) -> String? {
        let minimum = (nativeResolutionM / 4).rounded(.up)
        guard intervalM < minimum else { return nil }
        return "Interval \(Fmt.number(intervalM, decimals: intervalM.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) m is too fine for a ±\(Int(nativeResolutionM.rounded())) m DEM; ≥ \(Int(minimum)) m recommended."
    }
}

public struct ContourLine: Codable, Sendable, Hashable {
    public enum Kind: String, Sendable, Codable { case contour, index, form }

    public var elevation: Double
    public var kind: Kind
    public var points: [Point2D]
    public var isClosed: Bool

    public init(elevation: Double, kind: Kind, points: [Point2D], isClosed: Bool) {
        self.elevation = elevation
        self.kind = kind
        self.points = points
        self.isClosed = isClosed
    }

    /// ISOM symbol code: 101.0 contour, 102.0 index contour, 103.0 form line.
    public var symbolCode: String {
        switch kind {
        case .contour: return "101.0"
        case .index: return "102.0"
        case .form: return "103.0"
        }
    }

    public var symbolName: String {
        switch kind {
        case .contour: return "Contour"
        case .index: return "Index contour"
        case .form: return "Form line"
        }
    }

    public var length: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Line kind for a given elevation: index if it is a multiple of (interval × N) from the base elevation.
    public static func kind(elevation e: Double, settings s: ContourSettings) -> Kind {
        let step = s.intervalM * Double(max(s.indexEvery, 1))
        let k = (e - s.baseOffsetM) / step
        if abs(k - k.rounded()) < 1e-6 { return .index }
        let c = (e - s.baseOffsetM) / s.intervalM
        return abs(c - c.rounded()) < 1e-6 ? .contour : .form
    }
}

/// Contours from a DEM grid: marching squares per level, then segments are joined into polylines,
/// simplified, smoothed (Chaikin), and short lines are dropped (FR-8.5 – FR-8.8).
public enum ContourGenerator {
    public struct Result: Sendable {
        public var lines: [ContourLine]
        public var minElevation: Double
        public var maxElevation: Double

        public var relief: Double { maxElevation - minElevation }
    }

    public static func generate(_ grid: DEMGrid, settings s: ContourSettings, sheet: SheetSpec, clip: Rect2D? = nil) -> Result {
        guard let range = grid.range, s.intervalM > 0 else { return Result(lines: [], minElevation: 0, maxElevation: 0) }
        let lo = Double(range.lowerBound), hi = Double(range.upperBound)
        let step = s.showFormLines ? s.intervalM / 2 : s.intervalM
        let first = ((lo - s.baseOffsetM) / step).rounded(.up), last = ((hi - s.baseOffsetM) / step).rounded(.down)
        guard last >= first, last - first < 5000 else { return Result(lines: [], minElevation: lo, maxElevation: hi) }

        let minLengthM = sheet.groundMeters(forPaperMM: s.minLengthMM)
        let simplifyTolerance = grid.cellSize * 0.1
        var lines: [ContourLine] = []
        for k in Int(first)...Int(last) {
            let level = s.baseOffsetM + Double(k) * step
            let kind = ContourLine.kind(elevation: level, settings: s)
            for (pts, closed) in trace(grid, level: Float(level)) {
                var p = simplify(pts, tolerance: simplifyTolerance)
                if s.smoothing > 0 { p = chaikin(p, iterations: s.smoothing, closed: closed) }
                var line = ContourLine(elevation: level, kind: kind, points: p, isClosed: closed)
                if let clip, !(Rect2D(points: p).map(clip.intersects) ?? false) { continue }
                guard line.length >= minLengthM else { continue }
                if closed, line.points.first != line.points.last, let f = line.points.first { line.points.append(f) }
                lines.append(line)
            }
        }
        return Result(lines: lines, minElevation: lo, maxElevation: hi)
    }

    /// Marching squares: segments per cell, then joined through shared end points (key = cell edge).
    static func trace(_ g: DEMGrid, level: Float) -> [([Point2D], Bool)] {
        // Edge crossings get a unique key so adjacent segments share exactly the same point.
        struct EdgeKey: Hashable { var col: Int, row: Int, horizontal: Bool }
        var points: [EdgeKey: Point2D] = [:]
        var adjacency: [EdgeKey: [EdgeKey]] = [:]

        func crossing(_ a: (Int, Int), _ b: (Int, Int), horizontal: Bool) -> EdgeKey? {
            let va = g.value(col: a.0, row: a.1), vb = g.value(col: b.0, row: b.1)
            guard !va.isNaN, !vb.isNaN, (va < level) != (vb < level) else { return nil }
            let key = EdgeKey(col: a.0, row: a.1, horizontal: horizontal)
            if points[key] == nil {
                let t = Double((level - va) / (vb - va))
                let pa = g.center(col: a.0, row: a.1), pb = g.center(col: b.0, row: b.1)
                points[key] = Point2D(x: pa.x + (pb.x - pa.x) * t, y: pa.y + (pb.y - pa.y) * t)
            }
            return key
        }

        for r in 0..<(g.rows - 1) {
            for c in 0..<(g.cols - 1) {
                // Edges: top (c,r)-(c+1,r), bottom (c,r+1)-(c+1,r+1), left (c,r)-(c,r+1), right (c+1,r)-(c+1,r+1).
                let top = crossing((c, r), (c + 1, r), horizontal: true)
                let bottom = crossing((c, r + 1), (c + 1, r + 1), horizontal: true)
                let left = crossing((c, r), (c, r + 1), horizontal: false)
                let right = crossing((c + 1, r), (c + 1, r + 1), horizontal: false)
                let hits = [top, right, bottom, left].compactMap { $0 }
                if hits.count == 2 {
                    connect(hits[0], hits[1], &adjacency)
                } else if hits.count == 4 {
                    // Saddle: pick the pairing from the average of the four corners.
                    let mean = (g.value(col: c, row: r) + g.value(col: c + 1, row: r) + g.value(col: c, row: r + 1) + g.value(col: c + 1, row: r + 1)) / 4
                    let tlHigh = g.value(col: c, row: r) >= level
                    if (mean >= level) == tlHigh {
                        connect(top!, right!, &adjacency)
                        connect(bottom!, left!, &adjacency)
                    } else {
                        connect(top!, left!, &adjacency)
                        connect(bottom!, right!, &adjacency)
                    }
                }
            }
        }

        // Chain: start from free ends (degree 1) first so open lines stay whole; the rest are closed loops.
        var visited = Set<EdgeKey>()
        var out: [([Point2D], Bool)] = []
        func walk(from start: EdgeKey) -> ([Point2D], Bool) {
            var chain = [start]
            visited.insert(start)
            var current = start
            while let next = adjacency[current]?.first(where: { !visited.contains($0) }) {
                visited.insert(next)
                chain.append(next)
                current = next
            }
            let closed = chain.count > 2 && (adjacency[current]?.contains(start) ?? false)
            return (chain.compactMap { points[$0] }, closed)
        }
        for (k, n) in adjacency where n.count == 1 && !visited.contains(k) { out.append(walk(from: k)) }
        for k in adjacency.keys where !visited.contains(k) { out.append(walk(from: k)) }
        return out.filter { $0.0.count >= 2 }
    }

    static func connect<K: Hashable>(_ a: K, _ b: K, _ adj: inout [K: [K]]) {
        adj[a, default: []].append(b)
        adj[b, default: []].append(a)
    }

    /// Douglas–Peucker.
    public static func simplify(_ pts: [Point2D], tolerance: Double) -> [Point2D] {
        guard pts.count > 2, tolerance > 0 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var best = 0.0, index = a
            for i in (a + 1)..<b {
                let d = pts[i].distance(toSegment: pts[a], pts[b])
                if d > best { best = d; index = i }
            }
            if best > tolerance {
                keep[index] = true
                stack.append((a, index))
                stack.append((index, b))
            }
        }
        return pts.enumerated().filter { keep[$0.offset] }.map(\.element)
    }

    /// Chaikin corner cutting; end points of open lines are kept.
    public static func chaikin(_ pts: [Point2D], iterations: Int, closed: Bool) -> [Point2D] {
        var p = pts
        for _ in 0..<min(iterations, 4) {
            guard p.count > 2 else { return p }
            var q: [Point2D] = closed ? [] : [p[0]]
            let n = closed ? p.count : p.count - 1
            for i in 0..<n {
                let a = p[i], b = p[(i + 1) % p.count]
                q.append(Point2D(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
                q.append(Point2D(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
            }
            if !closed, let last = p.last { q.append(last) }
            p = q
        }
        return p
    }
}

extension ContourLine {
    /// Contour line as an ISOM-symbolized vector object (for export and "Convert to vector objects").
    /// Closed contours stay lines (not filled areas): the last point returns to the first.
    public func feature(settings s: ContourSettings) -> Feature {
        var pts = points
        if isClosed, let first = pts.first, pts.last != first { pts.append(first) }
        let elev = Fmt.number(elevation, decimals: elevation.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)
        return Feature(name: "\(symbolCode) \(symbolName) \(elev) m", kind: .line, colorHex: s.colorHex,
                       widthMM: kind == .index ? s.indexWidthMM : s.contourWidthMM,
                       nodes: pts.map { BezierNode(point: $0) }, symbolCode: symbolCode, symbolName: symbolName)
    }
}

extension ContourLine {
    /// Imported contour lines (GeoJSON) are stored in the package as contours.json.
    public static func writeImported(_ lines: [ContourLine], to directory: URL) throws {
        try JSONEncoder().encode(lines).write(to: directory.appendingPathComponent("contours.json"), options: .atomic)
    }

    public static func readImported(from directory: URL) -> [ContourLine]? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("contours.json")) else { return nil }
        return try? JSONDecoder().decode([ContourLine].self, from: data)
    }

    public static func removeImported(from directory: URL) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("contours.json"))
    }

    /// Reclassify imported lines (contour/index/form) according to the current interval settings.
    public static func classify(_ lines: [ContourLine], settings s: ContourSettings) -> [ContourLine] {
        lines.map { var l = $0; l.kind = kind(elevation: l.elevation, settings: s); return l }
    }
}
