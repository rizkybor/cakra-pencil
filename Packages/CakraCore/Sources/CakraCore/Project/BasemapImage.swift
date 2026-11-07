import Foundation

/// Basemap gambar ter-georeferensi (mis. GeoTIFF hasil georeferencing) yang tampil di bawah objek peta.
/// Berkasnya disimpan di dalam paket proyek (`fileName`), jadi ikut ke file .cpencil.
public struct BasemapImage: Codable, Hashable, Sendable {
    public enum CRS: Codable, Hashable, Sendable {
        case utm(epsg: Int)
        /// WGS84 lat/lon (EPSG:4326): x = bujur, y = lintang.
        case geographic
    }

    /// Nama berkas di dalam paket proyek.
    public var fileName: String
    /// Nama berkas asli (untuk ditampilkan).
    public var originalName: String
    public var crs: CRS
    /// Tepi kiri atas piksel (0,0) dan ukuran piksel (satuan CRS; y ke bawah = negatif di CRS).
    public var originX: Double
    public var originY: Double
    public var pixelSizeX: Double
    public var pixelSizeY: Double
    public var width: Int
    public var height: Int
    public var opacity: Double
    public var isVisible: Bool

    public init(fileName: String, originalName: String, crs: CRS, originX: Double, originY: Double,
                pixelSizeX: Double, pixelSizeY: Double, width: Int, height: Int, opacity: Double = 1, isVisible: Bool = true) {
        self.fileName = fileName
        self.originalName = originalName
        self.crs = crs
        self.originX = originX
        self.originY = originY
        self.pixelSizeX = pixelSizeX
        self.pixelSizeY = pixelSizeY
        self.width = width
        self.height = height
        self.opacity = opacity
        self.isVisible = isVisible
    }

    public var opacityValue: Double { min(max(opacity, 0), 1) }

    /// Titik CRS gambar di piksel (u ke kanan, v ke bawah; tepi piksel).
    func crsPoint(u: Double, v: Double) -> Point2D {
        Point2D(x: originX + u * pixelSizeX, y: originY - v * pixelSizeY)
    }

    /// Lat/lon di piksel (u, v).
    public func latLon(u: Double, v: Double) -> LatLon {
        let p = crsPoint(u: u, v: v)
        switch crs {
        case let .utm(epsg):
            // EPSG sudah divalidasi saat impor (GeoTIFFGeoref).
            guard let zone = UTMZone(epsg: epsg) else { return LatLon(lat: 0, lon: 0) }
            return zone.unproject(p)
        case .geographic:
            return LatLon(lat: p.y, lon: p.x)
        }
    }

    /// Pojok kiri atas, kanan atas, kanan bawah, kiri bawah dalam UTM proyek.
    public func corners(in zone: UTMZone) -> [Point2D] {
        let w = Double(width), h = Double(height)
        return [(0, 0), (w, 0), (w, h), (0, h)].map { zone.project(latLon(u: $0.0, v: $0.1)) }
    }

    /// Kotak UTM proyek yang memuat gambar.
    public func extent(in zone: UTMZone) -> Rect2D? { Rect2D(points: corners(in: zone)) }

    /// Ukuran tanah (meter) kira-kira, untuk ringkasan.
    public func groundSizeM(in zone: UTMZone) -> (width: Double, height: Double) {
        let c = corners(in: zone)
        return (c[0].distance(to: c[1]), c[0].distance(to: c[3]))
    }
}

/// Georeferensi GeoTIFF dari tag (tanpa men-decode piksel): ModelPixelScale (33550), ModelTiepoint (33922),
/// GeoKeyDirectory (34735) → UTM WGS84 (EPSG 326xx/327xx) atau WGS84 lat/lon (EPSG 4326).
public enum GeoTIFFGeoref {
    public enum GeorefError: Error, LocalizedError, Equatable {
        case notTIFF
        case notGeoreferenced
        case unsupportedCRS(Int?)
        case rotated

        public var errorDescription: String? {
            switch self {
            case .notTIFF: return "Bukan file TIFF."
            case .notGeoreferenced: return "TIFF ini belum ter-georeferensi (tidak ada tag GeoTIFF pixel scale/tiepoint)."
            case let .unsupportedCRS(epsg):
                return "Sistem koordinat \(epsg.map { "EPSG:\($0)" } ?? "gambar") belum didukung. Simpan ulang dalam UTM WGS84 atau WGS84 lat/lon."
            case .rotated: return "GeoTIFF yang diputar (ModelTransformation) belum didukung."
            }
        }
    }

