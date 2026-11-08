import Foundation

/// `.occafield` field data file: the fieldwork of a project (tracks, notes with photos, offsets, vegetation samples)
/// without the drawing. Sent from the iPad after each survey day and imported into the same project on the Mac (or
/// another iPad): new tracks and notes are added, nothing already there is duplicated, the drawing is untouched.
///
/// Contents: "OCCAFLD1" + the same LZFSE payload as `.occa` files, with `manifest.json`, `field.json` and
/// `field-photos/<name>.jpg`.
public struct FieldPackage: Sendable {
    public static let fileExtension = "occafield"
    public static let typeIdentifier = "id.cakrapencil.fielddata"
    static let magic = Data("OCCAFLD1".utf8)

    public struct Manifest: Codable, Hashable, Sendable {
        public var formatVersion = 1
        public var projectID: UUID
        public var projectName: String
        public var zone: UTMZone
        public var exportedAt: Date
        /// Only data made after this moment ("new since last export"); nil = everything.
        public var since: Date?
        public var app: String
    }

    public enum PackageError: LocalizedError, Equatable {
        case notFieldData, newerFormat, empty
        public var errorDescription: String? {
            switch self {
            case .notFieldData: return "This is not an \(AppInfo.name) field data file (.\(FieldPackage.fileExtension))."
            case .newerFormat: return "This field data file was made by a newer version of \(AppInfo.name). Update the app to import it."
            case .empty: return "There is no field data to export."
            }
        }
    }

    public var manifest: Manifest
    public var field: FieldData
    /// Photo file name → JPEG data.
    public var photos: [String: Data]

    /// Field data of a project; `since`: only tracks with points recorded after it and notes made after it.
    public static func make(field: FieldData, since: Date?, projectID: UUID, projectName: String, zone: UTMZone,
                            exportedAt: Date = Date(), photo: (String) -> Data?) throws -> FieldPackage {
        var f = field
        if let since {
            f.tracks = f.tracks.filter { t in t.endTime.map { $0 >= since } ?? true }
            f.notes = f.notes.filter { $0.createdAt >= since }
        }
        guard !f.isEmpty else { throw PackageError.empty }
        var photos: [String: Data] = [:]
        for name in f.attachmentFiles { if let d = photo(name) { photos[safeName(name)] = d } }
        let manifest = Manifest(projectID: projectID, projectName: projectName, zone: zone, exportedAt: exportedAt, since: since,
                                app: AppInfo.name)
        return FieldPackage(manifest: manifest, field: f, photos: photos)
    }

    static func safeName(_ name: String) -> String { (name as NSString).lastPathComponent }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        var entries: [(String, Data)] = [("manifest.json", try enc.encode(manifest)), ("field.json", try enc.encode(field))]
        for (name, data) in photos { entries.append(("\(CakraPackage.fieldPhotosFolder)/\(Self.safeName(name))", data)) }
        return try ProjectArchive.encode(entries, magic: Self.magic)
    }

    public static func decode(_ data: Data) throws -> FieldPackage {
        let entries: [String: Data]
        do { entries = try ProjectArchive.decode(data, magic: magic) } catch ProjectArchive.ArchiveError.notArchive { throw PackageError.notFieldData }
        guard let m = entries["manifest.json"], let f = entries["field.json"] else { throw PackageError.notFieldData }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let manifest = try dec.decode(Manifest.self, from: m)
        guard manifest.formatVersion <= 1 else { throw PackageError.newerFormat }
        let field = try dec.decode(FieldData.self, from: f)
        var photos: [String: Data] = [:]
        let prefix = CakraPackage.fieldPhotosFolder + "/"
        for (path, d) in entries where path.hasPrefix(prefix) {
            let name = String(path.dropFirst(prefix.count))
            guard !name.contains("/") else { continue }
            photos[name] = d
        }
        return FieldPackage(manifest: manifest, field: field, photos: photos)
    }
}

