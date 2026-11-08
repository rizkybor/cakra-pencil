@testable import CakraCore
import XCTest

/// OCCA's own ISOM 2017-2 / ISSprOM 2019-2 symbol sets (.occasym), checked against the IOF specifications.
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
                     (OccaStandardSymbols.issprFileName, OccaStandardSymbols.issprFile())]
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
    }

    func testColors() {
        let c = OccaStandardSymbols.colors()
        func hex(_ id: String) -> String { c.first { $0.id == id }!.hex }
        XCTAssertEqual(hex("brown"), "#D15C00")
        XCTAssertEqual(hex("purpleLower"), "#A626FF")
        XCTAssertEqual(hex("brown50"), "#E8AE80")
        XCTAssertEqual(hex("green100"), "#3DFF17")
        XCTAssertEqual(hex("black50"), "#808080")
        // Order: black above brown above lower purple above screens; upper purple on top.
        func i(_ id: String) -> Int { c.firstIndex { $0.id == id }! }
        XCTAssertEqual(i("purpleUpper"), 0)
        XCTAssertLessThan(i("black"), i("brown"))
        XCTAssertLessThan(i("brown"), i("purpleLower"), "Lower purple below black, blue, brown 100 %")
        XCTAssertLessThan(i("green100"), i("yellow100"))
    }

    /// Symbols from other sets (own color tables) get positions in OCCA's IOF order, so they layer with OCCA symbols.
    func testColorOrderAcrossSets() throws {
        let c = OccaStandardSymbols.colors()
        func i(_ id: String) -> Int { c.firstIndex { $0.id == id }! }
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#000000", kind: .line), i("black"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#FFBA36", kind: .area), i("yellow100"))
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#FFFFFF", kind: .area), i("white"), "White area = forest (bottom)")
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#3DFF17", kind: .point), i("greenSymbol"), "Green point above green screens")
        XCTAssertEqual(ColorHierarchy.iofPriority(hex: "#CC5A00", kind: .line), i("brown"), "Nearest color (BOF brown)")
        // A BOF-like footpath (black edges, light brown fill, own table priority 40) ends up above yellow.
        var path = MapSymbol(number: 505_000, name: "Footpath", kind: .line, colorHex: "#F1CEB3", lineWidthMM: nil, isEnabled: true,
                             lineStyle: LineStyle(colorHex: "#F1CEB3", widthMM: 0.45, casing: LineStyle.Casing(colorHex: "#000000", innerWidthMM: 0.25)))
        path.colorPriority = 40
        path.casingPriority = 41
        let n = path.withIOFColorOrder()
        XCTAssertEqual(n.casingPriority, i("blackEdge"), "Edges on the double-line edge color")
        XCTAssertLessThan(n.colorPriority ?? 99, n.casingPriority ?? -1, "Fill above its edges")
        XCTAssertLessThan(n.colorPriority ?? 99, i("yellow100"))
    }

    /// Double lines (railway, roads, tracks, stairway): the fill is drawn above the full-width edge line, otherwise the
    /// symbol shows as one solid black line.
    func testDoubleLineFillAboveEdges() throws {
        for f in [OccaStandardSymbols.isomFile(), OccaStandardSymbols.issprFile()] {
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
        for f in [OccaStandardSymbols.isomFile(), OccaStandardSymbols.issprFile()] {
            for s in f.symbols where s.kind == .point { XCTAssertFalse(s.pointElements?.isEmpty ?? true, "\(s.code) has a shape") }
            for s in f.symbols where s.kind == .line { XCTAssertNotNil(s.lineStyle, "\(s.code) has a line style") }
        }
        let set = OccaStandardSymbols.isomFile().symbolSet(sourceFile: OccaStandardSymbols.isomFileName)
        let k = set.sizeFactor(forMapScale: 10000)
        eq(k, 1.5)
        eq(try XCTUnwrap(set.scaled(by: k).symbols.first { $0.code == "101.0" }).lineStyle?.widthMM, 0.21, "1:10000 = 150 %")
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
