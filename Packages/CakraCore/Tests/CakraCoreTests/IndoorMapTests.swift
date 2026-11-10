import CakraCore
import Foundation
import XCTest

/// "Indoor map (ISInOM)": `SheetSpec.standardOverride` / `mapStandard` and everything it drives (course sizes, symbol
/// set preference, north lines, rescaling, indoor scales, indoor control description features).
final class IndoorMapTests: XCTestCase {
    private func eq(_ a: Double, _ b: Double, _ msg: String = "") { XCTAssertEqual(a, b, accuracy: 1e-6, msg) }
    private func indoor(_ scale: Int) -> SheetSpec { SheetSpec(scaleDenominator: scale, standardOverride: .isinom) }

    // MARK: SheetSpec

    func testSheetCodableWithoutOverrideIsBackwardCompatible() throws {
        // A sheet saved before the option existed.
        let old = #"{"paper":{"name":"A4","shortMM":210,"longMM":297},"orientation":"portrait","marginMM":0,"scaleDenominator":4000}"#
        let sheet = try JSONDecoder().decode(SheetSpec.self, from: Data(old.utf8))
        XCTAssertNil(sheet.standardOverride)
        XCTAssertEqual(sheet.mapStandard, .issprom)
        XCTAssertFalse(sheet.isIndoor)
        // Saving it again doesn't add the key.
        let json = String(decoding: try JSONEncoder().encode(sheet), as: UTF8.self)
        XCTAssertFalse(json.contains("standardOverride"), json)
    }