/// What an import added.
public struct FieldMergeResult: Hashable, Sendable {
    public var newTracks = 0
    /// Tracks already in the project that came back longer (recording continued after the last export).
    public var extendedTracks = 0
    public var newNotes = 0
    /// Tracks and notes already in the project (same id), kept as they are.
    public var alreadyThere = 0
    /// Photo files the project doesn't have yet (to be written into its field-photos folder).
    public var newPhotos: [String] = []

    public var addedAnything: Bool { newTracks + extendedTracks + newNotes > 0 || !newPhotos.isEmpty }

    /// "2 new tracks, 14 new notes · 3 already in the project"
    public var summary: String {
        func n(_ c: Int, _ word: String) -> String { "\(c) \(word)\(c == 1 ? "" : "s")" }
        var parts: [String] = []
        if newTracks > 0 { parts.append(n(newTracks, "new track")) }
        if extendedTracks > 0 { parts.append(n(extendedTracks, "longer track")) }
        if newNotes > 0 { parts.append(n(newNotes, "new note")) }
        if parts.isEmpty, !newPhotos.isEmpty { parts.append(n(newPhotos.count, "new photo")) }
        var s = parts.isEmpty ? "Nothing new" : parts.joined(separator: ", ")
        if alreadyThere > 0 { s += " · \(alreadyThere) already in the project" }
        return s
    }
}

extension FieldData {
    /// Add field data from another device. Same id = the same track or note: the local one is kept (its name, done
    /// state, map object link and edits made at the desk), a track that came back with more points gets them, a note
    /// gains photos it didn't have. Everything new is appended.
    @discardableResult
    public mutating func merge(_ incoming: FieldData, existingPhotos: Set<String> = []) -> FieldMergeResult {
        var r = FieldMergeResult()
        for t in incoming.tracks {
            if let i = tracks.firstIndex(where: { $0.id == t.id }) {
                if t.points.count > tracks[i].points.count {
                    tracks[i].points = t.points
                    r.extendedTracks += 1
                } else {
                    r.alreadyThere += 1
                }
            } else {
                var t = t
                // Another device's "Track 1": keep both, the incoming one becomes "Track 1 (2)".
                if tracks.contains(where: { $0.name == t.name }) {
                    var k = 2
                    while tracks.contains(where: { $0.name == "\(t.name) (\(k))" }) { k += 1 }
                    t.name = "\(t.name) (\(k))"
                }
                tracks.append(t)
                r.newTracks += 1
            }
        }
        for n in incoming.notes {
            if let i = notes.firstIndex(where: { $0.id == n.id }) {
                let missing = n.photos.filter { !notes[i].photos.contains($0) }
                notes[i].photos += missing
                // Markups drawn on the other device (kept if this one has its own).
                let marked = (n.markedPhotos ?? []).filter { !notes[i].hasMarkup($0) }
                if !marked.isEmpty { notes[i].markedPhotos = (notes[i].markedPhotos ?? []) + marked }
                r.alreadyThere += 1
            } else {
                notes.append(n)
                r.newNotes += 1
            }
        }
        let wanted = Set(attachmentFiles)
        r.newPhotos = incoming.attachmentFiles.filter { wanted.contains($0) && !existingPhotos.contains($0) }
        if r.newTracks + r.extendedTracks > 0 { showTracks = true }
        if r.newNotes > 0 { showNotes = true }
        return r
    }

    /// The same data in another UTM zone (a project whose area is in a different zone than the one it came from).
    public func reprojected(from a: UTMZone, to b: UTMZone) -> FieldData {
        guard a != b else { return self }
        func p(_ x: Point2D) -> Point2D { b.project(a.unproject(x)) }
        var f = self
        for i in f.tracks.indices { for j in f.tracks[i].points.indices { f.tracks[i].points[j].position = p(f.tracks[i].points[j].position) } }
        for i in f.notes.indices {
            f.notes[i].position = p(f.notes[i].position)
            if let from = f.notes[i].offset?.from { f.notes[i].offset?.from = p(from) }
        }
        return f
    }
}
