import Foundation

/// File proyek `.occa` (OCCA; dulu `.coca` dan `.cpencil`, tetap bisa dibuka): seluruh isi paket `.cakra` (project.json, objek, sketsa, lintasan, gambar lintasan,
/// kontur, DEM, pratinjau) dalam satu file yang bisa disimpan, dibagikan, lalu diimpor di iPad maupun Mac.
///
/// Isi: "CPENCIL1" (8 byte) + payload terkompresi LZFSE. Payload: jumlah entri (UInt32), lalu tiap entri
/// panjang path (UInt32) + path relatif UTF-8 + panjang data (UInt64) + data. Semua bilangan little-endian.
public enum ProjectArchive {
    public static let fileExtension = "occa"
    /// Ekstensi lama yang tetap diterima saat impor.
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
            case .notArchive: return "Bukan file proyek \(AppInfo.name) (.\(fileExtension))."
            case let .corrupt(what): return "File proyek rusak: \(what)."
            case let .unsafePath(p): return "File proyek berisi path tidak aman: \(p)."
            case .missingProject: return "File proyek tidak berisi project.json."
            }
        }
    }

    // MARK: Simpan

    /// Bungkus semua file di paket (rekursif) jadi satu arsip.
    public static func pack(packageAt dir: URL) throws -> Data {
        let base = dir.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys) else {
            throw ArchiveError.corrupt("paket tidak bisa dibaca")
        }
        var files: [(String, URL)] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: Set(keys)))?.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(base.path + "/") else { continue }
            let rel = String(full.dropFirst(base.path.count + 1))
            // Berkas sistem (mis. .DS_Store) tidak ikut.
            if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
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

    // MARK: Buka

    /// Isi arsip: path relatif → data. Menolak path absolut, "..", atau berkas tersembunyi.
    public static func entries(of archive: Data) throws -> [String: Data] {
        guard archive.count >= magic.count, archive.prefix(magic.count) == magic else { throw ArchiveError.notArchive }
        let payload: Data
        do {
            payload = try (Data(archive.dropFirst(magic.count)) as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw ArchiveError.corrupt("gagal dekompresi")
        }
        var reader = Reader(data: payload)
        let count = Int(try reader.uint32())
        guard count <= maxEntries else { throw ArchiveError.corrupt("terlalu banyak berkas") }
        var out: [String: Data] = [:]
        var total: UInt64 = 0
        for _ in 0..<count {
            let pathLen = Int(try reader.uint32())
            guard pathLen > 0, pathLen <= 1024 else { throw ArchiveError.corrupt("panjang path") }
            guard let path = String(data: try reader.bytes(pathLen), encoding: .utf8) else { throw ArchiveError.corrupt("path") }
            try validate(path)
            let size = try reader.uint64()
            total += size
            guard total <= maxTotalBytes, size <= UInt64(Int.max) else { throw ArchiveError.corrupt("ukuran berkas") }
            out[path] = try reader.bytes(Int(size))
        }
        guard reader.isAtEnd else { throw ArchiveError.corrupt("data sisa di akhir") }
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

    /// Bongkar arsip ke folder `dir` (dibuat bila belum ada).
    public static func unpack(_ archive: Data, into dir: URL) throws {
        for (path, data) in try entries(of: archive) {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Impor arsip sebagai proyek di folder `root` (paket `<id>.cakra`). Bila id-nya sudah dipakai
    /// (`existingIDs`), proyek mendapat id baru dan namanya diberi akhiran " (impor)" — tidak ada yang tertimpa.
    /// Kembalikan lokasi paket hasil impor.
    @discardableResult
    public static func importArchive(_ archive: Data, intoRoot root: URL, existingIDs: Set<UUID>) throws -> URL {
        let staging = root.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try unpack(archive, into: staging)
        var project = try CakraPackage.readProject(at: staging)
        if existingIDs.contains(project.id) {
            project.id = UUID()
            project.name += " (impor)"
            try CakraPackage.encoder().encode(project).write(to: staging.appendingPathComponent(CakraPackage.projectFile), options: .atomic)
        }
        // Pastikan isinya terbaca utuh sebelum masuk daftar proyek.
        _ = try CakraPackage.read(at: staging)
        let target = root.appendingPathComponent(project.id.uuidString).appendingPathExtension(CakraPackage.fileExtension)
        try FileManager.default.moveItem(at: staging, to: target)
        return target
    }

    // MARK: Biner

    static func append<T: FixedWidthInteger>(_ v: T, to d: inout Data) {
        withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
    }

    struct Reader {
        let data: Data
        var offset = 0

        init(data: Data) { self.data = Data(data) }

        var isAtEnd: Bool { offset == data.count }

        mutating func bytes(_ n: Int) throws -> Data {
            guard n >= 0, offset + n <= data.count else { throw ArchiveError.corrupt("terpotong") }
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
