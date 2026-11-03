import Compression
import Foundation

/// Sumber elevasi dengan georeferensi sendiri, sebelum di-resample ke grid UTM proyek.
public struct ElevationRaster: Sendable {
    public enum CRS: Sendable, Equatable {
        case geographic          // EPSG:4326, x = lon, y = lat
        case utm(UTMZone)
    }

    public var crs: CRS
    /// Koordinat tepi kiri atas sel (0,0) dan ukuran sel dalam satuan CRS (derajat atau meter).
    public var originX: Double
    public var originY: Double
    public var cellX: Double
    public var cellY: Double
    public var cols: Int
    public var rows: Int
    public var values: [Float]

    public init(crs: CRS, originX: Double, originY: Double, cellX: Double, cellY: Double, cols: Int, rows: Int, values: [Float]) {
        self.crs = crs
        self.originX = originX
        self.originY = originY
        self.cellX = cellX
        self.cellY = cellY
        self.cols = cols
        self.rows = rows
        self.values = values
    }

    /// Resolusi kira-kira dalam meter.
    public var resolutionM: Double {
        switch crs {
        case .utm: return cellX
        case .geographic:
            // Jarak antar baris (lintang) dalam meter; mis. 1 detik busur ≈ 30,9 m.
            return cellY * 111_320
        }
    }

    /// Elevasi bilinear di titik UTM proyek (dikonversi ke CRS raster lebih dulu).
    public func sample(_ p: Point2D, projectZone: UTMZone) -> Float {
        let (x, y): (Double, Double)
        switch crs {
        case .geographic:
            let ll = projectZone.unproject(p)
            (x, y) = (ll.lon, ll.lat)
        case let .utm(zone):
            if zone == projectZone {
                (x, y) = (p.x, p.y)
            } else {
                let q = zone.project(projectZone.unproject(p))
                (x, y) = (q.x, q.y)
            }
        }
        let fx = (x - originX) / cellX - 0.5, fy = (originY - y) / cellY - 0.5
        let c0 = Int(floor(fx)), r0 = Int(floor(fy))
        func v(_ c: Int, _ r: Int) -> Float { (c < 0 || r < 0 || c >= cols || r >= rows) ? .nan : values[r * cols + c] }
        let tx = Float(fx - Double(c0)), ty = Float(fy - Double(r0))
        return bilinear(v(c0, r0), v(c0 + 1, r0), v(c0, r0 + 1), v(c0 + 1, r0 + 1), tx, ty)
    }

    /// Resample ke grid UTM proyek. Ukuran sel = resolusi asli (minimal 0,5 m), dibatasi jumlah sel.
    public func grid(extent: Rect2D, zone: UTMZone, source: String) -> DEMGrid {
        let res = resolutionM
        return DEMGrid.resample(extent: extent, cellSize: max(res, 0.5), source: source, nativeResolutionM: res) {
            sample($0, projectZone: zone)
        }
    }
}

public enum DEMReadError: Error, LocalizedError, Equatable {
    case unsupported(String)
    case corrupt(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupported(s): return "Format DEM belum didukung: \(s)."
        case let .corrupt(s): return "File DEM rusak: \(s)."
        }
    }
}

// MARK: - ESRI ASCII Grid (.asc)

