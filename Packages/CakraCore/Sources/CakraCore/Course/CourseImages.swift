import Compression
import CoreGraphics
import Foundation
import ImageIO

/// Course object images (JPG/PNG) in the project package's `course-images/` folder.
///
/// Limits: JPG/JPEG/PNG only, file ≤ 10 MB, side ≤ 8000 px, max. 10 images per project. Large images
/// are downscaled to a longest side of 2000 px (enough for 30 cm on paper at 170 dpi) to keep the package and PDF light.
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
            case .unsupportedType: return "Unsupported format. Use JPG, JPEG, or PNG."
            case let .tooLarge(bytes):
                return "File of \(Fmt.bytes(bytes)) is too large (max. \(Fmt.bytes(CourseImages.maxFileBytes)))."
            case let .tooManyPixels(w, h):
                return "Image of \(w)×\(h) px is too large (max. \(CourseImages.maxSourcePixels) px per side)."
            case .unreadable: return "The image cannot be read (corrupt file?)."
            case .tooMany: return "Maximum \(CourseImages.maxImagesPerProject) images per project."
            }
        }
    }

    public enum Format: String, Sendable { case jpeg = "jpg", png }

    /// File type from the contents (not the extension).
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

    /// Validate + downscale if needed (format kept: JPG stays JPG, PNG stays PNG so logo transparency is preserved).
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
        // Downscale (and apply EXIF orientation) via an ImageIO thumbnail.
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

    /// Store the prepared image; return the file name.
    public static func store(_ p: Prepared, id: UUID, in package: URL) throws -> String {
        let dir = package.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(id.uuidString).\(p.format.rawValue)"
        try p.data.write(to: dir.appendingPathComponent(name), options: .atomic)
        return name
    }

    public static func load(_ name: String, in package: URL) -> Data? {
        // Name comes from courses.json: reject paths outside the image folder.
        guard !name.contains("/"), !name.contains("..") else { return nil }
        return try? Data(contentsOf: url(name, in: package))
    }

    /// Delete files not used by any object (called on save; undo stays safe during the session
    /// because files are only deleted when the saved courses.json no longer references them).
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

    /// PDF image object: RGB/gray JPG embedded directly (DCTDecode); otherwise RGB pixels + alpha (SMask), FlateDecode.
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
        // Redraw to 8-bit RGBA (premultiplication undone so transparent edge colors are correct).
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

    /// zlib stream (header + deflate + Adler-32) for FlateDecode.
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
        // Adler-32 in blocks of 5552 bytes (safe limit before modulo, as in zlib).
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
