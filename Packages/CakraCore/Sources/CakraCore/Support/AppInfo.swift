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
    public static let releaseDate = "November 2026"
    public static let supportedPlatforms = "iPad with iPadOS 17 or later · Mac with Apple silicon and macOS 14 Sonoma or later"
    public static let unsupportedPlatforms = "Not available for Windows, Android, or iPhone."
}
