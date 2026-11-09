import Foundation

/// OCCA's own ISOM 2017-2 and ISSprOM 2019-2 symbol sets, written from the IOF specifications (Revision 6,
/// January 2024): symbol codes, names, sizes (paper mm at the base scale), colors, and color order. Saved as the
/// built-in `.occasym` files (see `OccaSymbolFile`); regenerate them with the `OccaStandardSymbolsTests` generator.
///
/// Drawing in OCCA today: lines (width, dashes, round/flat caps, double lines), solid areas, and point shapes. Area
/// patterns and line decorations (tags, wall dots) are stored with each symbol per the specification; areas defined
/// only by a pattern (e.g. marsh) are disabled by default because they would show as a solid fill.
public enum OccaStandardSymbols {
    public static let author = "OCCA — Rizky Ajie Kurniawan"
    public static let license = "© 2026 Rizky Ajie Kurniawan. Part of OCCA. Symbol definitions follow the IOF specifications ISOM 2017-2 and ISSprOM 2019-2."

    // MARK: Colors (top → bottom = drawing order)

    /// IOF process colors (CMYK 0–1) as in common orienteering symbol sets; screens as IOF percentages.
    static let purple = [0.35, 0.85, 0, 0], black = [0.0, 0, 0, 1], blue = [1.0, 0, 0, 0], brown = [0.0, 0.56, 1, 0.18]
    static let yellow = [0.0, 0.27, 0.79, 0], green = [0.76, 0, 0.91, 0], darkGreen = [1.0, 0, 0.8, 0.3], white = [0.0, 0, 0, 0]

    static func colors() -> [OccaSymbolFile.Color] {
        typealias C = OccaSymbolFile.Color
        return [
            C(id: "purpleUpper", name: "Upper purple (course)", cmyk: purple),
            C(id: "black", name: "Black", cmyk: black),
            C(id: "blue", name: "Blue", cmyk: blue),
            C(id: "brown", name: "Brown", cmyk: brown),
            C(id: "purpleLower", name: "Lower purple (course)", cmyk: purple),
            C(id: "whiteTop", name: "White over symbols", cmyk: white),
            C(id: "greenSymbol", name: "Green (point and line symbols)", cmyk: green),
            C(id: "darkGreen", name: "Dark green", cmyk: darkGreen),
            C(id: "whiteMask", name: "White masks and holes", cmyk: white),
            C(id: "black50", name: "Black 50 %", cmyk: black, tint: 0.5),
            C(id: "black35", name: "Black 35 %", cmyk: black, tint: 0.35),
            C(id: "black20", name: "Black 20 %", cmyk: black, tint: 0.2),
            C(id: "brown50", name: "Brown 50 %", cmyk: brown, tint: 0.5),
            C(id: "brown30", name: "Brown 30 %", cmyk: brown, tint: 0.3),
            // Edges of double lines (roads, tracks, railway, stairway) sit below their fill colors, so the fill shows
            // between the edges (as in OCAD / OOM color tables).
            C(id: "blackEdge", name: "Black (double-line edges)", cmyk: black),
            C(id: "blue70", name: "Blue 70 %", cmyk: blue, tint: 0.7),
            C(id: "blue50", name: "Blue 50 %", cmyk: blue, tint: 0.5),
            C(id: "blue30", name: "Blue 30 %", cmyk: blue, tint: 0.3),
            C(id: "purple50", name: "Purple 50 %", cmyk: purple, tint: 0.5),
            C(id: "green100", name: "Green", cmyk: green),
            C(id: "green60", name: "Green 60 %", cmyk: green, tint: 0.6),
            C(id: "green30", name: "Green 30 %", cmyk: green, tint: 0.3),
            C(id: "olive", name: "Yellow + green 50 % (area that shall not be entered)", cmyk: [0.38, 0.27, 0.85, 0]),
            C(id: "yellow100", name: "Yellow", cmyk: yellow),
            C(id: "yellow75", name: "Yellow 75 %", cmyk: yellow, tint: 0.75),
            C(id: "yellow50", name: "Yellow 50 %", cmyk: yellow, tint: 0.5),
            C(id: "white", name: "White (forest)", cmyk: white),
        ]
    }

    // MARK: Files

    public static func isomFile() -> OccaSymbolFile {
        var b = Builder(colors: colors())
        isom(&b)
        return OccaSymbolFile(name: "ISOM 2017-2 · OCCA", standard: "ISOM 2017-2",
                              specification: "IOF International Specification for Orienteering Maps ISOM 2017-2, Revision 6, January 2024",
                              scale: 15000, author: author, license: license,
                              notes: "Sizes at 1:15000; OCCA enlarges them to 150 % on 1:10000 maps.",
                              colors: b.colors, symbols: b.symbols.sorted { $0.number < $1.number })
    }

    public static func issprFile() -> OccaSymbolFile {
        var b = Builder(colors: colors())
        issprom(&b)
        return OccaSymbolFile(name: "ISSprOM 2019-2 · OCCA", standard: "ISSprOM 2019-2",
                              specification: "IOF International Specification for Sprint Orienteering Maps ISSprOM 2019-2, Revision 6, January 2024",
                              scale: 4000, author: author, license: license,
                              notes: "Sizes at 1:4000; OCCA enlarges them to 133 % on 1:3000 maps.",
                              colors: b.colors, symbols: b.symbols.sorted { $0.number < $1.number })
    }

