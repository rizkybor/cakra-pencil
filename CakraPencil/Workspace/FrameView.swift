import CakraCore
import MapKit
import UIKit

/// A4 frame outline and the cover outside the frame, drawn in screen coordinates every time the map moves.
///
/// - Select Area mode (`followsMapCenter`): the frame is computed from the map center, so the frame stays in the
///   middle of the screen and the map pans/zooms beneath it. Outside the frame is only dimmed.
/// - After locking: outside the frame is covered in paper color, so only the mapped area shows.
///
/// This view doesn't receive touches; all gestures fall through to the map.
final class FrameView: UIView {
    weak var mapView: MKMapView?
    var frameModel: MapFrame?
    var zone: UTMZone?
    var sheet = SheetSpec()
    var snapStepM = 0
    var followsMapCenter = false
    var isLocked = false

    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let crosshairLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        maskLayer.fillRule = .evenOdd
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineJoin = .miter
        crosshairLayer.strokeColor = UIColor(hex: 0x8E4A2F).cgColor
        crosshairLayer.lineWidth = 1.5
        crosshairLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(maskLayer)
        layer.addSublayer(borderLayer)
        layer.addSublayer(crosshairLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }

    /// The frame currently shown: in Select Area mode it follows the map center (with the same snap as the model).
    var displayedFrame: (MapFrame, UTMZone)? {
        if followsMapCenter, let mapView, !mapView.bounds.isEmpty {
            let c = mapView.centerCoordinate
            let zone = UTMZone(containing: LatLon(lat: c.latitude, lon: c.longitude))
            let f = MapFrame(center: zone.project(LatLon(lat: c.latitude, lon: c.longitude)), sheet: sheet).snapped(toStep: snapStepM)
            return (f, zone)
        }
        guard let frameModel, let zone else { return nil }
        return (frameModel, zone)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { redraw() }
    }

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let mapView, let (frame, zone) = displayedFrame else {
            maskLayer.path = nil
            borderLayer.path = nil
            crosshairLayer.path = nil
            return
        }
        let poly = UIBezierPath()
        for (i, corner) in frame.corners.enumerated() {
            let ll = zone.unproject(corner)
            let pt = mapView.convert(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon), toPointTo: self)
            i == 0 ? poly.move(to: pt) : poly.addLine(to: pt)
        }
        poly.close()

        // A fixed large rectangle, independent of bounds at the first redraw (which may still be zero).
        let mask = UIBezierPath(rect: CGRect(x: -20_000, y: -20_000, width: 40_000, height: 40_000))
        mask.append(poly)
        maskLayer.path = mask.cgPath
        // Outside the frame: theme background color (dark in dark mode); inside the frame the map stays like paper.
        maskLayer.fillColor = isLocked
            ? UIColor(CP.paper2).resolvedColor(with: traitCollection).cgColor
            : UIColor.black.withAlphaComponent(0.5).cgColor

        borderLayer.path = poly.cgPath
        borderLayer.strokeColor = (isLocked ? UIColor(hex: 0x3F6B4A) : UIColor(hex: 0xF0B79A)).cgColor
        borderLayer.lineWidth = isLocked ? 1.5 : 3
        borderLayer.lineDashPattern = isLocked ? nil : [12, 6]

        if followsMapCenter {
            let c = CGPoint(x: bounds.midX, y: bounds.midY)
            let cross = UIBezierPath()
            cross.move(to: CGPoint(x: c.x - 10, y: c.y)); cross.addLine(to: CGPoint(x: c.x + 10, y: c.y))
            cross.move(to: CGPoint(x: c.x, y: c.y - 10)); cross.addLine(to: CGPoint(x: c.x, y: c.y + 10))
            crosshairLayer.path = cross.cgPath
        } else {
            crosshairLayer.path = nil
        }
    }
}