public enum AsciiGridReader {
    /// Header: ncols, nrows, xllcorner|xllcenter, yllcorner|yllcenter, cellsize, [NODATA_value].
    /// CRS dari .prj bila ada; tanpa .prj, nilai koordinat derajat dianggap EPSG:4326, selain itu UTM proyek.
    public static func read(_ data: Data, prj: String?, projectZone: UTMZone) throws -> ElevationRaster {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw DEMReadError.corrupt("bukan teks")
        }
        var header: [String: Double] = [:]
        var body = Substring(text)
        // Baca baris header selama baris diawali huruf.
        while let nl = body.firstIndex(where: \.isNewline) {
            let line = body[..<nl].trimmingCharacters(in: .whitespaces)
            guard let first = line.first, first.isLetter else { break }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, let v = Double(parts[1]) { header[parts[0].lowercased()] = v }
            body = body[body.index(after: nl)...]
        }
        guard let ncols = header["ncols"].map(Int.init), let nrows = header["nrows"].map(Int.init), let cell = header["cellsize"],
              ncols > 1, nrows > 1, ncols * nrows <= 100_000_000, cell > 0 else {
            throw DEMReadError.corrupt("header ncols/nrows/cellsize tidak lengkap")
        }
        let isCenter = header["xllcenter"] != nil
        let xll = (header["xllcorner"] ?? header["xllcenter"] ?? 0) - (isCenter ? cell / 2 : 0)
        let yll = (header["yllcorner"] ?? header["yllcenter"] ?? 0) - (isCenter ? cell / 2 : 0)
        let noData = Float(header["nodata_value"] ?? -9999)
        var values: [Float] = []
        values.reserveCapacity(ncols * nrows)
        for token in body.split(whereSeparator: { $0 == " " || $0 == "\t" || $0.isNewline }) {
            guard let v = Float(token) else { throw DEMReadError.corrupt("nilai bukan angka") }
            values.append(v == noData ? .nan : v)
            if values.count == ncols * nrows { break }
        }
        guard values.count == ncols * nrows else { throw DEMReadError.corrupt("jumlah nilai kurang dari ncols × nrows") }
        let crs = crsFrom(prj: prj, sampleX: xll, cell: cell, projectZone: projectZone)
        return ElevationRaster(crs: crs, originX: xll, originY: yll + Double(nrows) * cell, cellX: cell, cellY: cell,
                               cols: ncols, rows: nrows, values: values)
    }

    static func crsFrom(prj: String?, sampleX: Double, cell: Double, projectZone: UTMZone) -> ElevationRaster.CRS {
        if let prj, let zone = UTMZone(wkt: prj) { return .utm(zone) }
        if let prj, prj.uppercased().hasPrefix("GEOGCS") { return .geographic }
        return (abs(sampleX) <= 180 && cell < 0.1) ? .geographic : .utm(projectZone)
    }
}

extension UTMZone {
    /// Kenali zona UTM WGS84 dari WKT .prj (nama "UTM_Zone_48S", "UTM zone 48S", atau AUTHORITY EPSG 327xx).
    public init?(wkt: String) {
        let s = wkt.uppercased()
        if let r = s.range(of: #"326\d\d|327\d\d"#, options: .regularExpression), let code = Int(s[r]), let z = UTMZone(epsg: code) {
            self = z
            return
        }
        guard let r = s.range(of: #"UTM[ _]ZONE[ _](\d{1,2})([NS])"#, options: .regularExpression) else { return nil }
        let token = s[r]
        guard let num = Int(token.filter(\.isNumber)), let z = UTMZone(number: num, isNorth: token.last == "N") else { return nil }
        self = z
    }
}

// MARK: - GeoTIFF

/// Pembaca GeoTIFF minimal untuk DEM satu kanal: tanpa kompresi, Deflate (8/32946), LZW (5); predictor 1/2/3;
/// int16/uint16/int32/float32/float64; strip atau tile; little/big endian. Georeferensi dari ModelTiepoint +
/// ModelPixelScale, CRS dari GeoKey ProjectedCSType (UTM WGS84) atau GeographicType (4326).
public enum GeoTIFFReader {
    struct Decoded {
        var width: Int
        var height: Int
        var values: [Float]
        var pixelScale: [Double]
        var tiepoint: [Double]
        var crs: ElevationRaster.CRS?
    }

    public static func read(_ data: Data, projectZone: UTMZone) throws -> ElevationRaster {
        let d = try decode(data)
        let scale = d.pixelScale, tie = d.tiepoint
        guard scale.count >= 2, tie.count >= 6, scale[0] > 0, scale[1] > 0 else {
            throw DEMReadError.unsupported("GeoTIFF tanpa ModelPixelScale/ModelTiepoint (mungkin perlu world file)")
        }
        let originX = tie[3] - tie[0] * scale[0], originY = tie[4] + tie[1] * scale[1]
        let resolved = d.crs ?? ((abs(originX) <= 180 && scale[0] < 0.1) ? .geographic : .utm(projectZone))
        return ElevationRaster(crs: resolved, originX: originX, originY: originY, cellX: scale[0], cellY: scale[1],
                               cols: d.width, rows: d.height, values: d.values)
    }

