import Foundation

public enum OmapReadError: LocalizedError {
    case notXML(String)
    case notGeoreferenced

    public var errorDescription: String? {
        switch self {
        case let .notXML(m): return "Cannot read OOM file: \(m)"
        case .notGeoreferenced: return "The OOM map is not georeferenced (Map → Georeferencing in OOM), so its position is unknown."
        }
    }
}

/// Reader for OpenOrienteering Mapper maps (.omap / .xmap, XML): lines and areas (with bezier curves) along with
/// their symbol code, name, color, width, and dashes. Position comes from the OOM georeferencing: lat/lon reference
/// point, scale, and grivation. Points and text are skipped (reported), area holes are ignored.
public enum OmapReader {
    /// OOM coordinate flags.
    static let curveStart = 1, holePoint = 16

    public static func read(_ data: Data, zone: UTMZone) throws -> (features: [Feature], report: OcadImportReport) {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw OmapReadError.notXML(parser.parserError?.localizedDescription ?? "malformed XML")
        }
        return try delegate.features(zone: zone)
    }

    /// Map scale and reference point (lat/lon) from the georeferencing; nil when the map is not georeferenced.
    /// Used to pick the UTM zone before reading the objects.
    public static func georeference(_ data: Data) throws -> (scale: Int, reference: LatLon)? {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw OmapReadError.notXML(parser.parserError?.localizedDescription ?? "malformed XML")
        }
        guard let ll = delegate.refLatLon, delegate.scale > 0 else { return nil }
        return (delegate.scale, ll)
    }

    struct Symbol {
        var type = 0
        var code = ""
        var name = ""
        var color: Int?
        var lineWidthUM: Int?
        var dash: [Double]?
        var parts: [Int] = []
        var hasArea = false
    }

    struct Object {
        var type = 0
        var symbol = -1
        var coords: [(x: Double, y: Double, flags: Int)] = []
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var scale = 0
        var grivationDeg = 0.0
        var gridScaleFactor = 1.0
        var mapRef = (x: 0.0, y: 0.0)
        var refLatLon: LatLon?
        var inProjected = false
        var colors: [String] = []
        var symbols: [Int: Symbol] = [:]
        /// Nested symbols (parts of a private combined symbol): the outermost symbol uses the first style.
        var symbolStack: [(id: Int?, symbol: Symbol)] = []
        var objects: [Object] = []
        var current: Object?
        var text = ""
        var inCoords = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String] = [:]) {
            switch name {
            case "georeferencing":
                scale = Int(a["scale"] ?? "") ?? 0
                grivationDeg = Double(a["grivation"] ?? "") ?? 0
                gridScaleFactor = Double(a["grid_scale_factor"] ?? a["combined_scale_factor"] ?? "") ?? 1
            case "projected_crs": inProjected = true
            case "ref_point":
                // Map reference point (µm) only outside projected_crs.
                if !inProjected, current == nil { mapRef = (Double(a["x"] ?? "") ?? 0, Double(a["y"] ?? "") ?? 0) }
            case "ref_point_deg":
                if let lat = Double(a["lat"] ?? ""), let lon = Double(a["lon"] ?? "") { refLatLon = LatLon(lat: lat, lon: lon) }
            case "color":
                colors.append("#000000")
                if let c = Double(a["c"] ?? ""), let m = Double(a["m"] ?? ""), let y = Double(a["y"] ?? ""), let k = Double(a["k"] ?? "") {
                    colors[colors.count - 1] = hex((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k))
                }
            case "rgb":
                if let r = Double(a["r"] ?? ""), let g = Double(a["g"] ?? ""), let b = Double(a["b"] ?? ""), !colors.isEmpty {
                    colors[colors.count - 1] = hex(r, g, b)
                }
            case "symbol":
                var s = Symbol()
                s.type = Int(a["type"] ?? "") ?? 0
                s.code = a["code"] ?? ""
                s.name = a["name"] ?? ""
                symbolStack.append((Int(a["id"] ?? ""), s))
            case "line_symbol":
                styleOuter { s in
                    if s.color == nil, let c = Int(a["color"] ?? ""), c >= 0 {
                        s.color = c
                        s.lineWidthUM = Int(a["line_width"] ?? "")
                        if a["dashed"] == "true", let d = Double(a["dash_length"] ?? ""), let b = Double(a["break_length"] ?? "") {
                            s.dash = [d / 1000, b / 1000]
                        }
                    }
                }
            case "area_symbol":
                styleOuter { s in
                    s.hasArea = true
                    if s.color == nil, let c = Int(a["inner_color"] ?? ""), c >= 0 { s.color = c }
                }
            case "part":
                if let ref = Int(a["symbol"] ?? ""), !symbolStack.isEmpty { symbolStack[0].symbol.parts.append(ref) }
            case "object":
                var o = Object()
                o.type = Int(a["type"] ?? "") ?? 0
                o.symbol = Int(a["symbol"] ?? "") ?? -1
                current = o
            case "coords":
                inCoords = current != nil
                text = ""
            case "coord":
                if current != nil, let x = Double(a["x"] ?? ""), let y = Double(a["y"] ?? "") {
                    current!.coords.append((x, y, Int(a["flags"] ?? "") ?? 0))
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inCoords { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "projected_crs": inProjected = false
            case "symbol":
                guard let top = symbolStack.popLast() else { break }
                // Nested (private) symbols are not registered on their own.
                if symbolStack.isEmpty, let id = top.id { symbols[id] = top.symbol }
            case "coords":
                if inCoords {
                    // Text format: "x y [flags];" per point.
                    for item in text.split(separator: ";") {
                        let v = item.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).compactMap { Double($0) }
                        if v.count >= 2 { current?.coords.append((v[0], v[1], v.count > 2 ? Int(v[2]) : 0)) }
                    }
                }
                inCoords = false
            case "object":
                if let o = current { objects.append(o) }
                current = nil
            default: break
            }
        }

        private func styleOuter(_ change: (inout Symbol) -> Void) {
            guard !symbolStack.isEmpty else { return }
            change(&symbolStack[0].symbol)
        }

        private func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
            func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
        }

        /// Symbol style, taken from the combined symbol parts if the symbol itself has no color.
        private func resolved(_ id: Int, depth: Int = 0) -> Symbol? {
            guard var s = symbols[id] else { return nil }
            if s.color == nil, depth < 4 {
                for ref in s.parts {
                    guard let p = resolved(ref, depth: depth + 1), p.color != nil else { continue }
                    s.color = p.color
                    s.lineWidthUM = s.lineWidthUM ?? p.lineWidthUM
                    s.dash = s.dash ?? p.dash
                    s.hasArea = s.hasArea || p.hasArea
                    break
                }
            }
            return s
        }

        func features(zone: UTMZone) throws -> (features: [Feature], report: OcadImportReport) {
            guard let ll = refLatLon, scale > 0 else { throw OmapReadError.notGeoreferenced }
            let ref = zone.project(ll)
            let k = Double(scale) / 1_000_000 / max(gridScaleFactor, 0.5)
            let g = grivationDeg * .pi / 180
            let (cg, sg) = (cos(g), sin(g))
            // Map µm (y down) → grid meters; map top = magnetic north, grivation clockwise from grid north.
            func world(_ x: Double, _ y: Double) -> Point2D {
                let dx = (x - mapRef.x) * k, dy = -(y - mapRef.y) * k
                return Point2D(x: ref.x + dx * cg + dy * sg, y: ref.y - dx * sg + dy * cg)
            }

            var report = OcadImportReport()
            var out: [Feature] = []
            for o in objects {
                switch o.type {
                case 1: break
                case 0: report.skippedPoints += 1; continue
                default: report.skippedText += 1; continue
                }
                let sym = resolved(o.symbol)
                let isArea = sym?.type == 4 || (sym?.type == 16 && sym?.hasArea == true)
                var pts = o.coords
                if let hole = pts.indices.dropFirst().first(where: { pts[$0 - 1].flags & OmapReader.holePoint != 0 }) {
                    pts = Array(pts[..<hole])
                    report.droppedHoles += 1
                }
                guard let first = pts.first else { continue }
                // OOM: a point flagged curveStart is followed by 2 handles, then the curve's end point.
                var nodes = [BezierNode(point: world(first.x, first.y))]
                var i = 0
                while i < pts.count - 1 {
                    if pts[i].flags & OmapReader.curveStart != 0, i + 3 < pts.count {
                        nodes[nodes.count - 1].outHandle = world(pts[i + 1].x, pts[i + 1].y)
                        nodes.append(BezierNode(point: world(pts[i + 3].x, pts[i + 3].y), inHandle: world(pts[i + 2].x, pts[i + 2].y)))
                        i += 3
                    } else {
                        nodes.append(BezierNode(point: world(pts[i + 1].x, pts[i + 1].y)))
                        i += 1
                    }
                }
                // Closed paths repeat the start point; Feature closes itself.
                if nodes.count > 1, nodes.first!.point.distance(to: nodes.last!.point) < 1e-6 {
                    let last = nodes.removeLast()
                    nodes[0].inHandle = last.inHandle
                }
                guard nodes.count >= (isArea ? 3 : 2) else { continue }
                let code = sym?.code ?? ""
                var f = Feature(name: [code, sym?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " "),
                                kind: isArea ? .area : .line,
                                colorHex: sym?.color.flatMap { colors.indices.contains($0) ? colors[$0] : nil } ?? "#000000",
                                widthMM: sym?.lineWidthUM.map { Double($0) / 1000 } ?? (isArea ? 0.1 : 0.14),
                                nodes: nodes,
                                symbolCode: code.isEmpty ? nil : code,
                                symbolName: sym?.name)
                f.standardWidthMM = f.widthMM
                if !isArea { f.dashMM = sym?.dash }
                out.append(f)
                report.imported += 1
            }
            return (out, report)
        }
    }
}
