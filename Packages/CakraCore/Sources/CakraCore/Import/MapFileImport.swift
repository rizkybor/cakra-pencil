import Foundation

/// A new project from an OCAD (.ocd) or OOM (.omap/.xmap) map file: its objects, its courses (OCAD course setting
/// files), and a locked map frame centered on the content.
///
/// OCAD files keep projected (UTM) coordinates but not which UTM zone they are in, so the zone is chosen by the user;
/// OOM files store a lat/lon reference point, so the zone follows from it.
public struct MapFileContent: Sendable {
    public enum Source: Sendable { case ocad, omap }

    public var source: Source
    public var scale: Int
    /// Objects in projected meters (for OOM: in `knownZone`).
    public var features: [Feature]
    /// Controls and courses (OCAD course setting files); nil when there are none.
    public var courses: OcadCourseImport?
    /// UTM zone stated by the file (OOM); nil for OCAD.
    public var knownZone: UTMZone?
    public var report: OcadImportReport

    /// Bounding box of all objects and controls (projected meters).
    public var extent: Rect2D? {
        var pts = features.compactMap(\.bounds).flatMap { [Point2D(x: $0.minX, y: $0.minY), Point2D(x: $0.maxX, y: $0.maxY)] }
        pts += courses?.controls.map(\.position) ?? []
        return Rect2D(points: pts)
    }

    public var isEmpty: Bool { features.isEmpty && (courses?.controls.isEmpty ?? true) }
}

public enum MapFileImport {
    public static let fileExtensions = ["ocd", "omap", "xmap"]
    static let maxBytes = 200_000_000

    public enum ImportError: Error, LocalizedError, Equatable {
        case tooLarge
        case empty
        case unsupportedExtension(String)

        public var errorDescription: String? {
            switch self {
            case .tooLarge: return "The map file is larger than 200 MB."
            case .empty: return "No map objects or courses in this file."
            case let .unsupportedExtension(e): return "Unsupported map file (.\(e)). Use .ocd, .omap, or .xmap."
            }
        }
    }

    public static func read(_ data: Data, fileExtension: String) throws -> MapFileContent {
        guard data.count <= maxBytes else { throw ImportError.tooLarge }
        let content: MapFileContent
        switch fileExtension.lowercased() {
        case "ocd":
            let map = try OcadReader.read(data)
            let courses = try OcadReader.courses(data)
            var (features, report) = try map.features()
            // In a course setting file the course symbols (7xx) become Course Planner controls, not map objects.
            if !courses.controls.isEmpty {
                features.removeAll { f in f.symbolCode.flatMap { Double($0) }.map { (700..<800).contains($0) } ?? false }
            }
            content = MapFileContent(source: .ocad, scale: Int(map.scale.rounded()), features: features,
                                     courses: courses.controls.isEmpty ? nil : courses, knownZone: nil, report: report)
        case "omap", "xmap":
            guard let geo = try OmapReader.georeference(data) else { throw OmapReadError.notGeoreferenced }
            let zone = UTMZone(containing: geo.reference)
            let (features, report) = try OmapReader.read(data, zone: zone)
            content = MapFileContent(source: .omap, scale: geo.scale, features: features, courses: nil, knownZone: zone, report: report)
        default:
            throw ImportError.unsupportedExtension(fileExtension)
        }
        guard !content.isEmpty else { throw ImportError.empty }
        return content
    }

    /// Zones to try when looking for the right one for an OCAD map (which doesn't store its zone): the neighbors of
    /// `zone` first (±1, ±2, …), in the same hemisphere, then the same steps in the other hemisphere. `zone` itself is
    /// not included.
    public static func candidateZones(around zone: UTMZone, maxSteps: Int = 8) -> [UTMZone] {
        var out: [UTMZone] = []
        for north in [zone.isNorth, !zone.isNorth] {
            if north != zone.isNorth, let z = UTMZone(number: zone.number, isNorth: north) { out.append(z) }
            for step in 1...max(maxSteps, 1) {
                for n in [zone.number + step, zone.number - step] {
                    let wrapped = (n - 1 + 60) % 60 + 1
                    if let z = UTMZone(number: wrapped, isNorth: north), !out.contains(z), z != zone { out.append(z) }
                }
            }
        }
        return out
    }

    /// Scale for the project sheet: the map's own scale when it is a preset, otherwise the nearest preset.
    public static func sheetScale(for scale: Int) -> Int {
        MapPresets.scales.min { abs($0 - scale) < abs($1 - scale) } ?? 4000
    }

    /// Project document: A4 in the orientation that fits the content, frame centered on it and locked, objects and
    /// courses included.
    public static func document(name: String, content: MapFileContent, zone: UTMZone, snapStepM: Int = 10) -> ProjectDocument {
        let e = content.extent
        let orientation: SheetOrientation = (e.map { $0.width > $0.height } ?? false) ? .landscape : .portrait
        let sheet = SheetSpec(orientation: orientation, scaleDenominator: sheetScale(for: content.scale))
        var project = Project(name: name, sheet: sheet, crsEPSG: zone.epsg, areaLocked: true, snapStepM: snapStepM)
        if let e {
            project.frameOrigin = MapFrame(center: Point2D(x: (e.minX + e.maxX) / 2, y: (e.minY + e.maxY) / 2), sheet: sheet)
                .snapped(toStep: snapStepM).origin
        }
        var courses = CourseSet()
        if let c = content.courses {
            courses.controls = c.controls
            courses.courses = c.courses
        }
        return ProjectDocument(project: project, features: content.features, courses: courses)
    }
}
