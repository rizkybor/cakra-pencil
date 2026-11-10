@testable import CakraCore
import XCTest

/// OCCA's own ISOM 2017-2 / ISSprOM 2019-2 / ISInOM 6.7.3 symbol sets (.occasym), checked against the IOF specifications.
///
/// Regenerate the bundled files after changing `OccaStandardSymbols`:
///     OCCA_WRITE_SYMBOL_SETS=1 swift test --filter OccaStandardSymbolsTests
final class OccaStandardSymbolsTests: XCTestCase {
    private var bundleDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../CakraPencil/Resources/SymbolSets/OCCA").standardized
    }

    private func eq(_ a: Double?, _ b: Double, _ msg: String = "") { XCTAssertEqual(a ?? -1, b, accuracy: 0.0005, msg) }

    private func sym(_ f: OccaSymbolFile, _ code: String) throws -> MapSymbol {
        try XCTUnwrap(f.symbols.first { $0.code == code }, "\(code) in \(f.name)")
    }

    func testWriteOrVerifyBundledFiles() throws {
        let files = [(OccaStandardSymbols.isomFileName, OccaStandardSymbols.isomFile()),
                     (OccaStandardSymbols.issprFileName, OccaStandardSymbols.issprFile()),
                     (OccaStandardSymbols.isinomFileName, OccaStandardSymbols.isinomFile())]
        if ProcessInfo.processInfo.environment["OCCA_WRITE_SYMBOL_SETS"] != nil {
            try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
            for (name, file) in files { try file.encoded().write(to: bundleDir.appendingPathComponent(name), options: .atomic) }
        }
        for (name, file) in files {
            let bundled = try OccaSymbolFile.read(Data(contentsOf: bundleDir.appendingPathComponent(name)))
            XCTAssertEqual(bundled.symbols, file.symbols, "\(name) is up to date (regenerate with OCCA_WRITE_SYMBOL_SETS=1)")
            XCTAssertEqual(bundled.colors, file.colors)
        }
    }

    func testISOM() throws {
        let f = OccaStandardSymbols.isomFile()
        XCTAssertEqual(f.scale, 15000)
        XCTAssertGreaterThan(f.symbols.count, 110)
        XCTAssertEqual(Set(f.symbols.map(\.number)).count, f.symbols.count, "Unique codes")
        eq(try sym(f, "101.0").lineStyle?.widthMM, 0.14, "101 contour")
        eq(try sym(f, "102.0").lineStyle?.widthMM, 0.25, "102 index contour")
        XCTAssertEqual(try sym(f, "103.0").lineStyle?.dashMM, [2.0, 0.2], "103 form line")
        let road = try sym(f, "502.0").lineStyle
        eq(road?.casing?.innerWidthMM, 0.3); eq(road?.widthMM, 0.58, "502: infill 0.3 + 2 × 0.14")
        XCTAssertEqual(try sym(f, "505.0").lineStyle?.dashMM, [2.0, 0.25], "505 footpath")
        eq(try sym(f, "204.0").pointElements?.first?.diameterMM, 0.4, "204 boulder")
        XCTAssertEqual(try sym(f, "214.0").colorHex, "#A6A6A6", "214 bare rock 35 %")
        eq(try sym(f, "703.0").pointElements?.first?.diameterMM, 5.0, "703 control ø5.0")
        let finish = try sym(f, "706.0").pointElements?.map(\.diameterMM).sorted()
        XCTAssertEqual(finish, [4.0, 6.0], "706 finish ø4/ø6")
        XCTAssertNil(f.symbols.first { $0.code == "411.0" }, "No 411 in ISOM 2017-2")
        XCTAssertTrue(try sym(f, "308.0").isEnabled, "Pattern-only marsh drawn as its pattern, on by default")
        XCTAssertNotNil(try sym(f, "308.0").patterns, "Marsh pattern stored")
        XCTAssertNotNil(try sym(f, "516.0").decoration, "Fence tags stored")
        eq(try sym(f, "518.0").decoration?.pairMM, 0.6, "518 impassable fence: double tags 0.6 apart")
    }

    func testISSprOM() throws {
        let f = OccaStandardSymbols.issprFile()
        XCTAssertEqual(f.scale, 4000)
        XCTAssertGreaterThan(f.symbols.count, 110)
        XCTAssertEqual(Set(f.symbols.map(\.number)).count, f.symbols.count, "Unique codes")
        eq(try sym(f, "101.0").lineStyle?.widthMM, 0.21, "101")
        eq(try sym(f, "102.0").lineStyle?.widthMM, 0.30, "102")
        XCTAssertEqual(try sym(f, "103.0").lineStyle?.dashMM, [3.0, 0.3], "103")
        eq(try sym(f, "415.0").lineWidthMM, 0.15, "415 Rev 6")
        let path = try sym(f, "505.0").lineStyle
        eq(path?.casing?.innerWidthMM, 0.35); eq(path?.widthMM, 0.59, "505: 0.35 IM + 2 × 0.12 edges")
        XCTAssertEqual(path?.dashMM, [2.0, 0.25])
        XCTAssertEqual(try sym(f, "521.0").colorHex, "#808080", "521 building black 50 %")
        eq(try sym(f, "703.0").pointElements?.first?.diameterMM, 6.0, "703 control ø6.0")
        XCTAssertEqual(try sym(f, "706.0").pointElements?.map(\.diameterMM).sorted(), [5.0, 7.0], "706 finish ø5/ø7")
        XCTAssertNotNil(f.symbols.first { $0.code == "411.0" }, "411 uncrossable vegetation")
        XCTAssertNotNil(f.symbols.first { $0.code == "533.0" }, "533 Rev 6")
        XCTAssertNil(f.symbols.first { $0.code == "104.1" }, "No 104.1 in ISSprOM (the 1.65 is hidden text in the PDF)")
        // 518: 0.4 line, pairs of tags 0.75 × 0.14 at 60°, 0.9 apart in a pair, a pair every 3.75.
        let fence = try sym(f, "518.0")
        eq(fence.lineStyle?.widthMM, 0.4, "518 line")
        let tags = try XCTUnwrap(fence.decoration)
        XCTAssertEqual(tags.kind, .doubleTags, "518 pairs of tags")
        // Tags reach 0.75 from the centre line: 0.55 beyond the edge of the 0.4 line.
        eq(tags.sizeMM, 0.55); eq(tags.widthMM, 0.14); eq(tags.spacingMM, 3.75); eq(tags.angleDeg, 60); eq(tags.pairMM, 0.9)
    }

    func testISInOM() throws {
        let f = OccaStandardSymbols.isinomFile()
        XCTAssertEqual(f.scale, 700)
        XCTAssertEqual(f.standard, "ISInOM 6.7.3")
        XCTAssertEqual(Set(f.symbols.map(\.number)).count, f.symbols.count, "Unique codes")
        XCTAssertGreaterThanOrEqual(f.symbols.count, 90)
        eq(try sym(f, "1102.0").lineStyle?.widthMM, 0.8, "1102 outer wall")
        eq(try sym(f, "1103.0").lineStyle?.widthMM, 0.4, "1103 inner wall")
        eq(try sym(f, "1103.2").lineStyle?.widthMM, 0.3, "1103.2 small rooms")
        XCTAssertEqual(try sym(f, "1106.0").lineStyle?.dashMM.map { $0[0] + $0[1] } ?? 0, 0.5, accuracy: 0.001, "1106 dots every 0.5")
        eq(try sym(f, "1108.0").pointElements?.first?.diameterMM, 1.58, "1108 ø1.58")
        XCTAssertEqual(try sym(f, "1206.0").colorHex, "#FF1919", "1206 middle red 0/90/90/0")
        XCTAssertEqual(try sym(f, "1207.0").colorHex, "#4DA6FF", "1207 middle blue 70/35/0/0")
        XCTAssertEqual(try sym(f, "521.0").colorHex, "#808080", "521 black 50 %")
        eq(try sym(f, "703.0").pointElements?.first?.diameterMM, 6.0, "703 ø6.0")
        XCTAssertEqual(try sym(f, "707.0").lineStyle?.dashMM, [2.0, 0.75], "707 dash 2.0 / gap 0.75")
        XCTAssertEqual(try sym(f, "709.0").patterns?.count, 2, "709 cross hatch")
        XCTAssertEqual(try sym(f, "1205.0").category, .indoorFloor)
        XCTAssertEqual(try sym(f, "1401.0").category, .indoorFurniture)
        // Pattern-only areas are drawn at their pattern color's level (1205 steps above 1203 runnable area).
        XCTAssertLessThan(try sym(f, "1205.0").colorPriority ?? 99, try sym(f, "1203.0").colorPriority ?? -1)
        // Walls (colour 46) above the course overprint, temporary hidden walls (colour 2) below 1101 temporary gray.
        XCTAssertLessThan(try sym(f, "1103.0").colorPriority ?? 99, try sym(f, "705.0").colorPriority ?? -1)
        XCTAssertGreaterThan(try sym(f, "1103.1").colorPriority ?? -1, try sym(f, "1101.0").colorPriority ?? 99)
    }

    /// ISInOM is an extra standard: never chosen from the scale, the set is sized from 1:700 (enlarged, never reduced).
    func testISInOMStandardAndSizing() throws {
        XCTAssertEqual(MapStandard.for(scale: 700), .issprom, "Automatic choice stays ISSprOM for large scales")
        XCTAssertEqual(MapStandard.isinom.baseScale, 700)
        let set = OccaStandardSymbols.isinomFile().symbolSet(sourceFile: OccaStandardSymbols.isinomFileName)
        XCTAssertEqual(set.standard, .isinom)
        eq(set.sizeFactor(forMapScale: 700), 1)
        eq(set.sizeFactor(forMapScale: 500), 1.4, "1:500 = 140 %")
        eq(set.sizeFactor(forMapScale: 1500), 1, "Smaller scales keep the 1:700 sizes")
        eq(set.sizeFactor(forMapScale: 4000), 1)
        eq(try XCTUnwrap(set.scaled(by: 1.4).symbols.first { $0.code == "1102.0" }).lineStyle?.widthMM, 1.12)
        // Sprint sets keep their own rules.
        XCTAssertEqual(OccaStandardSymbols.issprFile().symbolSet(sourceFile: "x").standard, .issprom)
        let course = CourseStyle.standard(scale: 500, standard: .isinom)
        eq(course.controlDiameterMM, 8.4); eq(course.lineWidthMM, 0.49)
        eq(CourseStyle.standard(scale: 700, standard: .isinom).controlDiameterMM, 6)
        eq(CourseStyle.standard(scale: 1000, standard: .isinom).finishOuterMM, 7, "Not reduced")
    }

    /// IOF "Printing and Colour Definitions" Rev 4 (p.6): CMYK values and the colour order of each standard.
    func testColorsRev4() {
        let rows = OccaStandardSymbols.colorRows
        func row(_ id: String) -> OccaStandardSymbols.IOFColorRow { rows.first { $0.id == id }! }
        XCTAssertEqual(row("brownLine").cmyk, [25, 75, 100, 0], "Rev 4 brown")
        XCTAssertEqual(row("brown50Road").cmyk, [10, 35, 50, 0])
        XCTAssertEqual(row("brown30Paved").cmyk, [6, 23, 33, 0])
        XCTAssertEqual(row("green100").cmyk, [80, 0, 100, 0])
        XCTAssertEqual(row("green60").cmyk, [48, 0, 60, 0])
        XCTAssertEqual(row("green30").cmyk, [24, 0, 30, 0])
        XCTAssertEqual(row("olive").cmyk, [38, 27, 100, 0])
        XCTAssertEqual(row("olive").name, "Olive green")
        XCTAssertEqual(row("purple50").cmyk, [18, 43, 0, 0], "Purple 50 % is its own CMYK, not a screen")
        XCTAssertEqual(row("yellow75").cmyk, [0, 20, 59, 0])
        XCTAssertEqual(row("yellow50").cmyk, [0, 14, 40, 0])
        XCTAssertEqual(row("purpleLower").hex, "#A626FF")
        XCTAssertEqual(row("black50").hex, "#808080")

        // The order of each standard, top → bottom, exactly as the table (OCCA additions: white for point symbols,
        // yellow 75 % in ISSprOM, paper white).
        let isom = OccaStandardSymbols.colors(for: .isom).map(\.id)
        XCTAssertEqual(isom, ["purpleUpper", "whiteRailroad", "black", "bluePoint", "brownPoint", "whitePoint", "greenPoint", "blueLine",
                              "darkGreenEdge", "brownLine", "purpleLower", "brown50Road", "blackRoadOutline", "black50", "black20", "blue",
                              "blue70", "blue50", "whiteOverGreen", "brown50Paved", "olive", "green100", "green60", "green30", "black35",
                              "whiteOverYellow", "blackCultivated", "yellow100", "yellow75", "yellow50", "white"])
        let sprint = OccaStandardSymbols.colors(for: .issprom).map(\.id)
        XCTAssertEqual(sprint, ["purpleUpper", "whiteCourse", "purple50", "whiteRailroad", "black", "whitePoint", "greenPoint", "purpleLower",
                                "darkGreenLine", "bluePointLine", "brown", "whiteStripes", "brown50Road", "brown30Road", "blackRoadOutline",
                                "black50", "black20", "blue", "blue70", "blue50", "blue30", "whiteOverGreen", "brown50Paved", "brown30Paved",
                                "olive", "darkGreenArea", "green100", "green60", "green30", "black35", "whiteOverYellow", "blackCultivated",
                                "yellow100", "yellow75", "yellow50", "white"])
        // The .occasym files carry exactly that table.
        XCTAssertEqual(OccaStandardSymbols.isomFile().colors.map(\.id), isom)
        XCTAssertEqual(OccaStandardSymbols.issprFile().colors.map(\.id), sprint)
    }

    /// Symbols sit at the colour level of their role (lake below contours, road edges above screens, pattern-only areas
    /// at their pattern colour, purple placement…).
    func testSymbolColorLevels() throws {
        func p(_ f: OccaSymbolFile, _ code: String) throws -> Int { try XCTUnwrap(try sym(f, code).colorPriority, code) }
        for f in [OccaStandardSymbols.isomFile(), OccaStandardSymbols.issprFile()] {
            XCTAssertLessThan(try p(f, "101.0"), try p(f, "301.0"), "\(f.standard): contours above the lake (blue area)")
            XCTAssertLessThan(try p(f, "308.0"), try p(f, "410.0"), "\(f.standard): marsh pattern above green")
            XCTAssertLessThan(try p(f, "308.0"), try p(f, "401.0"), "\(f.standard): marsh pattern above yellow")
            XCTAssertLessThan(try p(f, "208.0"), try p(f, "403.0"), "\(f.standard): boulder field above rough open land")
            XCTAssertLessThan(try p(f, "709.0"), try p(f, "521.0"), "\(f.standard): 709 hatching (upper purple) above buildings")
            XCTAssertEqual(try p(f, "709.0"), ColorHierarchy.upperPurplePriority())
            XCTAssertEqual(try p(f, "705.0"), ColorHierarchy.lowerPurplePriority())
            XCTAssertLessThan(try p(f, "515.0"), try p(f, "705.0"), "\(f.standard): black above lower purple")
            XCTAssertLessThan(try p(f, "214.0"), try p(f, "412.0"), "\(f.standard): bare rock above cultivated land")
            // Point masks sit at "white over green and brown": above the screens, below brown / blue lines and the course.
            let tree = try XCTUnwrap(try sym(f, "417.0").pointElements)
            let mask = try XCTUnwrap(tree.first { $0.colorHex == "#FFFFFF" }).priority
            XCTAssertGreaterThan(mask, try p(f, "101.0"), "\(f.standard): 417 mask below contours")
            XCTAssertGreaterThan(mask, try p(f, "705.0"), "\(f.standard): 417 mask below lower purple")
            XCTAssertLessThan(mask, try p(f, "410.0"), "\(f.standard): 417 mask above green screens")
        }
        let isom = OccaStandardSymbols.isomFile(), sprint = OccaStandardSymbols.issprFile()
        // Road outline above screens and below the road infill; railway black body below its white dashes.
        let road = try sym(isom, "502.0")
        XCTAssertLessThan(road.colorPriority ?? 99, road.casingPriority ?? -1)
        XCTAssertLessThan(road.casingPriority ?? 99, try p(isom, "521.1"), "Road edges above black 50 %")
        XCTAssertLessThan(try p(isom, "502.0"), try p(isom, "501.0"), "Road infill above paved area")
        let rail = try sym(isom, "509.0")
        XCTAssertEqual(rail.casingPriority, OccaStandardSymbols.colorRow("black"))
        XCTAssertEqual(rail.colorPriority, OccaStandardSymbols.colorRow("whiteRailroad"))
        XCTAssertLessThan(try p(isom, "302.1"), try p(isom, "101.0"), "ISOM: blue lines above brown lines")
        XCTAssertLessThan(try p(isom, "101.0"), try p(isom, "705.0"), "ISOM: brown lines above lower purple")
        XCTAssertGreaterThan(try p(sprint, "101.0"), try p(sprint, "705.0"), "ISSprOM: brown below lower purple")
        XCTAssertLessThan(try p(sprint, "714.0"), try p(sprint, "521.0"), "ISSprOM 714 (upper purple 50 %) near the top")
        XCTAssertEqual(try p(sprint, "704.0"), ColorHierarchy.upperPurplePriority(), "ISSprOM 704 upper purple")
        XCTAssertEqual(try p(isom, "704.0"), ColorHierarchy.lowerPurplePriority(), "ISOM 704 lower purple")
        XCTAssertLessThan(try p(sprint, "411.0"), try p(sprint, "410.0"), "Dark green above green")
        XCTAssertGreaterThan(try p(sprint, "411.0"), try p(sprint, "302.0"), "Dark green area below blue screens")
        XCTAssertLessThan(try p(sprint, "512.3"), try p(sprint, "501.0"), "512.3 white stripes above paved area")
    }

    /// Symbols from other sets (own color tables) get positions in OCCA's IOF order, so they layer with OCCA symbols.
    func testColorOrderAcrossSets() throws {
        func i(_ id: String) -> Int { OccaStandardSymbols.colorRow(id) }
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#000000", kind: .line), i("black"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#000000", kind: .area), i("black"), "Black area: not the cultivated-land black")
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#000000", kind: .line, edge: true), i("blackRoadOutline"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#FFBA36", kind: .area), i("yellow100"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#FFFFFF", kind: .area), i("white"), "White area = forest (bottom)")
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#FFFFFF", kind: .point), i("whiteOverGreen"), "White point element = mask")
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#33FF00", kind: .point), i("greenPoint"), "Green point above green screens")
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#33FF00", kind: .area), i("green100"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#00FFFF", kind: .line, standard: .isom), i("blueLine"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#00FFFF", kind: .line, standard: .issprom), i("bluePointLine"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#00FFFF", kind: .area, standard: .issprom), i("blue"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#CC5A00", kind: .line, standard: .isom), i("brownLine"), "Nearest color (BOF brown)")
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#CC5A00", kind: .line, standard: .issprom), i("brown"))
        // A BOF-like footpath (black edges, light brown fill, own table priority 40) ends up above yellow.
        var path = MapSymbol(number: 505_000, name: "Footpath", kind: .line, colorHex: "#F1CEB3", lineWidthMM: nil, isEnabled: true,
                             lineStyle: LineStyle(colorHex: "#F1CEB3", widthMM: 0.45, casing: LineStyle.Casing(colorHex: "#000000", innerWidthMM: 0.25)))
        path.colorPriority = 40
        path.casingPriority = 41
        let n = path.withIOFColorOrder()
        XCTAssertEqual(n.casingPriority, i("blackRoadOutline"), "Edges on the road outline color")
        XCTAssertLessThan(n.colorPriority ?? 99, n.casingPriority ?? -1, "Fill above its edges")
        XCTAssertLessThan(n.colorPriority ?? 99, i("yellow100"))
        // Pattern-only areas of other sets: the pattern colour's level, not white at the bottom.
        var marsh = MapSymbol(number: 308_000, name: "Marsh", kind: .area, colorHex: "#FFFFFF", lineWidthMM: nil, isEnabled: true)
        marsh.patterns = [AreaPattern(kind: .lines, colorHex: "#00FFFF", sizeMM: 0.1, spacingMM: 0.3, angleDeg: 90)]
        XCTAssertEqual(marsh.withIOFColorOrder().colorPriority, i("blue"))
        // Point elements of other sets each get their level (417-like: white mask + green ring).
        var tree = MapSymbol(number: 417_000, name: "Tree", kind: .point, colorHex: "#33FF00", lineWidthMM: nil, isEnabled: true,
                             pointElements: [PointElement(kind: .dot, colorHex: "#FFFFFF", priority: 90, lineWidthMM: 0, diameterMM: 1.1, points: [Point2D(x: 0, y: 0)]),
                                             PointElement(kind: .circle, colorHex: "#33FF00", priority: 20, lineWidthMM: 0.18, diameterMM: 0.72, points: [Point2D(x: 0, y: 0)])])
        tree = tree.withIOFColorOrder()
        XCTAssertEqual(tree.pointElements?.map(\.priority), [i("whiteOverGreen"), i("greenPoint")])
        XCTAssertEqual(tree.colorPriority, i("greenPoint"))
        // ISInOM maps: the ISInOM table.
        XCTAssertEqual(ColorHierarchy.lowerPurplePriority(for: .isinom), OccaStandardSymbols.isinomColors().firstIndex { $0.id == "n52" })
    }

    /// Double lines (railway, roads, tracks, stairway): the fill is drawn above the full-width edge line, otherwise the
    /// symbol shows as one solid black line.
    func testDoubleLineFillAboveEdges() throws {
        for f in [OccaStandardSymbols.isomFile(), OccaStandardSymbols.issprFile(), OccaStandardSymbols.isinomFile()] {
            for s in f.symbols where s.lineStyle?.casing != nil {
                XCTAssertLessThan(s.colorPriority ?? 99, s.casingPriority ?? -1, "\(f.standard) \(s.code) \(s.name): fill above edges")
            }
        }
        let rail = try XCTUnwrap(OccaStandardSymbols.issprFile().symbols.first { $0.code == "509.1" })
        XCTAssertEqual(rail.lineStyle?.innerDashMM, [1.0, 1.5], "White 1.0 / black 1.5 dashes")
        XCTAssertEqual(rail.lineStyle?.widthMM, 0.45); XCTAssertEqual(rail.lineStyle?.casing?.innerWidthMM, 0.25)
        let paint = ColorHierarchy.paintOrder([Feature(name: "", kind: .line, colorHex: "#FFFFFF", widthMM: 0.45, nodes: [])]
            .map { var f = $0; f.casingColorHex = "#000000"; f.innerWidthMM = 0.25; f.colorPriority = rail.colorPriority; f.casingPriority = rail.casingPriority; return f })
        XCTAssertEqual(paint.map(\.part), [.casing, .main], "Edges drawn first, white dashes on top")
    }

    func testDrawableAndScaled() throws {
        for f in [OccaStandardSymbols.isomFile(), OccaStandardSymbols.issprFile(), OccaStandardSymbols.isinomFile()] {
            for s in f.symbols where s.kind == .point { XCTAssertFalse(s.pointElements?.isEmpty ?? true, "\(s.code) has a shape") }
            for s in f.symbols where s.kind == .line { XCTAssertNotNil(s.lineStyle, "\(s.code) has a line style") }
        }
        let set = OccaStandardSymbols.isomFile().symbolSet(sourceFile: OccaStandardSymbols.isomFileName)
        let k = set.sizeFactor(forMapScale: 10000)
        eq(k, 1.5)
        eq(try XCTUnwrap(set.scaled(by: k).symbols.first { $0.code == "101.0" }).lineStyle?.widthMM, 0.21, "1:10000 = 150 %")
        // Enlarged sprint map (1:1500): 518's tags, their pair distance, and the line all grow together.
        let sprint = OccaStandardSymbols.issprFile().symbolSet(sourceFile: OccaStandardSymbols.issprFileName)
        let ks = sprint.sizeFactor(forMapScale: 1500)
        let fence = try XCTUnwrap(sprint.scaled(by: ks).symbols.first { $0.code == "518.0" })
        eq(fence.lineStyle?.widthMM, 0.4 * ks, "518 line")
        eq(fence.decoration?.widthMM, 0.14 * ks, "518 tag width")
        eq(fence.decoration?.pairMM, 0.9 * ks, "518 pair distance")
    }

    func testRoundTripAndExport() throws {
        let f = OccaStandardSymbols.issprFile()
        let back = try OccaSymbolFile.read(f.encoded())
        XCTAssertEqual(back.symbols, f.symbols)
        XCTAssertEqual(back.standard, "ISSprOM 2019-2")
        // Exporting a library set (e.g. with some symbols disabled) keeps the enabled states.
        var set = f.symbolSet(sourceFile: "x.occasym")
        set.symbols[0].isEnabled = false
        let exported = try OccaSymbolFile.read(set.occaSymbolFile(author: "Tester", license: "Test").encoded())
        XCTAssertFalse(exported.symbols[0].isEnabled)
        XCTAssertEqual(exported.scale, 4000)
        XCTAssertThrowsError(try OccaSymbolFile.read(Data("{\"format\":\"x\"}".utf8)))
    }
}
