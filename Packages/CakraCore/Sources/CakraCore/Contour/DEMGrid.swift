import Foundation

/// Regular elevation grid in the project CRS (UTM, meters). Row 0 = northernmost.
/// NaN value = no data.
public struct DEMGrid: Sendable, Equatable {
    public struct Header: Codable, Sendable, Equatable {
        /// Top-left corner of the grid (cell edge, not center).
        public var minX: Double
        public var maxY: Double
        public var cellSize: Double
        public var cols: Int
        public var rows: Int
        /// Data source, e.g. "Terrain Tiles (AWS) z14" or the user's DEM file name.
        public var source: String
        /// Native data resolution (m), for the interval-too-fine warning (FR-8.11).
        public var nativeResolutionM: Double
    }

    public var header: Header
    public var values: [Float]

    public init(header: Header, values: [Float]) {
        precondition(values.count == header.cols * header.rows, "Value count does not match the grid size")
        self.header = header
        self.values = values
    }

    public var cols: Int { header.cols }
    public var rows: Int { header.rows }
    public var cellSize: Double { header.cellSize }

    /// Center coordinate of cell (col, row).
    public func center(col: Int, row: Int) -> Point2D {
        Point2D(x: header.minX + (Double(col) + 0.5) * cellSize, y: header.maxY - (Double(row) + 0.5) * cellSize)
    }

    public func value(col: Int, row: Int) -> Float {
        guard col >= 0, row >= 0, col < cols, row < rows else { return .nan }
        return values[row * cols + col]
    }

    /// Bilinear interpolation at a UTM point; NaN outside the grid or when neighbors have no data.
    public func sample(_ p: Point2D) -> Float {
        let fx = (p.x - header.minX) / cellSize - 0.5
        let fy = (header.maxY - p.y) / cellSize - 0.5
        let c0 = Int(floor(fx)), r0 = Int(floor(fy))
        let tx = Float(fx - Double(c0)), ty = Float(fy - Double(r0))
        return bilinear(value(col: c0, row: r0), value(col: c0 + 1, row: r0),
                        value(col: c0, row: r0 + 1), value(col: c0 + 1, row: r0 + 1), tx, ty)
    }

    /// Minimum and maximum elevation (ignoring NaN).
    public var range: ClosedRange<Float>? {
        var lo = Float.infinity, hi = -Float.infinity
        for v in values where !v.isNaN {
            lo = min(lo, v)
            hi = max(hi, v)
        }
        return lo <= hi ? lo...hi : nil
    }

    /// Build a UTM grid for `extent` by sampling an elevation function (e.g. a lat/lon DEM).
    /// The cell count is capped at `maxCells` by enlarging the cell size when needed.
    public static func resample(extent: Rect2D, cellSize requested: Double, maxCells: Int = 4_000_000,
                                source: String, nativeResolutionM: Double,
                                elevation: (Point2D) -> Float) -> DEMGrid {
        var cell = max(requested, 0.25)
        while (extent.width / cell).rounded(.up) * (extent.height / cell).rounded(.up) > Double(maxCells) { cell *= 1.25 }
        let cols = max(2, Int((extent.width / cell).rounded(.up)))
        let rows = max(2, Int((extent.height / cell).rounded(.up)))
        let header = Header(minX: extent.minX, maxY: extent.maxY, cellSize: cell, cols: cols, rows: rows,
                            source: source, nativeResolutionM: nativeResolutionM)
        var values = [Float](repeating: .nan, count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                values[r * cols + c] = elevation(Point2D(x: extent.minX + (Double(c) + 0.5) * cell, y: extent.maxY - (Double(r) + 0.5) * cell))
            }
        }
        return DEMGrid(header: header, values: values)
    }

    // MARK: Store in the project package (dem.json + dem.bin Float32 little-endian)

    public func write(to directory: URL) throws {
        try JSONEncoder().encode(header).write(to: directory.appendingPathComponent("dem.json"), options: .atomic)
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: directory.appendingPathComponent("dem.bin"), options: .atomic)
    }

    public static func read(from directory: URL) throws -> DEMGrid? {
        let headerURL = directory.appendingPathComponent("dem.json")
        guard FileManager.default.fileExists(atPath: headerURL.path) else { return nil }
        let header = try JSONDecoder().decode(Header.self, from: Data(contentsOf: headerURL))
        let data = try Data(contentsOf: directory.appendingPathComponent("dem.bin"))
        guard header.cols > 0, header.rows > 0, data.count == header.cols * header.rows * 4 else {
            throw OcadReadError.corrupt("DEM data does not match the header")
        }
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return DEMGrid(header: header, values: values)
    }

    public static func remove(from directory: URL) {
        for name in ["dem.json", "dem.bin"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }
}

/// NaN-aware bilinear: neighbors without data are ignored and the weights renormalized.
/// Result is NaN when the valid-data weight is < 0.5 (the point is closer to empty area than to data).
func bilinear(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ tx: Float, _ ty: Float) -> Float {
    let w = [(1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty]
    var sum: Float = 0, weight: Float = 0
    for (v, wi) in zip([a, b, c, d], w) where wi > 0 && !v.isNaN {
        sum += v * wi
        weight += wi
    }
    return weight >= 0.5 ? sum / weight : .nan
}
