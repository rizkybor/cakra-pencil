import Foundation

/// Project metadata (the `projects` table in the PRD).
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var sheet: SheetSpec
    public var sketchDPI: Int
    /// EPSG UTM WGS84; nil until the frame is first placed (FR-1.2).
    public var crsEPSG: Int?
    /// Lower-left corner of the frame in the project CRS (meters).
    public var frameOrigin: Point2D?
    public var areaLocked: Bool
    public var snapStepM: Int
    /// Basemap imagery opacity 0–1 (FR-2.5). Optional so older .cakra files still load.
    public var basemapOpacity: Double?
    /// North line grid (optional); nil = never configured.
    public var northGrid: NorthGrid?
    /// Contour settings (FR-8); nil = defaults for the scale.
    public var contourSettings: ContourSettings?
    /// Fill opacity of symbolized areas on the map (tracing aid); export always uses full color like OCAD/OOM.
    public var areaOpacity: Double?
    /// Imported georeferenced image basemap (GeoTIFF); its file lives in the project package.
    public var basemapImage: BasemapImage?
    /// Area locked before "Reselect area"; kept until the new area is locked (for Cancel).
    public var areaBackup: AreaBackup?
    /// Basemap mode once the area is locked: true = live Apple Maps (real-time check while online),
    /// false/nil = the saved HD image (`ImagerySnapshot`). Optional so older files still load.
    public var liveBasemap: Bool?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, sheet: SheetSpec = SheetSpec(), sketchDPI: Int = 900,
                crsEPSG: Int? = nil, frameOrigin: Point2D? = nil, areaLocked: Bool = false, snapStepM: Int = 10,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sheet = sheet
        self.sketchDPI = sketchDPI
        self.crsEPSG = crsEPSG
        self.frameOrigin = frameOrigin
        self.areaLocked = areaLocked
        self.snapStepM = snapStepM
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var zone: UTMZone? { crsEPSG.flatMap(UTMZone.init(epsg:)) }

    public var basemapOpacityValue: Double { min(max(basemapOpacity ?? 1, 0), 1) }

    /// Live Apple Maps instead of the saved HD image (see `liveBasemap`).
    public var usesLiveBasemap: Bool { liveBasemap ?? false }

    public var grid: NorthGrid { northGrid ?? .standard(scale: sheet.scaleDenominator) }

    public var areaOpacityValue: Double { min(max(areaOpacity ?? 1, 0.1), 1) }

    public var contours: ContourSettings { contourSettings ?? .defaults(scale: sheet.scaleDenominator) }

    /// Frame from the origin + ground size of the sheet; nil if not yet placed.
    public var frame: MapFrame? {
        frameOrigin.map { MapFrame(origin: $0, widthM: sheet.groundWidthM, heightM: sheet.groundHeightM) }
    }

    /// Technical summary, e.g. "1:4000 · 900 dpi · UTM 48S".
    public var technicalSummary: String {
        var parts = ["1:\(sheet.scaleDenominator)", "\(sketchDPI) dpi"]
        if let zone { parts.append(zone.label) }
        return parts.joined(separator: " · ")
    }
}

/// Locked map area (CRS, frame, sheet, snap) saved before "Reselect area".
public struct AreaBackup: Codable, Hashable, Sendable {
    public var crsEPSG: Int?
    public var frameOrigin: Point2D?
    public var sheet: SheetSpec
    public var snapStepM: Int

    public init(of p: Project) {
        crsEPSG = p.crsEPSG
        frameOrigin = p.frameOrigin
        sheet = p.sheet
        snapStepM = p.snapStepM
    }

    /// Re-apply to the project and lock its area.
    public func restore(into p: inout Project) {
        p.crsEPSG = crsEPSG
        p.frameOrigin = frameOrigin
        p.sheet = sheet
        p.snapStepM = snapStepM
        p.areaLocked = true
        p.areaBackup = nil
    }
}

/// Full contents of one project loaded into memory.
public struct ProjectDocument: Hashable, Sendable {
    public var project: Project
    public var strokes: [Stroke]
    public var features: [Feature]
    /// Course planner: controls + courses (courses.json; absent in older packages).
    public var courses: CourseSet
    /// Fieldwork: GPS tracks, field notes, averaged positions (field.json; absent in older packages).
    public var field: FieldData

