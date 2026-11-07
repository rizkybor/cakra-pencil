import CoreGraphics
import CoreText
import Foundation

/// Georeferenced basemap image placed under the map in exports (HD Apple Maps image or GeoTIFF basemap).
/// Raster and GeoPDF exports draw it under the map objects; vector exports (OMAP/DXF) write it next to the map
/// as an image + world file + .prj, so OCAD/OOM can load it as a background map/template.
public struct ExportBackground: Sendable {
    /// JPEG or PNG file contents.
    public var imageData: Data
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Image corners in the project CRS (UTM): top left, top right, bottom right, bottom left.
    public var corners: [Point2D]
    public var opacity: Double
    /// Credit printed on raster and PDF exports, e.g. "Imagery © Apple Maps"; nil = none.
    public var attribution: String?
    /// File extension of `imageData` ("jpg" or "png").
    public var fileExtension: String

    public init(imageData: Data, pixelWidth: Int, pixelHeight: Int, corners: [Point2D], opacity: Double = 1,
                attribution: String? = nil, fileExtension: String = "jpg") {
        self.imageData = imageData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.corners = corners
        self.opacity = opacity
        self.attribution = attribution
        self.fileExtension = fileExtension
    }

    /// World file of the image (affine; the small rotation between Web Mercator/lat-lon and UTM is kept).
    public var worldFile: WorldFile {
        let w = Double(max(pixelWidth, 1)), h = Double(max(pixelHeight, 1))
        let tl = corners[0], tr = corners[1], bl = corners[3]
        let a = (tr.x - tl.x) / w, d = (tr.y - tl.y) / w
        let b = (bl.x - tl.x) / h, e = (bl.y - tl.y) / h
        return WorldFile(pixelSizeX: a, rotationY: d, rotationX: b, pixelSizeY: e,
                         upperLeftX: tl.x + (a + b) / 2, upperLeftY: tl.y + (d + e) / 2)
    }

    /// World file extension for the image type (.jgw / .pgw).
    var worldFileExtension: String { fileExtension == "png" ? "pgw" : "jgw" }

    /// Write the image + world file + .prj as `<baseName>_basemap.*`; returns the written files.
    public func writeSidecar(baseName: String, zone: UTMZone, to directory: URL) throws -> [URL] {
        let base = directory.appendingPathComponent("\(baseName)_basemap")
        let image = base.appendingPathExtension(fileExtension)
        let world = base.appendingPathExtension(worldFileExtension)
        let prj = base.appendingPathExtension("prj")
        try imageData.write(to: image, options: .atomic)
        try worldFile.text.write(to: world, atomically: true, encoding: .ascii)
        try zone.prjWKT.write(to: prj, atomically: true, encoding: .ascii)
        return [image, world, prj]
    }

    /// Draw the image into `ctx` (y up), placing its corners with `toPixel` (project CRS → context point).
    func draw(in ctx: CGContext, toPixel: (Point2D) -> CGPoint) {
        guard corners.count == 4, let img = CourseImages.cgImage(imageData) else { return }
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let tl = toPixel(corners[0]), br = toPixel(corners[2]), bl = toPixel(corners[3])
        // Image space (y up, origin bottom left) → context: bl + u·(br − bl)/w + v·(tl − bl)/h.
        let t = CGAffineTransform(a: (br.x - bl.x) / w, b: (br.y - bl.y) / w, c: (tl.x - bl.x) / h, d: (tl.y - bl.y) / h,
                                  tx: bl.x, ty: bl.y)
        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(max(opacity, 0), 1)))
        ctx.concatenate(t)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    /// Small credit line at the bottom right of a `width` × `height` context (y up); `unit` = pixels per mm.
    func drawAttribution(in ctx: CGContext, width: Int, height: Int, unit: Double) {
        guard let text = attribution, !text.isEmpty else { return }
        let size = CGFloat(1.8 * unit)
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.25, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let bounds = CTLineGetImageBounds(line, ctx)
        let pad = CGFloat(0.8 * unit)
        let x = CGFloat(width) - bounds.width - 2 * pad, y = pad
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.75))
        ctx.fill(CGRect(x: x - pad / 2, y: y - pad / 2, width: bounds.width + pad, height: size + pad / 2))
        ctx.textPosition = CGPoint(x: x, y: y + size * 0.2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
