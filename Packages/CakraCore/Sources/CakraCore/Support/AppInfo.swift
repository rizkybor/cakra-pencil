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
    ]
}