    public init(project: Project, strokes: [Stroke] = [], features: [Feature] = [], courses: CourseSet = CourseSet(),
                field: FieldData = FieldData()) {
        self.project = project
        self.strokes = strokes
        self.features = features
        self.courses = courses
        self.field = field
    }
}

/// .cakra package = folder containing project.json + strokes.json + features.json.
///
/// Uses atomically written JSON for now; the PRD plan (SQLite + GRDB, WAL, R*Tree) follows
/// once the stroke count approaches the 20,000 target.
public enum CakraPackage {
    public static let fileExtension = "cakra"
    static let projectFile = "project.json"
    static let strokesFile = "strokes.json"
    static let featuresFile = "features.json"
    static let coursesFile = "courses.json"
    static let fieldFile = "field.json"
    /// Field note photos (JPEG) inside the package.
    public static let fieldPhotosFolder = "field-photos"
    static let formatVersion = 1

    struct StrokesEnvelope: Codable {
        var version: Int
        var strokes: [Stroke]
    }

    struct CoursesEnvelope: Codable {
        var version: Int
        var courses: CourseSet
    }

    struct FieldEnvelope: Codable {
        var version: Int
        var field: FieldData
    }

    struct FeaturesEnvelope: Codable {
        var version: Int
        var features: [Feature]
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func write(_ doc: ProjectDocument, to url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let enc = encoder()
        try enc.encode(doc.project).write(to: url.appendingPathComponent(projectFile), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try enc.encode(StrokesEnvelope(version: formatVersion, strokes: doc.strokes))
            .write(to: url.appendingPathComponent(strokesFile), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try enc.encode(FeaturesEnvelope(version: formatVersion, features: doc.features))
            .write(to: url.appendingPathComponent(featuresFile), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let coursesURL = url.appendingPathComponent(coursesFile)
        if doc.courses.isEmpty && doc.courses.eventTitle.isEmpty {
            try? FileManager.default.removeItem(at: coursesURL)
        } else {
            try enc.encode(CoursesEnvelope(version: formatVersion, courses: doc.courses))
                .write(to: coursesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let fieldURL = url.appendingPathComponent(fieldFile)
        if doc.field.isEmpty {
            try? FileManager.default.removeItem(at: fieldURL)
        } else {
            try enc.encode(FieldEnvelope(version: formatVersion, field: doc.field))
                .write(to: fieldURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    public static func readProject(at url: URL) throws -> Project {
        try decoder().decode(Project.self, from: Data(contentsOf: url.appendingPathComponent(projectFile)))
    }

    public static func read(at url: URL) throws -> ProjectDocument {
        let project = try readProject(at: url)
        let strokesURL = url.appendingPathComponent(strokesFile)
        let strokes: [Stroke]
        if FileManager.default.fileExists(atPath: strokesURL.path) {
            strokes = try decoder().decode(StrokesEnvelope.self, from: Data(contentsOf: strokesURL)).strokes
        } else {
            strokes = []
        }
        // features.json does not exist in older packages.
        let featuresURL = url.appendingPathComponent(featuresFile)
        let features: [Feature]
        if FileManager.default.fileExists(atPath: featuresURL.path) {
            features = try decoder().decode(FeaturesEnvelope.self, from: Data(contentsOf: featuresURL)).features
        } else {
            features = []
        }
        let coursesURL = url.appendingPathComponent(coursesFile)
        var courses = CourseSet()
        if FileManager.default.fileExists(atPath: coursesURL.path) {
            courses = try decoder().decode(CoursesEnvelope.self, from: Data(contentsOf: coursesURL)).courses
        }
        let fieldURL = url.appendingPathComponent(fieldFile)
        var field = FieldData()
        if FileManager.default.fileExists(atPath: fieldURL.path),
           let decoded = try? decoder().decode(FieldEnvelope.self, from: Data(contentsOf: fieldURL)) {
            field = decoded.field
        }
        return ProjectDocument(project: project, strokes: strokes, features: features, courses: courses, field: field)
    }
}

#if !os(iOS)
extension Data.WritingOptions {
    // Data Protection exists only on iOS; on macOS (unit tests) this option has no effect.
    static let completeFileProtectionUntilFirstUserAuthentication: Data.WritingOptions = []
}
#endif
