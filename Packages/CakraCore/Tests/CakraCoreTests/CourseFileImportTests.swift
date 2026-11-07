import CakraCore
import XCTest

/// Course page → Import course: .occa, OCAD course setting, and OOM course symbols.
final class CourseFileImportTests: XCTestCase {
    private func archive(zone: UTMZone, controls: [ControlPoint], courses: [Course]) throws -> Data {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var project = Project(name: "Source", crsEPSG: zone.epsg)
        project.areaLocked = true
        try CakraPackage.write(ProjectDocument(project: project, courses: CourseSet(controls: controls, courses: courses)), to: dir)
        return try ProjectArchive.pack(packageAt: dir)
    }

    func testOccaCoursesKeepDescriptionsAndOrderWithNewIDs() throws {
        let zone = UTMZone(epsg: 32748)!
        var c31 = ControlPoint(kind: .control, code: 31, position: Point2D(x: 700_100, y: 9_300_100))
        c31.description = ControlDescription(feature: "2.4")
        let start = ControlPoint(kind: .start, position: Point2D(x: 700_000, y: 9_300_000))
        let course = Course(name: "Elite", controlIDs: [start.id, c31.id])
        let data = try archive(zone: zone, controls: [start, c31], courses: [course])

        let imported = try CourseFileImport.read(data, fileExtension: "occa", zone: zone)
        XCTAssertEqual(imported.controls.count, 2)
        XCTAssertFalse(imported.controls.contains { $0.id == c31.id }, "New ids: no clash with the current project")
        let i31 = try XCTUnwrap(imported.controls.first { $0.code == 31 })
        XCTAssertEqual(i31.description.feature, "2.4", "Descriptions are kept")
        XCTAssertEqual(i31.position, c31.position, "Same zone: same position")
        XCTAssertEqual(imported.courses.first?.name, "Elite")
        XCTAssertEqual(imported.courses.first?.controlIDs, [imported.controls[0].id, i31.id])
    }

    func testOccaPositionsAreConvertedToTheCurrentZone() throws {
        let source = UTMZone(epsg: 32748)!, target = UTMZone(epsg: 32749)!
        let c = ControlPoint(kind: .control, code: 40, position: Point2D(x: 820_000, y: 9_250_000))
        let data = try archive(zone: source, controls: [c], courses: [Course(name: "A", controlIDs: [c.id])])
        let imported = try CourseFileImport.read(data, fileExtension: "occa", zone: target)
        let ll = source.unproject(c.position), back = target.unproject(imported.controls[0].position)
        XCTAssertEqual(back.lat, ll.lat, accuracy: 1e-7)
        XCTAssertEqual(back.lon, ll.lon, accuracy: 1e-7)
        XCTAssertNotEqual(imported.controls[0].position.x, c.position.x, accuracy: 1)
    }

    func testOcadCourseSettingAndMapOnlyFiles() throws {
        let zone = UTMZone(epsg: 32748)!
        let c = try CourseFileImport.read(Ocad10CourseTests.makeOcad10(withCourses: true), fileExtension: "ocd", zone: zone)
        XCTAssertEqual(c.courses.map(\.name), ["A", "B"])
        XCTAssertThrowsError(try CourseFileImport.read(Ocad10CourseTests.makeOcad10(withCourses: false), fileExtension: "ocd", zone: zone),
                             "A plain OCAD map has no courses")
    }

    func testOmapCourseSymbolsBecomeControls() throws {
        // OMAP with a start (701) and a control (702) point object, written by hand in the OOM format.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <map xmlns="http://openorienteering.org/apps/mapper/xml/v2" version="9">
        <georeferencing scale="4000" grid_scale_factor="1" auxiliary_scale_factor="1" declination="0" grivation="0">
        <ref_point x="0" y="0"/>
        <projected_crs id="UTM"><spec language="PROJ.4">+proj=utm +zone=48 +south +datum=WGS84</spec><ref_point x="700000" y="9300000"/></projected_crs>
        <geographic_crs id="Geographic coordinates"><spec language="PROJ.4">+proj=latlong +datum=WGS84</spec><ref_point_deg lat="-6.3241" lon="106.8098"/></geographic_crs>
        </georeferencing>
        <colors count="1"><color priority="0" name="Purple" c="0" m="1" y="0" k="0" opacity="1"/></colors>
        <barrier version="6" required="0.6.0">
        <symbols count="2">
        <symbol type="1" id="0" code="701.0" name="Start"/>
        <symbol type="1" id="1" code="702.0" name="Control point"/>
        </symbols>
        <parts count="1" current="0"><part name="default"><objects count="2">
        <object type="0" symbol="0"><coords count="1">0 0;</coords></object>
        <object type="0" symbol="1"><coords count="1">25000 0;</coords></object>
        </objects></part></parts>
        </barrier>
        </map>
        """
        let zone = UTMZone(epsg: 32748)!
        let c = try CourseFileImport.read(Data(xml.utf8), fileExtension: "omap", zone: zone)
        XCTAssertEqual(c.controls.map(\.kind), [.start, .control])
        XCTAssertTrue(c.courses.isEmpty, "OOM has no course order")
        // 25 mm on paper at 1:4000 = 100 m east of the start.
        XCTAssertEqual(c.controls[1].position.x - c.controls[0].position.x, 100, accuracy: 0.01)
    }
}
