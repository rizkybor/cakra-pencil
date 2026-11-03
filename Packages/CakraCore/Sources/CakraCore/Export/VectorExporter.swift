import Foundation

/// Simbol sketsa = satu kombinasi warna + tebal. Sampai kelas fitur ISOM ada (FR-4), stroke diberi kode
/// netral 990.x supaya mapper memetakan sendiri ke simbol ISOM di OOM/OCAD ("Change symbol"):
/// warna saja tidak cukup untuk menebak simbol (hitam bisa jalur, pagar, atau bangunan).
public struct SketchSymbol: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case line, point, area }

    public var index: Int
    public var colorHex: String
    public var widthMM: Double
    public var kind: Kind
    /// Kode + nama simbol ISOM bila objek memakai simbol dari set simbol.
    public var isomCode: String?
    public var isomName: String?

    public var isPoint: Bool { kind == .point }
    public var isArea: Bool { kind == .area }
    public var code: String { isomCode ?? "990.\(index + 1)" }

    public var colorName: String {
        PenPreset.isom.first { $0.colorHex.caseInsensitiveCompare(colorHex) == .orderedSame }?.name ?? colorHex.uppercased()
    }

    /// Mis. "Sketsa Coklat 0.14 mm" (titik desimal agar sama di OOM, OCAD, dan DXF).
    public var name: String {
        if let isomName, !isomName.isEmpty { return isomName }
        if isArea { return "Area \(colorName)" }
        return "Sketsa \(colorName)\(isPoint ? " titik" : "") \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), widthMM)) mm"
    }

    /// Nama layer DXF: hanya A–Z, 0–9, _ (aman untuk R12), mis. "990_1_SKETSA_COKLAT_014".
    public var dxfLayer: String {
        let mm = Int((widthMM * 100).rounded())
        if let isomCode {
            let raw = "\(isomCode.replacingOccurrences(of: ".", with: "_"))_\(isomName ?? "")"
            return String(raw.uppercased().prefix(31).map { $0.isLetter || $0.isNumber ? $0 : "_" })
        }
        let raw = isArea
            ? "990_\(index + 1)_AREA_\(colorName)"
            : "990_\(index + 1)_SKETSA_\(colorName)_\(String(format: "%03d", mm))\(isPoint ? "_TITIK" : "")"
        return String(raw.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}

/// Simbol unik dari stroke dan objek vektor, urut sesuai kemunculan pertama.
/// Garis bezier memakai simbol garis yang sama dengan stroke bila warna + tebalnya sama.
public struct SketchSymbolTable: Sendable {
    public private(set) var symbols: [SketchSymbol] = []
    private var lookup: [String: Int] = [:]

    public init(strokes: [Stroke], features: [Feature] = []) {
        for s in strokes { _ = add(Self.key(s)) }
        for f in features { _ = add(Self.key(f)) }
    }

    private struct Key: Hashable {
        var color: String
        var width: Int
        var kind: SketchSymbol.Kind
        var code: String? = nil
        var name: String? = nil

        /// Objek bersimbol ISOM dikelompokkan per kode + jenis; sisanya per warna + tebal.
        var string: String { code.map { "isom|\($0)|\(kind.rawValue)" } ?? "\(color)|\(width)|\(kind.rawValue)" }
    }

    private static func key(_ s: Stroke) -> Key {
        Key(color: s.colorHex.uppercased(), width: Int((s.widthMM * 100).rounded()), kind: s.points.count == 1 ? .point : .line)
    }

    private static func key(_ f: Feature) -> Key {
        f.kind == .area
            ? Key(color: f.colorHex.uppercased(), width: 0, kind: .area, code: f.symbolCode, name: f.symbolName)
            : Key(color: f.colorHex.uppercased(), width: Int((f.widthMM * 100).rounded()), kind: .line, code: f.symbolCode, name: f.symbolName)
    }

    public func symbol(of s: Stroke) -> SketchSymbol? { lookup[Self.key(s).string].map { symbols[$0] } }
    public func symbol(of f: Feature) -> SketchSymbol? { lookup[Self.key(f).string].map { symbols[$0] } }

    private mutating func add(_ k: Key) -> SketchSymbol {
        if let i = lookup[k.string] { return symbols[i] }
        let sym = SketchSymbol(index: symbols.count, colorHex: k.color, widthMM: Double(k.width) / 100, kind: k.kind,
                               isomCode: k.code, isomName: k.name)
        lookup[k.string] = symbols.count
        symbols.append(sym)
        return sym
    }
}

public enum VectorFormat: String, CaseIterable, Identifiable, Sendable {
    case omap, dxf

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }
}

