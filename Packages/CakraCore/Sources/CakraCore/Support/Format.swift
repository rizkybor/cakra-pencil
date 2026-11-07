import Foundation

/// Formats technical numbers using the English convention (comma thousands separator, decimal point).
public enum Fmt {
    static let locale = Locale(identifier: "en_US")

    public static func number(_ v: Double, decimals: Int) -> String {
        v.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    /// "1,050 m" or "0.141 m".
    public static func meters(_ v: Double, decimals: Int = 0) -> String { "\(number(v, decimals: decimals)) m" }

    /// "3.2 km" (course length, 0.1 km like Purple Pen).
    public static func km(_ m: Double) -> String { "\(number(m / 1000, decimals: 1)) km" }

    public static func mm(_ v: Double, decimals: Int = 2) -> String { "\(number(v, decimals: decimals)) mm" }

    public static func pixels(_ w: Int, _ h: Int) -> String {
        "\(number(Double(w), decimals: 0)) × \(number(Double(h), decimals: 0)) px"
    }

    public static func utm(_ p: Point2D) -> String {
        "E \(number(p.x, decimals: 1))  N \(number(p.y, decimals: 1))"
    }

    public static func latLon(_ c: LatLon) -> String {
        "\(number(c.lat, decimals: 6)), \(number(c.lon, decimals: 6))"
    }

    /// Degrees, minutes, seconds with hemisphere, e.g. "6°19'37.37\"S  106°25'51.37\"E" (seconds to 0.01″ ≈ 0.3 m).
    public static func dms(_ c: LatLon) -> String {
        "\(dms(c.lat, positive: "N", negative: "S"))  \(dms(c.lon, positive: "E", negative: "W"))"
    }

    static func dms(_ v: Double, positive: String, negative: String) -> String {
        // Round once in hundredths of a second, so 59.995″ carries into the minutes instead of showing 60.00″.
        let hundredths = Int((abs(v) * 360_000).rounded())
        let d = hundredths / 360_000, m = hundredths % 360_000 / 6000, s = Double(hundredths % 6000) / 100
        let sec = (s < 10 ? "0" : "") + String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), s)
        return "\(d)°\(m < 10 ? "0" : "")\(m)'\(sec)\"\(v < 0 ? negative : positive)"
    }

    public static func bytes(_ b: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}
