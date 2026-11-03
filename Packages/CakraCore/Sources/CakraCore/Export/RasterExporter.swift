import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum RasterFormat: String, CaseIterable, Identifiable, Sendable {
    case png, tiff, jpeg

    public var id: String { rawValue }
    public var label: String { rawValue.uppercased() }
    public var fileExtension: String { self == .tiff ? "tif" : (self == .jpeg ? "jpg" : "png") }

    /// .pgw (PNG), .tfw (TIFF), .jgw (JPEG) sesuai FR-6.2.
    public var worldFileExtension: String {
        switch self {
        case .png: return "pgw"
        case .tiff: return "tfw"
        case .jpeg: return "jgw"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .tiff: return .tiff
        case .jpeg: return .jpeg
        }
    }

    public var supportsTransparency: Bool { self != .jpeg }
}

public struct RasterExportRequest: Sendable {
    public var baseName: String
    public var frame: MapFrame
    public var sheet: SheetSpec
    public var zone: UTMZone
    public var dpi: Int
    public var format: RasterFormat
    public var strokes: [Stroke]
    public var features: [Feature]
    /// Grid garis utara; ikut digambar bila aktif dan `includeInExport`.
    public var grid: NorthGrid?
    public var includePRJ: Bool

    public init(baseName: String, frame: MapFrame, sheet: SheetSpec, zone: UTMZone, dpi: Int, format: RasterFormat, strokes: [Stroke],
                features: [Feature] = [], grid: NorthGrid? = nil, includePRJ: Bool = true) {
        self.baseName = baseName
        self.frame = frame
        self.sheet = sheet
        self.zone = zone
        self.dpi = dpi
        self.format = format
        self.strokes = strokes
        self.features = features
        self.grid = grid
        self.includePRJ = includePRJ
    }

    public var pixelSize: Double { sheet.pixelSizeM(dpi: dpi) }
    public var pixelDimensions: (width: Int, height: Int) { sheet.pixelDimensions(dpi: dpi) }

    /// Perkiraan memori bitmap (RGBA 8 bit) sebelum kompresi.
    public var estimatedBitmapBytes: Int {
        let d = pixelDimensions
        return d.width * d.height * 4
    }
}

public struct RasterExportResult: Sendable {
    public var imageURL: URL
    public var worldFileURL: URL
    public var prjURL: URL?
    public var pixelWidth: Int
    public var pixelHeight: Int

    public var allFiles: [URL] { [imageURL, worldFileURL] + (prjURL.map { [$0] } ?? []) }
}

public enum RasterExportError: Error, LocalizedError {
    case contextFailed(width: Int, height: Int)
    case encodeFailed

    public var errorDescription: String? {
        switch self {
        case let .contextFailed(w, h): return "Tidak cukup memori untuk raster \(w) × \(h) px."
        case .encodeFailed: return "Gagal menulis file gambar."
        }
    }
}

