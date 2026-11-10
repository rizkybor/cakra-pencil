import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum RasterFormat: String, CaseIterable, Identifiable, Sendable {
    case png, tiff, jpeg

    public var id: String { rawValue }
    public var label: String { rawValue.uppercased() }
    public var fileExtension: String { self == .tiff ? "tif" : (self == .jpeg ? "jpg" : "png") }

    /// .pgw (PNG), .tfw (TIFF), .jgw (JPEG) per FR-6.2.
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
    /// North line grid; drawn too when enabled and `includeInExport`.
    public var grid: NorthGrid?
    public var includePRJ: Bool
    /// Course overprint (purple), drawn on top.
    public var overprint: CourseOverprint?
    /// Course object images (JPG/PNG) by file name.
    public var overprintImages: [String: Data] = [:]
    /// Georeferenced basemap image under the map objects; nil = none.
    public var background: ExportBackground?
    /// Colour priority at which the lower purple course overprint is painted (below black, blue and brown 100 %);
    /// ISInOM maps use their own table (`ColorHierarchy.lowerPurplePriority(for: .isinom)`).
    public var overprintLowerPriority = ColorHierarchy.lowerPurplePriority()

    public init(baseName: String, frame: MapFrame, sheet: SheetSpec, zone: UTMZone, dpi: Int, format: RasterFormat, strokes: [Stroke],
                features: [Feature] = [], grid: NorthGrid? = nil, includePRJ: Bool = true, overprint: CourseOverprint? = nil) {
        self.overprint = overprint
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

    /// Estimated bitmap memory (8-bit RGBA) before compression.
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
        case let .contextFailed(w, h): return "Not enough memory for a \(w) × \(h) px raster."
        case .encodeFailed: return "Failed to write the image file."
        }
    }
}

