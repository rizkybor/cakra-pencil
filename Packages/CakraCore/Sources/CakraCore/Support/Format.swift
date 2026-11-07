import Foundation

/// Format angka teknis dengan konvensi Indonesia (titik ribuan, koma desimal).
public enum Fmt {
    static let locale = Locale(identifier: "id_ID")

    public static func number(_ v: Double, decimals: Int) -> String {
        v.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    /// "1.050 m" atau "0,141 m".
    public static func meters(_ v: Double, decimals: Int = 0) -> String { "\(number(v, decimals: decimals)) m" }

    /// "3,2 km" (panjang lintasan, 0,1 km seperti Purple Pen).
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

    public static func bytes(_ b: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }
}
