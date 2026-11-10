import Foundation

/// OCCA's own ISInOM symbol set (International Specification for Indoor Orienteering Maps, v6.7.3, IOF Map
/// Commission, July 2026): codes, names, sizes (paper mm at 1:700), colors (CMYK of the specification's color table)
/// and color order (§4.3). Shapes follow the specification's figures and the official OCAD set
/// "Indoor Symbols - ISInOM - 6.7.3.ocd"; curves are flattened to short lines.
///
/// Approximations (fig.) — OCCA has no symbol-along-line primitive for these:
/// - 512.1 Bridge or underpass entrance: the row of small triangles is drawn as half dots 0.7 mm every 0.7 mm.
/// - 1216 Escalator moving direction arrow / 1771.2 One-way passage (line of arrows): the chevrons are drawn as
///   slanted ticks (55°) at the chevron spacing; use 1771.1 (one large arrow) where the direction must be read.
///
/// ISInOM is never chosen from the map scale alone (see `MapStandard`): it is the default set on maps with "Indoor map
/// (ISInOM)" on (`SheetSpec.mapStandard`), and can be picked in the Symbols panel on any map.
extension OccaStandardSymbols {
    public static let isinomFileName = "OCCA ISInOM 6.7.3.occasym"
    public static let isinomLicense = "© 2026 Rizky Ajie Kurniawan. Part of OCCA. Symbol definitions follow the IOF specification ISInOM v6.7.3 (IOF Map Commission, CC BY 4.0)."

    public static func isinomFile() -> OccaSymbolFile {
        var b = Builder(colors: isinomColors())
        isinom(&b)
        return OccaSymbolFile(name: "ISInOM 6.7.3 · OCCA", standard: MapStandard.isinom.label,
                              specification: "IOF International Specification for Indoor Orienteering Maps ISInOM v6.7.3, July 2026 (mandatory from 1 September 2026)",
                              scale: MapStandard.isinom.baseScale, author: author, license: isinomLicense,
                              notes: "Sizes at 1:700. Larger scales enlarge all symbols proportionally; smaller scales (e.g. 1:1500) keep the 1:700 sizes.",
                              colors: b.colors, symbols: b.symbols.sorted { $0.number < $1.number })
    }

    // MARK: Colors (ISInOM §4.3, top → bottom; only the colors the symbols use)

    /// Color ids are the specification's color numbers ("n46" = colour 46).
    static func isinomColors() -> [OccaSymbolFile.Color] {
        func c(_ n: Int, _ name: String, _ cmyk: [Double]) -> OccaSymbolFile.Color {
            OccaSymbolFile.Color(id: "n\(n)", name: "\(n) \(name)", cmyk: cmyk.map { $0 / 100 })
        }
        return [
            c(54, "Purple for course layout", [20, 100, 0, 0]),
            c(46, "Black - underpass or tunnel (walls)", [0, 0, 0, 100]),
            c(50, "Upper purple for course planning", [20, 100, 0, 0]),
            c(903, "Dark purple for indoor funnel tapes", [45, 100, 0, 0]),
            c(914, "Orange for directions", [0, 60, 100, 0]),
            c(51, "White for course planning", [0, 0, 0, 0]),
            c(53, "Purple 50%", [10, 50, 0, 0]),
            c(902, "Indoor temporary gray 50%", [0, 0, 0, 50]),
            c(2, "Black", [0, 0, 0, 100]),
            c(915, "Out-of-bounds area", [5, 25, 0, 0]),
            c(6, "Green - point symbols", [80, 0, 100, 0]),
            c(57, "White - prominent bush or small tree", [0, 0, 0, 0]),
            c(52, "Lower purple for course planning", [20, 100, 0, 0]),
            c(48, "Dark green - hedge", [100, 0, 80, 30]),
            c(14, "Blue", [100, 0, 0, 0]),
            c(15, "Brown", [4, 50, 95, 15]),
            c(45, "White - two-level structure", [0, 0, 0, 0]),
            c(904, "Middle red for indoor stairway up", [0, 90, 90, 0]),
            c(905, "Dark red for indoor escalator up", [5, 90, 90, 20]),
            c(906, "Light red for indoor ramp up", [0, 45, 45, 0]),
            c(907, "Middle blue for indoor stairway down", [70, 35, 0, 0]),
            c(908, "Dark blue for indoor escalator down", [80, 40, 0, 20]),
            c(910, "Light blue for indoor ramp down", [35, 18, 0, 0]),
            c(42, "Brown 30% - ramp", [1, 10, 19, 3]),
            c(11, "Black 50%", [0, 0, 0, 50]),
            c(12, "Black 20%", [0, 0, 0, 20]),
            c(17, "Blue 70%", [70, 0, 0, 0]),
            c(3, "Blue 30%", [30, 0, 0, 0]),
            c(911, "Yellow for indoor lift", [0, 15, 100, 0]),
            c(19, "Brown 50% - paved area", [2, 25, 48, 8]),
            c(24, "Olive green", [38, 27, 100, 0]),
            c(913, "Green for couch/sofa", [80, 5, 20, 44]),
            c(912, "Light green for table", [20, 0, 25, 0]),
            c(901, "White for runnable area", [0, 0, 0, 0]),
        ]
    }