    /// Bundle file names of the built-in sets.
    public static let isomFileName = "OCCA ISOM 2017-2.occasym"
    public static let issprFileName = "OCCA ISSprOM 2019-2.occasym"

    // MARK: Builder

    struct Builder {
        let colors: [OccaSymbolFile.Color]
        var symbols: [MapSymbol] = []

        init(colors: [OccaSymbolFile.Color]) { self.colors = colors }

        func hex(_ id: String) -> String { colors.first { $0.id == id }!.hex }
        func prio(_ id: String) -> Int { colors.firstIndex { $0.id == id }! }

        static func number(_ code: String) -> Int {
            let p = code.split(separator: ".")
            return Int(p[0])! * 1000 + (p.count > 1 ? Int(p[1])! : 0)
        }

        private mutating func add(_ s: MapSymbol) {
            precondition(!symbols.contains { $0.number == s.number }, "duplicate \(s.code)")
            symbols.append(s)
        }

        mutating func line(_ code: String, _ name: String, _ color: String, _ w: Double, dash: [Double]? = nil,
                           round: Bool = false, deco: LineDecoration? = nil) {
            var s = MapSymbol(number: Self.number(code), name: name, kind: .line, colorHex: hex(color), lineWidthMM: w, isEnabled: true,
                              lineStyle: LineStyle(colorHex: hex(color), widthMM: w, casing: nil, dashMM: dash, roundCaps: round))
            s.colorPriority = prio(color)
            s.decoration = deco
            add(s)
        }

        /// Dotted line: dots of `d` every `cc` (round-capped tiny dashes).
        mutating func dotted(_ code: String, _ name: String, _ color: String, _ d: Double, _ cc: Double) {
            line(code, name, color, d, dash: [0.01, ((cc - 0.01) * 1000).rounded() / 1000], round: true)
        }

        /// Double line: two `edge`-wide edges with `inner` (inside measure) between them, filled with `fill`.
        mutating func double(_ code: String, _ name: String, edgeColor: String, edge: Double, inner: Double,
                             fill: String = "whiteMask", edgeDash: [Double]? = nil, innerDash: [Double]? = nil) {
            let total = ((inner + 2 * edge) * 1000).rounded() / 1000
            var s = MapSymbol(number: Self.number(code), name: name, kind: .line, colorHex: hex(fill), lineWidthMM: nil, isEnabled: true,
                              lineStyle: LineStyle(colorHex: hex(fill), widthMM: total,
                                                   casing: LineStyle.Casing(colorHex: hex(edgeColor), innerWidthMM: inner),
                                                   dashMM: edgeDash, innerDashMM: innerDash, roundCaps: false))
            s.colorPriority = prio(fill)
            s.casingPriority = prio(edgeColor == "black" ? "blackEdge" : edgeColor)
            add(s)
        }

        /// Area with a solid fill (`color`), optional patterns. Areas defined only by a pattern (`patternOnly`, white
        /// "fill") draw just the pattern, so what lies below stays visible.
        mutating func area(_ code: String, _ name: String, _ color: String, patterns: [AreaPattern]? = nil, patternOnly: Bool = false) {
            var s = MapSymbol(number: Self.number(code), name: name, kind: .area, colorHex: hex(color), lineWidthMM: nil, isEnabled: true)
            s.colorPriority = prio(color)
            s.patterns = patterns
            add(s)
        }

        func pattern(_ kind: AreaPattern.Kind, _ color: String, size: Double, cc: Double, angle: Double = 0) -> AreaPattern {
            AreaPattern(kind: kind, colorHex: hex(color), sizeMM: size, spacingMM: cc, angleDeg: angle)
        }

        mutating func point(_ code: String, _ name: String, _ elements: [PointElement]) {
            let top = elements.drawingOrder.last!
            var s = MapSymbol(number: Self.number(code), name: name, kind: .point, colorHex: top.colorHex, lineWidthMM: nil,
                              isEnabled: true, pointElements: elements)
            s.colorPriority = elements.map(\.priority).min()
            add(s)
        }

        mutating func text(_ code: String, _ name: String, _ color: String) {
            var s = MapSymbol(number: Self.number(code), name: name, kind: .text, colorHex: hex(color), lineWidthMM: nil, isEnabled: true)
            s.colorPriority = prio(color)
            add(s)
        }

        // Point elements (paper mm, y up, centred on the symbol position).

        func dot(_ d: Double, _ color: String, at p: Point2D = Point2D(x: 0, y: 0)) -> PointElement {
            PointElement(kind: .dot, colorHex: hex(color), priority: prio(color), lineWidthMM: 0, diameterMM: d, points: [p])
        }

        /// Ring of outside measure `om` and line width `lw`.
        func ring(_ om: Double, _ lw: Double, _ color: String, at p: Point2D = Point2D(x: 0, y: 0)) -> PointElement {
            PointElement(kind: .circle, colorHex: hex(color), priority: prio(color), lineWidthMM: lw, diameterMM: om - lw, points: [p])
        }

        /// Circle with centre-line diameter `cc`.
        func circleCC(_ cc: Double, _ lw: Double, _ color: String) -> PointElement {
            PointElement(kind: .circle, colorHex: hex(color), priority: prio(color), lineWidthMM: lw, diameterMM: cc, points: [Point2D(x: 0, y: 0)])
        }

        func lines(_ pts: [(Double, Double)], _ lw: Double, _ color: String) -> PointElement {
            PointElement(kind: .line, colorHex: hex(color), priority: prio(color), lineWidthMM: lw, diameterMM: 0,
                         points: pts.map { Point2D(x: $0.0, y: $0.1) })
        }