    public struct Info: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var crs: BasemapImage.CRS
        public var originX: Double
        public var originY: Double
        public var pixelSizeX: Double
        public var pixelSizeY: Double
    }

    public static func read(_ data: Data) throws -> Info {
        let b = [UInt8](data.prefix(16))
        guard b.count >= 8 else { throw GeorefError.notTIFF }
        let little: Bool
        switch (b[0], b[1]) {
        case (0x49, 0x49): little = true
        case (0x4D, 0x4D): little = false
        default: throw GeorefError.notTIFF
        }
        func u16(_ o: Int) throws -> Int {
            guard o >= 0, o + 2 <= data.count else { throw GeorefError.notTIFF }
            let x = data[data.startIndex + o], y = data[data.startIndex + o + 1]
            return little ? Int(x) | Int(y) << 8 : Int(x) << 8 | Int(y)
        }
        func u32(_ o: Int) throws -> Int {
            guard o >= 0, o + 4 <= data.count else { throw GeorefError.notTIFF }
            let s = data.startIndex + o
            let v = (0..<4).map { Int(data[s + $0]) }
            return little ? v[0] | v[1] << 8 | v[2] << 16 | v[3] << 24 : v[0] << 24 | v[1] << 16 | v[2] << 8 | v[3]
        }
        func f64(_ o: Int) throws -> Double {
            guard o >= 0, o + 8 <= data.count else { throw GeorefError.notTIFF }
            var bits: UInt64 = 0
            for i in 0..<8 { bits |= UInt64(data[data.startIndex + o + (little ? i : 7 - i)]) << (8 * UInt64(i)) }
            return Double(bitPattern: bits)
        }
        guard try u16(2) == 42 else { throw GeorefError.notTIFF }
        let ifd = try u32(4)
        let count = try u16(ifd)
        guard count < 1000 else { throw GeorefError.notTIFF }
        var tags: [Int: (type: Int, count: Int, valueOffset: Int)] = [:]
        for i in 0..<count {
            let e = ifd + 2 + i * 12
            tags[try u16(e)] = (try u16(e + 2), try u32(e + 4), e + 8)
        }
        let size = [3: 2, 4: 4, 12: 8]
        func numbers(_ tag: Int) throws -> [Double] {
            guard let t = tags[tag], let s = size[t.type], t.count < 10_000 else { return [] }
            let base = s * t.count <= 4 ? t.valueOffset : try u32(t.valueOffset)
            return try (0..<t.count).map { i in
                let o = base + i * s
                switch t.type {
                case 3: return Double(try u16(o))
                case 4: return Double(try u32(o))
                default: return try f64(o)
                }
            }
        }
        guard let width = try numbers(256).first.map(Int.init), let height = try numbers(257).first.map(Int.init),
              width > 0, height > 0 else { throw GeorefError.notTIFF }
        if tags[34264] != nil, tags[33550] == nil { throw GeorefError.rotated }
        let scale = try numbers(33550), tie = try numbers(33922)
        guard scale.count >= 2, tie.count >= 6, scale[0] > 0, scale[1] > 0 else { throw GeorefError.notGeoreferenced }

        var projected: Int?, geographic: Int?, model: Int?
        let keys = try numbers(34735).map(Int.init)
        if keys.count >= 4 {
            for k in 0..<keys[3] {
                let e = 4 + k * 4
                guard e + 3 < keys.count, keys[e + 1] == 0 else { continue }
                switch keys[e] {
                case 1024: model = keys[e + 3]
                case 2048: geographic = keys[e + 3]
                case 3072: projected = keys[e + 3]
                default: break
                }
            }
        }
        let crs: BasemapImage.CRS
        if let p = projected {
            guard UTMZone(epsg: p) != nil else { throw GeorefError.unsupportedCRS(p) }
            crs = .utm(epsg: p)
        } else if model == 2 || geographic == 4326 || geographic == 4979 {
            crs = .geographic
        } else {
            throw GeorefError.unsupportedCRS(geographic)
        }
        // Tiepoint (i, j, k, x, y, z): piksel (i, j) ↔ titik CRS (x, y). Pixel-is-area (default): tepi piksel.
        let originX = tie[3] - tie[0] * scale[0]
        let originY = tie[4] + tie[1] * scale[1]
        return Info(width: width, height: height, crs: crs, originX: originX, originY: originY,
                    pixelSizeX: scale[0], pixelSizeY: scale[1])
    }
}
