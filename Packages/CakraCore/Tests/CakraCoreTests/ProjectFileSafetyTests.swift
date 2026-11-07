import CakraCore
import XCTest

/// Project files can come from other people (.occa import): names read from them must stay inside the package.
final class ProjectFileSafetyTests: XCTestCase {
    func testBasemapFileNameMustBeAPlainNameInsideThePackage() {
        XCTAssertTrue(BasemapImage.isSafeFileName("basemap-1a2b3c4d.tif"))
        for bad in ["", "..", "../other.cakra/project.json", "a/b.tif", "/etc/hosts", ".hidden.tif", "a\\b.tif", "x\0.tif"] {
            XCTAssertFalse(BasemapImage.isSafeFileName(bad), bad)
        }
    }

    func testImagerySnapshotMetadataMustPointToItsOwnFile() {
        var s = ImagerySnapshot(mapType: "satellite", fileName: ImagerySnapshot.imagePath(for: "satellite"),
                                north: -6.88, south: -6.90, west: 107.60, east: 107.62, width: 100, height: 100)
        XCTAssertTrue(s.isValid)
        s.fileName = "../../other.cakra/project.json"
        XCTAssertFalse(s.isValid)
        s.fileName = ImagerySnapshot.imagePath(for: "satellite")
        s.mapType = "../x"
        XCTAssertFalse(s.isValid)
    }

    func testUnpackSkipsImageryFromOtherDevices() throws {
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dst) }
        // pack() already leaves imagery out; build an archive that still contains it, like a crafted file would.
        let archive = try craftedArchive(["project.json": Data("{}".utf8), ImagerySnapshot.metadataPath(for: "satellite"): Data([1])])
        try ProjectArchive.unpack(archive, into: dst)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.appendingPathComponent("project.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.appendingPathComponent(ImagerySnapshot.folder).path))
    }

    /// Archive in the documented format ("CPENCIL1" + LZFSE payload) with arbitrary entries.
    private func craftedArchive(_ entries: [String: Data]) throws -> Data {
        var payload = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { payload.append(contentsOf: $0) } }
        func u64(_ v: Int) { withUnsafeBytes(of: UInt64(v).littleEndian) { payload.append(contentsOf: $0) } }
        u32(entries.count)
        for (path, data) in entries.sorted(by: { $0.key < $1.key }) {
            let p = Data(path.utf8)
            u32(p.count); payload.append(p); u64(data.count); payload.append(data)
        }
        return Data("CPENCIL1".utf8) + (try (payload as NSData).compressed(using: .lzfse) as Data)
    }
}