    /// Dekode piksel + tag georeferensi mentah (tanpa memvalidasi georeferensi).
    static func decode(_ data: Data) throws -> Decoded {
        let b = [UInt8](data)
        guard b.count > 8 else { throw DEMReadError.corrupt("terlalu pendek") }
        let little: Bool
        switch (b[0], b[1]) {
        case (0x49, 0x49): little = true
        case (0x4D, 0x4D): little = false
        default: throw DEMReadError.unsupported("bukan TIFF")
        }
        func u16(_ o: Int) throws -> Int {
            guard o >= 0, o + 2 <= b.count else { throw DEMReadError.corrupt("offset di luar file") }
            return little ? Int(b[o]) | Int(b[o + 1]) << 8 : Int(b[o]) << 8 | Int(b[o + 1])
        }
        func u32(_ o: Int) throws -> Int {
            guard o >= 0, o + 4 <= b.count else { throw DEMReadError.corrupt("offset di luar file") }
            return little ? Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
                          : Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
        }
        func f64(_ o: Int) throws -> Double {
            guard o >= 0, o + 8 <= b.count else { throw DEMReadError.corrupt("offset di luar file") }
            var bits: UInt64 = 0
            for i in 0..<8 { bits |= UInt64(b[o + (little ? i : 7 - i)]) << (8 * UInt64(i)) }
            return Double(bitPattern: bits)
        }
        guard try u16(2) == 42 else { throw DEMReadError.unsupported("BigTIFF atau versi TIFF lain") }

        // IFD pertama.
        let ifd = try u32(4)
        let count = try u16(ifd)
        guard count < 1000 else { throw DEMReadError.corrupt("IFD") }
        var tags: [Int: (type: Int, count: Int, valueOffset: Int)] = [:]
        for i in 0..<count {
            let e = ifd + 2 + i * 12
            tags[try u16(e)] = (try u16(e + 2), try u32(e + 4), e + 8)
        }
        let typeSize = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 16: 8]
        /// Nilai-nilai tag sebagai array angka (dari dalam entri bila muat 4 byte, selain itu dari offset).
        func numbers(_ tag: Int) throws -> [Double] {
            guard let t = tags[tag], let size = typeSize[t.type], t.count < 50_000_000 else { return [] }
            let base = size * t.count <= 4 ? t.valueOffset : try u32(t.valueOffset)
            return try (0..<t.count).map { i -> Double in
                let o = base + i * size
                switch t.type {
                case 3: return Double(try u16(o))
                case 4: return Double(try u32(o))
                case 8: return Double(Int16(truncatingIfNeeded: try u16(o)))
                case 9: return Double(Int32(truncatingIfNeeded: try u32(o)))
                case 11: return Double(Float(bitPattern: UInt32(try u32(o))))
                case 12: return try f64(o)
                default: return Double(b[o])
                }
            }
        }
        func one(_ tag: Int) throws -> Int? { try numbers(tag).first.map(Int.init) }

        guard let width = try one(256), let height = try one(257), width > 1, height > 1, width * height <= 100_000_000 else {
            throw DEMReadError.corrupt("ukuran gambar")
        }
        let bits = try one(258) ?? 1
        let compression = try one(259) ?? 1
        let spp = try one(277) ?? 1
        let predictor = try one(317) ?? 1
        let format = try one(339) ?? 1 // 1 uint, 2 int, 3 float
        guard spp == 1 else { throw DEMReadError.unsupported("lebih dari 1 kanal") }
        guard [1, 5, 8, 32946].contains(compression) else { throw DEMReadError.unsupported("kompresi \(compression)") }
        guard [16, 32, 64].contains(bits) else { throw DEMReadError.unsupported("\(bits) bit per sampel") }
        let bps = bits / 8