    func testSheetCodableWithOverride() throws {
        let sheet = indoor(700)
        let json = String(decoding: try JSONEncoder().encode(sheet), as: UTF8.self)
        XCTAssertTrue(json.contains(#""standardOverride":"isinom""#), json)
        let back = try JSONDecoder().decode(SheetSpec.self, from: Data(json.utf8))
        XCTAssertEqual(back, sheet)
        XCTAssertEqual(back.mapStandard, .isinom)
        XCTAssertTrue(back.isIndoor)
        // A whole project round-trips too.
        let p = Project(name: "Indoor", sheet: sheet, sketchDPI: 600)
        let p2 = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(p2.sheet.mapStandard, .isinom)
    }

    func testMapStandard() {
        XCTAssertEqual(SheetSpec(scaleDenominator: 700).mapStandard, .issprom, "Automatic: never ISInOM from the scale")
        XCTAssertEqual(SheetSpec(scaleDenominator: 10000).mapStandard, .isom)
        XCTAssertEqual(indoor(700).mapStandard, .isinom)
        XCTAssertEqual(indoor(4000).mapStandard, .isinom)
        eq(indoor(700).symbolEnlargement, 1)
        eq(indoor(500).symbolEnlargement, 1.4)
        eq(indoor(1000).symbolEnlargement, 1, "Smaller scales keep the 1:700 sizes")
        eq(SheetSpec(scaleDenominator: 700).symbolEnlargement, 4000.0 / 700)
    }

    func testIndoorScales() {
        let s = MapPresets.scales(indoor: true)
        for v in [500, 700, 1000, 1500] { XCTAssertTrue(s.contains(v), "1:\(v)") }
        XCTAssertEqual(s, s.sorted())
        XCTAssertEqual(MapPresets.scales(indoor: false), MapPresets.scales)
    }

    // MARK: Course symbols

    func testCourseStyleOnIndoorMaps() {
        let base = CourseStyle.standard(sheet: indoor(700))
        eq(base.controlDiameterMM, 6); eq(base.startSideMM, 7); eq(base.lineWidthMM, 0.35)
        eq(base.finishInnerMM, 5); eq(base.finishOuterMM, 7); eq(base.numberHeightMM, 4)
        let enlarged = CourseStyle.standard(sheet: indoor(500))
        eq(enlarged.controlDiameterMM, 8.4, "1:500 = 140 %"); eq(enlarged.lineWidthMM, 0.49)
        eq(CourseStyle.standard(sheet: indoor(1000)).controlDiameterMM, 6, "1:1000: never reduced")
        // Without the option, 1:700 would be ISSprOM × 5.71 (≈ 34 mm circles).
        eq(CourseStyle.standard(sheet: SheetSpec(scaleDenominator: 700)).controlDiameterMM, 6 * 4000.0 / 700)
        eq(CourseStyle.standard(sheet: SheetSpec(scaleDenominator: 4000)).controlDiameterMM, 6)
    }

    func testOverprintUsesSheetStandard() {
        let c = ControlPoint(kind: .control, code: 31, position: Point2D(x: 0, y: 0))
        let course = Course(name: "A", controlIDs: [c.id])
        let set = CourseSet(controls: [c], courses: [course])
        func radius(_ sheet: SheetSpec) -> Double? {
            CourseOverprint.make(set, course: course, sheet: sheet).marks.compactMap { m -> Double? in
                if case let .circle(_, r) = m { return r } else { return nil }
            }.max()
        }
        // ø6.0 mm at 1:700 = 4.2 m on the ground → radius 2.1 m.
        eq(radius(indoor(700)) ?? 0, 2.1)
        eq(radius(indoor(500)) ?? 0, 8.4 / 2 / 1000 * 500)
        eq(radius(SheetSpec(scaleDenominator: 4000)) ?? 0, 12)
    }

    // MARK: Symbol set preference and lookup

    private var occaSets: [SymbolSet] {
        [OccaStandardSymbols.isomFile().symbolSet(sourceFile: OccaStandardSymbols.isomFileName),
         OccaStandardSymbols.issprFile().symbolSet(sourceFile: OccaStandardSymbols.issprFileName),
         OccaStandardSymbols.isinomFile().symbolSet(sourceFile: OccaStandardSymbols.isinomFileName)]
    }

    private func setName(of symbol: MapSymbol?, in ordered: [SymbolSet]) -> String? {
        guard let symbol else { return nil }
        return ordered.first { $0.symbols.contains(symbol) }?.name
    }

    func testIndoorMapPrefersISInOMSet() {
        let sets = occaSets
        let indoorOrder = SymbolSetPreference.ordered(sets, isOcca: { _ in true }, sheet: indoor(700))
        XCTAssertEqual(indoorOrder.first?.standard, .isinom)
        let sprintOrder = SymbolSetPreference.ordered(sets, isOcca: { _ in true }, sheet: SheetSpec(scaleDenominator: 700))
        XCTAssertEqual(sprintOrder.first?.standard, .issprom)
        let forestOrder = SymbolSetPreference.ordered(sets, isOcca: { _ in true }, sheet: SheetSpec(scaleDenominator: 10000))
        XCTAssertEqual(forestOrder.first?.standard, .isom)
    }

    func testSharedCodesResolveToTheMapStandard() throws {
        let sets = occaSets
        let isinom = try XCTUnwrap(sets.last), sprint = sets[1]
        for (code, sheet) in [("516.0", indoor(700)), ("518.0", indoor(700)), ("701.0", indoor(700)), ("516.0", indoor(500))] {
            let ordered = SymbolSetPreference.ordered(sets, isOcca: { _ in true }, sheet: sheet)
            let name = try XCTUnwrap(isinom.symbols.first { $0.code == code }?.name, code)
            XCTAssertEqual(sprint.symbols.first { $0.code == code }?.name, name, "\(code): same name in ISSprOM")
            let hit = SymbolSetPreference.symbol(code: code, name: name, in: ordered)
            XCTAssertEqual(setName(of: hit, in: ordered), isinom.name, "\(code) on indoor 1:\(sheet.scaleDenominator)")
        }
        for (code, scale) in [("516.0", 700), ("518.0", 4000), ("701.0", 3000)] {
            let ordered = SymbolSetPreference.ordered(sets, isOcca: { _ in true }, sheet: SheetSpec(scaleDenominator: scale))
            let name = try XCTUnwrap(sprint.symbols.first { $0.code == code }?.name)
            let hit = SymbolSetPreference.symbol(code: code, name: name, in: ordered)
            XCTAssertEqual(setName(of: hit, in: ordered), sprint.name, "\(code) on 1:\(scale)")
        }
        // 516 fence on an indoor 1:700 map: ISInOM 0.21 mm, not ISSprOM × 5.71.
        let ordered = SymbolSetPreference.ordered(sets, isOcca: { _ in true }, sheet: indoor(700))
        let fence = try XCTUnwrap(SymbolSetPreference.symbol(code: "516.0", name: nil, in: ordered))
        XCTAssertLessThan(fence.drawingWidthMM, 0.5)
    }

    // MARK: Rescaling

    func testRescaleWhenTogglingIndoor() {
        let sprint = SheetSpec(scaleDenominator: 700), inside = indoor(700)
        eq(MapStandard.symbolSizeFactor(from: sprint, to: inside), 700.0 / 4000)
        eq(MapStandard.symbolSizeFactor(from: inside, to: sprint), 4000.0 / 700)
        eq(MapStandard.symbolSizeFactor(from: inside, to: indoor(500)), 1.4)
        eq(MapStandard.symbolSizeFactor(from: indoor(1000), to: indoor(1500)), 1, "Never reduced")
        eq(MapStandard.symbolSizeFactor(from: SheetSpec(scaleDenominator: 4000), to: SheetSpec(scaleDenominator: 10000)), 1)
        eq(MapStandard.symbolSizeFactor(from: SheetSpec(scaleDenominator: 15000), to: SheetSpec(scaleDenominator: 10000)), 1.5)
        // An object round-trips: ISSprOM width × 5.71 → ISInOM → back.
        var f = Feature(kind: .line, colorHex: "#000000", widthMM: 1.2, nodes: [])
        f.symbolCode = "516.0"
        let down = f.withSymbolSize(scaledBy: MapStandard.symbolSizeFactor(from: sprint, to: inside))
        eq(down.widthMM, 0.21)
        eq(down.withSymbolSize(scaledBy: MapStandard.symbolSizeFactor(from: inside, to: sprint)).widthMM, 1.2)
    }

    // MARK: North lines

    func testNorthLinesOnIndoorMaps() {
        let p = Project(name: "Indoor", sheet: indoor(700), sketchDPI: 600)
        XCTAssertFalse(p.grid.isEnabled, "North orientation is not required: the grid stays optional")
        eq(p.grid.spacingM, 20)
        eq(p.grid.lineWidthMM, 0.18)
        XCTAssertTrue(NorthGrid.spacingPresetsM.contains(20))
    }

    // MARK: Indoor control description features

    func testIndoorDescriptionSymbols() {
        let expected: [(String, String)] = [("7.119", "Pillar"), ("7.132", "Toilet"), ("7.133", "Shower"), ("7.134", "Sink"),
                                            ("7.141", "Table or bench"), ("7.142", "Cupboard / shelf"), ("7.143", "Couch / sofa")]
        for (id, name) in expected {
            let s = IOFSymbols.symbol(id)
            XCTAssertEqual(s?.name, name, id)
            XCTAssertEqual(s?.column, .d, id)
            XCTAssertEqual(s?.group, IOFSymbols.indoorGroup, id)
            XCTAssertNotNil(IOFPictogram.shapes(id), id)
            XCTAssertNotNil(IOFSymbols.textName(id), id)
        }
        let outdoor = IOFSymbols.pickerSymbols(in: .d, indoor: false), inside = IOFSymbols.pickerSymbols(in: .d, indoor: true)
        XCTAssertEqual(Set(outdoor.map(\.id)), Set(inside.map(\.id)), "Offered on every map")
        XCTAssertEqual(inside.prefix(7).map(\.id), expected.map(\.0), "Indoor maps list them first")
        XCTAssertEqual(outdoor.suffix(7).map(\.id), expected.map(\.0), "Other maps list them last")
        XCTAssertEqual(IOFSymbols.pickerSymbols(in: .e, indoor: true), IOFSymbols.pickerSymbols(in: .e))
        // Pictograms stay inside the cell.
        for (id, _) in expected {
            for shape in IOFPictogram.shapes(id) ?? [] {
                let pts: [Point2D]
                switch shape {
                case let .line(p), let .poly(p, _): pts = p
                default: pts = []
                }
                XCTAssertTrue(pts.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }, id)
            }
        }
    }

    func testIndoorDescriptionInTextAndPDF() {
        var d = ControlDescription()
        d.feature = "7.141"
        XCTAssertEqual(IOFSymbols.textName(d.feature), "Table")
        XCTAssertEqual(d.migratedFrom2018().feature, "7.141", "The 2018 migration leaves indoor features alone")
    }
}
