import Foundation

/// Sketch symbol = one color + width combination. Until ISOM feature classes exist (FR-4), strokes get the neutral
/// code 990.x so the mapper assigns ISOM symbols in OOM/OCAD themselves ("Change symbol"):
/// color alone is not enough to guess the symbol (black could be a path, fence, or building).
public struct SketchSymbol: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case line, point, area }

    public var index: Int
    public var colorHex: String
    public var widthMM: Double
    public var kind: Kind
    /// ISOM symbol code + name if the object uses a symbol from the symbol set.
    public var isomCode: String?
    public var isomName: String?
    /// ISOM area patterns (marsh lines, scattered-tree holes…), written as OOM hatch / dot patterns.
    public var patterns: [AreaPattern]? = nil
    /// Line dash pattern (paper mm): [dash, gap] or 507's [dash, gap, dash, long gap] (OOM dash groups).
    public var dashMM: [Double]? = nil

    public var isPoint: Bool { kind == .point }
    public var isArea: Bool { kind == .area }
    public var code: String { isomCode ?? "990.\(index + 1)" }

    public var colorName: String {
        PenPreset.isom.first { $0.colorHex.caseInsensitiveCompare(colorHex) == .orderedSame }?.name ?? colorHex.uppercased()
    }

    /// E.g. "Sketch Brown 0.14 mm" (decimal point so it matches in OOM, OCAD, and DXF).
    public var name: String {
        if let isomName, !isomName.isEmpty { return isomName }
        if isArea { return "Area \(colorName)" }
        return "Sketch \(colorName)\(isPoint ? " point" : "") \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), widthMM)) mm"
    }

    /// DXF layer name: only A–Z, 0–9, _ (safe for R12), e.g. "990_1_SKETCH_BROWN_014".
    public var dxfLayer: String {
        let mm = Int((widthMM * 100).rounded())
        if let isomCode {
            let raw = "\(isomCode.replacingOccurrences(of: ".", with: "_"))_\(isomName ?? "")"
            return String(raw.uppercased().prefix(31).map { $0.isLetter || $0.isNumber ? $0 : "_" })
        }
        let raw = isArea
            ? "990_\(index + 1)_AREA_\(colorName)"
            : "990_\(index + 1)_SKETCH_\(colorName)_\(String(format: "%03d", mm))\(isPoint ? "_POINT" : "")"
        return String(raw.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}

/// Unique symbols from strokes and vector objects, in order of first appearance.
/// Bezier lines use the same line symbol as strokes when color + width match.
public struct SketchSymbolTable: Sendable {
    public private(set) var symbols: [SketchSymbol] = []
    private var lookup: [String: Int] = [:]

    public init(strokes: [Stroke], features: [Feature] = []) {
        for s in strokes { _ = add(Self.key(s)) }
        for f in features {
            let s = add(Self.key(f))
            if f.kind == .area, symbols[s.index].patterns == nil, let p = f.patterns, !p.isEmpty { symbols[s.index].patterns = p }
            if f.kind == .line, !f.isDoubleLine, symbols[s.index].dashMM == nil, let d = f.effectiveDashMM, d.count == 2 || d.count == 4 {
                symbols[s.index].dashMM = d
            }
        }
    }

    private struct Key: Hashable {
        var color: String
        var width: Int
        var kind: SketchSymbol.Kind
        var code: String? = nil
        var name: String? = nil

        /// ISOM-symbolized objects are grouped by code + kind; the rest by color + width.
        var string: String { code.map { "isom|\($0)|\(kind.rawValue)" } ?? "\(color)|\(width)|\(kind.rawValue)" }
    }

    private static func key(_ s: Stroke) -> Key {
        Key(color: s.colorHex.uppercased(), width: Int((s.widthMM * 100).rounded()), kind: s.points.count == 1 ? .point : .line)
    }

    private static func key(_ f: Feature) -> Key {
        if f.kind == .point {
            return Key(color: f.colorHex.uppercased(), width: Int((f.widthMM * 100).rounded()), kind: .point, code: f.symbolCode, name: f.symbolName)
        }
        return f.kind == .area
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
    /// Georeferenced basemap image, written next to the map as `<baseName>_basemap.jpg` + world file + .prj.
    public var background: ExportBackground?

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

    /// Strokes entirely outside the frame are excluded (FR-1.8). Strokes crossing the edge stay whole
    /// because vectors can be clipped in OCAD/OOM without losing data.
    public var exportedStrokes: [Stroke] {
        let e = frame.extent
        return strokes.filter { $0.bounds.map(e.intersects) ?? false }
    }

    /// Visible vector objects touching the frame, plus north lines (ISOM 601) when the grid is included in the export.
    public var exportedFeatures: [Feature] {
        let e = frame.extent
        let own = features.filter { f in
            f.isVisible && f.nodes.count >= (f.kind == .point ? 1 : 2) && (f.bounds.map(e.intersects) ?? false)
        }
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
        if let bg = req.background, !formats.isEmpty {
            urls += try bg.writeSidecar(baseName: req.baseName, zone: req.zone, to: directory)
        }
        return urls
    }
}

// MARK: - OpenOrienteering Mapper (.omap)

/// Our own OOM XML writer, written from the structure of sample files (without copying OOM's GPL v3 code).
///
/// OOM map coordinates = micrometers on paper, y axis down, relative to the map reference point (0, 0)
/// which is paired with the frame center in UTM. Grivation 0 because the frame is north-up relative to the grid.
public enum OmapWriter {
    public static func mapCoordinate(_ p: Point2D, reference: Point2D, scale: Int) -> (x: Int, y: Int) {
        let f = 1_000_000 / Double(scale)
        return (Int(((p.x - reference.x) * f).rounded()), Int((-(p.y - reference.y) * f).rounded()))
    }

    public static func document(_ req: VectorExportRequest) -> String {
        let strokes = req.exportedStrokes
        let features = req.exportedFeatures
        let table = SketchSymbolTable(strokes: strokes, features: features)
        // Color order = Color Hierarchy (priority 0 = topmost in OOM), so the color stacking matches OCAD.
        let colors = orderedColors(table.symbols, features: features)
        let ref = req.frame.center
        let refLL = req.zone.unproject(ref)
        let scale = req.sheet.scaleDenominator
        let zone = req.zone
        let proj = "+proj=utm +zone=\(zone.number)\(zone.isNorth ? "" : " +south") +datum=WGS84 +units=m +no_defs"

        var x = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map xmlns="http://openorienteering.org/apps/mapper/xml/v2" version="9">
        <notes>Created with \(AppInfo.name). Symbols 990.x are sketches; switch them to ISOM symbols via Change symbol.</notes>
        <georeferencing scale="\(scale)" grid_scale_factor="1" auxiliary_scale_factor="1" declination="0" grivation="0">
        <ref_point x="0" y="0"/>
        <projected_crs id="UTM"><spec language="PROJ.4">\(proj)</spec><parameter>\(zone.number) \(zone.isNorth ? "N" : "S")</parameter><ref_point x="\(num(ref.x, 3))" y="\(num(ref.y, 3))"/></projected_crs>
        <geographic_crs id="Geographic coordinates"><spec language="PROJ.4">+proj=latlong +datum=WGS84</spec><ref_point_deg lat="\(num(refLL.lat, 8))" lon="\(num(refLL.lon, 8))"/></geographic_crs>
        </georeferencing>
        <colors count="\(colors.count)">

        """
        for (i, hex) in colors.enumerated() {
            let rgb = rgbComponents(hex: hex) ?? (0, 0, 0)
            // OCCA's colours: the CMYK of the IOF colour table (Printing and Colour Definitions Rev 4) × screen; other
            // colours (sketches, other sets) converted from RGB.
            let spec = OccaStandardSymbols.cmyk(forHex: hex) ?? SymbolSet.cmyk(fromHex: hex)
            let c = spec[0], m = spec[1], yy = spec[2], k = spec[3]
            x += """
            <color priority="\(i)" name="\(escape(colorName(hex)))" c="\(num(c, 3))" m="\(num(m, 3))" y="\(num(yy, 3))" k="\(num(k, 3))" opacity="1"><spotcolors/><cmyk method="custom"/><rgb method="custom" r="\(num(rgb.r, 3))" g="\(num(rgb.g, 3))" b="\(num(rgb.b, 3))"/></color>

            """
        }
        x += "</colors>\n<barrier version=\"6\" required=\"0.6.0\">\n<symbols count=\"\(table.symbols.count)\">\n"
        for s in table.symbols {
            let color = colors.firstIndex(of: s.colorHex) ?? 0
            let um = Int((s.widthMM * 1000).rounded())
            if s.isArea {
                // Pattern-only areas (marsh, boulder field…): no fill, just the pattern.
                let patterns = s.patterns ?? []
                let inner = SymbolOrnaments.isPatternOnly(fillHex: s.colorHex, patterns: patterns) ? -1 : color
                x += "<symbol type=\"4\" id=\"\(s.index)\" code=\"\(s.code)\" name=\"\(escape(s.name))\"><area_symbol inner_color=\"\(inner)\" min_area=\"0\" patterns=\"\(patterns.count)\">\(Self.omapPatterns(patterns, colors: colors))</area_symbol></symbol>\n"
            } else if s.isPoint {
                x += "<symbol type=\"1\" id=\"\(s.index)\" code=\"\(s.code)\" name=\"\(escape(s.name))\"><point_symbol rotatable=\"true\" inner_radius=\"\(um / 2)\" inner_color=\"\(color)\" outer_width=\"0\" outer_color=\"-1\" elements=\"0\"/></symbol>\n"
            } else {
                // Dashes: OOM dash length / break, and dash groups for 507's pairs of dashes (dash, short gap, dash, gap).
                let d = (s.dashMM ?? []).map { Int(($0 * 1000).rounded()) }
                let dashed = d.count == 2 || d.count == 4
                let dash = dashed ? d[0] : 4000, brk = dashed ? d[d.count - 1] : 1000
                let group = d.count == 4 ? 2 : 1, inGroup = d.count == 4 ? d[1] : 500
                x += "<symbol type=\"2\" id=\"\(s.index)\" code=\"\(s.code)\" name=\"\(escape(s.name))\"><line_symbol color=\"\(color)\" line_width=\"\(um)\" minimum_length=\"0\" join_style=\"2\" cap_style=\"1\" start_offset=\"0\" end_offset=\"0\" dashed=\"\(dashed)\" segment_length=\"4000\" end_length=\"0\" show_at_least_one_symbol=\"true\" minimum_mid_symbol_count=\"0\" minimum_mid_symbol_count_when_closed=\"0\" dash_length=\"\(dash)\" break_length=\"\(brk)\" dashes_in_group=\"\(group)\" in_group_break_length=\"\(inGroup)\" half_outer_dashes=\"false\" mid_symbols_per_spot=\"1\" mid_symbol_distance=\"0\"/></symbol>\n"
            }
        }
        x += "</symbols>\n<parts count=\"1\" current=\"0\"><part name=\"Sketch\"><objects count=\"\(strokes.count + features.count)\">\n"
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
            if sym.isPoint {
                // OOM: radians, counterclockwise.
                let rotation = num(-f.rotationDegrees * .pi / 180, 6)
                x += "<object type=\"0\" symbol=\"\(sym.index)\" rotation=\"\(rotation)\"><coords count=\"1\">\(coords[0])</coords></object>\n"
                continue
            }
            x += "<object type=\"1\" symbol=\"\(sym.index)\"><coords count=\"\(coords.count)\">\(coords.joined())</coords></object>\n"
        }
        x += """
        </objects></part></parts>
        \(templates(req, proj: proj))
        </barrier>
        </map>

        """
        return x
    }

    /// OOM coordinate flags: 1 = curve start (the next two coordinates are control points), 2 = closing point,
    /// 16 = hole point (last point of a part: the next coordinate starts the next part, i.e. a hole of the area).
    static let curveStartFlag = 1
    static let closePointFlag = 2
    static let holePointFlag = 16

    /// Bezier object coordinates in OOM format: `x y flag;` per point.
    /// Closed paths end with the first point again, with the close flag. Area holes follow the outer ring as further
    /// parts; every part but the last ends with the hole flag (as OOM writes them).
    public static func featureCoords(_ f: Feature, reference: Point2D, scale: Int) -> [String] {
        func c(_ p: Point2D, _ flag: Int = 0) -> String {
            let m = mapCoordinate(p, reference: reference, scale: scale)
            return flag == 0 ? "\(m.x) \(m.y);" : "\(m.x) \(m.y) \(flag);"
        }
        let parts = f.ringFeatures.filter { !$0.segments.isEmpty }
        guard !parts.isEmpty else { return f.nodes.first.map { [c($0.point)] } ?? [] }
        var out: [String] = []
        for (k, part) in parts.enumerated() {
            let segs = part.segments
            for s in segs {
                if s.isCurve {
                    out += [c(s.p0, curveStartFlag), c(s.c1), c(s.c2)]
                } else {
                    out.append(c(s.p0))
                }
            }
            let hole = k < parts.count - 1 ? holePointFlag : 0
            out.append(c(f.isClosed ? segs[0].p0 : segs.last!.p3, (f.isClosed ? closePointFlag : 0) | hole))
        }
        return out
    }

    /// Unique colors sorted by the Color Hierarchy of the objects using them (topmost first); unsymbolized pencil
    /// sketch colors at the very top. Equal priority = order of appearance.
    static func orderedColors(_ symbols: [SketchSymbol], features: [Feature]) -> [String] {
        var priority: [String: Int] = [:]
        for f in features {
            let key = f.colorHex.uppercased(), p = ColorHierarchy.priority(of: f)
            priority[key] = min(priority[key] ?? .max, p)
        }
        return uniqueColors(symbols).enumerated()
            .sorted { a, b in
                let pa = priority[a.element.uppercased()] ?? -1, pb = priority[b.element.uppercased()] ?? -1
                return pa != pb ? pa < pb : a.offset < b.offset
            }
            .map(\.element)
    }

    static func uniqueColors(_ symbols: [SketchSymbol]) -> [String] {
        var seen: [String] = []
        for s in symbols {
            for c in [s.colorHex] + (s.patterns ?? []).map({ $0.colorHex.uppercased() }) where !seen.contains(c) { seen.append(c) }
        }
        return seen
    }

    /// OOM `<pattern>` elements (µm; angle in radians, 0 = east–west lines) for OCCA patterns (mm; 0° = north–south).
    static func omapPatterns(_ patterns: [AreaPattern], colors: [String]) -> String {
        patterns.map { p -> String in
            let c = colors.firstIndex(of: p.colorHex.uppercased()) ?? 0
            let rad = num((90 - p.angleDeg) * .pi / 180, 6), sp = Int((p.spacingMM * 1000).rounded()), size = Int((p.sizeMM * 1000).rounded())
            switch p.kind {
            case .lines:
                return "<pattern type=\"1\" angle=\"\(rad)\" line_spacing=\"\(sp)\" line_offset=\"0\" offset_along_line=\"0\" color=\"\(c)\" line_width=\"\(size)\"/>"
            case .dots, .holes:
                return "<pattern type=\"2\" angle=\"\(rad)\" line_spacing=\"\(sp)\" line_offset=\"0\" offset_along_line=\"0\" point_distance=\"\(sp)\">"
                    + "<symbol type=\"1\" code=\"\"><point_symbol rotatable=\"true\" inner_radius=\"\(size / 2)\" inner_color=\"\(c)\" outer_width=\"0\" outer_color=\"-1\" elements=\"0\"/></symbol></pattern>"
            case .triangles:
                // Triangle pointing north (OOM y grows downward).
                let h = Double(size) * 3.0.squareRoot() / 2
                let pts = [(0.0, -2 * h / 3), (-Double(size) / 2, h / 3), (Double(size) / 2, h / 3)]
                let coords = pts.map { "\(Int($0.0.rounded())) \(Int($0.1.rounded()));" }.joined()
                return "<pattern type=\"2\" angle=\"0\" line_spacing=\"\(sp)\" line_offset=\"0\" offset_along_line=\"0\" point_distance=\"\(sp)\">"
                    + "<symbol type=\"1\" code=\"\"><point_symbol rotatable=\"true\" inner_radius=\"0\" inner_color=\"-1\" outer_width=\"0\" outer_color=\"-1\" elements=\"1\">"
                    + "<element><symbol type=\"4\" code=\"\"><area_symbol inner_color=\"\(c)\" min_area=\"0\" patterns=\"0\"/></symbol>"
                    + "<object type=\"1\"><coords count=\"3\">\(coords)</coords></object></element></point_symbol></symbol></pattern>"
            }
        }.joined()
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

/// DXF R12 (AC1009) ASCII: UTM meter coordinates as-is, one layer per sketch symbol.
/// R12 was chosen because every OCAD version and the DXF importers in OOM/QGIS read it.
extension OmapWriter {
    /// Template list: the basemap image (when exported) as a georeferenced image template behind the map.
    static func templates(_ req: VectorExportRequest, proj: String) -> String {
        let defaults = "<defaults use_meters_per_pixel=\"true\" meters_per_pixel=\"0\" dpi=\"0\" scale=\"0\"/>"
        guard let bg = req.background else { return "<templates count=\"0\" first_front_template=\"0\">\(defaults)</templates>" }
        let file = escape("\(req.baseName)_basemap.\(bg.fileExtension)")
        return "<templates count=\"1\" first_front_template=\"1\"><template type=\"TemplateImage\" open=\"true\" name=\"\(file)\" "
            + "path=\"\(file)\" relpath=\"\(file)\" georef=\"true\" group=\"-1\"><crs_spec language=\"PROJ.4\">\(escape(proj))</crs_spec>"
            + "</template>\(defaults)</templates>"
    }
}

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
        // Frame boundary as a reference on a separate layer.
        polyline(layer: "FRAME", points: req.frame.corners, closed: true, g)
        for s in strokes {
            guard let sym = table.symbol(of: s) else { continue }
            if sym.isPoint, let p = s.points.first {
                g(0, "POINT"); g(8, sym.dxfLayer); g(10, num(p.x, 4)); g(20, num(p.y, 4)); g(30, "0.0")
            } else {
                polyline(layer: sym.dxfLayer, points: s.points, closed: false, g)
            }
        }
        // R12 has no spline that all importers read: curves are flattened with a 0.05 mm tolerance on paper.
        let tolerance = req.sheet.groundMeters(forPaperMM: 0.05)
        for f in features {
            guard let sym = table.symbol(of: f) else { continue }
            if f.kind == .point, let p = f.nodes.first?.point {
                g(0, "POINT"); g(8, sym.dxfLayer); g(10, num(p.x, 4)); g(20, num(p.y, 4)); g(30, "0.0")
                continue
            }
            // Area holes: R12 has no hatch with islands that every importer reads, so the outer ring and each hole are
            // separate closed polylines on the same layer.
            for ring in f.ringFeatures {
                var pts = ring.flattened(tolerance: tolerance)
                if f.isClosed, pts.count > 1, pts.first == pts.last { pts.removeLast() }
                polyline(layer: sym.dxfLayer, points: pts, closed: f.isClosed, g)
            }
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

    /// Nearest AutoCAD color index for the pen presets.
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
