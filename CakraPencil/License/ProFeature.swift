import Foundation

/// What a license key unlocks (Trial, Professional, Lifetime, Organization); Starter has `FreeLimits`.
/// Starter keeps everything else: drawing with all ISOM/ISSprOM symbols, layers, grid, Symbol Guide, course planning,
/// PDF export (with a small "Made with OCCA" credit), and up to `FreeLimits.courses` courses. No fieldwork, contours,
/// live basemap, or my location.
enum ProFeature: String, CaseIterable, Identifiable {
    // Free limits
    case unlimitedProjects
    case largeMap
    case unlimitedCourses
    case fieldwork
    // Map data
    case hdImagery
    case liveBasemap
    case myLocation
    case basemapImport
    case contours
    case importMaps
    case customSymbols
    // Course
    case courseExport
    // Field
    case trackRecording
    case gpx
    case fieldToMap
    case fieldTransfer
    case fieldReport
    // Export
    case rasterExport
    case vectorExport
    case noWatermark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimitedProjects: "Unlimited projects"
        case .largeMap: "Maps larger than \(FreeLimits.areaLabel)"
        case .unlimitedCourses: "More than \(FreeLimits.courses) courses"
        case .fieldwork: "Fieldwork: field mode, notes, and photos"
        case .hdImagery: "HD satellite imagery"
        case .liveBasemap: "Live basemap (real-time Apple Maps)"
        case .myLocation: "Show my location on the map"
        case .basemapImport: "GeoTIFF basemaps"
        case .contours: "Contours from elevation data"
        case .importMaps: "Import OCAD / OOM maps and courses"
        case .customSymbols: "Custom symbol sets"
        case .courseExport: "IOF XML 3.0 and course PNG export"
        case .trackRecording: "Track recording and survey coverage"
        case .gpx: "GPX import and export"
        case .fieldToMap: "Turn field notes and tracks into map objects"
        case .fieldTransfer: "Send field data between devices"
        case .fieldReport: "Field report PDF"
        case .rasterExport: "Raster export (TIFF, PNG, JPEG)"
        case .vectorExport: "Vector export (OOM .omap, DXF)"
        case .noWatermark: "PDF without the OCCA credit"
        }
    }

    var icon: String {
        switch self {
        case .unlimitedProjects: "square.stack.3d.up"
        case .largeMap: "arrow.up.left.and.arrow.down.right"
        case .unlimitedCourses: "point.3.connected.trianglepath.dotted"
        case .fieldwork: "figure.walk"
        case .hdImagery: "globe.asia.australia"
        case .liveBasemap: "dot.radiowaves.left.and.right"
        case .myLocation: "location"
        case .basemapImport: "photo.on.rectangle.angled"
        case .contours: "mountain.2"
        case .importMaps: "doc.badge.plus"
        case .customSymbols: "square.grid.3x3"
        case .courseExport: "doc.text"
        case .trackRecording: "record.circle"
        case .gpx: "point.topleft.down.to.point.bottomright.curvepath"
        case .fieldToMap: "wand.and.stars"
        case .fieldTransfer: "arrow.left.arrow.right"
        case .fieldReport: "doc.richtext"
        case .rasterExport: "photo"
        case .vectorExport: "square.and.arrow.up"
        case .noWatermark: "checkmark.seal"
        }
    }

    /// The short list shown on the plans screen.
    static let highlights: [ProFeature] = [.unlimitedProjects, .unlimitedCourses, .fieldwork, .contours, .hdImagery, .courseExport, .trackRecording, .importMaps, .vectorExport]
}

/// Starter (free) plan limits. Existing projects and data over a limit are never locked: they open, show, and export to PDF;
/// only adding more needs a license key.
enum FreeLimits {
    static let projects = 1
    static let areaKm2 = 1.0
    static let courses = 4

    static var areaLabel: String { "\(Int(areaKm2)) km²" }
}
