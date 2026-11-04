import Compression
import CoreGraphics
import Foundation
import ImageIO

/// Gambar objek lintasan (JPG/PNG) di folder `course-images/` paket proyek.
///
/// Batasan: hanya JPG/JPEG/PNG, file ≤ 10 MB, sisi ≤ 8000 px, maks. 10 gambar per proyek. Gambar besar
/// diperkecil ke sisi terpanjang 2000 px (cukup untuk 30 cm di kertas pada 170 dpi) agar paket dan PDF tetap ringan.
public enum CourseImages {
    public static let folder = "course-images"
    public static let maxFileBytes = 10 * 1024 * 1024
    public static let maxSourcePixels = 8000
    public static let storedMaxPixels = 2000
    public static let maxImagesPerProject = 10

    public enum ImageError: LocalizedError, Equatable {
        case unsupportedType, tooLarge(bytes: Int), tooManyPixels(width: Int, height: Int), unreadable, tooMany

        public var errorDescription: String? {
            switch self {
            case .unsupportedType: return "Format tidak didukung. Pakai JPG, JPEG, atau PNG."
            case let .tooLarge(bytes):
                return "File \(Fmt.bytes(bytes)) terlalu besar (maks. \(Fmt.bytes(CourseImages.maxFileBytes)))."
            case let .tooManyPixels(w, h):
                return "Gambar \(w)×\(h) px terlalu besar (maks. \(CourseImages.maxSourcePixels) px per sisi)."
            case .unreadable: return "Gambar tidak bisa dibaca (file rusak?)."
            case .tooMany: return "Maksimal \(CourseImages.maxImagesPerProject) gambar per proyek."
            }
        }
    }

    public enum Format: String, Sendable { case jpeg = "jpg", png }

    /// Jenis file dari isi (bukan ekstensi).
    public static func format(of data: Data) -> Format? {
        let b = [UInt8](data.prefix(8))
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return .jpeg }
        if b == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] { return .png }
        return nil
    }

    public struct Prepared: Sendable {
        public var data: Data
        public var format: Format
        public var width: Int
        public var height: Int
        public var aspect: Double { Double(height) / Double(max(width, 1)) }
    }

    /// Validasi + perkecil bila perlu (format tetap: JPG tetap JPG, PNG tetap PNG agar transparansi logo terjaga).
    public static func prepare(_ data: Data) throws -> Prepared {
        guard let format = format(of: data) else { throw ImageError.unsupportedType }
        guard data.count <= maxFileBytes else { throw ImageError.tooLarge(bytes: data.count) }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { throw ImageError.unreadable }
        guard w <= maxSourcePixels, h <= maxSourcePixels else { throw ImageError.tooManyPixels(width: w, height: h) }
        let oriented = (props[kCGImagePropertyOrientation] as? Int).map { $0 != 1 } ?? false
        if max(w, h) <= storedMaxPixels, !oriented {
            return Prepared(data: data, format: format, width: w, height: h)
        }
        // Perkecil (dan terapkan orientasi EXIF) lewat thumbnail ImageIO.
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: min(max(w, h), storedMaxPixels)]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw ImageError.unreadable }
        let out = NSMutableData()
        let type = (format == .jpeg ? "public.jpeg" : "public.png") as CFString
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { throw ImageError.unreadable }
        CGImageDestinationAddImage(dest, img, (format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.85] : [:]) as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageError.unreadable }
        return Prepared(data: out as Data, format: format, width: img.width, height: img.height)
    }

    public static func url(_ name: String, in package: URL) -> URL {
        package.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
    }

    /// Simpan gambar siap pakai; kembalikan nama file.
    public static func store(_ p: Prepared, id: UUID, in package: URL) throws -> String {
        let dir = package.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(id.uuidString).\(p.format.rawValue)"
        try p.data.write(to: dir.appendingPathComponent(name), options: .atomic)
        return name
    }

    public static func load(_ name: String, in package: URL) -> Data? {
        // Nama dari courses.json: tolak path di luar folder gambar.
        guard !name.contains("/"), !name.contains("..") else { return nil }
        return try? Data(contentsOf: url(name, in: package))
    }

    /// Hapus file yang tidak dipakai objek mana pun (dipanggil saat simpan; undo tetap aman selama sesi
    /// karena file baru dihapus bila tidak dirujuk courses.json yang disimpan).
    public static func removeUnused(keeping names: Set<String>, in package: URL) {
        let dir = package.appendingPathComponent(folder, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for f in files where !names.contains(f) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
    }

    public static func cgImage(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: PDF

    /// Objek gambar PDF: JPG RGB/abu-abu langsung (DCTDecode); selain itu piksel RGB + alpha (SMask), FlateDecode.
    struct PDFImage {
        var dictionary: String
        var stream: Data
        var mask: (dictionary: String, stream: Data)?
    }

    static func pdfImage(_ data: Data) -> PDFImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        if format(of: data) == .jpeg, (props[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
           let model = props[kCGImagePropertyColorModel] as? String, model == "RGB" || model == "Gray" {
            let cs = model == "RGB" ? "/DeviceRGB" : "/DeviceGray"
            return PDFImage(dictionary: "/Type /XObject /Subtype /Image /Width \(w) /Height \(h) /ColorSpace \(cs) /BitsPerComponent 8 /Filter /DCTDecode",
                            stream: data, mask: nil)
        }
        // Gambar ulang ke RGBA 8 bit (premultiplied dibatalkan agar warna tepi transparan benar).
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ok = rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        var alpha = [UInt8](repeating: 0, count: w * h)
        var hasAlpha = false
        for i in 0..<(w * h) {
            let a = rgba[i * 4 + 3]
            alpha[i] = a
            if a < 255 { hasAlpha = true }
            for k in 0..<3 {
                let v = rgba[i * 4 + k]
                rgb[i * 3 + k] = a == 0 ? 255 : UInt8(min(255, (Int(v) * 255 + Int(a) / 2) / Int(a)))
            }
        }
        guard let pixels = zlib(Data(rgb)) else { return nil }
        let mask = hasAlpha ? zlib(Data(alpha)).map {
            ("/Type /XObject /Subtype /Image /Width \(w) /Height \(h) /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode", $0)
        } : nil
        return PDFImage(dictionary: "/Type /XObject /Subtype /Image /Width \(w) /Height \(h) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode",
                        stream: pixels, mask: mask)
    }

    /// Aliran zlib (header + deflate + Adler-32) untuk FlateDecode.
    static func zlib(_ input: Data) -> Data? {
        let capacity = max(64, input.count + input.count / 10 + 64)
        var out = Data(count: capacity)
        let n = out.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        // Adler-32 per blok 5552 byte (batas aman sebelum modulo, seperti zlib).
        var a: UInt32 = 1, b: UInt32 = 0
        input.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = 0
            while i < bytes.count {
                let end = min(i + 5552, bytes.count)
                while i < end {
                    a &+= UInt32(bytes[i])
                    b &+= a
                    i += 1
                }
                a %= 65521
                b %= 65521
            }
        }
        let adler = (b << 16) | a
        var result = Data([0x78, 0x9C])
        result.append(out.prefix(n))
        result.append(contentsOf: [UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)])
        return result
    }
}
