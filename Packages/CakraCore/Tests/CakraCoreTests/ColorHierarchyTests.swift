import XCTest
@testable import CakraCore

/// Color Hierarchy: the OCAD color table order determines color stacking, not object order.
final class ColorHierarchyTests: XCTestCase {
    private func P(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    private func builtInSet() throws -> SymbolSet {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../CakraPencil/Resources/SymbolSets/BOF O_Map 4000 O12 v1_ISSprOM2019-2.ocd")
        guard let data = try? Data(contentsOf: url) else { throw XCTSkip("Bundled ISSprOM set not found") }
        return try OcadReader.read(data).symbolSet(name: "ISSprOM", sourceFile: "x.ocd")
    }

    /// Official ISSprOM 2019-2 color table order (BOF): black above blue, blue above 100% brown,
    /// brown above green, green above yellow; road fill above its black casing.
    func testBuiltInSetFollowsIssprom2019ColorTable() throws {
        let set = try builtInSet()
        XCTAssertEqual(set.readerVersion, SymbolSet.currentReaderVersion)
        func p(_ code: String) -> Int { set.symbols.first { $0.code == code }?.colorPriority ?? .max }
        XCTAssertLessThan(p("201.0"), p("305.0"), "100% black (cliff) above blue (watercourse)")
        XCTAssertLessThan(p("305.0"), p("101.0"), "Blue line above brown contour")
        XCTAssertLessThan(p("101.0"), p("301.0"), "Brown contour above blue area")
        XCTAssertLessThan(p("301.0"), p("406.0"), "Blue area above green")
        XCTAssertLessThan(p("406.0"), p("401.0"), "Green above yellow")
        XCTAssertLessThan(p("417.0"), p("406.0"), "Green point (tree) above green area")

        let street = try XCTUnwrap(set.symbols.first { $0.code == "501.30" })
        XCTAssertNotNil(street.casingPriority)
        XCTAssertLessThan(street.colorPriority!, street.casingPriority!, "Road fill above its black casing")
    }

    /// 509.1 Railway (ISSprOM 2019-2): 0.55 mm black fill below, 0.35 mm white line dashed 1.0/1.5 mm on top.
    func testRailwayHasBlackBaseAndWhiteDashes() throws {
        let set = try builtInSet()
        let rail = try XCTUnwrap(set.symbols.first { $0.code == "509.100" })
        let style = try XCTUnwrap(rail.lineStyle)
        XCTAssertEqual(style.widthMM, 0.55, accuracy: 1e-9, "Total width = black layer")
        XCTAssertEqual(style.casing?.innerWidthMM ?? 0, 0.35, accuracy: 1e-9, "White line on top")
        XCTAssertEqual(style.colorHex, "#FFFFFF")
        XCTAssertEqual(style.casing?.colorHex, "#000000")
        XCTAssertEqual(style.innerDashMM, [1.0, 1.5], "White dashes 1.0 mm, gap 1.5 mm")
        XCTAssertNil(style.dashMM, "Black layer is solid")
        XCTAssertLessThan(rail.colorPriority!, rail.casingPriority!, "White above black")

        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 0.35,
                        nodes: [BezierNode(point: P(0, 0)), BezierNode(point: P(10, 0))], symbolCode: "509.100")
        f.apply(style)
        XCTAssertEqual(f.effectiveInnerDashMM, [1.0, 1.5])
        // Footpath 505.0 unchanged: dashed casing, solid fill.
        let path = try XCTUnwrap(set.symbols.first { $0.code == "505.0" }?.lineStyle)
        XCTAssertNotNil(path.dashMM)
        XCTAssertNil(path.innerDashMM)
    }

