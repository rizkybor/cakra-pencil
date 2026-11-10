import Foundation

/// App identity for on-screen text and output files (PDF, OMAP, IOF XML, KML).
public enum AppInfo {
    /// Short app name.
    public static let name = "OCCA"
    /// Full app name.
    public static let fullName = "Orienteering Cakra CAD Application"
    /// Short description (front page, README).
    public static let tagline = "Draw, edit, and print ISOM/ISSprOM orienteering maps — on iPad and Mac."
    /// Credits (About screen, project list footer, export notes).
    public static let developer = "Rizky Ajie Kurniawan"
    public static let supporter = "PT. Jendela Cakra Digital"
    public static let supporterURL = "https://jcdigital.co.id"
    /// Contact of the supporting company (About screen), as in the company's letters and emails.
    public static let supporterAddress = "Jl. Pd. Cabe Raya No.7, Pd. Cabe Udik, Kec. Pamulang, Kota Tangerang Selatan, Banten 15418, Indonesia"
    public static let supporterEmail = "contact@jcdigital.co.id"
    public static let supporterPhone = "+62 878-8279-2511"
    /// WhatsApp number in international form without "+" (wa.me link).
    public static let supporterWhatsApp = "6287882792511"
    /// Country of origin (credits).
    public static let country = "Indonesia"
    public static let copyright = "© 2026 Rizky Ajie Kurniawan. All rights reserved."
    /// Release and supported platforms (About screen, README).
    /// Not released yet: "Coming soon", unpublished (not on the App Store).
    public static let releaseStatus = "Coming soon"
    public static let publication = "Unpublished — not yet available on the App Store."
    public static let supportedPlatforms = "iPad with iPadOS 17 or later · Mac with Apple silicon and macOS 14 Sonoma or later"
    public static let unsupportedPlatforms = "Not available for Windows, Android, or iPhone."
    /// File compatibility (About screen, README): what OCCA opens and writes.
    public static let supportedFiles: [(title: String, detail: String)] = [
        ("OCAD 10, OCAD 12 … OCAD 2018 (.ocd)", "Maps (lines, areas, point symbols, colors, georeferencing) and course setting files (controls and courses)."),
        ("OOM — OpenOrienteering Mapper (.omap, .xmap)", "Maps, and start / control / finish symbols as controls."),
        ("OCCA project (.occa)", "Whole projects between iPad and Mac; courses can be imported into another project."),
        ("GeoTIFF", "Georeferenced image basemaps (UTM WGS84 or WGS84 lat/lon)."),
        ("Export", "OOM .omap, DXF (for OCAD), IOF XML 3.0 courses, georeferenced PDF, PNG / TIFF / JPEG + world file, Shapefile / KML / KMZ contours."),
        ("Symbol sets", "OCCA symbol sets (.occasym — import and export), OCAD (.ocd) and OpenOrienteering Mapper (.omap, .xmap) symbol sets."),
    ]

    /// Built-in symbol sets, their source, and license (About screen, README).
    public struct SymbolSetCredit: Sendable {
        public let title: String
        public let source: String
        public let license: String
        public let url: String
    }

    public static let symbolSetCredits: [SymbolSetCredit] = [
        SymbolSetCredit(title: "ISOM 2017-2 (1:15000) and ISSprOM 2019-2 (1:4000) symbol sets · OCCA (default)",
                        source: "Made for OCCA by Rizky Ajie Kurniawan from the IOF specifications (Revision 6, January 2024): codes, names, sizes, colors and color order.",
                        license: "Part of OCCA (proprietary, see License). Stored as .occasym files.",
                        url: "https://orienteering.sport/iof/mapping/"),
        SymbolSetCredit(title: "ISInOM 6.7.3 indoor symbol set (1:700) · OCCA",
                        source: "Made for OCCA by Rizky Ajie Kurniawan from the IOF International Specification for Indoor Orienteering Maps v6.7.3 (IOF Map Commission, July 2026): codes, names, sizes, colors and color order.",
                        license: "Part of OCCA (proprietary, see License). The specification is licensed CC BY 4.0. Stored as an .occasym file.",
                        url: "https://orienteering.sport/iof/mapping/"),
        SymbolSetCredit(title: "ISSprOM 2019-2 symbol set (OCAD, 1:4000)",
                        source: "British Orienteering (BOF O-Map 4000 O12 v1).",
                        license: "Published by British Orienteering for orienteering mapping.",
                        url: "https://www.britishorienteering.org.uk"),
        SymbolSetCredit(title: "ISOM 2017-2 (1:10000), ISSprOM 2019 (1:4000), and Course design (1:4000, 1:10000) symbol sets",
                        source: "OpenOrienteering Mapper — © OpenOrienteering Mapper contributors. Included unmodified as data files; OCCA reads them with its own code.",
                        license: "GNU General Public License v3.0 (GPL-3.0). The full license text is included in the app.",
                        url: "https://github.com/OpenOrienteering/mapper/tree/master/symbol%20sets"),
    ]

    /// Specifications the symbol sets follow.
    public static let specificationCredit = "ISOM 2017-2, ISSprOM 2019-2 and ISInOM 6.7.3 specifications by the International Orienteering Federation (IOF); ISInOM is licensed CC BY 4.0."
}
