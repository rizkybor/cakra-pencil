import CakraCore
import MapKit
import UIKit

/// Field data on the map: GPS tracks as colored dashed lines and field notes as round pins with the category icon
/// (done notes faded, averaged positions with an extra ring), sketches as solid lines in the note's colour. Hidden
/// tracks and notes are left out (not drawn, not tappable). Constant size on screen at every zoom; never printed.
final class FieldOverlay: NSObject, MKOverlay {
    struct Track {
        var points: [MKMapPoint]
        var color: UIColor
    }

    struct Pin {
        var id: UUID
        var point: MKMapPoint
        var color: UIColor
        var icon: String
        var done: Bool
        var averaged: Bool
        /// Direction the camera faced for the note's photos (degrees from north).
        var heading: Double?
        var selected: Bool
        /// Light pin color (vegetation classes): dark icon.
        var darkIcon = false
    }

    /// A note's sketch: its strokes in the note's colour.
    struct Sketch {
        var strokes: [[MKMapPoint]]
        var color: UIColor
        var done: Bool
        var selected: Bool
    }

    struct State {
        var tracks: [Track] = []
        var sketches: [Sketch] = []
        var pins: [Pin] = []
        /// Survey coverage: walked segments and the radius in map points.
        var coverage: [[MKMapPoint]] = []
        var coverageRadius: Double = 0
        /// Track → line preview.
        var preview: [[MKMapPoint]] = []
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _state = State()

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    func update(field: FieldData, zone: UTMZone?, selected: UUID? = nil, preview: [[Point2D]] = []) {
        var next = State()
        if let zone {
            func mp(_ p: Point2D) -> MKMapPoint {
                let ll = zone.unproject(p)
                return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
            // One polyline per segment: the stretch walked while paused stays a gap.
            next.tracks = field.visibleTracks.flatMap { t in
                t.segments.filter { $0.count > 1 }.map {
                    Track(points: $0.map { mp($0.position) }, color: UIColor(hexString: t.colorHex))
                }
            }
            let notes = field.visibleNotes
            next.sketches = notes.filter(\.hasSketch).map {
                Sketch(strokes: ($0.sketch ?? []).map { $0.map(mp) }, color: UIColor(hexString: $0.vegetation?.colorHex ?? $0.category.colorHex),
                       done: $0.isDone, selected: $0.id == selected)
            }
            next.pins = notes.map {
                Pin(id: $0.id, point: mp($0.position), color: UIColor(hexString: $0.vegetation?.colorHex ?? $0.category.colorHex),
                    icon: $0.vegetation != nil ? "leaf.fill" : $0.category.icon,
                    done: $0.isDone, averaged: $0.averaging != nil, heading: $0.photos.isEmpty ? nil : $0.photoHeadingDeg,
                    selected: $0.id == selected, darkIcon: $0.vegetation != nil && $0.vegetation != .fight)
            }
            // Coverage of the tracks shown (hide a track, e.g. a drive to the area, to leave it out).
            if field.showCoverage == true {
                next.coverage = field.visibleTracks.flatMap { t in t.segments.map { $0.map { mp($0.position) } } }
                if let first = field.visibleTracks.first?.points.first {
                    let lat = zone.unproject(first.position).lat
                    next.coverageRadius = field.coverageRadius * MKMapPointsPerMeterAtLatitude(lat)
                }
            }
            next.preview = preview.map { $0.map(mp) }
        }
        lock.lock()
        _state = next
        lock.unlock()
    }

    /// The note pin nearest to `p` within `radius` (map points), for taps on the map.
    func pin(near p: MKMapPoint, radius: Double) -> UUID? {
        let pins = state.pins
        let best = pins.map { ($0.id, hypot($0.point.x - p.x, $0.point.y - p.y)) }.min { $0.1 < $1.1 }
        return best.flatMap { $0.1 <= radius ? $0.0 : nil }
    }
}

final class FieldRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? FieldOverlay else { return }
        let s = overlay.state
        let px = 1 / zoomScale                       // one screen point in map points
        let pad = mapRect.insetBy(dx: -30 * px, dy: -30 * px)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Survey coverage: a band of the coverage radius along every track, overlaps not darker (one transparency layer).
        if !s.coverage.isEmpty, s.coverageRadius > 0 {
            context.saveGState()
            context.setAlpha(0.28)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setStrokeColor(UIColor(red: 0.1, green: 0.55, blue: 0.95, alpha: 1).cgColor)
            context.setFillColor(UIColor(red: 0.1, green: 0.55, blue: 0.95, alpha: 1).cgColor)
            context.setLineWidth(2 * s.coverageRadius)
            for seg in s.coverage {
                guard let first = seg.first else { continue }
                if seg.count == 1 {
                    let c = point(for: first), r = s.coverageRadius
                    context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    continue
                }
                let path = CGMutablePath()
                path.move(to: point(for: first))
                for p in seg.dropFirst() { path.addLine(to: point(for: p)) }
                context.addPath(path)
                context.strokePath()
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }

        // Tracks: white halo + colored dashes, readable on imagery and on the map.
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

        // Track → line preview: the part that becomes objects, thick and solid.
        for part in s.preview {
            guard let first = part.first else { continue }
            let path = CGMutablePath()
            path.move(to: point(for: first))
            for p in part.dropFirst() { path.addLine(to: point(for: p)) }
            context.addPath(path)
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(9 * px)
            context.strokePath()
            context.addPath(path)
            context.setStrokeColor(UIColor(red: 0.95, green: 0.2, blue: 0.5, alpha: 1).cgColor)
            context.setLineWidth(5 * px)
            context.strokePath()
            for p in [part.first!, part.last!] {
                let c = point(for: p), r = 6 * px
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: CGRect(x: c.x - r - 2 * px, y: c.y - r - 2 * px, width: 2 * r + 4 * px, height: 2 * r + 4 * px))
                context.setFillColor(UIColor(red: 0.95, green: 0.2, blue: 0.5, alpha: 1).cgColor)
                context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }
        }

