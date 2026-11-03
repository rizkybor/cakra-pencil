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

/// Lapisan warna kertas di atas citra dan di bawah sketsa. Alpha-nya = 1 − opacity basemap (FR-2.5),
/// jadi citra memudar ke kertas tetapi garis sketsa tetap pekat.
final class VeilOverlay: NSObject, MKOverlay {
    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }
}

final class VeilRenderer: MKOverlayRenderer {
    var color = UIColor(hex: 0xFAF7F2).cgColor

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setFillColor(color)
        context.fill(rect(for: mapRect))
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

/// Objek vektor (garis/area bezier) dirender per tile seperti stroke. Kurva digambar sebagai kurva kubik di
/// ruang map point: pada skala lembar A4, selisihnya dengan kurva di UTM jauh di bawah satu piksel layar.
final class FeatureOverlay: NSObject, MKOverlay {
    struct Item {
        let path: CGPath
        let bounds: MKMapRect
        let color: CGColor
        let fill: CGColor?
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

    func update(features: [Feature], zone: UTMZone, sheet: SheetSpec) {
        func mp(_ p: Point2D) -> MKMapPoint {
            let ll = zone.unproject(p)
            return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
        }
        let built = features.compactMap { f -> Item? in
            guard f.isVisible, let first = f.nodes.first, let b = f.bounds else { return nil }
            // Path disimpan dalam map point absolut; renderer menggesernya ke koordinat overlay.
            let path = CGMutablePath()
            let start = mp(first.point)
            path.move(to: CGPoint(x: start.x, y: start.y))
            for s in f.segments {
                let p3 = mp(s.p3)
                if s.isCurve {
                    let c1 = mp(s.c1), c2 = mp(s.c2)
                    path.addCurve(to: CGPoint(x: p3.x, y: p3.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
                } else {
                    path.addLine(to: CGPoint(x: p3.x, y: p3.y))
                }
            }
            if f.isClosed { path.closeSubpath() }
            let lo = mp(Point2D(x: b.minX, y: b.maxY)), hi = mp(Point2D(x: b.maxX, y: b.minY))
            let widthMP = sheet.groundMeters(forPaperMM: f.widthMM) / MKMetersPerMapPointAtLatitude(start.coordinate.latitude)
            let rect = MKMapRect(x: min(lo.x, hi.x), y: min(lo.y, hi.y), width: abs(hi.x - lo.x), height: abs(hi.y - lo.y))
                .insetBy(dx: -widthMP * 2, dy: -widthMP * 2)
            let color = UIColor(hexString: f.colorHex)
            return Item(path: path, bounds: rect, color: color.cgColor,
                        fill: f.kind == .area ? color.withAlphaComponent(0.35).cgColor : nil, widthMapPoints: widthMP)
        }
        lock.lock()
        _items = built
        lock.unlock()
    }
}

final class FeatureRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? FeatureOverlay else { return }
        let origin = point(for: MKMapPoint(x: 0, y: 0))
        context.translateBy(x: origin.x, y: origin.y)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let minWidth = 0.5 / zoomScale
        for item in overlay.items where item.bounds.intersects(mapRect) {
            if let fill = item.fill {
                context.addPath(item.path)
                context.setFillColor(fill)
                context.fillPath()
            }
            context.addPath(item.path)
            context.setStrokeColor(item.color)
            context.setLineWidth(max(item.widthMapPoints, minWidth))
            context.strokePath()
        }
    }
}

/// Grid garis utara di dalam frame (di atas citra, di bawah sketsa dan objek).
final class GridOverlay: NSObject, MKOverlay {
    struct State {
        var segments: [(MKMapPoint, MKMapPoint)] = []
        var color: CGColor = UIColor.black.cgColor
        var widthMapPoints: Double = 0
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _state = State()

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    func update(grid: NorthGrid, frame: MapFrame?, zone: UTMZone?, sheet: SheetSpec) {
        var next = State()
        if grid.isEnabled, let frame, let zone {
            func mp(_ p: Point2D) -> MKMapPoint {
                let ll = zone.unproject(p)
                return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
            next.segments = grid.lines(in: frame).map { (mp($0.0), mp($0.1)) }
            next.color = UIColor(hexString: grid.colorHex).withAlphaComponent(grid.opacity).cgColor
            let lat = zone.unproject(frame.center).lat
            next.widthMapPoints = sheet.groundMeters(forPaperMM: grid.lineWidthMM) / MKMetersPerMapPointAtLatitude(lat)
        }
        lock.lock()
        _state = next
        lock.unlock()
    }
}

final class GridRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? GridOverlay else { return }
        let s = overlay.state
        guard !s.segments.isEmpty else { return }
        context.setStrokeColor(s.color)
        context.setLineWidth(max(s.widthMapPoints, 0.75 / zoomScale))
        for (a, b) in s.segments {
            context.move(to: point(for: a))
            context.addLine(to: point(for: b))
        }
        context.strokePath()
    }
}
