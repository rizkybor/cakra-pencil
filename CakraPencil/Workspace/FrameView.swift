import CakraCore
import MapKit
import UIKit

/// Garis frame A4 dan penutup area di luar frame, digambar di koordinat layar setiap kali peta bergerak.
///
/// - Mode Pilih Area (`followsMapCenter`): frame dihitung dari titik tengah peta, jadi frame diam di tengah
///   layar dan peta yang digeser/zoom di bawahnya. Luar frame hanya diredupkan.
/// - Setelah dikunci: luar frame ditutup warna kertas, jadi hanya area yang dipetakan yang tampil.
///
/// View ini tidak menerima sentuhan; semua gestur jatuh ke peta.
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

    /// Frame yang sedang tampil: di mode Pilih Area mengikuti tengah peta (dengan snap yang sama seperti model).
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

        // Persegi besar tetap, tidak bergantung pada bounds saat redraw pertama (bisa masih nol).
        let mask = UIBezierPath(rect: CGRect(x: -20_000, y: -20_000, width: 40_000, height: 40_000))
        mask.append(poly)
        maskLayer.path = mask.cgPath
        maskLayer.fillColor = isLocked
            ? UIColor(hex: 0xF2EDE4).cgColor
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
