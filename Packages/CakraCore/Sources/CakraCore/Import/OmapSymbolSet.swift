import Foundation

/// Reads the symbol set of an OpenOrienteering Mapper file (.omap / .xmap, XML format v2) into a `SymbolSet`:
/// point symbols with their elements (dots, rings, lines, areas), line symbols (width, dashes, caps, double lines from
/// borders), area symbols (fill color), combined symbols (area + outline, railway-like layered lines), and the color
/// order (OOM color priority 0 = topmost, like OCAD's color table). Sizes are paper mm at the file's scale.
///
/// Area hatch and dot patterns are read as `AreaPattern`s (lines, dots, white holes, triangles); pattern-only areas get a
/// white "fill" that is not painted. Not read: mid/start/end symbols along lines, text symbols (listed, not drawable).
public enum OmapSymbolSet {
    public enum ReadError: LocalizedError {
        case notAnOmapFile
        case noSymbols

        public var errorDescription: String? {
            switch self {
            case .notAnOmapFile: return "This is not an OpenOrienteering Mapper file (.omap / .xmap in XML format)."
            case .noSymbols: return "The file has no symbols."
            }
        }
    }

    /// - Parameters:
    ///   - codeFilter: keep only symbols whose main code passes (e.g. 700...799 for course design sets).
    public static func read(_ data: Data, name: String, sourceFile: String,
                            codeFilter: ((Int) -> Bool)? = nil) throws -> SymbolSet {
        let tree = XMLTree()
        let parser = XMLParser(data: data)
        parser.delegate = tree
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = tree.root, root.name == "map" else { throw ReadError.notAnOmapFile }

        let scale = Int(Double(root.first("georeferencing")?.attributes["scale"] ?? "") ?? 0)
        // Colors: index → hex and priority (0 = topmost).
        var colors: [Int: (hex: String, priority: Int)] = [:]
        for (i, c) in (root.first("colors")?.children(named: "color") ?? []).enumerated() {
            let priority = Int(c.attributes["priority"] ?? "") ?? i
            let rgb = c.first("rgb")
            func v(_ k: String) -> Double { Double(rgb?.attributes[k] ?? "") ?? 0 }
            colors[priority] = (Self.hex(v("r"), v("g"), v("b")), priority)
        }
        guard let symbolsNode = root.descendant("symbols") else { throw ReadError.noSymbols }
        let topLevel = symbolsNode.children(named: "symbol")
        var byID: [String: XMLTree.Node] = [:]
        for s in topLevel { if let id = s.attributes["id"] { byID[id] = s } }

        let context = Context(colors: colors, byID: byID)
        var used = Set<Int>()
        var symbols: [MapSymbol] = []
        for node in topLevel {
            guard let code = node.attributes["code"], let number = Self.number(code), !used.contains(number) else { continue }
            if let codeFilter, !codeFilter(number / 1000) { continue }
            guard var symbol = context.symbol(node, number: number) else { continue }
            // Hidden in OOM: off by default (can be enabled in Manage). Pattern-only areas are drawn as their patterns.
            symbol.isEnabled = node.attributes["is_hidden"] != "true"
            used.insert(number)
            symbols.append(symbol)
        }
        guard !symbols.isEmpty else { throw ReadError.noSymbols }
        return SymbolSet(name: name, sourceFile: sourceFile, scale: scale, symbols: symbols.sorted { $0.number < $1.number })
    }

    /// "101" → 101000, "501.1" → 501001, "512.10" → 512010; nil for codes that aren't numbers.
    static func number(_ code: String) -> Int? {
        let parts = code.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard let main = Int(parts.first ?? ""), main >= 0, main < 1_000_000 else { return nil }
        let sub = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        guard sub < 1000 else { return nil }
        return main * 1000 + sub
    }