        // Blok data: tile (322/323/324/325) atau strip (278/273/279).
        let tiled = tags[322] != nil
        let blockW = tiled ? (try one(322) ?? width) : width
        let blockH = tiled ? (try one(323) ?? height) : (try one(278) ?? height)
        let offsets = try numbers(tiled ? 324 : 273).map(Int.init)
        let lengths = try numbers(tiled ? 325 : 279).map(Int.init)
        guard !offsets.isEmpty, offsets.count == lengths.count, blockW > 0, blockH > 0 else { throw DEMReadError.corrupt("tabel strip/tile") }
        let across = tiled ? (width + blockW - 1) / blockW : 1

        var noData: Float?
        if let t = tags[42113] {
            let base = t.count <= 4 ? t.valueOffset : try u32(t.valueOffset)
            let raw = b[base..<min(base + t.count, b.count)].prefix { $0 != 0 }
            noData = Float(String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespaces))
        }

        var values = [Float](repeating: .nan, count: width * height)
        for (i, (off, len)) in zip(offsets, lengths).enumerated() {
            guard off >= 0, len >= 0, off + len <= b.count else { throw DEMReadError.corrupt("blok di luar file") }
            var block = Array(b[off..<(off + len)])
            let expected = blockW * blockH * bps
            switch compression {
            case 5: block = try lzwDecode(block, expected: expected)
            case 8, 32946: block = try inflate(block, expected: expected)
            default: break
            }
            guard block.count >= blockW * min(blockH, height) * bps || compression == 1 else { throw DEMReadError.corrupt("blok terlalu pendek") }
            let rowsInBlock = min(blockH, block.count / (blockW * bps))
            if predictor == 2 { undoHorizontal(&block, width: blockW, rows: rowsInBlock, bytesPerSample: bps, little: little) }
            if predictor == 3 { undoFloatingPoint(&block, width: blockW, rows: rowsInBlock, bytesPerSample: bps) }
            let x0 = tiled ? (i % across) * blockW : 0
            let y0 = tiled ? (i / across) * blockH : i * blockH
            for r in 0..<rowsInBlock {
                let y = y0 + r
                guard y < height else { break }
                for c in 0..<blockW {
                    let x = x0 + c
                    guard x < width else { break }
                    let o = (r * blockW + c) * bps
                    // Predictor 3 menyusun ulang byte ke big-endian; selain itu ikuti urutan file.
                    let le = predictor == 3 ? false : little
                    var raw: UInt64 = 0
                    for k in 0..<bps { raw |= UInt64(block[o + (le ? k : bps - 1 - k)]) << (8 * UInt64(k)) }
                    let v: Float
                    switch (format, bits) {
                    case (3, 32): v = Float(bitPattern: UInt32(raw))
                    case (3, 64): v = Float(Double(bitPattern: raw))
                    case (2, 16): v = Float(Int16(truncatingIfNeeded: raw))
                    case (2, 32): v = Float(Int32(truncatingIfNeeded: raw))
                    case (_, 16): v = Float(UInt16(truncatingIfNeeded: raw))
                    case (_, 32): v = Float(UInt32(truncatingIfNeeded: raw))
                    default: v = .nan
                    }
                    values[y * width + x] = (v == noData || v < -10_000 || !v.isFinite) ? .nan : v
                }
            }
        }