public struct VectorExportRequest: Sendable {
    public var baseName: String
    public var frame: MapFrame
    public var sheet: SheetSpec
    public var zone: UTMZone
    public var strokes: [Stroke]
    public var features: [Feature]
    public var grid: NorthGrid?

    public init(baseName: String, frame: MapFrame, sheet: SheetSpec, zone: UTMZone, strokes: [Stroke], features: [Feature] = [],
                grid: NorthGrid? = nil) {
        self.baseName = baseName
        self.frame = frame
        self.sheet = sheet
        self.zone = zone
        self.strokes = strokes
        self.features = features
        self.grid = grid
    }

    /// Stroke yang seluruhnya di luar frame tidak ikut (FR-1.8). Yang terpotong tepi tetap utuh
    /// karena vektor bisa dipotong di OCAD/OOM tanpa kehilangan data.
    public var exportedStrokes: [Stroke] {
        let e = frame.extent
        return strokes.filter { $0.bounds.map(e.intersects) ?? false }
    }

    /// Objek vektor yang tampil dan menyentuh frame, plus garis utara (ISOM 601) bila grid ikut export.
    public var exportedFeatures: [Feature] {
        let e = frame.extent
        let own = features.filter { $0.isVisible && $0.nodes.count > 1 && ($0.bounds.map(e.intersects) ?? false) }
        guard let g = grid, g.isEnabled, g.includeInExport else { return own }
        return g.features(in: frame) + own
    }
}

public enum VectorExporter {
    public static func export(_ req: VectorExportRequest, formats: Set<VectorFormat>, to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls: [URL] = []
        for format in VectorFormat.allCases where formats.contains(format) {
            let url = directory.appendingPathComponent(req.baseName).appendingPathExtension(format.fileExtension)
            switch format {
            case .omap: try OmapWriter.document(req).write(to: url, atomically: true, encoding: .utf8)
            case .dxf: try DXFWriter.document(req).write(to: url, atomically: true, encoding: .ascii)
            }
            urls.append(url)
        }
        return urls
    }
}

// MARK: - OpenOrienteering Mapper (.omap)

/// Writer XML OOM sendiri, ditulis dari struktur file contoh (tanpa menyalin kode OOM yang GPL v3).
///
/// Koordinat peta OOM = mikrometer di kertas, sumbu y ke bawah, relatif ke titik referensi peta (0, 0)
/// yang dipasangkan ke titik tengah frame di UTM. Grivation 0 karena frame north-up terhadap grid.
public enum OmapWriter {
    public static func mapCoordinate(_ p: Point2D, reference: Point2D, scale: Int) -> (x: Int, y: Int) {
        let f = 1_000_000 / Double(scale)
        return (Int(((p.x - reference.x) * f).rounded()), Int((-(p.y - reference.y) * f).rounded()))
    }

