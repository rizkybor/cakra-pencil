import Foundation

/// Zona UTM di datum WGS84 (EPSG 326xx utara, 327xx selatan).
///
/// Pengecualian zona Norwegia/Svalbard tidak ditangani; Indonesia berada di zona 46–54.
public struct UTMZone: Codable, Hashable, Sendable {
    public let number: Int
    public let isNorth: Bool

    public init?(number: Int, isNorth: Bool) {
        guard (1...60).contains(number) else { return nil }
        self.number = number
        self.isNorth = isNorth
    }

    /// Zona yang memuat koordinat ini.
    public init(containing c: LatLon) {
        var lon = c.lon.truncatingRemainder(dividingBy: 360)
        if lon >= 180 { lon -= 360 }
        if lon < -180 { lon += 360 }
        let n = Int(floor((lon + 180) / 6)) + 1
        self.number = min(max(n, 1), 60)
        self.isNorth = c.lat >= 0
    }

    /// Hanya EPSG UTM WGS84 (32601–32660, 32701–32760) yang didukung sampai PROJ terpasang.
    public init?(epsg: Int) {
        switch epsg {
        case 32601...32660: self.init(number: epsg - 32600, isNorth: true)
        case 32701...32760: self.init(number: epsg - 32700, isNorth: false)
        default: return nil
        }
    }

    public var epsg: Int { (isNorth ? 32600 : 32700) + number }
    public var centralMeridian: Double { Double(number - 1) * 6 - 180 + 3 }
    public var falseNorthing: Double { isNorth ? 0 : 10_000_000 }

    /// Label ringkas untuk top bar, mis. "UTM 48S".
    public var label: String { "UTM \(number)\(isNorth ? "N" : "S")" }

    /// WKT1 gaya ESRI untuk file .prj; dibaca OCAD, OOM, dan QGIS.
    public var prjWKT: String {
        let name = "WGS_1984_UTM_Zone_\(number)\(isNorth ? "N" : "S")"
        return "PROJCS[\"\(name)\",GEOGCS[\"GCS_WGS_1984\",DATUM[\"D_WGS_1984\",SPHEROID[\"WGS_1984\",6378137.0,298.257223563]],PRIMEM[\"Greenwich\",0.0],UNIT[\"Degree\",0.0174532925199433]],PROJECTION[\"Transverse_Mercator\"],PARAMETER[\"False_Easting\",500000.0],PARAMETER[\"False_Northing\",\(Int(falseNorthing)).0],PARAMETER[\"Central_Meridian\",\(Int(centralMeridian)).0],PARAMETER[\"Scale_Factor\",0.9996],PARAMETER[\"Latitude_Of_Origin\",0.0],UNIT[\"Meter\",1.0]]"
    }

    public func project(_ c: LatLon) -> Point2D { UTM.forward(c, zone: self) }
    public func unproject(_ p: Point2D) -> LatLon { UTM.inverse(p, zone: self) }
}

/// Transverse Mercator dengan deret Krüger orde n⁴ (akurasi sub-milimeter di dalam zona).
public enum UTM {
    static let a = 6_378_137.0
    static let f = 1 / 298.257223563
    static let k0 = 0.9996
    static let falseEasting = 500_000.0

    static let n = f / (2 - f)
    static let bigA: Double = {
        let n2 = n * n
        return a / (1 + n) * (1 + n2 / 4 + n2 * n2 / 64)
    }()
    static let alpha: [Double] = {
        let n2 = n * n, n3 = n2 * n, n4 = n3 * n
        return [
            n / 2 - 2 * n2 / 3 + 5 * n3 / 16 + 41 * n4 / 180,
            13 * n2 / 48 - 3 * n3 / 5 + 557 * n4 / 1440,
            61 * n3 / 240 - 103 * n4 / 140,
            49561 * n4 / 161280,
        ]
    }()
    static let beta: [Double] = {
        let n2 = n * n, n3 = n2 * n, n4 = n3 * n
        return [
            n / 2 - 2 * n2 / 3 + 37 * n3 / 96 - n4 / 360,
            n2 / 48 + n3 / 15 - 437 * n4 / 1440,
            17 * n3 / 480 - 37 * n4 / 840,
            4397 * n4 / 161280,
        ]
    }()
    static let delta: [Double] = {
        let n2 = n * n, n3 = n2 * n, n4 = n3 * n
        return [
            2 * n - 2 * n2 / 3 - 2 * n3 + 116 * n4 / 45,
            7 * n2 / 3 - 8 * n3 / 5 - 227 * n4 / 45,
            56 * n3 / 15 - 136 * n4 / 35,
            4279 * n4 / 630,
        ]
    }()

    public static func forward(_ c: LatLon, zone: UTMZone) -> Point2D {
        let phi = c.lat * .pi / 180
        let dLambda = (c.lon - zone.centralMeridian) * .pi / 180
        let k = 2 * n.squareRoot() / (1 + n)
        let t = sinh(atanh(sin(phi)) - k * atanh(k * sin(phi)))
        let xiP = atan2(t, cos(dLambda))
        let etaP = atanh(sin(dLambda) / (1 + t * t).squareRoot())

        var xi = xiP, eta = etaP
        for j in 1...4 {
            let jj = Double(2 * j)
            xi += alpha[j - 1] * sin(jj * xiP) * cosh(jj * etaP)
            eta += alpha[j - 1] * cos(jj * xiP) * sinh(jj * etaP)
        }
        return Point2D(x: falseEasting + k0 * bigA * eta,
                       y: zone.falseNorthing + k0 * bigA * xi)
    }

    public static func inverse(_ p: Point2D, zone: UTMZone) -> LatLon {
        let xi = (p.y - zone.falseNorthing) / (k0 * bigA)
        let eta = (p.x - falseEasting) / (k0 * bigA)

        var xiP = xi, etaP = eta
        for j in 1...4 {
            let jj = Double(2 * j)
            xiP -= beta[j - 1] * sin(jj * xi) * cosh(jj * eta)
            etaP -= beta[j - 1] * cos(jj * xi) * sinh(jj * eta)
        }
        let chi = asin(sin(xiP) / cosh(etaP))
        var phi = chi
        for j in 1...4 {
            phi += delta[j - 1] * sin(Double(2 * j) * chi)
        }
        let lambda = atan2(sinh(etaP), cos(xiP))
        return LatLon(lat: phi * 180 / .pi, lon: zone.centralMeridian + lambda * 180 / .pi)
    }
}
