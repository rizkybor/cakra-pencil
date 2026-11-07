import Foundation

/// Export of contour data only: Shapefile (project UTM), KML and KMZ (WGS84, for Google Earth and map apps).
public enum ContourExportFormat: String, CaseIterable, Identifiable, Sendable {
    case shp, kml, kmz

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .shp: return "Shapefile (.shp)"
        case .kml: return "KML (.kml)"
        case .kmz: return "KMZ (.kmz)"
        }
    }
}

public enum ContourExporter {
    /// Write the selected formats to `directory`; return all files created (Shapefile = 5 files).
    public static func export(_ lines: [ContourLine], formats: Set<ContourExportFormat>, zone: UTMZone, settings: ContourSettings,
                              baseName: String, title: String, to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        let usable = lines.filter { $0.points.count >= 2 }
        if formats.contains(.shp) {
            let shp = Shapefile.polylines(usable)
            for (ext, data) in [("shp", shp.shp), ("shx", shp.shx), ("dbf", shp.dbf), ("prj", Data(zone.prjWKT.utf8)), ("cpg", Data("UTF-8".utf8))] {
                let url = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
        }
        let kml = formats.contains(.kml) || formats.contains(.kmz) ? KML.document(usable, zone: zone, settings: settings, title: title) : ""
        if formats.contains(.kml) {
            let url = directory.appendingPathComponent(baseName).appendingPathExtension("kml")
            try Data(kml.utf8).write(to: url, options: .atomic)
            urls.append(url)
        }
        if formats.contains(.kmz) {
            let url = directory.appendingPathComponent(baseName).appendingPathExtension("kmz")
            try ZipWriter.archive([("doc.kml", Data(kml.utf8))]).write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }
}

// MARK: - Shapefile (ESRI, PolyLine) + DBF

public enum Shapefile {
    public struct Files {
        public var shp: Data
        public var shx: Data
        public var dbf: Data
    }

    static let polyLineType: Int32 = 3

    /// One PolyLine record per contour line; attributes ELEV (N 12.2), TYPE (C 10), ISOM (C 6).
    public static func polylines(_ lines: [ContourLine]) -> Files {
        var records: [Data] = []
        var all: [Point2D] = []
        for line in lines {
            var c = Data()
            let box = Rect2D(points: line.points) ?? Rect2D(minX: 0, minY: 0, maxX: 0, maxY: 0)
            c.appendLE(polyLineType)
            for v in [box.minX, box.minY, box.maxX, box.maxY] { c.appendLE(v) }
            c.appendLE(Int32(1))                   // NumParts
            c.appendLE(Int32(line.points.count))   // NumPoints
            c.appendLE(Int32(0))                   // Parts[0]
            for p in line.points {
                c.appendLE(p.x)
                c.appendLE(p.y)
            }
            records.append(c)
            all += line.points
        }
        let box = Rect2D(points: all) ?? Rect2D(minX: 0, minY: 0, maxX: 0, maxY: 0)

        var shp = header(fileLengthBytes: 100 + records.reduce(0) { $0 + 8 + $1.count }, box: box)
        var shx = header(fileLengthBytes: 100 + records.count * 8, box: box)
        var offset = 100
        for (i, r) in records.enumerated() {
            shp.appendBE(Int32(i + 1))
            shp.appendBE(Int32(r.count / 2))
            shp.append(r)
            shx.appendBE(Int32(offset / 2))
            shx.appendBE(Int32(r.count / 2))
            offset += 8 + r.count
        }
        return Files(shp: shp, shx: shx, dbf: dbf(lines))
    }

    /// 100-byte .shp/.shx header: file code + length (big-endian, 16-bit units), version + type + bbox (little-endian).
    static func header(fileLengthBytes: Int, box: Rect2D) -> Data {
        var d = Data()
        d.appendBE(Int32(9994))
        for _ in 0..<5 { d.appendBE(Int32(0)) }
        d.appendBE(Int32(fileLengthBytes / 2))
        d.appendLE(Int32(1000))
        d.appendLE(polyLineType)
        for v in [box.minX, box.minY, box.maxX, box.maxY, 0, 0, 0, 0] { d.appendLE(v) }
        return d
    }

    /// dBase III: 32-byte header, 32-byte field descriptors, 0x0D, records (flag + fixed-width fields), 0x1A.
    static func dbf(_ lines: [ContourLine]) -> Data {
        let fields: [(name: String, type: Character, length: Int, decimals: Int)] = [("ELEV", "N", 12, 2), ("TYPE", "C", 10, 0), ("ISOM", "C", 6, 0)]
        let recordLength = 1 + fields.reduce(0) { $0 + $1.length }
        let headerLength = 32 + 32 * fields.count + 1
        var d = Data()
        d.append(0x03)
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        d.append(contentsOf: [UInt8((comps.year ?? 2026) - 1900), UInt8(comps.month ?? 1), UInt8(comps.day ?? 1)])
        d.appendLE(UInt32(lines.count))
        d.appendLE(UInt16(headerLength))
        d.appendLE(UInt16(recordLength))
        d.append(Data(count: 20))
        for f in fields {
            var name = Data(f.name.utf8.prefix(10))
            name.append(Data(count: 11 - name.count))
            d.append(name)
            d.append(UInt8(f.type.asciiValue!))
            d.append(Data(count: 4))
            d.append(UInt8(f.length))
            d.append(UInt8(f.decimals))
            d.append(Data(count: 14))
        }
        d.append(0x0D)
        for line in lines {
            d.append(UInt8(ascii: " "))
            let elev = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), line.elevation)
            d.append(Data((String(repeating: " ", count: max(0, 12 - elev.count)) + elev).utf8.prefix(12)))
            for (value, length) in [(line.kind.rawValue, 10), (line.symbolCode, 6)] {
                let v = String(value.prefix(length))
                d.append(Data((v + String(repeating: " ", count: length - v.count)).utf8))
            }
        }
        d.append(0x1A)
        return d
    }
}

