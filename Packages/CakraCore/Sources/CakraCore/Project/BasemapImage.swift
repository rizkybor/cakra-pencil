import Foundation

/// Georeferenced image basemap (e.g. a GeoTIFF produced by georeferencing) shown beneath the map objects.
/// Its file is stored inside the project package (`fileName`), so it travels with the .cpencil file.
public struct BasemapImage: Codable, Hashable, Sendable {
    public enum CRS: Codable, Hashable, Sendable {
        case utm(epsg: Int)
        /// WGS84 lat/lon (EPSG:4326): x = longitude, y = latitude.
        case geographic
    }

    /// File name inside the project package.
    public var fileName: String
    /// Original file name (for display).
    public var originalName: String
    public var crs: CRS
    /// Upper-left edge of pixel (0,0) and pixel size (CRS units; y down = negative in the CRS).
    public var originX: Double
    public var originY: Double
    public var pixelSizeX: Double
    public var pixelSizeY: Double
    public var width: Int
    public var height: Int
    public var opacity: Double
    public var isVisible: Bool
    /// Date from the TIFF metadata (DateTime tag, "YYYY:MM:DD HH:MM:SS"), if present.
    public var dateTime: String?

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

    /// `fileName` is a plain file name inside the package (no folders, "..", or hidden files). Project files can come
    /// from other people (.occa import), so a crafted name must never reach a file outside the package.
    public var hasSafeFileName: Bool { Self.isSafeFileName(fileName) }

    public static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && !name.hasPrefix(".") && name != ".."
            && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    /// Human-readable metadata date, e.g. "17-05-2024"; nil if absent.
    public var dateLabel: String? {
        guard let d = dateTime else { return nil }
        let p = d.split(whereSeparator: { $0 == ":" || $0 == " " || $0 == "-" })
        guard p.count >= 3, p[0].count == 4 else { return d }
        return "\(p[2])-\(p[1])-\(p[0])"
    }

    /// Image CRS point at pixel (u right, v down; pixel edges).
    func crsPoint(u: Double, v: Double) -> Point2D {
        Point2D(x: originX + u * pixelSizeX, y: originY - v * pixelSizeY)
    }

    /// Lat/lon at pixel (u, v).
    public func latLon(u: Double, v: Double) -> LatLon {
        let p = crsPoint(u: u, v: v)
        switch crs {
        case let .utm(epsg):
            // EPSG was already validated on import (GeoTIFFGeoref).
            guard let zone = UTMZone(epsg: epsg) else { return LatLon(lat: 0, lon: 0) }
            return zone.unproject(p)
        case .geographic:
            return LatLon(lat: p.y, lon: p.x)
        }
    }

    /// Upper-left, upper-right, lower-right, lower-left corners in project UTM.
    public func corners(in zone: UTMZone) -> [Point2D] {
        let w = Double(width), h = Double(height)
        return [(0, 0), (w, 0), (w, h), (0, h)].map { zone.project(latLon(u: $0.0, v: $0.1)) }
    }

    /// Project UTM box containing the image.
    public func extent(in zone: UTMZone) -> Rect2D? { Rect2D(points: corners(in: zone)) }

    /// Approximate ground size (meters), for the summary.
    public func groundSizeM(in zone: UTMZone) -> (width: Double, height: Double) {
        let c = corners(in: zone)
        return (c[0].distance(to: c[1]), c[0].distance(to: c[3]))
    }
}

/// GeoTIFF georeferencing from tags (without decoding pixels): ModelPixelScale (33550), ModelTiepoint (33922),
/// GeoKeyDirectory (34735) → UTM WGS84 (EPSG 326xx/327xx) or WGS84 lat/lon (EPSG 4326).
public enum GeoTIFFGeoref {
    public enum GeorefError: Error, LocalizedError, Equatable {
        case notTIFF
        case notGeoreferenced
        case unsupportedCRS(Int?)
        case rotated

        public var errorDescription: String? {
            switch self {
            case .notTIFF: return "Not a TIFF file."
            case .notGeoreferenced: return "This TIFF is not georeferenced (no GeoTIFF pixel scale/tiepoint tags)."
            case let .unsupportedCRS(epsg):
                return "The \(epsg.map { "EPSG:\($0)" } ?? "image") coordinate system is not supported yet. Re-save it in UTM WGS84 or WGS84 lat/lon."
            case .rotated: return "Rotated GeoTIFFs (ModelTransformation) are not supported yet."
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
        /// TIFF DateTime tag (306), e.g. "2024:05:17 10:22:31"; nil if absent.
        public var dateTime: String? = nil
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
        // Tiepoint (i, j, k, x, y, z): pixel (i, j) ↔ CRS point (x, y). Pixel-is-area (default): pixel edges.
        let originX = tie[3] - tie[0] * scale[0]
        let originY = tie[4] + tie[1] * scale[1]
        // DateTime tag (306, ASCII): image creation/capture time according to the software that produced it.
        var dateTime: String?
        if let t = tags[306], t.type == 2, t.count > 1, t.count < 64 {
            let base = t.count <= 4 ? t.valueOffset : try u32(t.valueOffset)
            if base >= 0, base + t.count <= data.count {
                let bytes = data[(data.startIndex + base)..<(data.startIndex + base + t.count)].prefix { $0 != 0 }
                dateTime = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
                if dateTime?.isEmpty == true { dateTime = nil }
            }
        }
        return Info(width: width, height: height, crs: crs, originX: originX, originY: originY,
                    pixelSizeX: scale[0], pixelSizeY: scale[1], dateTime: dateTime)
    }
}