/// Render sketsa ke raster north-up seukuran frame, lalu tulis world file + .prj.
///
/// Catatan: bitmap masih dirender utuh di memori (A4 900 dpi ≈ 300 MB). Penulisan per strip via
/// libtiff (budget RAM < 1,5 GB untuk area besar) menyusul bersama dukungan imagery.
public enum RasterExporter {
    public static func export(_ req: RasterExportRequest, to directory: URL) throws -> RasterExportResult {
        let (w, h) = req.pixelDimensions
        let p = req.pixelSize

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RasterExportError.contextFailed(width: w, height: h)
        }
        if !req.format.supportsTransparency {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        let visible = req.features.filter(\.isVisible)
        drawFeatures(visible.filter { $0.kind == .area }, in: ctx, frame: req.frame, pixelSize: p, height: h, dpi: req.dpi)
        if let g = req.grid, g.isEnabled, g.includeInExport, let rgb = rgbComponents(hex: g.colorHex) {
            ctx.setStrokeColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: g.opacity))
            ctx.setLineWidth(g.lineWidthMM * Double(req.dpi) / 25.4)
            for (a, b) in g.lines(in: req.frame) {
                ctx.move(to: pixelPoint(a, frame: req.frame, pixelSize: p, height: h))
                ctx.addLine(to: pixelPoint(b, frame: req.frame, pixelSize: p, height: h))
            }
            ctx.strokePath()
        }
        draw(req.strokes, in: ctx, frame: req.frame, pixelSize: p, height: h, dpi: req.dpi)
        drawFeatures(visible.filter { $0.kind == .line }, in: ctx, frame: req.frame, pixelSize: p, height: h, dpi: req.dpi)
        // Simbol titik: bentuk standar × sizeFactor; mm kertas → piksel = dpi / 25,4 (sumbu y bitmap ke atas = utara).
        let k = Double(req.dpi) / 25.4
        for f in visible where f.kind == .point {
            guard let node = f.nodes.first, req.frame.extent.insetBy(-p * 50).intersects(Rect2D(points: [node.point])!) else { continue }
            let c = pixelPoint(node.point, frame: req.frame, pixelSize: p, height: h)
            PointSymbolRenderer.draw(f.scaledPointElements, in: ctx, mmToUnits: k) { CGPoint(x: c.x + $0.x * k, y: c.y + $0.y * k) }
        }

        guard let image = ctx.makeImage() else { throw RasterExportError.encodeFailed }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let imageURL = directory.appendingPathComponent(req.baseName).appendingPathExtension(req.format.fileExtension)
        try write(image, format: req.format, dpi: req.dpi, to: imageURL)

        let worldURL = directory.appendingPathComponent(req.baseName).appendingPathExtension(req.format.worldFileExtension)
        try WorldFile(frame: req.frame, pixelSize: p).text.write(to: worldURL, atomically: true, encoding: .ascii)

        var prjURL: URL?
        if req.includePRJ {
            let url = directory.appendingPathComponent(req.baseName).appendingPathExtension("prj")
            try req.zone.prjWKT.write(to: url, atomically: true, encoding: .ascii)
            prjURL = url
        }
        return RasterExportResult(imageURL: imageURL, worldFileURL: worldURL, prjURL: prjURL, pixelWidth: w, pixelHeight: h)
    }

    /// Koordinat CG bitmap: origin kiri bawah, baris pertama memori = baris paling atas gambar.
    /// Dijangkar ke tepi atas frame agar cocok dengan world file (pusat piksel kiri atas = maxY − p/2).
    static func pixelPoint(_ pt: Point2D, frame: MapFrame, pixelSize p: Double, height h: Int) -> CGPoint {
        let e = frame.extent
        return CGPoint(x: (pt.x - e.minX) / p, y: Double(h) - (e.maxY - pt.y) / p)
    }

    static func draw(_ strokes: [Stroke], in ctx: CGContext, frame: MapFrame, pixelSize p: Double, height h: Int, dpi: Int) {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShouldAntialias(true)
        let clip = frame.extent
        for s in strokes {
            guard let b = s.bounds, b.intersects(clip), let rgb = rgbComponents(hex: s.colorHex), let first = s.points.first else { continue }
            let color = CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            let width = s.pixelWidth(dpi: dpi)
            let start = pixelPoint(first, frame: frame, pixelSize: p, height: h)
            if s.points.count == 1 {
                ctx.setFillColor(color)
                ctx.fillEllipse(in: CGRect(x: start.x - width / 2, y: start.y - width / 2, width: width, height: width))
                continue
            }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.beginPath()
            ctx.move(to: start)
            for pt in s.points.dropFirst() {
                ctx.addLine(to: pixelPoint(pt, frame: frame, pixelSize: p, height: h))
            }
            ctx.strokePath()
        }
    }

    /// Area: isi 35% + garis tepi; garis: kurva bezier asli (bukan polyline) di tebal mm.
    static func drawFeatures(_ features: [Feature], in ctx: CGContext, frame: MapFrame, pixelSize p: Double, height h: Int, dpi: Int) {
        let clip = frame.extent
        for f in features {
            guard f.nodes.count > 1, let b = f.bounds, b.intersects(clip), let rgb = rgbComponents(hex: f.colorHex) else { continue }
            func px(_ pt: Point2D) -> CGPoint { pixelPoint(pt, frame: frame, pixelSize: p, height: h) }
            let path = CGMutablePath()
            path.move(to: px(f.nodes[0].point))
            for s in f.segments {
                if s.isCurve { path.addCurve(to: px(s.p3), control1: px(s.c1), control2: px(s.c2)) } else { path.addLine(to: px(s.p3)) }
            }
            if f.isClosed { path.closeSubpath() }
            if f.kind == .area {
                ctx.addPath(path)
                ctx.setFillColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 0.35))
                ctx.fillPath()
            }
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1))
            ctx.setLineWidth(f.widthMM * Double(dpi) / 25.4)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }
    }

    static func write(_ image: CGImage, format: RasterFormat, dpi: Int, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw RasterExportError.encodeFailed
        }
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        switch format {
        case .tiff:
            props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5] // LZW
        case .jpeg:
            props[kCGImageDestinationLossyCompressionQuality] = 0.92
        case .png:
            break
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw RasterExportError.encodeFailed }
    }
}

/// Cek sebelum export (toolset Validasi): goresan di luar frame.
public struct ExportCheck: Sendable {
    public var outside: Int
    public var partlyOutside: Int

    public init(strokes: [Stroke], frame: MapFrame) {
        let e = frame.extent
        var outside = 0, partly = 0
        for s in strokes {
            guard let b = s.bounds else { continue }
            if !b.intersects(e) { outside += 1 } else if !e.contains(b) { partly += 1 }
        }
        self.outside = outside
        self.partlyOutside = partly
    }

    public var isClean: Bool { outside == 0 && partlyOutside == 0 }
}
