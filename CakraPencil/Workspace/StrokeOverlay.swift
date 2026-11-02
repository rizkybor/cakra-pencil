import CakraCore
import MapKit
import UIKit

/// Semua stroke yang sudah di-commit, dirender MapKit per tile (MapKit yang meng-cache tile per zoom).
/// Tebal digambar dalam meter tanah, jadi tampil berubah sesuai zoom tetapi ukuran cetak tetap (FR-3.2).
final class StrokeOverlay: NSObject, MKOverlay {
    struct Item {
        let points: [MKMapPoint]
        let bounds: MKMapRect
        let color: CGColor
        let widthMapPoints: Double
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _items: [Item] = []

    var items: [Item] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    func update(strokes: [Stroke], zone: UTMZone, sheet: SheetSpec) {
        let built = strokes.compactMap { s -> Item? in
            let pts = s.points.map { p -> MKMapPoint in
                let ll = zone.unproject(p)
                return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
            guard let first = pts.first else { return nil }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in pts {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let widthM = sheet.groundMeters(forPaperMM: s.widthMM)
            let widthMP = widthM / MKMetersPerMapPointAtLatitude(first.coordinate.latitude)
            let r = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -widthMP, dy: -widthMP)
            return Item(points: pts, bounds: r, color: UIColor(hexString: s.colorHex).cgColor, widthMapPoints: widthMP)
        }
        lock.lock()
        _items = built
        lock.unlock()
    }
}

final class StrokeRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? StrokeOverlay else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // Batas bawah 0,5 pt layar supaya garis 0,05 mm tetap terlihat saat zoom jauh.
        let minWidth = 0.5 / zoomScale
        for item in overlay.items where item.bounds.intersects(mapRect) {
            let width = max(item.widthMapPoints, minWidth)
            if item.points.count == 1 {
                let c = point(for: item.points[0])
                context.setFillColor(item.color)
                context.fillEllipse(in: CGRect(x: c.x - width / 2, y: c.y - width / 2, width: width, height: width))
                continue
            }
            context.setStrokeColor(item.color)
            context.setLineWidth(width)
            context.beginPath()
            context.move(to: point(for: item.points[0]))
            for p in item.points.dropFirst() { context.addLine(to: point(for: p)) }
            context.strokePath()
        }
    }
}