    public static func document(_ req: VectorExportRequest) -> String {
        let strokes = req.exportedStrokes
        let features = req.exportedFeatures
        let table = SketchSymbolTable(strokes: strokes, features: features)
        let colors = uniqueColors(table.symbols)
        let ref = req.frame.center
        let refLL = req.zone.unproject(ref)
        let scale = req.sheet.scaleDenominator
        let zone = req.zone
        let proj = "+proj=utm +zone=\(zone.number)\(zone.isNorth ? "" : " +south") +datum=WGS84 +units=m +no_defs"

        var x = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map xmlns="http://openorienteering.org/apps/mapper/xml/v2" version="9">
        <notes>Dibuat oleh Cakra Pencil. Simbol 990.x adalah sketsa; ganti ke simbol ISOM lewat Change symbol.</notes>
        <georeferencing scale="\(scale)" grid_scale_factor="1" auxiliary_scale_factor="1" declination="0" grivation="0">
        <ref_point x="0" y="0"/>
        <projected_crs id="UTM"><spec language="PROJ.4">\(proj)</spec><parameter>\(zone.number) \(zone.isNorth ? "N" : "S")</parameter><ref_point x="\(num(ref.x, 3))" y="\(num(ref.y, 3))"/></projected_crs>
        <geographic_crs id="Geographic coordinates"><spec language="PROJ.4">+proj=latlong +datum=WGS84</spec><ref_point_deg lat="\(num(refLL.lat, 8))" lon="\(num(refLL.lon, 8))"/></geographic_crs>
        </georeferencing>
        <colors count="\(colors.count)">

        """
        for (i, hex) in colors.enumerated() {
            let rgb = rgbComponents(hex: hex) ?? (0, 0, 0)
            let k = 1 - max(rgb.r, rgb.g, rgb.b)
            let d = k < 1 ? 1 - k : 1
            let c = (1 - rgb.r - k) / d, m = (1 - rgb.g - k) / d, yy = (1 - rgb.b - k) / d
            x += """
            <color priority="\(i)" name="\(escape(colorName(hex)))" c="\(num(c, 3))" m="\(num(m, 3))" y="\(num(yy, 3))" k="\(num(k, 3))" opacity="1"><spotcolors/><cmyk method="custom"/><rgb method="custom" r="\(num(rgb.r, 3))" g="\(num(rgb.g, 3))" b="\(num(rgb.b, 3))"/></color>

            """
        }
        x += "</colors>\n<barrier version=\"6\" required=\"0.6.0\">\n<symbols count=\"\(table.symbols.count)\">\n"
        for s in table.symbols {
            let color = colors.firstIndex(of: s.colorHex) ?? 0
            let um = Int((s.widthMM * 1000).rounded())
            if s.isArea {
                x += "<symbol type=\"4\" id=\"\(s.index)\" code=\"\(s.code)\" name=\"\(escape(s.name))\"><area_symbol inner_color=\"\(color)\" min_area=\"0\" patterns=\"0\"/></symbol>\n"
            } else if s.isPoint {
                x += "<symbol type=\"1\" id=\"\(s.index)\" code=\"\(s.code)\" name=\"\(escape(s.name))\"><point_symbol rotatable=\"false\" inner_radius=\"\(um / 2)\" inner_color=\"\(color)\" outer_width=\"0\" outer_color=\"-1\" elements=\"0\"/></symbol>\n"
            } else {
                x += "<symbol type=\"2\" id=\"\(s.index)\" code=\"\(s.code)\" name=\"\(escape(s.name))\"><line_symbol color=\"\(color)\" line_width=\"\(um)\" minimum_length=\"0\" join_style=\"2\" cap_style=\"1\" start_offset=\"0\" end_offset=\"0\" dashed=\"false\" segment_length=\"4000\" end_length=\"0\" show_at_least_one_symbol=\"true\" minimum_mid_symbol_count=\"0\" minimum_mid_symbol_count_when_closed=\"0\" dash_length=\"4000\" break_length=\"1000\" dashes_in_group=\"1\" in_group_break_length=\"500\" half_outer_dashes=\"false\" mid_symbols_per_spot=\"1\" mid_symbol_distance=\"0\"/></symbol>\n"
            }
        }
        x += "</symbols>\n<parts count=\"1\" current=\"0\"><part name=\"Sketsa\"><objects count=\"\(strokes.count + features.count)\">\n"
        for s in strokes {
            guard let sym = table.symbol(of: s) else { continue }
            let coords = s.points.map { p -> String in
                let c = mapCoordinate(p, reference: ref, scale: scale)
                return "\(c.x) \(c.y);"
            }
            if sym.isPoint {
                x += "<object type=\"0\" symbol=\"\(sym.index)\" rotation=\"0\"><coords count=\"1\">\(coords[0])</coords></object>\n"
            } else {
                x += "<object type=\"1\" symbol=\"\(sym.index)\"><coords count=\"\(coords.count)\">\(coords.joined())</coords></object>\n"
            }
        }
        for f in features {
            guard let sym = table.symbol(of: f) else { continue }
            let coords = featureCoords(f, reference: ref, scale: scale)
            x += "<object type=\"1\" symbol=\"\(sym.index)\"><coords count=\"\(coords.count)\">\(coords.joined())</coords></object>\n"
        }
        x += """
        </objects></part></parts>
        <templates count="0" first_front_template="0"><defaults use_meters_per_pixel="true" meters_per_pixel="0" dpi="0" scale="0"/></templates>
        </barrier>
        </map>

        """
        return x
    }

    /// Flag koordinat OOM: 1 = awal kurva (dua koordinat berikutnya adalah titik kontrol), 2 = titik penutup.
    static let curveStartFlag = 1
    static let closePointFlag = 2

    /// Koordinat objek bezier dalam format OOM: `x y flag;` per titik.
    /// Path tertutup diakhiri titik pertama lagi dengan flag penutup.
    public static func featureCoords(_ f: Feature, reference: Point2D, scale: Int) -> [String] {
        func c(_ p: Point2D, _ flag: Int = 0) -> String {
            let m = mapCoordinate(p, reference: reference, scale: scale)
            return flag == 0 ? "\(m.x) \(m.y);" : "\(m.x) \(m.y) \(flag);"
        }
        let segs = f.segments
        guard let first = segs.first else { return f.nodes.first.map { [c($0.point)] } ?? [] }
        var out: [String] = []
        for s in segs {
            if s.isCurve {
                out += [c(s.p0, curveStartFlag), c(s.c1), c(s.c2)]
            } else {
                out.append(c(s.p0))
            }
        }
        out.append(c(f.isClosed ? first.p0 : segs.last!.p3, f.isClosed ? closePointFlag : 0))
        return out
    }

    static func uniqueColors(_ symbols: [SketchSymbol]) -> [String] {
        var seen: [String] = []
        for s in symbols where !seen.contains(s.colorHex) { seen.append(s.colorHex) }
        return seen
    }

    static func colorName(_ hex: String) -> String {
        PenPreset.isom.first { $0.colorHex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? hex
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - DXF R12

/// DXF R12 (AC1009) ASCII: koordinat meter UTM apa adanya, satu layer per simbol sketsa.
/// R12 dipilih karena dibaca semua versi OCAD dan importer DXF di OOM/QGIS.
public enum DXFWriter {
    public static func document(_ req: VectorExportRequest) -> String {
        let strokes = req.exportedStrokes
        let features = req.exportedFeatures
        let table = SketchSymbolTable(strokes: strokes, features: features)
        let e = req.frame.extent
        var out: [String] = []
        func g(_ code: Int, _ value: String) {
            out.append(String(code))
            out.append(value)
        }

        g(0, "SECTION"); g(2, "HEADER")
        g(9, "$ACADVER"); g(1, "AC1009")
        g(9, "$EXTMIN"); g(10, num(e.minX, 4)); g(20, num(e.minY, 4)); g(30, "0.0")
        g(9, "$EXTMAX"); g(10, num(e.maxX, 4)); g(20, num(e.maxY, 4)); g(30, "0.0")
        g(0, "ENDSEC")

        g(0, "SECTION"); g(2, "TABLES")
        g(0, "TABLE"); g(2, "LAYER"); g(70, String(table.symbols.count + 1))
        for (name, color) in [("FRAME", 8)] + table.symbols.map({ ($0.dxfLayer, aci($0.colorHex)) }) {
            g(0, "LAYER"); g(2, name); g(70, "0"); g(62, String(color)); g(6, "CONTINUOUS")
        }
        g(0, "ENDTAB")
        g(0, "ENDSEC")

        g(0, "SECTION"); g(2, "ENTITIES")
        // Batas frame sebagai acuan di layer terpisah.
        polyline(layer: "FRAME", points: req.frame.corners, closed: true, g)
        for s in strokes {
            guard let sym = table.symbol(of: s) else { continue }
            if sym.isPoint, let p = s.points.first {
                g(0, "POINT"); g(8, sym.dxfLayer); g(10, num(p.x, 4)); g(20, num(p.y, 4)); g(30, "0.0")
            } else {
                polyline(layer: sym.dxfLayer, points: s.points, closed: false, g)
            }
        }
        // R12 tidak punya spline yang dibaca semua importer: kurva diratakan dengan toleransi 0,05 mm di kertas.
        let tolerance = req.sheet.groundMeters(forPaperMM: 0.05)
        for f in features {
            guard let sym = table.symbol(of: f) else { continue }
            var pts = f.flattened(tolerance: tolerance)
            if f.isClosed, pts.count > 1, pts.first == pts.last { pts.removeLast() }
            polyline(layer: sym.dxfLayer, points: pts, closed: f.isClosed, g)
        }
        g(0, "ENDSEC")
        g(0, "EOF")
        return out.joined(separator: "\r\n") + "\r\n"
    }

    private static func polyline(layer: String, points: [Point2D], closed: Bool, _ g: (Int, String) -> Void) {
        g(0, "POLYLINE"); g(8, layer); g(66, "1"); g(10, "0.0"); g(20, "0.0"); g(30, "0.0"); g(70, closed ? "1" : "0")
        for p in points {
            g(0, "VERTEX"); g(8, layer); g(10, num(p.x, 4)); g(20, num(p.y, 4)); g(30, "0.0")
        }
        g(0, "SEQEND"); g(8, layer)
    }

    /// Warna indeks AutoCAD terdekat untuk preset pena.
    static func aci(_ hex: String) -> Int {
        switch hex.uppercased() {
        case "#000000": return 7
        case "#D15C00": return 30
        case "#00A0E6": return 5
        case "#FFBA35": return 2
        case "#3EB54A": return 3
        case "#E30613": return 1
        default: return 7
        }
    }
}

func num(_ v: Double, _ decimals: Int) -> String {
    String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)
}
