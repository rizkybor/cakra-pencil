import CakraCore
import MapKit
import SwiftUI
import UIKit

/// MKMapView + FrameView + InkView dalam satu container. Rotasi dan pitch dikunci (north-up).
struct MapCanvas: UIViewRepresentable {
    @ObservedObject var model: WorkspaceModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> UIView {
        let c = context.coordinator
        let container = UIView()
        let map = c.mapView
        map.delegate = c
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        // Urutan tambah = urutan gambar dalam satu level: veil dulu, sketsa di atasnya.
        map.addOverlay(c.veilOverlay, level: .aboveLabels)
        map.addOverlay(c.strokeOverlay, level: .aboveLabels)

        for v in [map, c.frameView, c.inkView] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                v.topAnchor.constraint(equalTo: container.topAnchor),
                v.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        c.frameView.mapView = map
        c.inkView.mapView = map
        c.wireCallbacks()

        // Ketuk 2 jari = undo, ketuk 3 jari = redo.
        let undoTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.undoTap))
        undoTap.numberOfTouchesRequired = 2
        let redoTap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.redoTap))
        redoTap.numberOfTouchesRequired = 3
        map.addGestureRecognizer(undoTap)
        map.addGestureRecognizer(redoTap)

        // Double-tap Pencil = pena ↔ penghapus.
        let pencil = UIPencilInteraction()
        pencil.delegate = c
        container.addInteraction(pencil)

        c.sync(force: true)
        c.initialCamera()
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.model = model
        context.coordinator.sync(force: false)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIPencilInteractionDelegate {
        var model: WorkspaceModel
        let mapView = MKMapView()
        let frameView = FrameView()
        let inkView = InkView()
        let strokeOverlay = StrokeOverlay()
        let veilOverlay = VeilOverlay()
        private let locationManager = CLLocationManager()
        private weak var strokeRenderer: StrokeRenderer?
        private weak var veilRenderer: VeilRenderer?
        private var lastOpacity: Double?
        private var lastStrokesVersion = -1
        private var lastSheet: SheetSpec?
        private var lastEPSG: Int?
        private var lastBasemap: Basemap?
        private var lastCommand: UUID?

        init(model: WorkspaceModel) {
            self.model = model
        }

        func wireCallbacks() {
            frameView.onDragBegan = { [weak self] in self?.model.beginFrameDrag() }
            frameView.onDragChanged = { [weak self] origin in
                self?.model.moveFrame(origin: origin)
            }
            frameView.onDragEnded = { [weak self] in self?.model.finishFrameDrag() }
            inkView.onStroke = { [weak self] pts in self?.model.addStroke(points: pts) }
            inkView.onErase = { [weak self] p, r in self?.model.erase(at: p, radiusM: r) }
            inkView.onEraseEnded = { [weak self] in self?.model.endErase() }
        }

        func initialCamera() {
            if model.frame != nil {
                DispatchQueue.main.async { self.zoomToFrame(animated: false) }
            } else {
                // Default Jawa Barat; frame langsung ditempatkan di tengah peta supaya bisa digeser.
                let start = LatLon(lat: -6.8915, lon: 107.6107)
                mapView.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: start.lat, longitude: start.lon),
                                                     latitudinalMeters: 3000, longitudinalMeters: 3000), animated: false)
                DispatchQueue.main.async { self.model.placeFrame(centeredAt: start, recordUndo: false) }
            }
        }

        func sync(force: Bool) {
            let p = model.project
            if force || lastBasemap != model.basemap {
                lastBasemap = model.basemap
                switch model.basemap {
                case .satellite: mapView.preferredConfiguration = MKImageryMapConfiguration()
                case .hybrid: mapView.preferredConfiguration = MKHybridMapConfiguration()
                case .standard: mapView.preferredConfiguration = MKStandardMapConfiguration()
                }
            }

            if force || lastOpacity != p.basemapOpacityValue {
                lastOpacity = p.basemapOpacityValue
                veilRenderer?.alpha = 1 - p.basemapOpacityValue
            }

            if let zone = model.zone,
               force || lastStrokesVersion != model.strokesVersion || lastSheet != p.sheet || lastEPSG != p.crsEPSG {
                lastStrokesVersion = model.strokesVersion
                lastSheet = p.sheet
                lastEPSG = p.crsEPSG
                strokeOverlay.update(strokes: model.strokes, zone: zone, sheet: p.sheet)
                strokeRenderer?.setNeedsDisplay()
            }

            frameView.frameModel = model.frame
            frameView.zone = model.zone
            frameView.isLocked = p.areaLocked
            frameView.isDraggable = model.tool == .area && !p.areaLocked
            frameView.redraw()

            inkView.zone = model.zone
            inkView.sheet = p.sheet
            inkView.fingerDraws = model.fingerDraws
            inkView.penColor = UIColor(hexString: model.pen.colorHex)
            inkView.penWidthMM = model.pen.widthMM
            inkView.mode = model.zone == nil ? .off : (model.tool == .pen ? .pen : (model.tool == .eraser ? .eraser : .off))

            if let cmd = model.mapCommand, cmd.id != lastCommand {
                lastCommand = cmd.id
                run(cmd)
            }
        }

        private func run(_ cmd: MapCommand) {
            switch cmd.kind {
            case .zoomToFrame:
                zoomToFrame(animated: true)
            case let .center(c, span):
                mapView.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon),
                                                     latitudinalMeters: span, longitudinalMeters: span), animated: true)
            case .followUser:
                locationManager.requestWhenInUseAuthorization()
                mapView.showsUserLocation = true
                mapView.setUserTrackingMode(.follow, animated: true)
            }
        }

        func zoomToFrame(animated: Bool) {
            guard let frame = model.frame, let zone = model.zone else { return }
            let pts = frame.corners.map { p -> MKMapPoint in
                let ll = zone.unproject(p)
                return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            let rect = MKMapRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 80, left: 90, bottom: 110, right: model.showsInspector ? 340 : 90), animated: animated)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let o = overlay as? StrokeOverlay {
                let r = StrokeRenderer(overlay: o)
                strokeRenderer = r
                return r
            }
            if let o = overlay as? VeilOverlay {
                let r = VeilRenderer(overlay: o)
                r.alpha = 1 - model.project.basemapOpacityValue
                veilRenderer = r
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            frameView.redraw()
        }

        // MARK: Gestur

        @objc func undoTap() { model.undo() }
        @objc func redoTap() { model.redo() }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            model.togglePenEraser()
        }
    }
}
