import CakraCore
import MapKit
import UIKit

/// Garis frame A4 + area gelap di luar frame, digambar di koordinat layar dan diperbarui tiap peta bergerak.
/// Saat alat Frame aktif dan area belum dikunci, satu jari di dalam frame menggeser frame (FR-1.4);
/// sentuhan di luar frame diteruskan ke peta.
final class FrameView: UIView {
    weak var mapView: MKMapView?
    var frameModel: MapFrame?
    var zone: UTMZone?
    var isDraggable = false
    var isLocked = false

    var onDragBegan: (() -> Void)?
    var onDragChanged: ((Point2D) -> Void)?
    var onDragEnded: (() -> Void)?

    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var screenPolygon: UIBezierPath?
    private var dragStartTouch: Point2D?
    private var dragStartOrigin: Point2D?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineJoin = .miter
        layer.addSublayer(dimLayer)
        layer.addSublayer(borderLayer)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let mapView, let frameModel, let zone else {
            dimLayer.path = nil
            borderLayer.path = nil
            screenPolygon = nil
            return
        }
        let poly = UIBezierPath()
        for (i, corner) in frameModel.corners.enumerated() {
            let ll = zone.unproject(corner)
            let pt = mapView.convert(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon), toPointTo: self)
            i == 0 ? poly.move(to: pt) : poly.addLine(to: pt)
        }
        poly.close()
        screenPolygon = poly

        // Persegi besar tetap, tidak bergantung pada bounds saat redraw pertama (bisa masih nol).
        let dim = UIBezierPath(rect: CGRect(x: -20_000, y: -20_000, width: 40_000, height: 40_000))
        dim.append(poly)
        dimLayer.path = isLocked ? dim.cgPath : nil

        borderLayer.path = poly.cgPath
        borderLayer.strokeColor = (isLocked ? UIColor(hex: 0x3F6B4A) : UIColor(hex: 0xF0B79A)).cgColor
        borderLayer.lineWidth = isLocked ? 1.5 : 2.5
        borderLayer.lineDashPattern = isLocked ? nil : [10, 6]
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isDraggable, let screenPolygon else { return false }
        return screenPolygon.contains(point)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let mapView, let zone, let frameModel else { return }
        let coord = mapView.convert(g.location(in: self), toCoordinateFrom: self)
        let p = zone.project(LatLon(lat: coord.latitude, lon: coord.longitude))
        switch g.state {
        case .began:
            dragStartTouch = p
            dragStartOrigin = frameModel.origin
            onDragBegan?()
        case .changed:
            guard let start = dragStartTouch, let origin = dragStartOrigin else { return }
            onDragChanged?(origin + (p - start))
        default:
            dragStartTouch = nil
            dragStartOrigin = nil
            onDragEnded?()
        }
    }
}