    static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }

    // MARK: - Symbol conversion

    private struct Context {
        let colors: [Int: (hex: String, priority: Int)]
        let byID: [String: XMLTree.Node]

        func hex(_ index: Int) -> String? { colors[index]?.hex }
        func priority(_ index: Int) -> Int? { colors[index]?.priority }
        /// Priority of the (first) color with this RGB.
        func colorPriority(_ hex: String) -> Int? { colors.values.filter { $0.hex == hex }.map(\.priority).min() }

        /// Nesting limit for combined parts / point elements: a (malicious) file whose combined symbol contains itself
        /// would otherwise recurse forever.
        static let maxDepth = 8

        func symbol(_ node: XMLTree.Node, number: Int, depth: Int = 0) -> MapSymbol? {
            guard depth <= Self.maxDepth else { return nil }
            let name = (node.attributes["name"] ?? "").trimmingCharacters(in: .whitespaces)
            switch node.attributes["type"] {
            case "1":
                guard let p = node.first("point_symbol") else { return nil }
                let elements = pointElements(p)
                guard !elements.isEmpty else { return nil }
                var m = MapSymbol(number: number, name: name, kind: .point, colorHex: elements.drawingOrder.last?.colorHex ?? "#000000",
                                  lineWidthMM: nil, isEnabled: true, pointElements: elements)
                m.colorPriority = elements.map(\.priority).min()
                return m
            case "2":
                guard let l = node.first("line_symbol"), let line = line(l) else { return nil }
                return line.symbol(number: number, name: name)
            case "4":
                guard let a = node.first("area_symbol") else { return nil }
                return areaSymbol([a], number: number, name: name)
            case "8":
                let color = Int(node.first("text_symbol")?.first("text")?.attributes["color"] ?? "") ?? -1
                var m = MapSymbol(number: number, name: name, kind: .text, colorHex: hex(color) ?? "#000000", lineWidthMM: nil, isEnabled: true)
                m.colorPriority = priority(color)
                return m
            case "16":
                return combined(node, number: number, name: name, depth: depth)
            default:
                return nil
            }
        }

        /// Area symbol (or combined symbol with an area) without a fill color, drawn only by its patterns.
        func isPatternOnlyArea(_ node: XMLTree.Node) -> Bool {
            let areas: [XMLTree.Node]
            switch node.attributes["type"] {
            case "4": areas = [node]
            case "16": areas = parts(node).filter { $0.attributes["type"] == "4" }
            default: return false
            }
            guard let a = areas.first?.first("area_symbol") else { return false }
            return (Int(a.attributes["inner_color"] ?? "") ?? -1) < 0
        }

        /// Parts of a combined symbol: shared (`symbol="id"`) or private (inline).
        private func parts(_ node: XMLTree.Node) -> [XMLTree.Node] {
            (node.first("combined_symbol")?.children(named: "part") ?? []).compactMap { part in
                if let ref = part.attributes["symbol"] { return byID[ref] }
                return part.first("symbol")
            }
        }

        private func combined(_ node: XMLTree.Node, number: Int, name: String, depth: Int) -> MapSymbol? {
            let parts = parts(node)
            // Area + outline (e.g. building), or areas stacked (cultivated land = yellow + black dots): one area symbol with
            // the first fill and every part's pattern.
            let areaParts = parts.filter { $0.attributes["type"] == "4" }.compactMap { $0.first("area_symbol") }
            if !areaParts.isEmpty, let m = areaSymbol(areaParts, number: number, name: name) { return m }
            let lines = parts.filter { $0.attributes["type"] == "2" }.compactMap { $0.first("line_symbol").flatMap(line) }
            guard !lines.isEmpty else {
                // Combined points / nested combined: first part that converts.
                return parts.lazy.compactMap { symbol($0, number: number, depth: depth + 1) }.first.map { var s = $0; s.name = name; return s }
            }
            // Layered line (railway): a double line plus a dashed line in the edge color on top → the fill shows as
            // dashes between the edge-colored dashes.
            if let double = lines.first(where: { $0.casing != nil }),
               let dashed = lines.first(where: { $0.casing == nil && $0.dash != nil && $0.colorIndex == double.casing?.colorIndex }) {
                var l = double
                l.innerDash = dashed.dash.map { [$0[1], $0[0]] }
                return l.symbol(number: number, name: name)
            }
            let widest = lines.max { $0.totalWidth < $1.totalWidth }!
            return widest.symbol(number: number, name: name)
        }

        // Line symbols

        struct Line {
            var colorIndex: Int
            var colorHex: String
            var priority: Int?
            var width: Double
            var dash: [Double]?
            var roundCaps: Bool
            var casing: (colorIndex: Int, hex: String, priority: Int?, total: Double, inner: Double, dash: [Double]?)?
            var innerDash: [Double]?

            var totalWidth: Double { casing?.total ?? width }

            func symbol(number: Int, name: String) -> MapSymbol {
                let style: LineStyle
                if let c = casing {
                    style = LineStyle(colorHex: colorHex, widthMM: c.total, casing: LineStyle.Casing(colorHex: c.hex, innerWidthMM: c.inner),
                                      dashMM: c.dash, innerDashMM: innerDash ?? dash, roundCaps: roundCaps)
                } else {
                    style = LineStyle(colorHex: colorHex, widthMM: width, casing: nil, dashMM: dash, roundCaps: roundCaps)
                }
                var m = MapSymbol(number: number, name: name, kind: .line, colorHex: casing == nil ? colorHex : (colorIndex >= 0 ? colorHex : casing!.hex),
                                  lineWidthMM: casing == nil ? width : nil, isEnabled: true, lineStyle: style)
                m.colorPriority = priority ?? casing?.priority
                m.casingPriority = casing?.priority
                return m
            }
        }

        func line(_ l: XMLTree.Node) -> Line? {
            func mm(_ k: String, in n: XMLTree.Node = l) -> Double { (Double(n.attributes[k] ?? "") ?? 0) / 1000 }
            func round(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
            let color = Int(l.attributes["color"] ?? "") ?? -1
            var width = mm("line_width")
            let dashed = l.attributes["dashed"] == "true"
            let dash = dashed && mm("dash_length") > 0 ? [mm("dash_length"), mm("break_length")] : nil
            var hex = hex(color)
            var prio = priority(color)
            var result: (colorIndex: Int, hex: String, priority: Int?, total: Double, inner: Double, dash: [Double]?)?
            if let b = l.first("borders")?.children(named: "border").first, let bc = Int(b.attributes["color"] ?? ""), bc >= 0,
               let bhex = self.hex(bc) {
                let bw = mm("width", in: b), shift = mm("shift", in: b)
                let total = round((width / 2 + shift + bw / 2) * 2)
                let inner = round(max((width / 2 + shift - bw / 2) * 2, 0.01))
                let bdash = b.attributes["dashed"] == "true" && mm("dash_length", in: b) > 0
                    ? [mm("dash_length", in: b), mm("break_length", in: b)] : nil
                result = (bc, bhex, priority(bc), total, inner, bdash)
            }
            // A line drawn only by its mid symbols (e.g. dotted lines): use the mid symbol's color and size.
            if hex == nil, result == nil, let mid = l.first("mid_symbol")?.first("symbol")?.first("point_symbol") {
                let els = pointElements(mid)
                guard let top = els.drawingOrder.last else { return nil }
                hex = top.colorHex
                prio = top.priority
                width = max(els.diameterMM, 0.1)
            }
            guard let fill = hex ?? (result != nil ? "#FFFFFF" : nil), width > 0 || result != nil else { return nil }
            return Line(colorIndex: color, colorHex: fill, priority: prio, width: round(max(width, 0.01)),
                        dash: dash.map { $0.map(round) }, roundCaps: l.attributes["cap_style"] == "1", casing: result, innerDash: nil)
        }

        /// Area symbol from one or more area parts: the first inner color as fill (none: white, not painted — a
        /// pattern-only area), plus all hatch / dot patterns.
        func areaSymbol(_ areas: [XMLTree.Node], number: Int, name: String) -> MapSymbol? {
            let patterns = areas.flatMap(areaPatterns)
            let filled = areas.lazy.compactMap { a -> (hex: String, priority: Int?)? in
                guard let c = Int(a.attributes["inner_color"] ?? ""), c >= 0, let h = hex(c) else { return nil }
                return (h, priority(c))
            }.first
            let fill: (hex: String, priority: Int?)
            if let filled { fill = filled } else if let p = patterns.first {
                // Pattern only: white "fill" (not painted); the pattern color sets the drawing order.
                fill = ("#FFFFFF", colorPriority(p.colorHex))
            } else if let c = areas.lazy.compactMap(areaColor).first { fill = c } else { return nil }
            var m = MapSymbol(number: number, name: name, kind: .area, colorHex: fill.hex, lineWidthMM: nil, isEnabled: true)
            m.colorPriority = fill.priority
            m.patterns = patterns.isEmpty ? nil : patterns
            return m
        }

        /// OOM patterns (sizes in µm; angle in radians, 0 = east–west lines) → OCCA patterns (mm; 0° = north–south).
        func areaPatterns(_ a: XMLTree.Node) -> [AreaPattern] {
            a.children(named: "pattern").compactMap { p -> AreaPattern? in
                func mm(_ k: String) -> Double { (Double(p.attributes[k] ?? "") ?? 0) / 1000 }
                // Rounded to 0.01° (OOM stores π/2 as 1.5708 = 90.0001°).
                let oomDeg = ((Double(p.attributes["angle"] ?? "") ?? 0) * 180 / .pi * 100).rounded() / 100
                let angle = ((90 - oomDeg).truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
                let spacing = mm("line_spacing")
                guard spacing > 0 else { return nil }
                if p.attributes["type"] == "1" {
                    guard let c = Int(p.attributes["color"] ?? ""), c >= 0, let h = hex(c), mm("line_width") > 0 else { return nil }
                    return AreaPattern(kind: .lines, colorHex: h, sizeMM: mm("line_width"), spacingMM: spacing, angleDeg: angle)
                }
                // Point pattern: one dot per cell (scattered trees), several scattered dots (broken ground), or triangles.
                guard let ps = p.first("symbol")?.first("point_symbol") else { return nil }
                let els = pointElements(ps)
                let cell = max(mm("point_distance"), 0.01) * spacing
                let dots = els.filter { $0.kind == .dot }
                if let d = dots.first {
                    let white = d.colorHex.uppercased() == "#FFFFFF"
                    return AreaPattern(kind: white ? .holes : .dots, colorHex: d.colorHex, sizeMM: d.diameterMM,
                                       spacingMM: (cell / Double(dots.count)).squareRoot(), angleDeg: angle)
                }
                let polys = els.filter { $0.kind == .area && $0.points.count >= 3 }
                if let t = polys.first {
                    let xs = t.points.map(\.x)
                    return AreaPattern(kind: .triangles, colorHex: t.colorHex, sizeMM: (xs.max()! - xs.min()!),
                                       spacingMM: (cell / Double(polys.count)).squareRoot(), angleDeg: angle)
                }
                return nil
            }
        }

        // Area symbols: inner color, else the first pattern's color (hatch line or pattern dot).
        func areaColor(_ a: XMLTree.Node) -> (hex: String, priority: Int?)? {
            if let c = Int(a.attributes["inner_color"] ?? ""), c >= 0, let h = hex(c) { return (h, priority(c)) }
            for p in a.children(named: "pattern") {
                if let c = Int(p.attributes["color"] ?? ""), c >= 0, let h = hex(c) { return (h, priority(c)) }
                if let ps = p.first("symbol")?.first("point_symbol"), let top = pointElements(ps).drawingOrder.last {
                    return (top.colorHex, top.priority)
                }
            }
            return nil
        }

        // Point symbols

        /// Elements of a point symbol at `offset` (paper mm, y up): its own dot / ring, then its elements.
        func pointElements(_ p: XMLTree.Node, offset: Point2D = Point2D(x: 0, y: 0), depth: Int = 0) -> [PointElement] {
            guard depth <= Self.maxDepth else { return [] }
            var out: [PointElement] = []
            func mm(_ k: String) -> Double { (Double(p.attributes[k] ?? "") ?? 0) / 1000 }
            let r = mm("inner_radius"), ow = mm("outer_width")
            if let ic = Int(p.attributes["inner_color"] ?? ""), ic >= 0, r > 0, let h = hex(ic) {
                out.append(PointElement(kind: .dot, colorHex: h, priority: priority(ic) ?? 0, lineWidthMM: 0, diameterMM: 2 * r, points: [offset]))
            }
            if let oc = Int(p.attributes["outer_color"] ?? ""), oc >= 0, ow > 0, let h = hex(oc) {
                out.append(PointElement(kind: .circle, colorHex: h, priority: priority(oc) ?? 0, lineWidthMM: ow,
                                        diameterMM: 2 * (r + ow / 2), points: [offset]))
            }
            for e in p.children(named: "element") {
                guard let s = e.first("symbol"), let obj = e.first("object") else { continue }
                let pts = Self.coords(obj.first("coords")?.text ?? "").map { Point2D(x: $0.x + offset.x, y: $0.y + offset.y) }
                switch s.attributes["type"] {
                case "1":
                    if let ps = s.first("point_symbol") { out += pointElements(ps, offset: pts.first ?? offset, depth: depth + 1) }
                case "2":
                    guard let l = s.first("line_symbol"), let c = Int(l.attributes["color"] ?? ""), c >= 0, let h = hex(c), pts.count > 1 else { continue }
                    let w = (Double(l.attributes["line_width"] ?? "") ?? 0) / 1000
                    out.append(PointElement(kind: .line, colorHex: h, priority: priority(c) ?? 0, lineWidthMM: w, diameterMM: 0, points: pts))
                case "4":
                    guard let a = s.first("area_symbol"), let fill = areaColor(a), pts.count > 2 else { continue }
                    out.append(PointElement(kind: .area, colorHex: fill.hex, priority: fill.priority ?? 0, lineWidthMM: 0, diameterMM: 0, points: pts))
                default:
                    continue
                }
            }
            return out
        }

        /// OOM coordinates "x y flags;…" (µm, y down) → paper mm, y up. Flag 1 = the next two points are bezier
        /// control points; the curve is flattened into straight segments.
        static func coords(_ text: String) -> [Point2D] {
            let raw: [(p: Point2D, flags: Int)] = text.split(separator: ";").compactMap { item in
                let v = item.split(separator: " ").compactMap { Double($0) }
                guard v.count >= 2 else { return nil }
                return (Point2D(x: v[0] / 1000, y: -v[1] / 1000), v.count > 2 ? Int(v[2]) : 0)
            }
            var out: [Point2D] = []
            var i = 0
            while i < raw.count {
                let a = raw[i]
                out.append(a.p)
                if a.flags & 1 != 0, i + 3 < raw.count {
                    let (c1, c2, b) = (raw[i + 1].p, raw[i + 2].p, raw[i + 3].p)
                    for step in 1..<8 {
                        let t = Double(step) / 8, u = 1 - t
                        let x = u * u * u * a.p.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x
                        let y = u * u * u * a.p.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y
                        out.append(Point2D(x: x, y: y))
                    }
                    i += 3
                } else {
                    i += 1
                }
            }
            return out
        }
    }
}

// MARK: - Minimal XML tree

/// Small DOM built with XMLParser (Foundation's XMLDocument isn't available on iOS).
final class XMLTree: NSObject, XMLParserDelegate {
    final class Node {
        let name: String
        let attributes: [String: String]
        var children: [Node] = []
        var text = ""

        init(name: String, attributes: [String: String]) {
            self.name = name
            self.attributes = attributes
        }

        func first(_ name: String) -> Node? { children.first { $0.name == name } }
        func children(named name: String) -> [Node] { children.filter { $0.name == name } }
        /// First descendant with this name (depth-first).
        func descendant(_ name: String) -> Node? {
            for c in children {
                if c.name == name { return c }
                if let d = c.descendant(name) { return d }
            }
            return nil
        }
    }

    private(set) var root: Node?
    private var stack: [Node] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let node = Node(name: name, attributes: attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Only keep text where it matters (coordinates); descriptions can be long.
        if let top = stack.last, top.name == "coords" { top.text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        _ = stack.popLast()
    }
}

extension SymbolSet {
    /// The same set at another size: all widths, dashes, and point shapes × `k` (e.g. an ISOM 1:10000 set, which is
    /// the 1:15000 set enlarged to 150%, used on a 1:15000 map → k = 1 / 1.5).
    public func scaled(by k: Double) -> SymbolSet {
        guard abs(k - 1) > 1e-9 else { return self }
        func r(_ v: Double) -> Double { (v * k * 1000).rounded() / 1000 }
        var copy = self
        copy.symbols = symbols.map { s in
            var s = s
            s.lineWidthMM = s.lineWidthMM.map(r)
            if var l = s.lineStyle {
                l.widthMM = r(l.widthMM)
                l.casing = l.casing.map { LineStyle.Casing(colorHex: $0.colorHex, innerWidthMM: r($0.innerWidthMM)) }
                l.dashMM = l.dashMM?.map(r)
                l.innerDashMM = l.innerDashMM?.map(r)
                s.lineStyle = l
            }
            s.pointElements = s.pointElements?.map { e in
                PointElement(kind: e.kind, colorHex: e.colorHex, priority: e.priority, lineWidthMM: r(e.lineWidthMM),
                         diameterMM: r(e.diameterMM), points: e.points.map { Point2D(x: $0.x * k, y: $0.y * k) }, flatEnds: e.flatEnds)
            }
            s.patterns = s.patterns?.map { $0.scaled(by: k) }
            s.decoration = s.decoration?.scaled(by: k)
            s.textSizeMM = s.textSizeMM.map(r)
            return s
        }
        return copy
    }

    /// Only course-planning symbols (701–799).
    public var isCourseDesign: Bool { !symbols.isEmpty && symbols.allSatisfy { (700_000..<800_000).contains($0.number) } }

    /// The IOF standard of the set, from its scale (nil if unknown). Sets at 1:700 (ISInOM's base scale, used by no
    /// other standard) are indoor sets.
    public var standard: MapStandard? {
        guard scale > 0 else { return nil }
        return scale == MapStandard.isinom.baseScale ? .isinom : MapStandard.for(scale: scale)
    }

    /// Size factor to use this set on a map of `mapScale` with the same standard: enlargement at the map scale ÷
    /// enlargement the set already has (1 if the standards differ). An indoor (ISInOM) set is used on any map scale:
    /// enlarged on maps larger than 1:700, never reduced (ISInOM §3.1).
    public func sizeFactor(forMapScale mapScale: Int) -> Double {
        if standard == .isinom { return MapStandard.isinom.enlargement(scale: mapScale) }
        guard let s = standard, s == MapStandard.for(scale: mapScale) else { return 1 }
        return s.enlargement(scale: mapScale) / s.enlargement(scale: scale)
    }
}