        // Georeferensi.
        let scale = try numbers(33550), tie = try numbers(33922)
        var crs: ElevationRaster.CRS?
        let keys = try numbers(34735).map(Int.init)
        if keys.count >= 4 {
            for k in 0..<keys[3] {
                let e = 4 + k * 4
                guard e + 3 < keys.count, keys[e + 1] == 0 else { continue }
                if keys[e] == 3072, let z = UTMZone(epsg: keys[e + 3]) { crs = .utm(z) }
                if keys[e] == 2048, keys[e + 3] == 4326 || keys[e + 3] == 4979 { crs = crs ?? .geographic }
                if keys[e] == 1024, keys[e + 3] == 2 { crs = crs ?? .geographic }
            }
        }
        return Decoded(width: width, height: height, values: values, pixelScale: scale, tiepoint: tie, crs: crs)
    }

    /// Deflate TIFF = zlib (2 byte header + data + adler32); framework Compression memakai deflate mentah.
    static func inflate(_ src: [UInt8], expected: Int) throws -> [UInt8] {
        guard src.count > 2 else { throw DEMReadError.corrupt("blok deflate kosong") }
        let raw = Array(src.dropFirst(2))
        var out = [UInt8](repeating: 0, count: max(expected, 1))
        let n = raw.withUnsafeBufferPointer { s in
            out.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, d.count, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { throw DEMReadError.corrupt("deflate gagal") }
        return Array(out.prefix(n))
    }

    /// LZW TIFF (MSB-first, kode 9–12 bit, Clear 256, EOI 257).
    static func lzwDecode(_ src: [UInt8], expected: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(expected)
        var table: [[UInt8]] = (0..<256).map { [UInt8($0)] } + [[], []]
        var codeLen = 9, bitPos = 0
        var prev: [UInt8]?
        func next() -> Int? {
            guard bitPos + codeLen <= src.count * 8 else { return nil }
            var v = 0
            for _ in 0..<codeLen {
                v = (v << 1) | Int((src[bitPos >> 3] >> (7 - UInt8(bitPos & 7))) & 1)
                bitPos += 1
            }
            return v
        }
        while let code = next() {
            if code == 257 { break }
            if code == 256 {
                table.removeSubrange(258...)
                codeLen = 9
                prev = nil
                continue
            }
            let entry: [UInt8]
            if code < table.count {
                entry = table[code]
                if let p = prev { table.append(p + [entry[0]]) }
            } else if let p = prev, code == table.count {
                entry = p + [p[0]]
                table.append(entry)
            } else {
                throw DEMReadError.corrupt("kode LZW")
            }
            out.append(contentsOf: entry)
            prev = entry
            // TIFF "early change": lebar kode naik satu kode lebih awal.
            if table.count + 1 >= (1 << codeLen), codeLen < 12 { codeLen += 1 }
            if out.count >= expected { break }
        }
        return out
    }

    /// Predictor 2: selisih horizontal per sampel.
    static func undoHorizontal(_ b: inout [UInt8], width: Int, rows: Int, bytesPerSample bps: Int, little: Bool) {
        for r in 0..<rows {
            var prev: UInt64 = 0
            for c in 0..<width {
                let o = (r * width + c) * bps
                guard o + bps <= b.count else { return }
                var v: UInt64 = 0
                for k in 0..<bps { v |= UInt64(b[o + (little ? k : bps - 1 - k)]) << (8 * UInt64(k)) }
                let mask: UInt64 = bps == 8 ? .max : (1 << (8 * UInt64(bps))) - 1
                v = (v &+ prev) & mask
                prev = v
                for k in 0..<bps { b[o + (little ? k : bps - 1 - k)] = UInt8((v >> (8 * UInt64(k))) & 0xFF) }
            }
        }
    }

    /// Predictor 3 (floating point): selisih per byte lalu byte tiap baris disusun ulang per bidang (MSB dulu).
    static func undoFloatingPoint(_ b: inout [UInt8], width: Int, rows: Int, bytesPerSample bps: Int) {
        let rowBytes = width * bps
        for r in 0..<rows {
            let start = r * rowBytes
            guard start + rowBytes <= b.count else { return }
            for i in 1..<rowBytes { b[start + i] = b[start + i] &+ b[start + i - 1] }
            let row = Array(b[start..<(start + rowBytes)])
            for c in 0..<width {
                for k in 0..<bps { b[start + c * bps + k] = row[k * width + c] }
            }
        }
    }
}

// MARK: - Terrain Tiles (AWS, encoding Terrarium)

public enum TerrainTiles {
    /// Elevasi Terrarium: (R × 256 + G + B / 256) − 32768 meter.
    public static func elevation(r: UInt8, g: UInt8, b: UInt8) -> Float {
        Float(r) * 256 + Float(g) + Float(b) / 256 - 32768
    }

    public static func url(z: Int, x: Int, y: Int) -> URL {
        URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(z)/\(x)/\(y).png")!
    }

