import Foundation

/// `.occa` project file (OCCA; formerly `.coca` and `.cpencil`, which can still be opened): the entire contents of a `.cakra` package (project.json, objects, sketches, courses, course drawings,
/// contours, DEM, preview) in a single file that can be saved, shared, and then imported on either iPad or Mac.
///
/// Contents: "CPENCIL1" (8 bytes) + LZFSE-compressed payload. Payload: entry count (UInt32), then for each entry
/// path length (UInt32) + UTF-8 relative path + data length (UInt64) + data. All numbers are little-endian.
public enum ProjectArchive {
    public static let fileExtension = "occa"
    /// Legacy extensions still accepted on import.
    public static let legacyFileExtensions = ["coca", "cpencil"]
    public static var acceptedExtensions: [String] { [fileExtension] + legacyFileExtensions }
    public static let typeIdentifier = "id.cakrapencil.project"
    static let magic = Data("CPENCIL1".utf8)
    static let maxEntries = 100_000
    static let maxTotalBytes: UInt64 = 4 << 30

    public enum ArchiveError: Error, LocalizedError, Equatable {
        case notArchive
        case corrupt(String)
        case unsafePath(String)
        case missingProject

        public var errorDescription: String? {
            switch self {
            case .notArchive: return "Not an \(AppInfo.name) project file (.\(fileExtension))."
            case let .corrupt(what): return "Corrupt project file: \(what)."
            case let .unsafePath(p): return "Project file contains an unsafe path: \(p)."
            case .missingProject: return "Project file does not contain project.json."
            }
        }
    }

    // MARK: Save

    /// Pack all files in the package (recursively) into a single archive.
    public static func pack(packageAt dir: URL) throws -> Data {
        let base = dir.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys) else {
            throw ArchiveError.corrupt("package cannot be read")
        }
        var files: [(String, URL)] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: Set(keys)))?.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(base.path + "/") else { continue }
            let rel = String(full.dropFirst(base.path.count + 1))
            // System files (e.g. .DS_Store) are excluded.
            if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            // Captured Apple Maps imagery is a local cache: each device captures its own.
            if rel.hasPrefix(ImagerySnapshot.folder + "/") { continue }
            files.append((rel, url))
        }
        guard files.contains(where: { $0.0 == "project.json" }) else { throw ArchiveError.missingProject }
        files.sort { $0.0 < $1.0 }

        var payload = Data()
        append(UInt32(files.count), to: &payload)
        for (rel, url) in files {
            let path = Data(rel.utf8)
            let data = try Data(contentsOf: url)
            append(UInt32(path.count), to: &payload)
            payload.append(path)
            append(UInt64(data.count), to: &payload)
            payload.append(data)
        }
        let compressed = try (payload as NSData).compressed(using: .lzfse) as Data
        return magic + compressed
    }

    // MARK: Open

    /// Archive contents: relative path → data. Rejects absolute paths, "..", or hidden files.
    public static func entries(of archive: Data) throws -> [String: Data] {
        guard archive.count >= magic.count, archive.prefix(magic.count) == magic else { throw ArchiveError.notArchive }
        let payload: Data
        do {
            payload = try (Data(archive.dropFirst(magic.count)) as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw ArchiveError.corrupt("decompression failed")
        }
        var reader = Reader(data: payload)
        let count = Int(try reader.uint32())
        guard count <= maxEntries else { throw ArchiveError.corrupt("too many files") }
        var out: [String: Data] = [:]
        var total: UInt64 = 0
        for _ in 0..<count {
            let pathLen = Int(try reader.uint32())
            guard pathLen > 0, pathLen <= 1024 else { throw ArchiveError.corrupt("path length") }
            guard let path = String(data: try reader.bytes(pathLen), encoding: .utf8) else { throw ArchiveError.corrupt("path") }
            try validate(path)
            let size = try reader.uint64()
            total += size
            guard total <= maxTotalBytes, size <= UInt64(Int.max) else { throw ArchiveError.corrupt("file size") }
            out[path] = try reader.bytes(Int(size))
        }
        guard reader.isAtEnd else { throw ArchiveError.corrupt("trailing data at end") }
        guard out["project.json"] != nil else { throw ArchiveError.missingProject }
        return out
    }

    static func validate(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.contains("\\"), !parts.isEmpty,
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.hasPrefix(".") }) else {
            throw ArchiveError.unsafePath(path)
        }
    }

    /// Unpack the archive into folder `dir` (created if it does not exist).
    public static func unpack(_ archive: Data, into dir: URL) throws {
        for (path, data) in try entries(of: archive) {
            // Captured imagery is a per-device cache; never taken from someone else's file.
            if path.hasPrefix(ImagerySnapshot.folder + "/") { continue }
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Import the archive as a project in folder `root` (package `<id>.cakra`). If its id is already taken
    /// (`existingIDs`), the project gets a new id and its name gets the suffix " (imported)" — nothing is overwritten.
    /// Returns the location of the imported package.
    @discardableResult
    public static func importArchive(_ archive: Data, intoRoot root: URL, existingIDs: Set<UUID>) throws -> URL {
        let staging = root.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try unpack(archive, into: staging)
        var project = try CakraPackage.readProject(at: staging)
        if existingIDs.contains(project.id) {
            project.id = UUID()
            project.name += " (imported)"
            try CakraPackage.encoder().encode(project).write(to: staging.appendingPathComponent(CakraPackage.projectFile), options: .atomic)
        }
        // Make sure the contents read completely before it enters the project list.
        _ = try CakraPackage.read(at: staging)
        let target = root.appendingPathComponent(project.id.uuidString).appendingPathExtension(CakraPackage.fileExtension)
        try FileManager.default.moveItem(at: staging, to: target)
        return target
    }

    // MARK: Binary

    static func append<T: FixedWidthInteger>(_ v: T, to d: inout Data) {
        withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
    }

    struct Reader {
        let data: Data
        var offset = 0

        init(data: Data) { self.data = Data(data) }

        var isAtEnd: Bool { offset == data.count }

        mutating func bytes(_ n: Int) throws -> Data {
            guard n >= 0, offset + n <= data.count else { throw ArchiveError.corrupt("truncated") }
            defer { offset += n }
            return data.subdata(in: offset..<offset + n)
        }

        mutating func uint32() throws -> UInt32 {
            let b = try bytes(4)
            return b.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        }

        mutating func uint64() throws -> UInt64 {
            let b = try bytes(8)
            return b.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
        }
    }
}
