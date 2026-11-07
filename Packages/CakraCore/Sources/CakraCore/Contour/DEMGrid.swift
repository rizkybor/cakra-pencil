import Foundation

/// Grid elevasi reguler di CRS proyek (UTM, meter). Baris 0 = paling utara.
/// Nilai NaN = tidak ada data.
public struct DEMGrid: Sendable, Equatable {
    public struct Header: Codable, Sendable, Equatable {
        /// Pojok kiri atas grid (tepi sel, bukan pusat).
        public var minX: Double
        public var maxY: Double
        public var cellSize: Double
        public var cols: Int
        public var rows: Int
        /// Asal data, mis. "Terrain Tiles (AWS) z14" atau nama file DEM user.
        public var source: String
        /// Resolusi data asli (m), untuk peringatan interval terlalu rapat (FR-8.11).
        public var nativeResolutionM: Double
    }

    public var header: Header
    public var values: [Float]

    public init(header: Header, values: [Float]) {
        precondition(values.count == header.cols * header.rows, "Jumlah nilai tidak cocok dengan ukuran grid")
        self.header = header
        self.values = values
    }

    public var cols: Int { header.cols }
    public var rows: Int { header.rows }
    public var cellSize: Double { header.cellSize }

    /// Koordinat pusat sel (col, row).
    public func center(col: Int, row: Int) -> Point2D {
        Point2D(x: header.minX + (Double(col) + 0.5) * cellSize, y: header.maxY - (Double(row) + 0.5) * cellSize)
    }

    public func value(col: Int, row: Int) -> Float {
        guard col >= 0, row >= 0, col < cols, row < rows else { return .nan }
        return values[row * cols + col]
    }

    /// Interpolasi bilinear di titik UTM; NaN di luar grid atau bila tetangga tidak ada data.
    public func sample(_ p: Point2D) -> Float {
        let fx = (p.x - header.minX) / cellSize - 0.5
        let fy = (header.maxY - p.y) / cellSize - 0.5
        let c0 = Int(floor(fx)), r0 = Int(floor(fy))
        let tx = Float(fx - Double(c0)), ty = Float(fy - Double(r0))
        return bilinear(value(col: c0, row: r0), value(col: c0 + 1, row: r0),
                        value(col: c0, row: r0 + 1), value(col: c0 + 1, row: r0 + 1), tx, ty)
    }

    /// Elevasi minimum dan maksimum (abaikan NaN).
    public var range: ClosedRange<Float>? {
        var lo = Float.infinity, hi = -Float.infinity
        for v in values where !v.isNaN {
            lo = min(lo, v)
            hi = max(hi, v)
        }
        return lo <= hi ? lo...hi : nil
    }

    /// Bangun grid UTM untuk `extent` dengan mengambil sampel dari fungsi elevasi (mis. DEM lat/lon).
    /// Jumlah sel dibatasi `maxCells` dengan memperbesar ukuran sel bila perlu.
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

    // MARK: Simpan di paket proyek (dem.json + dem.bin Float32 little-endian)

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
            throw OcadReadError.corrupt("data DEM tidak cocok dengan header")
        }
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return DEMGrid(header: header, values: values)
    }

    public static func remove(from directory: URL) {
        for name in ["dem.json", "dem.bin"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }
}

/// Bilinear yang paham NaN: tetangga tanpa data diabaikan dan bobot dinormalisasi ulang.
/// Hasil NaN bila bobot data valid < 0,5 (titik lebih dekat ke area kosong daripada ke data).
func bilinear(_ a: Float, _ b: Float, _ c: Float, _ d: Float, _ tx: Float, _ ty: Float) -> Float {
    let w = [(1 - tx) * (1 - ty), tx * (1 - ty), (1 - tx) * ty, tx * ty]
    var sum: Float = 0, weight: Float = 0
    for (v, wi) in zip([a, b, c, d], w) where wi > 0 && !v.isNaN {
        sum += v * wi
        weight += wi
    }
    return weight >= 0.5 ? sum / weight : .nan
}
