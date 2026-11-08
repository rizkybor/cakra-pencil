import CakraCore
import MapKit
import UIKit

/// Field data on the map: GPS tracks as colored dashed lines and field notes as round pins with the category icon
/// (done notes faded, averaged positions with an extra ring). Constant size on screen at every zoom.
final class FieldOverlay: NSObject, MKOverlay {
    struct Track {
        var points: [MKMapPoint]
        var color: UIColor
    }

    struct Pin {
        var point: MKMapPoint
        var color: UIColor
        var icon: String
        var done: Bool
        var averaged: Bool
    }

    struct State {
        var tracks: [Track] = []
        var pins: [Pin] = []
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _state = State()

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    func update(field: FieldData, zone: UTMZone?) {
        var next = State()
        if let zone {
            func mp(_ p: Point2D) -> MKMapPoint {
                let ll = zone.unproject(p)
                return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
            if field.showTracks {
                next.tracks = field.tracks.filter { $0.isVisible && $0.points.count > 1 }.map {
                    Track(points: $0.points.map { mp($0.position) }, color: UIColor(hexString: $0.colorHex))
                }
            }
            if field.showNotes {
                next.pins = field.notes.map {
                    Pin(point: mp($0.position), color: UIColor(hexString: $0.category.colorHex), icon: $0.category.icon,
                        done: $0.isDone, averaged: $0.averaging != nil)
                }
            }
        }
        lock.lock()
        _state = next
        lock.unlock()
    }
}

final class FieldRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? FieldOverlay else { return }
        let s = overlay.state
        let px = 1 / zoomScale                       // one screen point in map points
        let pad = mapRect.insetBy(dx: -30 * px, dy: -30 * px)

        // Tracks: white halo + colored dashes, readable on imagery and on the map.
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for t in s.tracks {
            guard let first = t.points.first else { continue }
            let path = CGMutablePath()
            path.move(to: point(for: first))
            for p in t.points.dropFirst() { path.addLine(to: point(for: p)) }
            guard path.boundingBoxOfPath.insetBy(dx: -10 * px, dy: -10 * px).intersects(rect(for: pad)) else { continue }
            context.addPath(path)
            context.setLineDash(phase: 0, lengths: [])
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(5 * px)
            context.strokePath()
            context.addPath(path)
            context.setLineDash(phase: 0, lengths: [7 * px, 4 * px])
            context.setStrokeColor(t.color.cgColor)
            context.setLineWidth(3 * px)
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [])

        // Note pins.
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        let r = 11 * px
        for pin in s.pins {
            let c = point(for: pin.point)
            guard rect(for: pad).contains(c) else { continue }
            let alpha: CGFloat = pin.done ? 0.45 : 1
            if pin.averaged {
                context.setStrokeColor(pin.color.withAlphaComponent(alpha).cgColor)
                context.setLineWidth(2 * px)
                context.strokeEllipse(in: CGRect(x: c.x - r * 1.6, y: c.y - r * 1.6, width: r * 3.2, height: r * 3.2))
            }
            context.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: c.x - r - 2 * px, y: c.y - r - 2 * px, width: 2 * r + 4 * px, height: 2 * r + 4 * px))
            context.setFillColor(pin.color.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            let cfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            if let img = UIImage(systemName: pin.done ? "checkmark" : pin.icon, withConfiguration: cfg)?
                .withTintColor(.white.withAlphaComponent(alpha), renderingMode: .alwaysOriginal) {
                let w = img.size.width * px, h = img.size.height * px
                let k = min(1, 1.25 * r / max(w, h))
                img.draw(in: CGRect(x: c.x - w * k / 2, y: c.y - h * k / 2, width: w * k, height: h * k))
            }
        }
    }
}
