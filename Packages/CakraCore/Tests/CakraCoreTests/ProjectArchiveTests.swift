import XCTest
@testable import CakraCore

/// File proyek .cpencil: simpan di satu device, impor di device lain (iPad ↔ Mac), isi tetap utuh.
final class ProjectArchiveTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Paket lengkap: objek, sketsa, lintasan, gambar lintasan (subfolder), DEM biner, pratinjau.
    private func makePackage() throws -> (URL, ProjectDocument) {
        let line = Feature(kind: .line, colorHex: "#000000", widthMM: 0.3,
                           nodes: [BezierNode(point: Point2D(x: 1, y: 2)), BezierNode(point: Point2D(x: 3, y: 4), inHandle: Point2D(x: 2, y: 4))],
                           symbolCode: "505.0", symbolName: "Footpath")
        let doc = ProjectDocument(project: Project(name: "Taman", crsEPSG: 32748, frameOrigin: Point2D(x: 786_000, y: 9_234_000), areaLocked: true),
                                  strokes: [Stroke(colorHex: "#D15C00", widthMM: 0.14, points: [Point2D(x: 0, y: 0), Point2D(x: 5, y: 5)])],
                                  features: [line])
        let dir = tmp.appendingPathComponent("\(doc.project.id.uuidString).cakra")
        try CakraPackage.write(doc, to: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("CourseImages"), withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0x01, 0x02]).write(to: dir.appendingPathComponent("CourseImages/logo.jpg"))
        try Data((0..<10_000).map { UInt8($0 % 251) }).write(to: dir.appendingPathComponent("dem.bin"))
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent(".DS_Store"))
        return (dir, doc)
    }

    func testRoundTripKeepsEverything() throws {
        let (dir, doc) = try makePackage()
        let original = try CakraPackage.read(at: dir)   // tanggal di paket tanpa pecahan detik
        let archive = try ProjectArchive.pack(packageAt: dir)
        XCTAssertEqual(archive.prefix(8), Data("CPENCIL1".utf8))

        let entries = try ProjectArchive.entries(of: archive)
        XCTAssertNotNil(entries["CourseImages/logo.jpg"], "Subfolder ikut")
        XCTAssertEqual(entries["dem.bin"]?.count, 10_000)
        XCTAssertNil(entries[".DS_Store"], "Berkas sistem tidak ikut")

        // "Device lain": folder proyek kosong.
        let other = tmp.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let imported = try ProjectArchive.importArchive(archive, intoRoot: other, existingIDs: [])
        let back = try CakraPackage.read(at: imported)
        XCTAssertEqual(back, original, "Objek, sketsa, proyek identik")
        XCTAssertEqual(imported.lastPathComponent, "\(doc.project.id.uuidString).cakra")
        XCTAssertEqual(try Data(contentsOf: imported.appendingPathComponent("CourseImages/logo.jpg")), Data([0xFF, 0xD8, 0x01, 0x02]))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: other.path).filter { $0.hasPrefix(".import-") }
        XCTAssertTrue(leftovers.isEmpty, "Folder sementara dibersihkan")
    }

    func testImportingSameProjectTwiceMakesACopy() throws {
        let (dir, doc) = try makePackage()
        let original = try CakraPackage.read(at: dir)
        let archive = try ProjectArchive.pack(packageAt: dir)
        let copy = try ProjectArchive.importArchive(archive, intoRoot: tmp, existingIDs: [doc.project.id])
        let project = try CakraPackage.readProject(at: copy)
        XCTAssertNotEqual(project.id, doc.project.id, "Proyek yang ada tidak tertimpa")
        XCTAssertEqual(project.name, "Taman (impor)")
        XCTAssertEqual(try CakraPackage.read(at: dir), original, "Paket asli tidak berubah")
    }

    func testRejectsNonArchiveAndUnsafePaths() throws {
        XCTAssertThrowsError(try ProjectArchive.entries(of: Data("hello".utf8))) {
            XCTAssertEqual($0 as? ProjectArchive.ArchiveError, .notArchive)
        }
        for bad in ["../evil.json", "/etc/passwd", "a/../../b", ".hidden", "a//b"] {
            XCTAssertThrowsError(try ProjectArchive.validate(bad), bad)
        }
        XCTAssertNoThrow(try ProjectArchive.validate("CourseImages/logo.jpg"))

        // Arsip buatan dengan path "../x" ditolak saat dibaca.
        var payload = Data()
        ProjectArchive.append(UInt32(1), to: &payload)
        let p = Data("../x".utf8)
        ProjectArchive.append(UInt32(p.count), to: &payload)
        payload.append(p)
        ProjectArchive.append(UInt64(1), to: &payload)
        payload.append(0)
        let evil = Data("CPENCIL1".utf8) + (try (payload as NSData).compressed(using: .lzfse) as Data)
        XCTAssertThrowsError(try ProjectArchive.entries(of: evil)) {
            XCTAssertEqual($0 as? ProjectArchive.ArchiveError, .unsafePath("../x"))
        }
    }

    func testTruncatedArchiveIsRejected() throws {
        let (dir, _) = try makePackage()
        let archive = try ProjectArchive.pack(packageAt: dir)
        XCTAssertThrowsError(try ProjectArchive.entries(of: archive.prefix(archive.count / 2)))
    }
}
