import CakraCore
import ImageIO
import MapKit
import UIKit

/// Image basemap on the map (GeoTIFF, or the HD Apple Maps image of the locked area): above the live imagery and
/// its fade (veil), below map objects.
final class BasemapImageOverlay: NSObject, MKOverlay {
    /// Identity of the shown image (file + georeference); a different key means a new overlay.
    let key: String
    let pixelWidth: Int
    let pixelHeight: Int
    /// Top-left, top-right, bottom-right, bottom-left corners (map points).
    let corners: [MKMapPoint]
    let boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate }
    let levels: ImageLevels
    /// Opacity the renderer starts with.
    var opacity: Double = 1

    init(key: String, corners: [MKMapPoint], pixelWidth: Int, pixelHeight: Int, fileURL: URL) {
        self.key = key
        self.corners = corners
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        let xs = corners.map(\.x), ys = corners.map(\.y)
        boundingMapRect = MKMapRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        levels = ImageLevels(url: fileURL)
    }

    /// GeoTIFF basemap (UTM or lat/lon).
    convenience init(image: BasemapImage, fileURL: URL) {
        let w = Double(image.width), h = Double(image.height)
        let corners = [(0, 0), (w, 0), (w, h), (0, h)].map { uv in
            let ll = image.latLon(u: uv.0, v: uv.1)
            return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
        }
        self.init(key: "\(image.fileName)|\(image.crs)", corners: corners, pixelWidth: image.width, pixelHeight: image.height, fileURL: fileURL)
    }

    /// HD Apple Maps image (Web Mercator, north-up).
    convenience init(snapshot s: ImagerySnapshot, fileURL: URL) {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: s.north, longitude: s.west))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: s.south, longitude: s.east))
        let corners = [nw, MKMapPoint(x: se.x, y: nw.y), se, MKMapPoint(x: nw.x, y: se.y)]
        self.init(key: "\(s.fileName)|\(s.capturedAt.timeIntervalSince1970)", corners: corners,
                  pixelWidth: s.width, pixelHeight: s.height, fileURL: fileURL)
    }
}

/// Image in two resolutions: compact (max. 2048 px) for zoomed out, full for zoomed in. Loaded once
/// when first needed; safe to call from the renderer thread.
final class ImageLevels: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var preview: CGImage?
    private var full: CGImage?

    init(url: URL) { self.url = url }

    static let previewMaxPixels = 2048

    func image(full wantFull: Bool) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        if wantFull, let full { return full }
        if !wantFull, let preview { return preview }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        if wantFull {
            if full == nil {
                full = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            }
            if let full { return full }
        }
        if preview == nil {
            preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.previewMaxPixels,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        }
        return preview
    }
}

final class BasemapImageRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let o = overlay as? BasemapImageOverlay else { return }
        // On-screen image width (retina pixels); larger than the compact version → use full resolution.
        let onScreen = o.boundingMapRect.width * Double(zoomScale) * 2
        guard let cg = o.levels.image(full: onScreen > Double(ImageLevels.previewMaxPixels) * 1.2) else { return }
        let w = CGFloat(o.pixelWidth), h = CGFloat(o.pixelHeight)
        let tl = point(for: o.corners[0]), tr = point(for: o.corners[1]), bl = point(for: o.corners[3])
        let a = CGPoint(x: (tr.x - tl.x) / w, y: (tr.y - tl.y) / w)
        let b = CGPoint(x: (bl.x - tl.x) / h, y: (bl.y - tl.y) / h)
        // CG image space (y up, pixels) → renderer coordinates: (u, v = h − y) ↦ tl + u·a + v·b.
        context.saveGState()
        context.concatenate(CGAffineTransform(a: a.x, b: a.y, c: -b.x, d: -b.y, tx: tl.x + h * b.x, ty: tl.y + h * b.y))
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.restoreGState()
    }
}
