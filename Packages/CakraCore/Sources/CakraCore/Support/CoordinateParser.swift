import Foundation

/// Membaca input koordinat dari kolom "Cari lokasi": lat/lon desimal atau UTM.
///
/// Contoh yang diterima:
/// - `-6.9147, 107.6098`
/// - `-6,9147 107,6098` (koma desimal Indonesia dipisah spasi)
/// - `48S 787500 9234500` atau `48 S 787500 9234500`
public enum CoordinateParser {
    public static func parse(_ raw: String) -> LatLon? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        return parseUTM(s) ?? parseLatLon(s)
    }

    static func parseLatLon(_ s: String) -> LatLon? {
        let tokens: [String]
        if s.contains(";") {
            tokens = s.split(separator: ";").map { String($0) }
        } else if s.contains(" ") && s.split(separator: " ", omittingEmptySubsequences: true).count == 2 {
            tokens = s.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }
        } else {
            tokens = s.split(separator: ",").map { String($0) }
        }
        guard tokens.count == 2 else { return nil }
        let nums = tokens.map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ",")).replacingOccurrences(of: ",", with: ".") }
            .compactMap(Double.init)
        guard nums.count == 2, (-90...90).contains(nums[0]), (-180...180).contains(nums[1]) else { return nil }
        return LatLon(lat: nums[0], lon: nums[1])
    }

    static func parseUTM(_ s: String) -> LatLon? {
        let pattern = #"^\s*(\d{1,2})\s*([A-Za-z])\s+(\d+(?:[.,]\d+)?)\s+(\d+(?:[.,]\d+)?)\s*$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges == 5 else { return nil }
        func group(_ i: Int) -> String { String(s[Range(m.range(at: i), in: s)!]) }
        guard let number = Int(group(1)) else { return nil }
        let letter = group(2).uppercased()
        // "N"/"S" = belahan; huruf band MGRS C–M = selatan, N–X = utara.
        let isNorth: Bool
        switch letter {
        case "S": isNorth = false
        case "N": isNorth = true
        case "C"..."M": isNorth = false
        default: isNorth = true
        }
        guard let zone = UTMZone(number: number, isNorth: isNorth),
              let e = Double(group(3).replacingOccurrences(of: ",", with: ".")),
              let n = Double(group(4).replacingOccurrences(of: ",", with: ".")),
              (100_000...900_000).contains(e), (0...10_000_000).contains(n) else { return nil }
        return zone.unproject(Point2D(x: e, y: n))
    }
}
