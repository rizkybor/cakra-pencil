import CakraCore
import MapKit
import UIKit

/// Lapisan input sketsa di atas peta. Pencil selalu menggambar, jari selalu navigasi (FR-3.6):
/// sentuhan jari tidak di-hit-test ke view ini sehingga jatuh ke MKMapView di bawahnya.
///
/// Stroke aktif digambar di CAShapeLayer terpisah memakai coalesced + predicted touches, lalu
/// di-commit ke model (dan overlay ber-tile) saat Pencil diangkat.
final class InkView: UIView {
    enum Mode { case off, pen, eraser }

    weak var mapView: MKMapView?
    var zone: UTMZone?
    var sheet = SheetSpec()
    var mode = Mode.off
    var fingerDraws = false
    var penColor = UIColor.black
    var penWidthMM = 0.14

    var onStroke: (([Point2D]) -> Void)?
    var onErase: ((Point2D, Double) -> Void)?
    var onEraseEnded: (() -> Void)?

    private let activeLayer = CAShapeLayer()
    private let predictedLayer = CAShapeLayer()
    private let eraserLayer = CAShapeLayer()
    private var screenPoints: [CGPoint] = []
    private var trackedTouch: UITouch?
    static let eraserRadiusPt: CGFloat = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        for l in [activeLayer, predictedLayer] {
            l.fillColor = UIColor.clear.cgColor
            l.lineCap = .round
            l.lineJoin = .round
            layer.addSublayer(l)
        }
        predictedLayer.opacity = 0.5
        eraserLayer.fillColor = UIColor(hex: 0xF5D0D3).withAlphaComponent(0.5).cgColor
        eraserLayer.strokeColor = UIColor(hex: 0x933340).cgColor
        eraserLayer.lineWidth = 1
        layer.addSublayer(eraserLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard mode != .off, self.point(inside: point, with: event) else { return nil }
        let touches = event?.allTouches ?? []
        let isPencil = touches.contains { $0.type == .pencil }
        if isPencil || (fingerDraws && touches.count <= 1) { return self }
        return nil
    }

    /// Meter tanah per point layar di tengah peta. Diukur dari dua titik layar, jadi tetap benar saat peta diputar.
    private var metersPerPoint: Double {
        guard let mapView, mapView.bounds.width > 0 else { return 1 }
        let c = CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY)
        let a = MKMapPoint(mapView.convert(c, toCoordinateFrom: mapView))
        let b = MKMapPoint(mapView.convert(CGPoint(x: c.x + 100, y: c.y), toCoordinateFrom: mapView))
        return a.distance(to: b) / 100
    }

    private func project(_ pt: CGPoint) -> Point2D? {
        guard let mapView, let zone else { return nil }
        let c = mapView.convert(pt, toCoordinateFrom: self)
        return zone.project(LatLon(lat: c.latitude, lon: c.longitude))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        screenPoints = [touch.preciseLocation(in: self)]
        if mode == .pen {
            let widthPt = CGFloat(sheet.groundMeters(forPaperMM: penWidthMM) / metersPerPoint)
            for l in [activeLayer, predictedLayer] {
                l.strokeColor = penColor.cgColor
                l.lineWidth = max(widthPt, 0.5)
            }
        }
        handle(touch, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        handle(touch, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        handle(touch, event: event)
        finish(commit: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        finish(commit: false)
    }

    private func handle(_ touch: UITouch, event: UIEvent?) {
        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        let newPoints = coalesced.map { $0.preciseLocation(in: self) }
        switch mode {
        case .pen:
            screenPoints.append(contentsOf: newPoints)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            activeLayer.path = path(screenPoints).cgPath
            let predicted = (event?.predictedTouches(for: touch) ?? []).map { $0.preciseLocation(in: self) }
            if let last = screenPoints.last, !predicted.isEmpty {
                predictedLayer.path = path([last] + predicted).cgPath
            } else {
                predictedLayer.path = nil
            }
            CATransaction.commit()
        case .eraser:
            let radiusM = Double(Self.eraserRadiusPt) * metersPerPoint
            for pt in newPoints {
                if let p = project(pt) { onErase?(p, radiusM) }
            }
            if let pt = newPoints.last {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                eraserLayer.path = UIBezierPath(ovalIn: CGRect(x: pt.x - Self.eraserRadiusPt, y: pt.y - Self.eraserRadiusPt,
                                                               width: Self.eraserRadiusPt * 2, height: Self.eraserRadiusPt * 2)).cgPath
                CATransaction.commit()
            }
        case .off:
            break
        }
    }

    private func finish(commit: Bool) {
        if mode == .pen, commit {
            let pts = simplified(screenPoints).compactMap(project)
            onStroke?(pts)
        }
        if mode == .eraser { onEraseEnded?() }
        trackedTouch = nil
        screenPoints = []
        // Hapus stroke aktif setelah overlay sempat menggambar versi commit-nya.
        DispatchQueue.main.async { [weak self] in
            self?.activeLayer.path = nil
            self?.predictedLayer.path = nil
            self?.eraserLayer.path = nil
        }
    }

    /// Buang titik yang jaraknya < 0,25 pt dari titik sebelumnya; bentuk tetap, ukuran file turun.
    private func simplified(_ pts: [CGPoint]) -> [CGPoint] {
        guard var last = pts.first else { return [] }
        var out = [last]
        for p in pts.dropFirst() where hypot(p.x - last.x, p.y - last.y) >= 0.25 {
            out.append(p)
            last = p
        }
        if let end = pts.last, out.count > 1, end != out.last { out.append(end) }
        return out
    }

    private func path(_ pts: [CGPoint]) -> UIBezierPath {
        let p = UIBezierPath()
        guard let first = pts.first else { return p }
        p.move(to: first)
        if pts.count == 1 { p.addLine(to: first) }
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }
}
