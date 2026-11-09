import Foundation

/// What OCCA Pro unlocks (see internal/business/OCCA-Paket-dan-Harga.pdf). Club and Education seats get Pro too.
/// Free keeps everything else: drawing with all ISOM/ISSprOM symbols, layers, grid, Symbol Guide, one course with
/// IOF descriptions, field notes and Pencil markup, and PDF export (with a small "Made with OCCA" credit).
enum ProFeature: String, CaseIterable, Identifiable {
    // Free limits
    case unlimitedProjects
    case largeMap
    case unlimitedCourses
    case unlimitedNotes
    // Map data
    case hdImagery
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
        case .unlimitedCourses: "Unlimited courses"
        case .unlimitedNotes: "Unlimited field notes"
        case .hdImagery: "HD satellite imagery"
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
        case .unlimitedNotes: "note.text"
        case .hdImagery: "globe.asia.australia"
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
    static let highlights: [ProFeature] = [.unlimitedProjects, .hdImagery, .contours, .courseExport, .trackRecording, .importMaps, .vectorExport]
}

/// Free plan limits. Existing projects and data over a limit are never locked: they open, show, and export to PDF;
/// only adding more needs Pro.
enum FreeLimits {
    static let projects = 2
    static let areaKm2 = 1.0
    static let courses = 1
    static let notes = 20

    static var areaLabel: String { "\(Int(areaKm2)) km²" }
}
