@testable import CakraCore
import XCTest

/// OpenOrienteering Mapper symbol sets bundled with the app (GPL-3.0, OpenOrienteering Mapper contributors),
/// read with `OmapSymbolSet` and checked against ISOM 2017-2 / ISSprOM 2019-2 sizes.
final class OmapSymbolSetTests: XCTestCase {
    private func load(_ file: String, course: Bool = false) throws -> SymbolSet {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../CakraPencil/Resources/SymbolSets/OpenOrienteering/\(file)")
        return try OmapSymbolSet.read(Data(contentsOf: url), name: file, sourceFile: file,
                                      codeFilter: course ? { (700...799).contains($0) } : nil)
    }

    private func sym(_ set: SymbolSet, _ code: String) throws -> MapSymbol {
        try XCTUnwrap(set.symbols.first { $0.code == code }, "\(code) in \(set.name)")
    }

    private func eq(_ a: Double?, _ b: Double, _ msg: String = "") { XCTAssertEqual(a ?? -1, b, accuracy: 0.001, msg) }

    func testCodes() {
        XCTAssertEqual(OmapSymbolSet.number("101"), 101_000)
        XCTAssertEqual(OmapSymbolSet.number("501.1"), 501_001)
        XCTAssertEqual(OmapSymbolSet.number("512.10"), 512_010)
        XCTAssertNil(OmapSymbolSet.number("abc"))
    }

    func testISOM10000() throws {
        let set = try load("ISOM 2017-2_10000.omap")
        XCTAssertEqual(set.scale, 10000)
        XCTAssertEqual(set.standard, .isom)
        XCTAssertGreaterThan(set.symbols.filter(\.isDrawable).count, 150)
        // 1:10000 = 150% of the 1:15000 sizes.
        eq(try sym(set, "101.0").lineStyle?.widthMM, 0.21, "Contour 0.14 × 1.5")
        eq(try sym(set, "102.0").lineStyle?.widthMM, 0.375, "Index contour 0.25 × 1.5")
        let form = try sym(set, "103.0").lineStyle
        eq(form?.widthMM, 0.15); XCTAssertEqual(form?.dashMM, [3.0, 0.3], "Form line dash 2.0/0.2 × 1.5")
        let road = try sym(set, "502.0").lineStyle
        XCTAssertEqual(road?.casing?.colorHex, "#000000", "Wide road: black edges")
        eq(road?.casing?.innerWidthMM, 0.45); eq(road?.widthMM, 0.87)
        XCTAssertEqual(try sym(set, "505.0").lineStyle?.dashMM, [3.0, 0.375], "Footpath dashed")
        XCTAssertEqual(try sym(set, "521.0").kind, .area)
        let tree = try sym(set, "417.0")
        XCTAssertEqual(tree.kind, .point)
        XCTAssertTrue(tree.pointElements?.contains { $0.kind == .circle && $0.colorHex == tree.colorHex } ?? false)
        // Color order: black (2) above brown (6) above yellow.
        XCTAssertLessThan(try sym(set, "201.0").colorPriority ?? 99, try sym(set, "101.0").colorPriority ?? -1)
        XCTAssertLessThan(try sym(set, "101.0").colorPriority ?? 99, try sym(set, "401.0").colorPriority ?? -1)
        // Hatch-only areas are off by default (OCCA fills areas solid).
        XCTAssertFalse(try sym(set, "308.0").isEnabled, "Marsh is a hatch pattern")
        XCTAssertTrue(try sym(set, "401.0").isEnabled)
    }

    func testISSprOM4000() throws {
        let set = try load("ISSprOM 2019_4000.omap")
        XCTAssertEqual(set.scale, 4000)
        XCTAssertEqual(set.standard, .issprom)
        eq(try sym(set, "101.0").lineStyle?.widthMM, 0.21, "ISSprOM 101")
        eq(try sym(set, "102.0").lineStyle?.widthMM, 0.30, "ISSprOM 102")
        XCTAssertEqual(try sym(set, "103.0").lineStyle?.dashMM, [3.0, 0.3], "ISSprOM 103")
        let rail = try sym(set, "509.1").lineStyle
        XCTAssertEqual(rail?.casing?.colorHex, "#000000", "Railway: black edges")
        XCTAssertNotNil(rail?.innerDashMM, "Railway: dashed inner line")
        XCTAssertEqual(try sym(set, "521.0").colorHex, "#666666", "Building: dark grey")
    }

    func testCourseDesign() throws {
        let set = try load("Course_Design_4000.omap", course: true)
        XCTAssertTrue(set.isCourseDesign, "Only 7xx symbols")
        let finish = try sym(set, "706.0").pointElements?.filter { $0.kind == .circle }.map(\.diameterMM).sorted()
        XCTAssertEqual(finish?.count, 2)
        eq(finish?.first, 5.0, "ISSprOM finish ø5"); eq(finish?.last, 7.0, "ISSprOM finish ø7")
        eq(try sym(set, "702.0").pointElements?.first?.diameterMM, 6.0, "Control circle ø6")
        let forest = try load("Course_Design_10000.omap", course: true)
        XCTAssertTrue(forest.isCourseDesign)
    }

    func testScaledToAnotherMapScale() throws {
        let set = try load("ISOM 2017-2_10000.omap")
        let k = set.sizeFactor(forMapScale: 15000)
        eq(k, 1 / 1.5, "1:10000 set on a 1:15000 map")
        let base = set.scaled(by: k)
        eq(try sym(base, "101.0").lineStyle?.widthMM, 0.14, "Back to the ISOM base width")
        eq(try sym(base, "502.0").lineStyle?.casing?.innerWidthMM, 0.3)
        eq(set.sizeFactor(forMapScale: 10000), 1)
        eq(set.sizeFactor(forMapScale: 4000), 1, "Different standard: unchanged")
    }

    /// A combined symbol that contains itself must not recurse forever (crash on import).
    func testSelfReferencingCombinedSymbolDoesNotRecurse() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map xmlns="http://openorienteering.org/apps/mapper/xml/v2" version="9"><georeferencing scale="4000"/>
        <colors count="1"><color priority="0" name="Black"><rgb r="0" g="0" b="0"/></color></colors>
        <barrier version="6"><symbols count="2">
        <symbol type="16" id="0" code="900" name="Loop"><combined_symbol parts="1"><part symbol="0"/></combined_symbol></symbol>
        <symbol type="2" id="1" code="901" name="Line"><line_symbol color="0" line_width="300"/></symbol>
        </symbols></barrier></map>
        """
        let set = try OmapSymbolSet.read(Data(xml.utf8), name: "x", sourceFile: "x.omap")
        XCTAssertEqual(set.symbols.map(\.code), ["901.0"], "Looping symbol skipped, the rest is read")
    }

    func testRejectsNonOmap() {
        XCTAssertThrowsError(try OmapSymbolSet.read(Data("<html/>".utf8), name: "x", sourceFile: "x"))
    }
}
