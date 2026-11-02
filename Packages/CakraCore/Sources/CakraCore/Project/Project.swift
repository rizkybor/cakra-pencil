import Foundation

/// Metadata proyek (tabel `projects` di PRD).
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var sheet: SheetSpec
    public var sketchDPI: Int
    /// EPSG UTM WGS84; nil sampai frame pertama kali ditempatkan (FR-1.2).
    public var crsEPSG: Int?
    /// Pojok kiri bawah frame dalam CRS proyek (meter).
    public var frameOrigin: Point2D?
    public var areaLocked: Bool
    public var snapStepM: Int
    /// Opacity citra basemap 0–1 (FR-2.5). Opsional agar file .cakra lama tetap terbaca.
    public var basemapOpacity: Double?
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

    /// Frame sesuai origin + ukuran tanah dari sheet; nil bila belum ditempatkan.
    public var frame: MapFrame? {
        frameOrigin.map { MapFrame(origin: $0, widthM: sheet.groundWidthM, heightM: sheet.groundHeightM) }
    }

    /// Ringkasan teknis, mis. "1:4000 · 900 dpi · UTM 48S".
    public var technicalSummary: String {
        var parts = ["1:\(sheet.scaleDenominator)", "\(sketchDPI) dpi"]
        if let zone { parts.append(zone.label) }
        return parts.joined(separator: " · ")
    }
}

/// Isi lengkap satu proyek yang dimuat ke memori.
public struct ProjectDocument: Hashable, Sendable {
    public var project: Project
    public var strokes: [Stroke]

    public init(project: Project, strokes: [Stroke] = []) {
        self.project = project
        self.strokes = strokes
    }
}

/// Paket .cakra = folder berisi project.json + strokes.json.
///
/// Sementara memakai JSON yang ditulis atomik; rencana PRD (SQLite + GRDB, WAL, R*Tree) menyusul
/// begitu jumlah stroke mendekati target 20.000.
public enum CakraPackage {
    public static let fileExtension = "cakra"
    static let projectFile = "project.json"
    static let strokesFile = "strokes.json"
    static let formatVersion = 1

    struct StrokesEnvelope: Codable {
        var version: Int
        var strokes: [Stroke]
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
        return ProjectDocument(project: project, strokes: strokes)
    }
}

#if !os(iOS)
extension Data.WritingOptions {
    // Data Protection hanya ada di iOS; di macOS (unit test) opsi ini tidak berpengaruh.
    static let completeFileProtectionUntilFirstUserAuthentication: Data.WritingOptions = []
}
#endif