    /// Posisi tile Web Mercator (pecahan) untuk lat/lon pada zoom z.
    public static func tileXY(_ c: LatLon, z: Int) -> (x: Double, y: Double) {
        let n = pow(2.0, Double(z))
        let lat = c.lat * .pi / 180
        return ((c.lon + 180) / 360 * n, (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2 * n)
    }

    /// Tile yang menutup kotak UTM (dengan zona proyek).
    public static func tiles(covering extent: Rect2D, zone: UTMZone, z: Int) -> [(x: Int, y: Int)] {
        let corners = [Point2D(x: extent.minX, y: extent.minY), Point2D(x: extent.maxX, y: extent.maxY),
                       Point2D(x: extent.minX, y: extent.maxY), Point2D(x: extent.maxX, y: extent.minY)]
        let t = corners.map { tileXY(zone.unproject($0), z: z) }
        let x0 = Int(floor(t.map(\.x).min()!)), x1 = Int(floor(t.map(\.x).max()!))
        let y0 = Int(floor(t.map(\.y).min()!)), y1 = Int(floor(t.map(\.y).max()!))
        return (y0...y1).flatMap { y in (x0...x1).map { (x: $0, y: y) } }
    }

    /// Resolusi tile di lintang tertentu (m/piksel; tile 256 px).
    public static func resolutionM(z: Int, lat: Double) -> Double {
        40_075_016.686 * cos(lat * .pi / 180) / (256 * pow(2.0, Double(z)))
    }
}

/// Mosaik tile Terrarium yang sudah didekode (elevasi per piksel), untuk di-resample ke grid UTM.
public struct TerrainMosaic: Sendable {
    public var z: Int
    public var tiles: [String: [Float]] // "x/y" → 256×256

    public init(z: Int, tiles: [String: [Float]] = [:]) {
        self.z = z
        self.tiles = tiles
    }

    public func sample(_ c: LatLon) -> Float {
        let t = TerrainTiles.tileXY(c, z: z)
        let px = t.x * 256 - 0.5, py = t.y * 256 - 0.5
        let x0 = Int(floor(px)), y0 = Int(floor(py))
        func v(_ x: Int, _ y: Int) -> Float {
            guard let tile = tiles["\(x >> 8)/\(y >> 8)"] else { return .nan }
            return tile[(y & 255) * 256 + (x & 255)]
        }
        let tx = Float(px - Double(x0)), ty = Float(py - Double(y0))
        return bilinear(v(x0, y0), v(x0 + 1, y0), v(x0, y0 + 1), v(x0 + 1, y0 + 1), tx, ty)
    }
}

// MARK: - GeoJSON garis kontur

public enum ContourGeoJSON {
    static let elevationKeys = ["elev", "ELEV", "elevation", "ELEVATION", "Elevation", "contour", "CONTOUR", "height", "HEIGHT", "z", "Z"]

    /// LineString/MultiLineString dengan properti elevasi. Koordinat lon/lat (RFC 7946); bila nilainya jelas
    /// meter (> 180), dianggap UTM zona proyek.
    public static func read(_ data: Data, zone: UTMZone) throws -> [(elevation: Double, points: [Point2D])] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DEMReadError.corrupt("GeoJSON") }
        let features = (root["features"] as? [[String: Any]]) ?? (root["type"] as? String == "Feature" ? [root] : [])
        var out: [(Double, [Point2D])] = []
        for f in features {
            let props = f["properties"] as? [String: Any] ?? [:]
            guard let elev = elevationKeys.lazy.compactMap({ props[$0] }).compactMap({ ($0 as? NSNumber)?.doubleValue ?? Double("\($0)") }).first,
                  let geom = f["geometry"] as? [String: Any], let type = geom["type"] as? String else { continue }
            let lines: [[[Double]]]
            switch type {
            case "LineString": lines = [(geom["coordinates"] as? [[Double]]) ?? []]
            case "MultiLineString": lines = (geom["coordinates"] as? [[[Double]]]) ?? []
            default: continue
            }
            for line in lines where line.count >= 2 {
                let pts = line.compactMap { c -> Point2D? in
                    guard c.count >= 2 else { return nil }
                    return abs(c[0]) > 180 ? Point2D(x: c[0], y: c[1]) : zone.project(LatLon(lat: c[1], lon: c[0]))
                }
                out.append((elev, pts))
            }
        }
        guard !out.isEmpty else { throw DEMReadError.corrupt("tidak ada LineString dengan properti elevasi (elev/elevation/contour)") }
        return out
    }
}