// MARK: - KML

public enum KML {
    /// KML 2.2 document: one folder per line kind, one style per kind (project contour color), elevation in the name and ExtendedData.
    public static func document(_ lines: [ContourLine], zone: UTMZone, settings s: ContourSettings, title: String) -> String {
        // KML: color is aabbggrr; width in screen pixels.
        let rgb = rgbComponents(hex: s.colorHex) ?? (0.82, 0.36, 0)
        let alpha = Int((s.opacity * 255).rounded())
        let color = String(format: "%02x%02x%02x%02x", alpha, Int(rgb.b * 255), Int(rgb.g * 255), Int(rgb.r * 255))
        var x = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document>
        <name>\(escape(title))</name>
        <description>Kontur interval \(num(s.intervalM, 2)) m, indeks tiap \(s.indexEvery) garis. Dibuat oleh \(AppInfo.name).</description>
        <Style id="contour"><LineStyle><color>\(color)</color><width>1.5</width></LineStyle></Style>
        <Style id="index"><LineStyle><color>\(color)</color><width>3</width></LineStyle></Style>
        <Style id="form"><LineStyle><color>\(color)</color><width>1</width></LineStyle></Style>

        """
        for kind in [ContourLine.Kind.index, .contour, .form] {
            let group = lines.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            x += "<Folder><name>\(group[0].symbolName) (\(group.count))</name>\n"
            for line in group {
                let coords = line.points.map { p -> String in
                    let ll = zone.unproject(p)
                    return "\(num(ll.lon, 8)),\(num(ll.lat, 8)),\(num(line.elevation, 2))"
                }.joined(separator: " ")
                x += """
                <Placemark><name>\(num(line.elevation, line.elevation.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2)) m</name><styleUrl>#\(kind.rawValue)</styleUrl>\
                <ExtendedData><Data name="elev"><value>\(num(line.elevation, 2))</value></Data><Data name="isom"><value>\(line.symbolCode)</value></Data></ExtendedData>\
                <LineString><tessellate>1</tessellate><altitudeMode>clampToGround</altitudeMode><coordinates>\(coords)</coordinates></LineString></Placemark>

                """
            }
            x += "</Folder>\n"
        }
        x += "</Document>\n</kml>\n"
        return x
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - ZIP (for KMZ)

/// Minimal ZIP archive (Store method, no compression): local header + data + central directory + end record.
public enum ZipWriter {
    public static func archive(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data(), central = Data()
        for (name, data) in entries {
            let crc = crc32(data), nameData = Data(name.utf8)
            let offset = UInt32(out.count)
            out.appendLE(UInt32(0x0403_4B50))
            out.appendLE(UInt16(20)); out.appendLE(UInt16(0)); out.appendLE(UInt16(0)) // version, flags, store method
            out.appendLE(UInt16(0)); out.appendLE(UInt16(0x21))                        // time, date (1980-01-01)
            out.appendLE(crc); out.appendLE(UInt32(data.count)); out.appendLE(UInt32(data.count))
            out.appendLE(UInt16(nameData.count)); out.appendLE(UInt16(0))
            out.append(nameData)
            out.append(data)

            central.appendLE(UInt32(0x0201_4B50))
            central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0x21))
            central.appendLE(crc); central.appendLE(UInt32(data.count)); central.appendLE(UInt32(data.count))
            central.appendLE(UInt16(nameData.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0))
            central.appendLE(offset)
            central.append(nameData)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.appendLE(UInt32(0x0605_4B50))
        out.appendLE(UInt16(0)); out.appendLE(UInt16(0))
        out.appendLE(UInt16(entries.count)); out.appendLE(UInt16(entries.count))
        out.appendLE(UInt32(central.count)); out.appendLE(centralOffset)
        out.appendLE(UInt16(0))
        return out
    }

    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ v: T) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func appendBE<T: FixedWidthInteger>(_ v: T) { Swift.withUnsafeBytes(of: v.bigEndian) { append(contentsOf: $0) } }
    mutating func appendLE(_ v: Double) { appendLE(v.bitPattern) }
}
