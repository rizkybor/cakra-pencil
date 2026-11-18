import CryptoKit
import Foundation

/// The device id OCCA sends to the License Manager on a Mac, derived from the Mac's hardware UUID (IOKit
/// `IOPlatformUUID`), so it stays the same after the app and its data are deleted and installed again. The raw
/// hardware UUID never leaves the Mac: the id is SHA-256 of `"occa-device:" + UUID` (uppercased), its first 16 bytes
/// formatted as a UUID string (version 5 / RFC 4122 variant bits set, so it looks like any other device id).
public enum LicenseDeviceID {
    public static let salt = "occa-device:"

    /// nil for an empty or blank hardware UUID.
    public static func derive(hardwareUUID: String) -> String? {
        let normalized = hardwareUUID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        var b = Array(SHA256.hash(data: Data((salt + normalized).utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])).uuidString
    }
}
