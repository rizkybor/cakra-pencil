import CakraCore
import ImageIO
import MapKit
import UIKit

/// Basemap gambar (GeoTIFF) di peta: di atas citra satelit dan pemudarnya (veil), di bawah objek peta.
final class BasemapImageOverlay: NSObject, MKOverlay {
    let image: BasemapImage
    let fileURL: URL
    /// Pojok kiri atas, kanan atas, kanan bawah, kiri bawah (map point).
    let corners: [MKMapPoint]
    let boundingMapRect: MKMapRect
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate }
    let levels: ImageLevels

    init(image: BasemapImage, fileURL: URL) {
        self.image = image
        self.fileURL = fileURL
        let w = Double(image.width), h = Double(image.height)
        corners = [(0, 0), (w, 0), (w, h), (0, h)].map { uv in
            let ll = image.latLon(u: uv.0, v: uv.1)
            return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
        }
        let xs = corners.map(\.x), ys = corners.map(\.y)
        boundingMapRect = MKMapRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        levels = ImageLevels(url: fileURL)
    }
}

/// Gambar dalam dua resolusi: ringkas (maks. 2048 px) untuk zoom jauh, penuh untuk zoom dekat. Dimuat sekali
/// saat pertama dibutuhkan; aman dipanggil dari thread renderer.
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
        // Lebar gambar di layar (piksel retina); lebih besar dari versi ringkas → pakai resolusi penuh.
        let onScreen = o.boundingMapRect.width * Double(zoomScale) * 2
        guard let cg = o.levels.image(full: onScreen > Double(ImageLevels.previewMaxPixels) * 1.2) else { return }
        let w = CGFloat(o.image.width), h = CGFloat(o.image.height)
        let tl = point(for: o.corners[0]), tr = point(for: o.corners[1]), bl = point(for: o.corners[3])
        let a = CGPoint(x: (tr.x - tl.x) / w, y: (tr.y - tl.y) / w)
        let b = CGPoint(x: (bl.x - tl.x) / h, y: (bl.y - tl.y) / h)
        // Ruang gambar CG (y ke atas, piksel) → koordinat renderer: (u, v = h − y) ↦ tl + u·a + v·b.
        context.saveGState()
        context.concatenate(CGAffineTransform(a: a.x, b: a.y, c: -b.x, d: -b.y, tx: tl.x + h * b.x, ty: tl.y + h * b.y))
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.restoreGState()
    }
}
