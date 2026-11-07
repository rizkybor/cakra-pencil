import CakraCore
import XCTest

/// New project from an OCAD / OOM map file (project list → Open file).
final class MapFileImportTests: XCTestCase {
    func testOcadCourseSettingBecomesProjectWithCoursesAndNoCourseSymbols() throws {
        let content = try MapFileImport.read(Ocad10CourseTests.makeOcad10(withCourses: true), fileExtension: "ocd")
        XCTAssertEqual(content.source, .ocad)
        XCTAssertNil(content.knownZone, "OCAD does not store the UTM zone")
        XCTAssertEqual(content.scale, 10000)
        XCTAssertEqual(content.features.compactMap(\.symbolCode), ["101.0"], "Course symbols are not map objects")
        XCTAssertEqual(content.courses?.courses.first?.name, "A")

        let zone = UTMZone(number: 50, isNorth: false)!
        let doc = MapFileImport.document(name: "Ampenan", content: content, zone: zone)
        XCTAssertEqual(doc.project.crsEPSG, 32750)
        XCTAssertTrue(doc.project.areaLocked)
        XCTAssertEqual(doc.project.sheet.scaleDenominator, 10000)
        let frame = try XCTUnwrap(doc.project.frame)
        let extent = try XCTUnwrap(content.extent)
        let f = frame.extent
        XCTAssertEqual((f.minX + f.maxX) / 2, (extent.minX + extent.maxX) / 2, accuracy: 10, "Frame centered on the content")
        XCTAssertEqual((f.minY + f.maxY) / 2, (extent.minY + extent.maxY) / 2, accuracy: 10)
        XCTAssertEqual(doc.courses.controls.count, 4)
        XCTAssertEqual(doc.courses.courses.count, 2)
    }

    func testOmapGetsItsZoneFromTheFile() throws {
        let sheet = SheetSpec(scaleDenominator: 4000)
        let zone = UTMZone(epsg: 32748)!
        let frame = MapFrame(origin: Point2D(x: 788_000, y: 9_237_000), widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
        let line = Feature(name: "505.0", kind: .line, colorHex: "#000000", widthMM: 0.25,
                           nodes: [BezierNode(point: Point2D(x: 788_100, y: 9_237_100)), BezierNode(point: Point2D(x: 788_300, y: 9_237_200))],
                           symbolCode: "505.0", symbolName: "Footpath")
        let xml = OmapWriter.document(VectorExportRequest(baseName: "t", frame: frame, sheet: sheet, zone: zone, strokes: [], features: [line]))
        let content = try MapFileImport.read(Data(xml.utf8), fileExtension: "omap")
        XCTAssertEqual(content.knownZone, zone)
        XCTAssertEqual(content.scale, 4000)
        XCTAssertEqual(content.features.count, 1)
        XCTAssertEqual(content.features[0].nodes[0].point.x, 788_100, accuracy: 0.01)
    }

    func testRejectsEmptyAndUnknownFiles() {
        XCTAssertThrowsError(try MapFileImport.read(Data("x".utf8), fileExtension: "pdf")) { e in
            XCTAssertEqual(e as? MapFileImport.ImportError, .unsupportedExtension("pdf"))
        }
        XCTAssertEqual(MapFileImport.sheetScale(for: 5000), 5000)
        XCTAssertEqual(MapFileImport.sheetScale(for: 4800), 5000)
        XCTAssertEqual(MapFileImport.sheetScale(for: 25000), 15000)
    }
}