    func testPaintOrderFollowsPriorityThenObjectOrder() {
        func f(_ name: String, _ kind: FeatureKind, _ prio: Int?, code: String? = "x") -> Feature {
            var g = Feature(name: name, kind: kind, colorHex: "#000000", widthMM: 0.3,
                            nodes: [BezierNode(point: P(0, 0)), BezierNode(point: P(1, 0)), BezierNode(point: P(1, 1))],
                            symbolCode: code)
            g.colorPriority = prio
            return g
        }
        // Object order: black first, then yellow covers it → yellow is still drawn below.
        let features = [f("hitam", .line, 6), f("kuning", .area, 41), f("hijau-a", .area, 33), f("hijau-b", .area, 33),
                        f("sketsa", .line, nil, code: nil)]
        let order = ColorHierarchy.paintOrder(features).map { features[$0.index].name }
        XCTAssertEqual(order, ["kuning", "hijau-a", "hijau-b", "hitam", "sketsa"])
        XCTAssertEqual(ColorHierarchy.topDownIndices(features).map { features[$0].name },
                       ["sketsa", "hitam", "hijau-b", "hijau-a", "kuning"])
    }

    func testDoubleLineSplitsIntoCasingAndFillLayers() {
        var road = Feature(name: "jalan", kind: .line, colorHex: "#E0C8A0", widthMM: 0.6,
                           nodes: [BezierNode(point: P(0, 0)), BezierNode(point: P(10, 0))], symbolCode: "501.30")
        road.casingColorHex = "#000000"
        road.innerWidthMM = 0.4
        road.colorPriority = 21
        road.casingPriority = 24
        var black = Feature(name: "hitam", kind: .line, colorHex: "#000000", widthMM: 0.3,
                            nodes: [BezierNode(point: P(0, 0)), BezierNode(point: P(10, 0))], symbolCode: "x")
        black.colorPriority = 22
        let order = ColorHierarchy.paintOrder([road, black]).map { "\($0.index)\($0.part)" }
        // Road casing (24) → other line (22) → road fill (21): fill covers lines crossing the road.
        XCTAssertEqual(order, ["0casing", "1whole", "0main"])
    }

    func testWithColorPrioritiesUsesSymbolLookup() {
        var s = MapSymbol(number: 101_000, name: "Contour", kind: .line, colorHex: "#000000", lineWidthMM: 0.14, isEnabled: true)
        s.colorPriority = 11
        let line = Feature(kind: .line, colorHex: "#000000", widthMM: 0.14,
                           nodes: [BezierNode(point: P(0, 0)), BezierNode(point: P(1, 0))], symbolCode: "101.0")
        let sketch = Feature(kind: .line, colorHex: "#000000", widthMM: 0.14, nodes: line.nodes)
        let out = [line, sketch].withColorPriorities { $0 == "101.0" ? s : nil }
        XCTAssertEqual(out[0].colorPriority, 11)
        XCTAssertNil(out[1].colorPriority)
    }

    func testRasterExportPaintsHigherColorOverLower() throws {
        // Yellow area (41) comes AFTER black area (6) in the object list, but black must stay on top.
        let sheet = SheetSpec(marginMM: 5, scaleDenominator: 4000)
        let frame = MapFrame(origin: P(788_100, 9_236_860), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        func square(_ hex: String, _ prio: Int) -> Feature {
            let c = P(788_300, 9_237_200)
            var f = Feature(kind: .area, colorHex: hex, widthMM: 0.1,
                            nodes: [P(c.x - 50, c.y - 50), P(c.x + 50, c.y - 50), P(c.x + 50, c.y + 50), P(c.x - 50, c.y + 50)].map { BezierNode(point: $0) },
                            symbolCode: "x")
            f.colorPriority = prio
            return f
        }
        let pdf = GeoPDFExporter.document(GeoPDFRequest(title: "uji", frame: frame, sheet: sheet, zone: UTMZone(epsg: 32748)!,
                                                        strokes: [], features: [square("#000000", 6), square("#FFDD00", 41)]))
        let text = String(decoding: pdf, as: UTF8.self)
        let yellow = try XCTUnwrap(text.range(of: "1 0.867 0 rg")), black = try XCTUnwrap(text.range(of: "0 0 0 rg"))
        XCTAssertLessThan(yellow.lowerBound, black.lowerBound, "Yellow drawn first, black over it")
    }
}
