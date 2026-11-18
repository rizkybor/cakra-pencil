import CryptoKit
import XCTest
@testable import CakraCore

/// The Mac's license device id: stable, salted, UUID-shaped, and never the hardware UUID itself.
final class LicenseDeviceIDTests: XCTestCase {
    private let hardware = "8F3A2C1E-5B7D-4E9F-A0B1-C2D3E4F5A6B7"

    func testStableAndCaseInsensitive() throws {
        let id = try XCTUnwrap(LicenseDeviceID.derive(hardwareUUID: hardware))
        XCTAssertEqual(LicenseDeviceID.derive(hardwareUUID: hardware.lowercased()), id)
        XCTAssertEqual(LicenseDeviceID.derive(hardwareUUID: " \(hardware)\n"), id)
    }

    func testUUIDShapedAndNotTheHardwareUUID() throws {
        let id = try XCTUnwrap(LicenseDeviceID.derive(hardwareUUID: hardware))
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(id, id.uppercased())
        XCTAssertNotEqual(id, hardware)
        let chars = Array(id)
        XCTAssertEqual(chars[14], "5")
        XCTAssertTrue("89AB".contains(chars[19]))
    }

    func testSaltedSHA256() throws {
        let id = try XCTUnwrap(LicenseDeviceID.derive(hardwareUUID: hardware))
        let digest = SHA256.hash(data: Data(("occa-device:" + hardware).utf8)).map { String(format: "%02X", $0) }.joined()
        // Bytes 0-5, 7 and 9-15 are the digest's own; 6 and 8 carry the version and variant bits.
        let hex: [Character] = Array(id.replacingOccurrences(of: "-", with: ""))
        let want: [Character] = Array(digest)
        XCTAssertEqual(String(hex[0..<12]), String(want[0..<12]))
        XCTAssertEqual(String(hex[13..<16]), String(want[13..<16]))
        XCTAssertEqual(String(hex[18..<32]), String(want[18..<32]))
    }

    func testDifferentMacsDifferentIDs() {
        XCTAssertNotEqual(LicenseDeviceID.derive(hardwareUUID: hardware),
                          LicenseDeviceID.derive(hardwareUUID: "00000000-0000-0000-0000-000000000001"))
        XCTAssertNil(LicenseDeviceID.derive(hardwareUUID: "  "))
    }
}