        // Sketches: white halo + solid line in the note's colour (done notes faded, the open note thicker).
        for sk in s.sketches.sorted(by: { !$0.selected && $1.selected }) {
            let alpha: CGFloat = sk.done && !sk.selected ? 0.45 : 1
            let w: CGFloat = sk.selected ? 4.5 : 3
            for stroke in sk.strokes {
                guard let first = stroke.first else { continue }
                if stroke.count == 1 {
                    let c = point(for: first), r = (w + 1.5) * px
                    context.setFillColor(UIColor.white.withAlphaComponent(0.9 * alpha).cgColor)
                    context.fillEllipse(in: CGRect(x: c.x - r - 1.5 * px, y: c.y - r - 1.5 * px, width: 2 * r + 3 * px, height: 2 * r + 3 * px))
                    context.setFillColor(sk.color.withAlphaComponent(alpha).cgColor)
                    context.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    continue
                }
                let path = CGMutablePath()
                path.move(to: point(for: first))
                for p in stroke.dropFirst() { path.addLine(to: point(for: p)) }
                guard path.boundingBoxOfPath.insetBy(dx: -10 * px, dy: -10 * px).intersects(rect(for: pad)) else { continue }
                context.addPath(path)
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.85 * alpha).cgColor)
                context.setLineWidth((w + 2.5) * px)
                context.strokePath()
                context.addPath(path)
                context.setStrokeColor(sk.color.withAlphaComponent(alpha).cgColor)
                context.setLineWidth(w * px)
                context.strokePath()
            }
        }

        // Note pins.
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        // The open note on top, drawn last.
        for pin in s.pins.sorted(by: { !$0.selected && $1.selected }) {
            let r = (pin.selected ? 14 : 11) * px
            let c = point(for: pin.point)
            guard rect(for: pad).contains(c) else { continue }
            let alpha: CGFloat = pin.done && !pin.selected ? 0.45 : 1
            // Camera direction: a wedge pointing where the photo was taken (map north up; it turns with the map).
            if let h = pin.heading {
                let a = h * .pi / 180, spread = 0.42, len = r * 2.6
                let wedge = CGMutablePath()
                wedge.move(to: c)
                wedge.addLine(to: CGPoint(x: c.x + sin(a - spread) * len, y: c.y - cos(a - spread) * len))
                wedge.addLine(to: CGPoint(x: c.x + sin(a + spread) * len, y: c.y - cos(a + spread) * len))
                wedge.closeSubpath()
                context.addPath(wedge)
                context.setFillColor(pin.color.withAlphaComponent(0.35 * alpha).cgColor)
                context.fillPath()
                context.addPath(wedge)
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.9 * alpha).cgColor)
                context.setLineWidth(1.5 * px)
                context.strokePath()
            }
            if pin.selected {
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(5 * px)
                context.strokeEllipse(in: CGRect(x: c.x - r * 1.55, y: c.y - r * 1.55, width: r * 3.1, height: r * 3.1))
                context.setStrokeColor(pin.color.cgColor)
                context.setLineWidth(2.5 * px)
                context.strokeEllipse(in: CGRect(x: c.x - r * 1.55, y: c.y - r * 1.55, width: r * 3.1, height: r * 3.1))
            }
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
                .withTintColor((pin.darkIcon ? UIColor(red: 0.15, green: 0.3, blue: 0.12, alpha: 1) : .white).withAlphaComponent(alpha),
                               renderingMode: .alwaysOriginal) {
                let w = img.size.width * px, h = img.size.height * px
                let k = min(1, 1.25 * r / max(w, h))
                img.draw(in: CGRect(x: c.x - w * k / 2, y: c.y - h * k / 2, width: w * k, height: h * k))
            }
        }
    }
}