        func fill(_ pts: [(Double, Double)], _ color: String) -> PointElement {
            PointElement(kind: .area, colorHex: hex(color), priority: prio(color), lineWidthMM: 0, diameterMM: 0,
                         points: pts.map { Point2D(x: $0.0, y: $0.1) })
        }

        /// "V" of outside measure w × h (pit, waterhole, rocky pit).
        func vee(_ w: Double, _ h: Double, _ lw: Double, _ color: String) -> PointElement {
            let x = (w - lw) / 2, y = (h - lw) / 2
            return lines([(-x, y), (0, -y), (x, y)], lw, color)
        }

        /// Half ring "U" of outside measure w × h (small depression, spring).
        func cup(_ w: Double, _ h: Double, _ lw: Double, _ color: String) -> PointElement {
            let rx = (w - lw) / 2, ry = h - lw
            let pts = (0...16).map { i -> (Double, Double) in
                let t = Double.pi + Double(i) / 16 * Double.pi
                return (rx * cos(t), ry * sin(t) + ry / 2)
            }
            return lines(pts, lw, color)
        }

        /// "x" of outside measure `om`.
        func cross(_ om: Double, _ lw: Double, _ color: String) -> [PointElement] {
            let a = (om - lw) / 2
            return [lines([(-a, -a), (a, a)], lw, color), lines([(-a, a), (a, -a)], lw, color)]
        }

        /// "+" with arms of length `size` and width `lw` (first aid post, registration mark).
        func plus(_ size: Double, _ lw: Double, _ color: String) -> [PointElement] {
            let a = size / 2
            return [lines([(-a, 0), (a, 0)], lw, color), lines([(0, -a), (0, a)], lw, color)]
        }

        func ellipse(_ w: Double, _ h: Double, _ color: String) -> PointElement {
            fill((0..<24).map { i in
                let t = Double(i) / 24 * 2 * Double.pi
                return (w / 2 * cos(t), h / 2 * sin(t))
            }, color)
        }

        /// Equilateral triangle with side `s`, pointing up (north), centred on its centroid.
        func triangle(_ s: Double, _ color: String, outline lw: Double? = nil) -> PointElement {
            let h = s * sqrt(3) / 2
            let pts = [(0, 2 * h / 3), (-s / 2, -h / 3), (s / 2, -h / 3)]
            if let lw { return lines(pts + [pts[0]], lw, color) }
            return fill(pts, color)
        }

        /// Two lines curving outward, `length` long, `gap` apart inside (crossing points).
        func crossing(_ length: Double, _ gap: Double, _ lw: Double, _ color: String) -> [PointElement] {
            let x0 = gap / 2 + lw / 2, bend = length * 0.12
            let left = (0...10).map { i -> (Double, Double) in
                let t = Double(i) / 5 - 1
                return (-x0 - bend * t * t, t * length / 2)
            }
            return [lines(left, lw, color), lines(left.map { (-$0.0, $0.1) }, lw, color)]
        }
    }

    // MARK: ISOM 2017-2 (1:15000)