/// Render the sketch to a north-up raster the size of the frame, then write the world file + .prj.
///
/// Note: the bitmap is still rendered whole in memory (A4 at 900 dpi ≈ 300 MB). Strip-wise writing via
/// libtiff (RAM budget < 1.5 GB for large areas) will follow together with imagery support.
public enum RasterExporter {
    public static func export(_ req: RasterExportRequest, to directory: URL) throws -> RasterExportResult {
        let (w, h) = req.pixelDimensions
        let p = req.pixelSize

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RasterExportError.contextFailed(width: w, height: h)
        }
        // White background for JPEG, and under a basemap (so its opacity looks like the map: faded toward paper).
        if !req.format.supportsTransparency || req.background != nil {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        // Basemap image under everything (clipped by the frame = the whole bitmap).
        req.background?.draw(in: ctx) { pixelPoint($0, frame: req.frame, pixelSize: p, height: h) }
        // Map objects follow the Color Hierarchy (OCAD color table): higher colors cover the colors below them. The
        // course overprint is painted in the colour order (IOF Printing and Colour Definitions Rev 4 §4): lower purple
        // below black, blue and brown 100 %, upper purple on top of everything — no multiply blending.
        let visible = req.features.filter(\.isVisible)
        let overprint = req.overprint?.levels
        let images = req.overprintImages.compactMapValues(CourseImages.cgImage)
        func drawOverprint(_ o: CourseOverprint?) {
            guard let o, !o.isEmpty else { return }
            CourseOverprintRenderer.draw(o, in: ctx, unitsPerMeter: 1 / p, flipped: false, images: images) {
                pixelPoint($0, frame: req.frame, pixelSize: p, height: h)
            }
        }
        drawFeatures(visible, in: ctx, frame: req.frame, pixelSize: p, height: h, dpi: req.dpi,
                     lowerPurple: (req.overprintLowerPriority, { drawOverprint(overprint?.lower) }))
        // North grid and pencil sketch on top of the map objects.
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

        drawOverprint(overprint?.upper)

        req.background?.drawAttribution(in: ctx, width: w, height: h, unit: Double(req.dpi) / 25.4)

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

    /// CG bitmap coordinates: origin bottom-left, first memory row = top image row.
    /// Anchored to the top edge of the frame to match the world file (top-left pixel center = maxY − p/2).
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

    /// Objects in Color Hierarchy order. Symbol areas: solid fill; sketch areas: 35% fill + outline;
    /// lines: original bezier curves at their mm width (double lines: casing and fill each on their own color layer);
    /// points: standard shape × sizeFactor, each element at its own color level. `lowerPurple`: drawn when the paint
    /// order passes that priority (the lower purple course overprint, below the colors above it).
    static func drawFeatures(_ features: [Feature], in ctx: CGContext, frame: MapFrame, pixelSize p: Double, height h: Int, dpi: Int,
                             lowerPurple: (priority: Int, draw: () -> Void)? = nil) {
        let clip = frame.extent
        let k = Double(dpi) / 25.4
        var lowerDone = lowerPurple == nil
        for paint in ColorHierarchy.paintOrder(features) {
            if !lowerDone, let lp = lowerPurple, paint.priority < lp.priority {
                lp.draw()
                lowerDone = true
            }
            let f = features[paint.index]
            if f.kind == .point {
                guard let node = f.nodes.first, clip.insetBy(-p * 50).intersects(Rect2D(points: [node.point])!) else { continue }
                let c = pixelPoint(node.point, frame: frame, pixelSize: p, height: h)
                var level: Int?
                if case let .elements(l) = paint.part { level = l }
                PointSymbolRenderer.draw(f.scaledPointElements, in: ctx, mmToUnits: k, level: level) { CGPoint(x: c.x + $0.x * k, y: c.y + $0.y * k) }
                continue
            }
            guard f.nodes.count > 1, let b = f.bounds, b.intersects(clip), let rgb = rgbComponents(hex: f.colorHex) else { continue }
            func px(_ pt: Point2D) -> CGPoint { pixelPoint(pt, frame: frame, pixelSize: p, height: h) }
            // Areas: outer ring + holes as subpaths, filled with the even-odd rule.
            let path = CGMutablePath()
            for ring in f.ringFeatures where !ring.nodes.isEmpty {
                path.move(to: px(ring.nodes[0].point))
                for s in ring.segments {
                    if s.isCurve { path.addCurve(to: px(s.p3), control1: px(s.c1), control2: px(s.c2)) } else { path.addLine(to: px(s.p3)) }
                }
                if f.closesPath { path.closeSubpath() }
            }
            if f.kind == .area {
                // Like OCAD/OOM: symbol area = solid color fill without outline (pattern-only areas: no fill), then its
                // ISOM pattern; sketch area = transparent fill + outline.
                if !SymbolOrnaments.isPatternOnly(fillHex: f.colorHex, patterns: f.patterns) {
                    ctx.addPath(path)
                    ctx.setFillColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: f.isSymbolArea ? 1 : 0.35))
                    ctx.fillPath(using: .evenOdd)
                }
                if let patterns = f.patterns, f.isSymbolArea {
                    let bb = path.boundingBoxOfPath.intersection(ctx.boundingBoxOfClipPath)
                    if !bb.isNull {
                        OrnamentRenderer.drawPatterns(patterns, outline: path,
                                                      rect: Rect2D(minX: bb.minX, minY: bb.minY, maxX: bb.maxX, maxY: bb.maxY),
                                                      in: ctx, unitsPerMM: k, yUp: true, minSpacing: 1.5, seed: f.patternSeed)  // bitmap space: y up
                    }
                }
                if f.isSymbolArea { continue }
            }
            ctx.setLineCap(f.roundCaps == false ? .butt : .round)
            ctx.setLineJoin(f.roundCaps == false ? .miter : .round)
            ctx.setLineDash(phase: 0, lengths: f.effectiveDashMM.map { $0.map { CGFloat($0 * k) } } ?? [])
            // Double line: casing at full width below, fill at inner width on top.
            if f.kind == .line, let casing = f.casingColorHex.flatMap(rgbComponents(hex:)), let inner = f.innerWidthMM {
                if paint.part != .main {
                    ctx.addPath(path)
                    ctx.setStrokeColor(CGColor(red: casing.r, green: casing.g, blue: casing.b, alpha: 1))
                    ctx.setLineWidth(f.widthMM * k)
                    ctx.strokePath()
                }
                if paint.part != .casing {
                    // Fill: its own dash pattern (e.g. white railway dashes); otherwise solid.
                    ctx.setLineDash(phase: 0, lengths: f.effectiveInnerDashMM.map { $0.map { CGFloat($0 * k) } } ?? [])
                    ctx.addPath(path)
                    ctx.setStrokeColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1))
                    ctx.setLineWidth(inner * k)
                    ctx.strokePath()
                }
                ctx.setLineDash(phase: 0, lengths: [])
                continue
            }
            if !f.hidesMainLine {
                ctx.addPath(path)
                ctx.setStrokeColor(CGColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1))
                ctx.setLineWidth(f.widthMM * k)
                ctx.strokePath()
            }
            ctx.setLineDash(phase: 0, lengths: [])
            // ISOM decorations: tags, wall dots, fence tags, ticks, chevrons, edges of transparent double lines…
            if f.kind == .line, let deco = f.decoration {
                let pts = SymbolOrnaments.polyline(f) { let c = px($0); return Point2D(x: c.x, y: c.y) }
                OrnamentRenderer.draw(SymbolOrnaments.decorationMarks(deco, along: pts, unitsPerMM: k, lineWidthMM: f.widthMM,
                                                                      colorHex: f.colorHex, yUp: true, dashMM: f.effectiveDashMM), in: ctx, unitsPerMM: k)
            }
        }
        if !lowerDone { lowerPurple?.draw() }
        ctx.setLineDash(phase: 0, lengths: [])
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

/// Pre-export check (Validation toolset): strokes outside the frame.
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