    // MARK: Symbols (1:700)

    static func isinom(_ b: inout Builder) {
        // 1100 Construction
        b.area("521", "Building body", "n11")
        b.area("1101", "Temporary building body", "n902")
        b.line("1102", "Outer wall", "n46", 0.8)
        b.line("1103", "Inner wall", "n46", 0.4)
        b.line("1103.1", "Temporary hidden inner wall", "n2", 0.4)
        b.line("1103.2", "Inner wall for very small rooms", "n46", 0.3)
        b.line("1103.3", "Temporary hidden inner wall for very small rooms", "n2", 0.3)
        b.line("516", "Passable fence or railing", "n2", 0.21,
               deco: LineDecoration(kind: .tags, sizeMM: 0.75, widthMM: 0.14, spacingMM: 3.75, angleDeg: 60))
        b.line("518", "Uncrossable fence or railing", "n2", 0.4,
               deco: LineDecoration(kind: .doubleTags, sizeMM: 0.75, widthMM: 0.14, spacingMM: 3.75, angleDeg: 60, pairMM: 0.9))
        b.line("1104", "Automatically closing doors", "n17", 0.3)
        b.line("1105", "Partition wall", "n11", 0.35)
        b.dotted("1106", "Curtain or flexible wall", "n11", 0.32, 0.5)
        b.point("1107", "Small pillar", [b.dot(0.7, "n2")])
        b.point("1108", "Larger pillar", [b.dot(1.58, "n2")])
        b.point("1109", "Square pillar", [b.fill([(-0.28, -0.28), (0.28, -0.28), (0.28, 0.28), (-0.28, 0.28)], "n2")])
        b.area("520", "Area that shall not be entered", "n24")
        b.line("520.2", "Area that shall not be entered (outline)", "n2", 0.2)
        b.line("1110", "Building outline of floor below", "n11", 0.1)
        b.line("1111", "Building outline of floor above", "n2", 0.15, dash: [0.8, 0.3])

        // 1200 Floor
        b.line("1201", "Step", "n15", 0.21)
        b.point("1201.1", "Slope line", [b.lines([(0, 0), (0, -0.7)], 0.21, "n15")])
        // Tags 0.18 wide reaching 0.7 from the line centre, every 0.7 mm (falling side = right of the drawing direction).
        b.line("1202", "Stage edge or steep stairway", "n15", 0.3,
               deco: LineDecoration(kind: .tags, sizeMM: 0.55, widthMM: 0.18, spacingMM: 0.7))
        b.area("1203", "Runnable area", "n901")
        b.line("1204", "Outdoor passage (outline)", "n903", 0.3)
        // Steps: brown lines 0.24 every 0.61 mm (pattern only; drawn at the brown color's level, above 1203 white).
        b.area("1205", "Stairs not leading to another floor", "n901", patterns: [b.pattern(.lines, "n15", size: 0.24, cc: 0.61, angle: 90)])
        b.lastSymbolPriority("n15")
        b.area("1206", "Stairway leading to next floor up", "n904")
        b.area("1207", "Stairway leading to next floor down", "n907")
        b.line("1207.1", "White gap between up/down stairs/escalator/ramp", "n45", 0.4)
        b.point("1208", "Spiral stairway leading to next floor up", spiral(b, [("n904", -0.0, 0, 180, -90)]))
        b.point("1209", "Spiral stairway leading to next floor down", spiral(b, [("n907", 0, 0, 180, -90)]))
        // Up and down: two sectors split along a 45° white gap (as in the OCAD set).
        b.point("1210", "Spiral stairway to next floor up and down",
                spiral(b, [("n904", -0.12, 0, 180, 48.7), ("n907", 0, -0.12, 41.6, -90)]))
        b.point("1211", "Spiral stairway to next floor down and up",
                spiral(b, [("n907", -0.12, 0, 180, 48.7), ("n904", 0, -0.12, 41.6, -90)]))
        // (fig.) Small triangles 0.7 wide every 0.7 mm in OCAD; drawn as half dots.
        b.line("512.1", "Bridge or underpass entrance", "n2", 0.05,
               deco: LineDecoration(kind: .halfDots, sizeMM: 0.7, spacingMM: 0.7))
        b.area("512.3", "Area accessible in two levels in same floor", "n19", patterns: [b.pattern(.lines, "n45", size: 0.3, cc: 0.6, angle: 45)])
        b.line("512.2", "Underpass or tunnel walls / back of stairs", "n2", 0.2, dash: [0.25, 0.2])
        b.area("1214", "Escalator to next floor up", "n905")
        b.area("1215", "Escalator to next floor down", "n908")
        // (fig.) White chevrons 1.84 high every 0.6 mm, arms at 55°: drawn as slanted ticks.
        b.line("1216", "Escalator moving direction arrow", "n45", 0.01,
               deco: LineDecoration(kind: .ticks, sizeMM: 2.25, widthMM: 0.2, spacingMM: 0.6, angleDeg: 55))
        b.area("1217", "Lift", "n911")
        b.area("1218", "Ramp", "n42")
        b.area("1219", "Ramp to next floor up", "n906")
        b.area("1220", "Ramp to next floor down", "n910")
        b.text("1221", "Stairway identity letter", "n54")
        b.area("1222", "Out-of-bounds area", "n915")
        b.line("1223", "Distinct floor marking", "n2", 0.1)

        // 1300 Water
        b.area("301", "Uncrossable body of water", "n14")
        b.area("301.1", "Uncrossable body of water, dominant (70 %)", "n17")
        b.line("301.2", "Uncrossable body of water (outline)", "n2", 0.18)
        b.area("302", "Shallow body of water", "n3")
        b.line("302.4", "Shallow body of water (outline)", "n14", 0.18)
        // "V" 0.96 × 1.07 with 0.24 arms; the opening faces the wall.
        b.point("1302", "Toilet or urinal", [b.fill([(-0.48, 0), (0, -1.08), (0.48, 0), (0.22, 0), (0, -0.53), (-0.23, 0)], "n14")])
        b.point("1303", "Shower", [b.circleCC(0.7, 0.21, "n14")])
        b.point("1304", "Sink", [b.lines(ocadPath([(-0.36, 0, 0), (-0.39, -0.32, 1), (-0.30, -0.47, 2), (0, -0.47, 0),
                                                  (0.31, -0.47, 1), (0.38, -0.35, 2), (0.35, 0, 0)]), 0.21, "n14")])
        b.point("1305", "Prominent water feature",
                [(0.57, 0.18), (0.36, -0.48), (-0.36, -0.48), (-0.57, 0.18), (0, 0.6)].map { b.lines([(0, 0), $0], 0.25, "n14") })

        // 1400 Furniture
        b.area("1401", "Table or bench", "n912")
        b.area("1402", "Cupboard or tall shelf", "n12")
        b.area("1403", "Couch / sofa", "n913")
        b.line("1404", "Furniture outline", "n2", 0.16)
        b.point("417", "Large tree or plant", [b.dot(1.4, "n57"), b.circleCC(0.95, 0.25, "n6")])
        b.point("418", "Tree or plant", [b.dot(0.2, "n57"), b.circleCC(0.5, 0.3, "n6")])
        b.area("1407", "Area with obstacles", "n901", patterns: [b.pattern(.dots, "n11", size: 0.55, cc: 1.3, angle: 45)])
        b.lastSymbolPriority("n11")
        b.area("1408", "Area with dense obstacles", "n901", patterns: [b.pattern(.dots, "n11", size: 0.6, cc: 0.78, angle: 45)])
        b.lastSymbolPriority("n11")
        b.point("526", "Sculpture or small monument", [b.circleCC(0.8, 0.16, "n2"), b.dot(0.14, "n2")])
        b.point("530", "Prominent feature – ring", [b.circleCC(0.8, 0.16, "n2")])
        b.point("531", "Prominent feature – cross",
                [b.lines([(-0.52, -0.52), (0.52, 0.52)], 0.22, "n2"), b.lines([(-0.52, 0.52), (0.52, -0.52)], 0.22, "n2")])

        // 1700 Directions and map layout
        b.point("1771.1", "One-way passage - one large arrow",
                [b.fill([(0.72, 1.82), (-0.57, 0), (0.72, -1.87), (1.82, -1.87), (0.54, 0), (1.82, 1.82)], "n914")])
        // (fig.) Orange chevrons 1.84 high, 0.55 thick, at 55°: drawn as slanted ticks (no main line).
        b.line("1771.2", "One-way passage (line of arrows)", "n914", 0.01,
               deco: LineDecoration(kind: .ticks, sizeMM: 2.25, widthMM: 0.45, spacingMM: 1.16, angleDeg: 55))
        b.point("1772", "Compulsory crossing", compulsoryCrossing(b))
        b.point("1773", "Compulsory diagonal switch", diagonalSwitch(b, oneWay: false))
        b.point("1774", "Compulsory diagonal one-way switch", diagonalSwitch(b, oneWay: true))
        b.line("1775", "Uncrossable border", "n903", 0.7)
        b.text("1781", "Text", "n2")
        b.text("1782", "Floor designator", "n907")
        b.text("1783", "Building designator", "n6")
        b.line("1784", "Floor level separation line on map print", "n907", 2.5)
        b.line("1785", "Thin level separation line on map print", "n907", 1.25)
        b.point("1720", "Map flip point",
                [(2.28, 0.72), (1.44, -1.92), (-1.44, -1.92), (-2.28, 0.72), (0, 2.4)].map { b.lines([(0, 0), $0], 1.4, "n48") })

        // 700 Course print (sizes as in ISSprOM at 1:4000; colors as in "Indoor Course Setting - 6.7.3.ocd")
        let lw = 0.35
        b.point("701", "Start", [b.triangle(7.0, "n52", outline: lw)])
        b.point("702", "Map issue point", [b.lines([(0, -1.0), (0, 1.0)], 0.48, "n50")])
        b.point("703", "Control point", [b.circleCC(6.0, lw, "n52")])
        b.point("1703", "Alternate control point", [b.circleCC(6.0, lw, "n52"), b.dot(0.6, "n52")])
        b.text("704", "Control number", "n50")
        b.line("705", "Course line", "n52", lw)
        b.point("706", "Finish", [b.circleCC(5.0, lw, "n52"), b.circleCC(7.0, lw, "n52")])
        b.line("707", "Marked route", "n50", lw, dash: [2.0, 0.75])
        b.line("708", "Out-of-bounds boundary", "n52", 1.0)
        b.area("709", "Out-of-bounds area", "n901", patterns: [b.pattern(.lines, "n50", size: 0.2, cc: 0.8, angle: 45),
                                                              b.pattern(.lines, "n50", size: 0.2, cc: 0.8, angle: 135)])
        b.lastSymbolPriority("n50")
        b.line("709.4", "Out-of-bounds area boundary", "n50", 0.4)
        b.area("714", "Temporary construction or closed area", "n53")
        b.line("714.1", "Temporary construction or closed area, outline", "n52", 0.1)
        b.point("715", "Continuing point after map exchange", [b.circleCC(6.0, lw, "n52"), b.triangle(4.69, "n52", outline: lw)])
    }