    static func isom(_ b: inout Builder) {
        // 1 Landforms
        b.line("101", "Contour", "brown", 0.14, round: true)
        b.point("101.1", "Slope line, contour", [b.lines([(0, 0), (0, -0.4)], 0.14, "brown")])
        b.line("102", "Index contour", "brown", 0.25, round: true)
        b.text("102.1", "Index contour value", "brown")
        b.line("103", "Form line", "brown", 0.1, dash: [2.0, 0.2])
        b.point("103.1", "Slope line, form line", [b.lines([(0, 0), (0, -0.4)], 0.1, "brown")])
        b.line("104", "Earth bank", "brown", 0.25, deco: LineDecoration(kind: .tags, sizeMM: 0.4, widthMM: 0.14, spacingMM: 0.5))
        b.line("105.1", "Earth wall", "brown", 0.18, deco: LineDecoration(kind: .dots, sizeMM: 0.45, spacingMM: 2.0))
        b.line("105.2", "Retaining earth wall", "brown", 0.18, deco: LineDecoration(kind: .halfDots, sizeMM: 0.45, spacingMM: 1.0))
        b.line("106", "Ruined earth wall", "brown", 0.18, dash: [1.5, 0.5], deco: LineDecoration(kind: .dots, sizeMM: 0.45, spacingMM: 2.0))
        b.line("107", "Erosion gully", "brown", 0.25)
        b.dotted("108", "Small erosion gully", "brown", 0.25, 0.45)
        b.point("109", "Small knoll", [b.dot(0.5, "brown")])
        b.point("110", "Small elongated knoll", [b.ellipse(0.8, 0.4, "brown")])
        b.point("111", "Small depression", [b.cup(0.8, 0.4, 0.18, "brown")])
        b.point("112", "Pit", [b.vee(0.8, 0.7, 0.18, "brown")])
        b.area("113", "Broken ground", "white", patterns: [b.pattern(.dots, "brown", size: 0.2, cc: 0.55)], patternOnly: true)
        b.area("114", "Very broken ground", "white", patterns: [b.pattern(.dots, "brown", size: 0.2, cc: 0.32)], patternOnly: true)
        b.point("115", "Prominent landform feature", b.cross(0.9, 0.18, "brown"))
        // 2 Rock and boulders
        b.line("201", "Impassable cliff", "black", 0.35, deco: LineDecoration(kind: .tags, sizeMM: 0.5, widthMM: 0.12, spacingMM: 0.5))
        b.line("202", "Cliff", "black", 0.25)
        b.line("202.1", "Cliff with tags", "black", 0.25, deco: LineDecoration(kind: .tags, sizeMM: 0.4, widthMM: 0.12, spacingMM: 0.5))
        b.point("203.1", "Rocky pit or cave", [b.vee(0.8, 0.7, 0.16, "black")])
        b.point("203.2", "Dangerous pit", [b.vee(0.9, 0.9, 0.35, "black")])
        b.point("204", "Boulder", [b.dot(0.4, "black")])
        b.point("205", "Large boulder", [b.dot(0.6, "black")])
        b.area("206", "Gigantic boulder or rock pillar", "black")
        b.point("207", "Boulder cluster", [b.triangle(0.8, "black")])
        b.area("208", "Boulder field", "white", patterns: [b.pattern(.triangles, "black", size: 0.8, cc: 1.0)], patternOnly: true)
        b.area("209", "Dense boulder field", "white", patterns: [b.pattern(.triangles, "black", size: 0.8, cc: 0.6)], patternOnly: true)
        b.area("210", "Stony ground, slow running", "white", patterns: [b.pattern(.dots, "black", size: 0.2, cc: 0.52)], patternOnly: true)
        b.area("211", "Stony ground, walk", "white", patterns: [b.pattern(.dots, "black", size: 0.2, cc: 0.36)], patternOnly: true)
        b.area("212", "Stony ground, fight", "white", patterns: [b.pattern(.dots, "black", size: 0.2, cc: 0.28)], patternOnly: true)
        b.area("213", "Sandy ground", "yellow50", patterns: [b.pattern(.dots, "black", size: 0.16, cc: 0.45, angle: 45)])
        b.area("214", "Bare rock", "black35")
        b.double("215", "Trench", edgeColor: "black", edge: 0.1, inner: 0.3)
        // 3 Water and marsh
        b.area("301", "Uncrossable body of water", "blue")
        b.area("301.1", "Uncrossable body of water, dominant (70 %)", "blue70")
        b.line("301.2", "Uncrossable body of water, bank line", "black", 0.12)
        b.area("302", "Shallow body of water", "blue50")
        b.line("302.1", "Shallow body of water, outline", "blue", 0.1)
        b.line("302.2", "Shallow body of water, seasonal outline", "blue", 0.1, dash: [1.25, 0.25])
        b.point("303", "Waterhole", [b.vee(0.8, 0.7, 0.18, "blue")])
        b.line("304", "Crossable watercourse", "blue", 0.3)
        b.line("305", "Small crossable watercourse", "blue", 0.18)
        b.line("306", "Minor/seasonal water channel", "blue", 0.18, dash: [1.25, 0.25])
        b.area("307", "Uncrossable marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.25, cc: 0.5, angle: 90)], patternOnly: true)
        b.line("307.1", "Uncrossable marsh, outline", "black", 0.12)
        b.area("308", "Marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.1, cc: 0.3, angle: 90)], patternOnly: true)
        b.dotted("309", "Narrow marsh", "blue", 0.25, 0.45)
        b.area("310", "Indistinct marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.1, cc: 0.3, angle: 90)], patternOnly: true)
        b.point("311", "Well, fountain or water tank", [b.ring(0.8, 0.18, "blue")])
        b.point("312", "Spring", [b.cup(0.9, 0.45, 0.18, "blue")])
        b.point("313", "Prominent water feature", b.cross(0.9, 0.16, "blue"))
        // 4 Vegetation
        b.area("401", "Open land", "yellow100")
        b.area("401.1", "Open land, dominant (75 %)", "yellow75")
        b.area("402", "Open land with scattered trees", "yellow100", patterns: [b.pattern(.holes, "whiteMask", size: 0.4, cc: 0.7, angle: 45)])
        b.area("403", "Rough open land", "yellow50")
        b.area("404", "Rough open land with scattered trees", "yellow50", patterns: [b.pattern(.holes, "whiteMask", size: 0.5, cc: 0.8, angle: 45)])
        b.area("405", "Forest", "white")
        b.area("406", "Vegetation: slow running", "green30")
        b.area("407", "Vegetation: slow running, good visibility", "white", patterns: [b.pattern(.lines, "greenSymbol", size: 0.12, cc: 0.84)], patternOnly: true)
        b.area("408", "Vegetation: walk", "green60")
        b.area("409", "Vegetation: walk, good visibility", "white", patterns: [b.pattern(.lines, "greenSymbol", size: 0.14, cc: 0.42)], patternOnly: true)
        b.area("410", "Vegetation: fight", "green100")
        b.area("412", "Cultivated land", "yellow100", patterns: [b.pattern(.dots, "black", size: 0.2, cc: 0.8)])
        b.area("413", "Orchard", "yellow100", patterns: [b.pattern(.dots, "greenSymbol", size: 0.45, cc: 0.8)])
        b.area("414", "Vineyard or similar", "yellow100", patterns: [b.pattern(.lines, "greenSymbol", size: 0.2, cc: 0.85)])
        b.line("415", "Distinct cultivation boundary", "black", 0.1)
        b.dotted("416", "Distinct vegetation boundary", "black", 0.22, 0.45)
        b.line("416.1", "Distinct vegetation boundary, green dashed line", "darkGreen", 0.14, dash: [0.3, 0.2])
        b.point("417", "Prominent large tree", [b.dot(1.1, "whiteMask"), b.ring(0.9, 0.18, "greenSymbol")])
        b.point("418", "Prominent bush or tree", [b.dot(0.6, "greenSymbol"), b.dot(0.2, "whiteTop")])
        b.point("419", "Prominent vegetation feature",
                b.cross(0.9 + 0.36, 0.36, "whiteMask") + b.cross(0.9, 0.18, "greenSymbol"))
        // 5 Man-made features
        b.area("501", "Paved area", "brown50")
        b.line("501.1", "Paved area, bounding line", "black", 0.1)
        b.double("502", "Wide road", edgeColor: "black", edge: 0.14, inner: 0.3, fill: "brown50")
        b.line("503", "Road", "black", 0.35)
        b.line("504", "Vehicle track", "black", 0.35, dash: [3.0, 0.25])
        b.line("505", "Footpath", "black", 0.25, dash: [2.0, 0.25])
        b.line("506", "Small footpath", "black", 0.18, dash: [1.0, 0.25])
        b.line("507", "Less distinct small footpath", "black", 0.18, dash: [1.0, 0.8])
        b.line("508", "Narrow ride or linear trace through the terrain", "black", 0.14, dash: [2.0, 0.25])
        b.double("509", "Railway", edgeColor: "black", edge: 0.1, inner: 0.25, fill: "whiteMask", innerDash: [1.0, 1.5])
        b.line("510", "Power line, cableway or skilift", "black", 0.14,
               deco: LineDecoration(kind: .bars, sizeMM: 0.3, widthMM: 0.14, spacingMM: 0))
        b.double("511", "Major power line, cableway or skilift", edgeColor: "black", edge: 0.2, inner: 0.2)
        b.line("512", "Bridge / tunnel", "black", 0.18, deco: LineDecoration(kind: .ticks, sizeMM: 0.4, widthMM: 0.18, spacingMM: 0, angleDeg: 60))
        b.point("512.1", "Footbridge", [b.lines([(-0.6, 0), (0.6, 0)], 0.18, "black")])
        b.line("513.1", "Wall", "black", 0.14, deco: LineDecoration(kind: .dots, sizeMM: 0.4, spacingMM: 2.0))
        b.line("513.2", "Retaining wall", "black", 0.14, deco: LineDecoration(kind: .halfDots, sizeMM: 0.4, spacingMM: 1.0))
        b.line("514", "Ruined wall", "black", 0.14, dash: [1.5, 0.5], deco: LineDecoration(kind: .dots, sizeMM: 0.4, spacingMM: 2.0))
        b.line("515", "Impassable wall", "black", 0.25, deco: LineDecoration(kind: .dots, sizeMM: 0.6, spacingMM: 3.0))
        b.line("516", "Fence", "black", 0.14, deco: LineDecoration(kind: .tags, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2.0, angleDeg: 60))
        b.line("517", "Ruined fence", "black", 0.14, dash: [1.5, 0.5],
               deco: LineDecoration(kind: .tags, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2.0, angleDeg: 60))
        b.line("518", "Impassable fence", "black", 0.25,
               deco: LineDecoration(kind: .doubleTags, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2.5, angleDeg: 60, pairMM: 0.6))
        b.point("519", "Crossing point", [b.lines([(-0.3, -0.5), (-0.3, 0.5)], 0.18, "black"), b.lines([(0.3, -0.5), (0.3, 0.5)], 0.18, "black")])
        b.area("520", "Area that shall not be entered", "olive",
               patterns: [b.pattern(.lines, "green100", size: 0.25, cc: 0.5, angle: 45)])
        b.line("520.1", "Area that shall not be entered, bounding line", "black", 0.18)
        b.area("521", "Building", "black")
        b.area("521.1", "Large building", "black50")
        b.line("521.2", "Large building, outline", "black", 0.2)
        b.area("522", "Canopy", "black20")
        b.line("522.1", "Canopy, outline", "black", 0.1)
        b.line("523", "Ruin", "black", 0.16, dash: [0.5, 0.25])
        b.point("524", "High tower", [b.dot(0.8, "black"), b.lines([(-0.7, 0), (0.7, 0)], 0.16, "black")])
        b.point("525", "Small tower", [b.lines([(-0.42, -0.42), (-0.42, 0.42), (0.42, 0.42), (0.42, -0.42)], 0.16, "black")])
        b.point("526", "Cairn, memorial or boundary stone", [b.ring(0.8, 0.16, "black")])
        b.point("527", "Fodder rack", [b.lines([(-0.37, -0.32), (0, 0.32), (0.37, -0.32)], 0.16, "black")])
        b.line("528", "Prominent line feature", "black", 0.14, deco: LineDecoration(kind: .ticks, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2.0, angleDeg: 45))
        b.line("529", "Prominent impassable line feature", "black", 0.25,
               deco: LineDecoration(kind: .doubleTicks, sizeMM: 0.4, widthMM: 0.14, spacingMM: 2.0, angleDeg: 45))
        b.point("530", "Prominent man-made feature – ring", [b.ring(0.8, 0.16, "black")])
        b.point("531", "Prominent man-made feature – x", b.cross(0.8, 0.16, "black"))
        b.double("532", "Stairway", edgeColor: "black", edge: 0.1, inner: 0.4)
        // 6 Technical symbols
        b.line("601", "Magnetic north line", "black", 0.1)
        b.line("601.1", "Magnetic north line, blue", "blue", 0.12)
        b.point("602", "Registration mark", [b.ring(1.2, 0.1, "black")] + b.plus(4.0, 0.1, "black"))
        b.point("603", "Spot height", [b.dot(0.3, "black")])
        b.text("603.1", "Spot height, value", "black")
        // 7 Course planning (1:15000)
        course(&b, start: 6.0, control: 5.0, finish: (4.0, 6.0), boundary: 0.7, oobLine: 0.25, sprint: false)
    }

    // MARK: ISSprOM 2019-2 (1:4000)

    static func issprom(_ b: inout Builder) {
        // 1 Landforms
        b.line("101", "Contour", "brown", 0.21, round: true)
        b.point("101.1", "Slope line, contour", [b.lines([(0, 0), (0, -0.75)], 0.21, "brown")])
        b.line("102", "Index contour", "brown", 0.3, round: true)
        b.text("102.1", "Index contour value", "brown")
        b.line("103", "Form line", "brown", 0.15, dash: [3.0, 0.3])
        b.point("103.1", "Slope line, form line", [b.lines([(0, 0), (0, -0.6)], 0.15, "brown")])
        b.line("104", "Earth bank", "brown", 0.27, deco: LineDecoration(kind: .tags, sizeMM: 0.75, widthMM: 0.21, spacingMM: 0.75))
        b.line("104.1", "Earth bank, very high", "brown", 0.37, deco: LineDecoration(kind: .tags, sizeMM: 1.65, widthMM: 0.21, spacingMM: 0.75))
        b.line("105.1", "Small earth wall", "brown", 0.27, deco: LineDecoration(kind: .dots, sizeMM: 0.7, spacingMM: 3.75))
        b.line("105.2", "Retaining earth wall", "brown", 0.27, deco: LineDecoration(kind: .halfDots, sizeMM: 0.7, spacingMM: 1.9))
        b.line("107", "Erosion gully", "brown", 0.37)
        b.dotted("108", "Small erosion gully", "brown", 0.37, 0.6)
        b.point("109", "Small knoll", [b.dot(0.75, "brown")])
        b.point("110", "Small elongated knoll", [b.ellipse(1.2, 0.6, "brown")])
        b.point("111", "Small depression", [b.cup(1.2, 0.6, 0.25, "brown")])
        b.point("112", "Pit or hole", [b.vee(1.1, 1.25, 0.25, "brown")])
        b.area("113", "Broken ground", "white", patterns: [b.pattern(.dots, "brown", size: 0.3, cc: 0.75)], patternOnly: true)
        b.point("115", "Prominent landform feature", b.cross(1.35, 0.25, "brown"))
        // 2 Rock and boulders
        b.line("201", "Uncrossable cliff", "black", 0.5, deco: LineDecoration(kind: .tags, sizeMM: 0.75, widthMM: 0.18, spacingMM: 0.75))
        b.line("202", "Passable rock face", "black", 0.3, round: true)
        b.line("202.1", "Passable rock face with tags", "black", 0.3, deco: LineDecoration(kind: .tags, sizeMM: 0.6, widthMM: 0.18, spacingMM: 0.75))
        b.point("203", "Rocky pit or cave", [b.vee(1.1, 1.25, 0.25, "black")])
        b.point("204", "Boulder", [b.dot(0.6, "black")])
        b.point("205", "Large boulder", [b.dot(0.9, "black")])
        b.area("206", "Gigantic boulder or rock pillar", "black")
        b.point("207", "Boulder cluster", [b.triangle(1.2, "black")])
        b.area("208", "Boulder field", "white", patterns: [b.pattern(.triangles, "black", size: 0.96, cc: 1.5)], patternOnly: true)
        b.area("210", "Stony ground", "white", patterns: [b.pattern(.dots, "black", size: 0.25, cc: 0.6)], patternOnly: true)
        b.area("213", "Open sandy ground", "yellow50", patterns: [b.pattern(.dots, "black", size: 0.18, cc: 0.5, angle: 45)])
        b.area("214", "Bare rock", "black35")
        // 3 Water and marsh
        b.area("301", "Uncrossable body of water", "blue")
        b.area("301.1", "Uncrossable body of water, dominant (70 %)", "blue70")
        b.line("301.2", "Uncrossable body of water, outline", "black", 0.18)
        b.area("302", "Shallow body of water", "blue30")
        b.line("302.1", "Shallow body of water, outline", "blue", 0.18)
        b.point("303", "Waterhole", [b.vee(1.1, 1.25, 0.25, "blue")])
        b.line("305", "Small crossable watercourse", "blue", 0.21)
        b.line("306", "Minor/seasonal watercourse", "blue", 0.21, dash: [1.87, 0.37])
        b.area("307", "Uncrossable marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.25, cc: 0.5, angle: 90)], patternOnly: true)
        b.line("307.1", "Uncrossable marsh, outline", "black", 0.18)
        b.area("308", "Marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.12, cc: 0.38, angle: 90)], patternOnly: true)
        b.dotted("309", "Narrow marsh", "blue", 0.37, 0.6)
        b.area("310", "Indistinct marsh", "white", patterns: [b.pattern(.lines, "blue", size: 0.12, cc: 0.38, angle: 90)], patternOnly: true)
        b.point("311", "Small fountain or well", [b.ring(0.9, 0.25, "blue")])
        b.point("312", "Spring", [b.cup(1.2, 0.6, 0.25, "blue")])
        b.point("313", "Prominent water feature", b.cross(1.2, 0.25, "blue"))
        // 4 Vegetation
        b.area("401", "Open land", "yellow100")
        b.area("401.1", "Open land, dominant (75 %)", "yellow75")
        b.area("402", "Open land with scattered trees", "yellow100", patterns: [b.pattern(.holes, "whiteMask", size: 0.6, cc: 0.75, angle: 45)])
        b.area("403", "Rough open land", "yellow50")
        b.area("404", "Rough open land with scattered trees", "yellow50", patterns: [b.pattern(.holes, "whiteMask", size: 0.7, cc: 1.0, angle: 45)])
        b.area("405", "Forest", "white")
        b.area("406", "Vegetation: slow running", "green30")
        b.area("407", "Vegetation: slow running, good visibility", "white", patterns: [b.pattern(.lines, "greenSymbol", size: 0.12, cc: 0.84)], patternOnly: true)
        b.area("408", "Vegetation: walk", "green60")
        b.area("409", "Vegetation: walk, good visibility", "white", patterns: [b.pattern(.lines, "greenSymbol", size: 0.14, cc: 0.42)], patternOnly: true)
        b.area("410", "Vegetation: fight", "green100")
        b.area("411", "Uncrossable vegetation", "darkGreen")
        b.area("412", "Cultivated land", "yellow100", patterns: [b.pattern(.dots, "black", size: 0.2, cc: 0.8)])
        b.area("413", "Orchard", "yellow100", patterns: [b.pattern(.dots, "greenSymbol", size: 0.68, cc: 1.2)])
        b.area("414", "Vineyard or similar", "yellow100", patterns: [b.pattern(.lines, "greenSymbol", size: 0.3, cc: 1.3)])
        b.line("415", "Distinct cultivation boundary", "black", 0.15)
        b.dotted("416", "Distinct vegetation boundary", "black", 0.25, 0.6)
        b.point("417", "Prominent large tree", [b.dot(1.4, "whiteMask"), b.ring(1.2, 0.25, "greenSymbol")])
        b.point("418", "Prominent bush or small tree", [b.dot(0.8, "greenSymbol"), b.dot(0.2, "whiteTop")])
        b.point("419", "Prominent vegetation feature",
                b.cross(1.2 + 0.5, 0.5, "whiteMask") + b.cross(1.2, 0.25, "greenSymbol"))
        // 5 Man-made features
        b.area("501", "Paved area", "brown30")
        b.line("501.1", "Step or edge of paved area", "black", 0.1)
        b.line("501.2", "Step or edge of paved area at lower level", "black", 0.1, dash: [0.7, 0.2])
        b.area("501.3", "Paved area with scattered trees", "brown30", patterns: [b.pattern(.holes, "whiteMask", size: 0.6, cc: 0.75, angle: 45)])
        b.area("501.4", "Paved area, heavy traffic", "brown50")
        b.double("505", "Unpaved footpath or track", edgeColor: "black", edge: 0.12, inner: 0.35, fill: "brown30", edgeDash: [2.0, 0.25])
        b.line("506", "Small unpaved footpath", "black", 0.27, dash: [1.5, 0.37])
        b.line("507", "Less distinct small path", "black", 0.27, dash: [3.37, 1.5])
        b.line("508", "Narrow ride", "black", 0.21, dash: [4.5, 0.75])
        b.double("509.1", "Railway", edgeColor: "black", edge: 0.1, inner: 0.25, fill: "whiteMask", innerDash: [1.0, 1.5])
        b.double("509.2", "Tramway", edgeColor: "black", edge: 0.08, inner: 0.22)
        b.line("510", "Power line, cableway or ski lift", "black", 0.14,
               deco: LineDecoration(kind: .bars, sizeMM: 0.3, widthMM: 0.14, spacingMM: 0))
        b.line("511", "Major power line", "black", 0.14,
               deco: LineDecoration(kind: .bars, sizeMM: 0.8, widthMM: 0.2, spacingMM: 0))
        b.line("512.1", "Bridge or tunnel entrance", "black", 0.15,
               deco: LineDecoration(kind: .ticks, sizeMM: 0.7, widthMM: 0.15, spacingMM: 0, angleDeg: 45))
        b.line("512.2", "Underpass or tunnel", "black", 0.2, dash: [0.25, 0.2])
        b.area("512.3", "Area runnable at lower level", "white", patterns: [b.pattern(.lines, "whiteMask", size: 0.3, cc: 0.6, angle: 45)], patternOnly: true)
        b.line("513.1", "Passable wall", "black", 0.21, deco: LineDecoration(kind: .dots, sizeMM: 0.6, spacingMM: 3.75))
        b.line("513.2", "Passable retaining wall", "black", 0.21, deco: LineDecoration(kind: .halfDots, sizeMM: 0.6, spacingMM: 1.9))
        b.line("515", "Uncrossable wall", "black", 0.4)
        b.line("516", "Passable fence or railing", "black", 0.21,
               deco: LineDecoration(kind: .tags, sizeMM: 0.75, widthMM: 0.14, spacingMM: 3.75, angleDeg: 60))
        // Pairs of tags 0.75 long, 0.14 wide, 60°; 0.9 between the tags of a pair, pairs every 3.75 (ISSprOM 2019-2).
        b.line("518", "Uncrossable fence or railing", "black", 0.4,
               deco: LineDecoration(kind: .doubleTags, sizeMM: 0.75, widthMM: 0.14, spacingMM: 3.75, angleDeg: 60, pairMM: 0.9))
        b.point("519", "Crossing point", b.crossing(1.4, 1.0, 0.25, "black"))
        b.area("520", "Area that shall not be entered", "olive",
               patterns: [b.pattern(.lines, "green100", size: 0.25, cc: 0.5, angle: 45)])
        b.line("520.1", "Area that shall not be entered, bounding line", "black", 0.1)
        b.area("521", "Building", "black50")
        b.line("521.1", "Building, outline", "black", 0.14)
        b.area("522", "Canopy", "black20")
        b.point("522.1", "Pillar", [b.fill([(-0.25, -0.25), (-0.25, 0.25), (0.25, 0.25), (0.25, -0.25)], "black")])
        b.line("522.2", "Canopy, outline", "black", 0.1)
        b.point("524", "High tower", [b.dot(1.2, "black"), b.lines([(-1.05, 0), (1.05, 0)], 0.25, "black")])
        b.point("525", "Small tower", [b.lines([(-0.64, -0.64), (-0.64, 0.64), (0.64, 0.64), (0.64, -0.64)], 0.22, "black")])
        b.point("526", "Cairn, memorial, sculpture, small monument or boundary stone", [b.ring(1.0, 0.22, "black"), b.dot(0.2, "black")])
        b.point("527", "Fodder rack", [b.lines([(-0.64, -0.33), (0, 0.33), (0.64, -0.33)], 0.22, "black")])
        b.line("528", "Prominent line feature", "black", 0.21,
               deco: LineDecoration(kind: .ticks, sizeMM: 0.75, widthMM: 0.14, spacingMM: 3.75, angleDeg: 45))
        b.line("529", "Prominent uncrossable line feature", "black", 0.4,
               deco: LineDecoration(kind: .ticks, sizeMM: 0.9, widthMM: 0.14, spacingMM: 3.75, angleDeg: 45))
        b.point("530", "Prominent man-made feature – ring", [b.ring(1.0, 0.22, "black")])
        b.point("531", "Prominent man-made feature – x", b.cross(1.2, 0.22, "black"))
        b.double("532", "Stairway", edgeColor: "black", edge: 0.1, inner: 0.4, fill: "brown30")
        b.area("533", "Area with obstacles", "black50", patterns: [b.pattern(.holes, "whiteMask", size: 0.55, cc: 0.75, angle: 45)])
        // 6 Technical symbols
        b.line("601", "Magnetic north line", "black", 0.14)
        b.line("601.1", "Magnetic north line, blue", "blue", 0.18)
        b.point("602", "Registration mark", [b.ring(1.2, 0.1, "black")] + b.plus(4.0, 0.1, "black"))
        // 7 Course planning (1:4000)
        course(&b, start: 7.0, control: 6.0, finish: (5.0, 7.0), boundary: 1.0, oobLine: 0.4, sprint: true)
    }

    // MARK: Course planning (both standards; purple)

    static func course(_ b: inout Builder, start: Double, control: Double, finish: (Double, Double), boundary: Double,
                       oobLine: Double, sprint: Bool) {
        let lw = 0.35
        b.point("701", "Start", [b.triangle(start, "purpleLower", outline: lw)])
        b.point("702", "Map issue point", [b.lines([(0, -1.25), (0, 1.25)], 0.6, "purpleUpper")])
        b.point("703", "Control point", [b.circleCC(control, lw, "purpleLower")])
        b.text("704", "Control number", "purpleLower")
        b.line("705", "Course line", "purpleLower", lw)
        b.point("706", "Finish", [b.circleCC(finish.0, lw, "purpleLower"), b.circleCC(finish.1, lw, "purpleLower")])
        b.line("707", "Marked route", "purpleUpper", lw, dash: [2.0, 0.5])
        b.line("708", "Out-of-bounds boundary", "purpleLower", boundary)
        b.area("709", "Out-of-bounds area", "white", patterns: [b.pattern(.lines, "purpleUpper", size: 0.2, cc: 1.2, angle: 45)], patternOnly: true)
        b.line("709.1", "Out-of-bounds area, solid boundary", "purpleUpper", oobLine)
        b.line("709.2", "Out-of-bounds area, dashed boundary", "purpleUpper", oobLine, dash: [3.0, 0.5])
        if sprint {
            b.point("710.1", "Crossing point", b.crossing(4.5, 1.0, 0.5, "purpleLower"))
            b.line("710.2", "Crossing section", "purpleUpper", lw)
            b.area("714", "Temporary construction or closed area", "purple50")
            b.line("714.1", "Temporary construction or closed area, outline", "purpleUpper", 0.1)
        } else {
            b.point("710", "Crossing point", b.crossing(3.0, 0.6, lw, "purpleLower"))
            b.point("711", "Out-of-bounds route", b.cross(3.0, lw, "purpleUpper"))
            b.point("712", "First aid post", b.plus(4.0, 1.33, "purpleLower"))
            b.point("713", "Refreshment point",
                    [b.lines([(-1.55, 1.3), (-0.85, -1.3), (0.85, -1.3), (1.55, 1.3)], 0.4, "purpleLower")])
        }
        let r = control / 2
        b.point("715", "Continuing point after map exchange",
                [b.circleCC(control, lw, "purpleLower"), b.triangle(r * 1.2, "purpleLower", outline: lw)])
    }
}