    // MARK: Shapes

    /// OCAD path → polyline: points flagged 1 / 2 are the control points of a cubic Bézier between their neighbours.
    static func ocadPath(_ pts: [(Double, Double, Int)], steps: Int = 8) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        var i = 0
        while i < pts.count {
            let p = pts[i]
            if p.2 == 1, i + 2 < pts.count, out.last != nil {
                let a = out.last!, c1 = p, c2 = pts[i + 1], e = pts[i + 2]
                for k in 1...steps {
                    let t = Double(k) / Double(steps), u = 1 - t
                    let x = u * u * u * a.0 + 3 * u * u * t * c1.0 + 3 * u * t * t * c2.0 + t * t * t * e.0
                    let y = u * u * u * a.1 + 3 * u * u * t * c1.1 + 3 * u * t * t * c2.1 + t * t * t * e.1
                    out.append(((x * 1000).rounded() / 1000, (y * 1000).rounded() / 1000))
                }
                i += 3
            } else {
                out.append((p.0, p.1))
                i += 1
            }
        }
        return out
    }

    /// Spiral stairway: colored sectors (apex offset, arc from → to in degrees, clockwise) of radius 1.47 (ø min. 3.0
    /// with the 0.18 rim), the black rim over the same 270° and a ø0.18 centre dot.
    static func spiral(_ b: Builder, _ sectors: [(color: String, ax: Double, ay: Double, from: Double, to: Double)]) -> [PointElement] {
        let r = 1.47
        func arc(_ from: Double, _ to: Double) -> [(Double, Double)] {
            let n = max(2, Int(abs(from - to) / 10))
            return (0...n).map { i in
                let a = (from + (to - from) * Double(i) / Double(n)) * .pi / 180
                return ((r * cos(a) * 1000).rounded() / 1000, (r * sin(a) * 1000).rounded() / 1000)
            }
        }
        let fills = sectors.map { s in b.fill([(s.ax, s.ay)] + arc(s.from, s.to), s.color) }
        return fills + [b.lines(arc(180, -90), 0.18, "n2"), b.dot(0.18, "n2")]
    }

    /// 1772: two crossing orange arrows (straight on, no turning) with corner arrow heads, on white halos.
    static func compulsoryCrossing(_ b: Builder) -> [PointElement] {
        let o = "n914", w = "n51"
        func l(_ pts: [(Double, Double, Int)], _ c: String) -> PointElement { b.lines(ocadPath(pts), c == o ? 0.25 : 0.4, c) }
        return [
            l([(-0.84, -0.87, 0), (-0.01, -0.04, 0)], o), l([(0.85, -0.87, 0), (0.16, -0.18, 0)], o), l([(-0.19, 0.17, 0), (-0.91, 0.88, 0)], o),
            l([(0.18, -0.34, 0), (0.20, -0.32, 1), (0.23, -0.30, 2), (0.25, -0.28, 0), (0.40, -0.14, 1), (0.40, 0.11, 2), (0.25, 0.25, 0),
               (0.11, 0.40, 1), (-0.14, 0.40, 2), (-0.28, 0.25, 0)], o),
            l([(0.38, 0.36, 0), (0.86, 0.84, 0)], o),
            l([(0.27, 0.88, 0), (0.89, 0.88, 0), (0.89, 0.26, 0)], o), l([(-0.91, 0.29, 0), (-0.91, 0.88, 0), (-0.29, 0.88, 0)], o),
            l([(-0.32, -0.91, 0), (-0.91, -0.91, 0), (-0.91, -0.29, 0)], o), l([(0.89, -0.27, 0), (0.89, -0.91, 0), (0.27, -0.91, 0)], o),
            l([(-0.79, -0.81, 0), (0.79, 0.76, 0)], w), l([(0.77, -0.80, 0), (-0.83, 0.80, 0)], w),
            l([(0.23, 0.87, 0), (0.89, 0.87, 0), (0.89, 0.21, 0)], w), l([(-0.91, 0.24, 0), (-0.91, 0.87, 0), (-0.23, 0.87, 0)], w),
            l([(-0.27, -0.91, 0), (-0.90, -0.91, 0), (-0.90, -0.23, 0)], w), l([(0.89, -0.20, 0), (0.89, -0.90, 0), (0.21, -0.90, 0)], w),
        ]
    }

    /// 1773 / 1774: two lanes switching diagonally (1774: one way, arrow heads at one end only), on white halos.
    static func diagonalSwitch(_ b: Builder, oneWay: Bool) -> [PointElement] {
        let o = "n914", w = "n51"
        func l(_ pts: [(Double, Double)], _ c: String) -> PointElement { b.lines(pts, c == o ? 0.25 : 0.4, c) }
        func a(_ pts: [(Double, Double, Int)]) -> PointElement { b.fill(ocadPath(pts), o) }
        // Crossing loop (the lane passing under the other) and its small tail.
        let loop = a([(-0.11, -0.42, 0), (-0.27, -0.23, 1), (-0.31, -0.03, 2), (-0.17, 0.12, 0), (-0.06, 0.24, 1), (0.16, 0.18, 2),
                      (0.23, 0.03, 0), (oneWay ? 0.32 : 0.35, oneWay ? 0.14 : 0.16, 1), (oneWay ? 0.29 : 0.31, oneWay ? 0.12 : 0.11, 2),
                      (oneWay ? 0.30 : 0.32, 0.17, 0), (0.32, 0.26, 1), (0.24, 0.29, 2), (0.17, 0.34, 0), (-0.03, 0.45, 1),
                      (-0.18, 0.40, 2), (-0.34, 0.25, 0), (-0.51, 0.07, 1), (-0.47, -0.20, 2), (-0.31, -0.53, 0)])
        let tail = a([(-0.40, 0.61, 0), (-0.30, 0.46, 0), (-0.33, 0.43, 1), (-0.37, 0.44, 2), (-0.40, 0.41, 0), (-0.43, 0.38, 1),
                      (-0.43, 0.35, 2), (-0.46, 0.32, 0), (-0.62, 0.50, 0)])
        var e: [PointElement] = [
            l([(-1.19, -0.60), (-0.41, -0.60), oneWay ? (-0.30, -0.46) : (-0.21, -0.35)], o),
            l([(1.20, -0.60), (0.40, -0.60), (0.01, -0.11)], o),
            l([(0.19, oneWay ? 0.18 : 0.17), (0.33, 0.34)], o), l([(0.33, 0.34), (0.49, 0.54), (1.20, 0.54)], o),
            loop, tail, l([(-1.20, 0.54), (-0.50, 0.54)], o),
        ]
        if oneWay {
            e += [l([(-0.33, -0.50), (-0.20, -0.34)], o),
                  l([(-0.82, 0.12), (-1.24, 0.53), (-0.81, 0.96)], o), l([(0.84, 0.96), (1.25, 0.54), (0.82, 0.12)], o),
                  l([(0.77, 1.02), (1.24, 0.54), (0.78, 0.08)], w), l([(-0.77, 0.07), (-1.24, 0.53), (-0.76, 1.01)], w),
                  l([(-1.20, -0.60), (-0.41, -0.60), (0.37, 0.40)], w), l([(1.20, -0.60), (0.40, -0.60), (-0.43, 0.45)], w),
                  l([(0.37, 0.40), (0.48, 0.54), (1.06, 0.54)], w), l([(-0.39, 0.40), (-0.50, 0.54), (-1.02, 0.54)], w)]
        } else {
            e += [l([(-0.82, 0.11), (-1.24, 0.52), (-0.81, 0.95)], o), l([(0.84, 0.95), (1.25, 0.53), (0.82, 0.11)], o),
                  l([(-0.84, -1.02), (-1.25, -0.61), (-0.83, -0.18)], o), l([(0.82, -0.18), (1.23, -0.60), (0.81, -1.02)], o),
                  l([(-1.06, -0.59), (-0.41, -0.59), (0.37, 0.41)], w), l([(1.05, -0.59), (0.40, -0.59), (-0.43, 0.46)], w),
                  l([(0.37, 0.41), (0.48, 0.55), (1.06, 0.55)], w), l([(-0.39, 0.41), (-0.50, 0.55), (-1.02, 0.55)], w),
                  l([(0.77, 1.01), (1.24, 0.53), (0.78, 0.07)], w), l([(-0.77, 0.06), (-1.24, 0.52), (-0.76, 1.00)], w),
                  l([(0.75, -0.13), (1.22, -0.61), (0.76, -1.07)], w), l([(-0.79, -1.08), (-1.26, -0.62), (-0.78, -0.14)], w)]
        }
        return e
    }
}

extension OccaStandardSymbols.Builder {
    /// Pattern-only areas (white fill): drawn at their pattern color's level, as OCAD does, so e.g. 1205 steps show
    /// above 1203 runnable area.
    mutating func lastSymbolPriority(_ color: String) {
        symbols[symbols.count - 1].colorPriority = prio(color)
    }
}
