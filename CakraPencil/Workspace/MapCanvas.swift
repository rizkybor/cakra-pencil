import CakraCore
import MapKit
import SwiftUI
import UIKit

/// MKMapView + FrameView + InkView dalam satu container.
///
/// Jari: geser (1 jari), zoom dan putar (2 jari). Pencil: menggambar. Pitch dikunci supaya skala tetap seragam.
struct MapCanvas: UIViewRepresentable {
    @ObservedObject var model: WorkspaceModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> UIView {
        let c = context.coordinator
        let container = UIView()
        let map = c.mapView
        map.delegate = c
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        // Urutan tambah = urutan gambar dalam satu level: veil dulu, sketsa di atasnya.
        map.addOverlay(c.veilOverlay, level: .aboveLabels)
        map.addOverlay(c.contourOverlay, level: .aboveLabels)
        map.addOverlay(c.gridOverlay, level: .aboveLabels)
        map.addOverlay(c.strokeOverlay, level: .aboveLabels)
        map.addOverlay(c.featureOverlay, level: .aboveLabels)

        for v in [map, c.frameView, c.inkView, c.vectorView] as [UIView] {
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
        c.vectorView.mapView = map
        c.vectorView.model = model
        c.wireCallbacks()

        // Ketuk 2 jari = undo, ketuk 3 jari = redo.
        map.addGestureRecognizer(c.undoTap)
        map.addGestureRecognizer(c.redoTap)
        // Gestur internal MapKit dibuat setelah layout pertama.
        DispatchQueue.main.async { c.resolveTapConflicts() }

        // Double-tap Pencil = pena ↔ penghapus.
        let pencil = UIPencilInteraction()
        pencil.delegate = c
        container.addInteraction(pencil)

        c.sync(force: true)
        c.initialCamera()
        #if DEBUG
        // `-cp-perf`: uji performa otomatis, hasil di Documents/perf.txt.
        if ProcessInfo.processInfo.arguments.contains("-cp-perf") {
            let probe = PerformanceProbe()
            c.perfProbe = probe
            Task { await probe.run(model: model, map: map) }
        }
        // `-cp-zoom-probe`: ukur jarak kamera terdekat yang diizinkan MapKit, tulis ke Documents/zoomprobe.txt.
        if ProcessInfo.processInfo.arguments.contains("-cp-zoom-probe") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                let cam = map.camera.copy() as! MKMapCamera
                cam.centerCoordinateDistance = 5
                map.setCamera(cam, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    let mpp = map.visibleMapRect.width / Double(map.bounds.width) * MKMetersPerMapPointAtLatitude(map.centerCoordinate.latitude)
                    let text = String(format: "distance=%.1f m, %.4f m/pt", map.camera.centerCoordinateDistance, mpp)
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    try? text.write(to: docs.appendingPathComponent("zoomprobe.txt"), atomically: true, encoding: .utf8)
                }
            }
        }
        #endif
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.model = model
        context.coordinator.sync(force: false)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIPencilInteractionDelegate, CLLocationManagerDelegate {
        var model: WorkspaceModel
        let mapView = MKMapView()
        let frameView = FrameView()
        let inkView = InkView()
        let vectorView = VectorEditView()
        let strokeOverlay = StrokeOverlay()
        let featureOverlay = FeatureOverlay()
        let gridOverlay = GridOverlay()
        let contourOverlay = ContourOverlay()
        private weak var contourRenderer: ContourRenderer?
        private var lastContourGeometry: (Int, Bool, SheetSpec, Int?)?
        private var lastContourStyle: ContourSettings?
        private weak var gridRenderer: GridRenderer?
        private var lastGrid: (NorthGrid, MapFrame?)?
        let veilOverlay = VeilOverlay()
        let undoTap = UITapGestureRecognizer()
        let redoTap = UITapGestureRecognizer()
        private let locationManager = CLLocationManager()
        private weak var strokeRenderer: StrokeRenderer?
        private weak var veilRenderer: VeilRenderer?
        private weak var featureRenderer: FeatureRenderer?
        private var lastFeaturesVersion = -1
        private var lastSketchVisible: Bool?
        private var lastOpacity: Double?
        private var lastStrokesVersion = -1
        private var lastSheet: SheetSpec?
        private var lastEPSG: Int?
        private var lastBasemap: Basemap?
        private var lastCommand: UUID?
        private var lastLimitFrame: MapFrame?? = .none
        #if DEBUG
        var perfProbe: AnyObject?
        #endif
        private var lastShowsLocation = false
        private var centerOnNextFix = false
        private weak var radarView: UserRadarView?
        /// Jarak kamera terdekat yang diminta (m). MapKit tetap membatasi sesuai level detail citra.
        static let minZoomDistance: CLLocationDistance = 5

        init(model: WorkspaceModel) {
            self.model = model
            super.init()
            undoTap.numberOfTouchesRequired = 2
            undoTap.addTarget(self, action: #selector(undoTapped))
            redoTap.numberOfTouchesRequired = 3
            redoTap.addTarget(self, action: #selector(redoTapped))
            locationManager.delegate = self
            locationManager.headingFilter = 1
            if CLLocationManager.headingAvailable() { locationManager.startUpdatingHeading() }
        }

        /// Gambar ulang hanya area yang berubah (plus margin untuk tebal garis).
        private func redraw(_ renderer: MKOverlayRenderer?, _ rect: MKMapRect) {
            guard let renderer else { return }
            if rect.width >= MKMapRect.world.width / 2 {
                renderer.setNeedsDisplay()
            } else {
                let pad = max(rect.width, rect.height) * 0.1 + 200
                renderer.setNeedsDisplay(rect.insetBy(dx: -pad, dy: -pad))
            }
        }

        func wireCallbacks() {
            // Drag objek: perbarui overlay untuk objek itu saja, tanpa lewat SwiftUI.
            model.onLiveFeatureChange = { [weak self] f in
                guard let self else { return }
                if let dirty = self.featureOverlay.updateOne(f) { self.redraw(self.featureRenderer, dirty) }
            }
            inkView.onStroke = { [weak self] pts in self?.model.addStroke(points: pts) }
            inkView.onErase = { [weak self] p, r in self?.model.erase(at: p, radiusM: r) }
            inkView.onEraseEnded = { [weak self] in self?.model.endErase() }
        }

        /// Ketuk 2 jari bawaan MapKit = zoom out, bentrok dengan undo. Zoom out lewat tombol − atau cubit.
        func resolveTapConflicts() {
            func all(_ v: UIView) -> [UIGestureRecognizer] {
                (v.gestureRecognizers ?? []) + v.subviews.flatMap(all)
            }
            for g in all(mapView) {
                guard let tap = g as? UITapGestureRecognizer, tap !== undoTap, tap !== redoTap,
                      tap.numberOfTouchesRequired >= 2 else { continue }
                tap.require(toFail: tap.numberOfTouchesRequired == 2 ? undoTap : redoTap)
            }
        }

        func initialCamera() {
            if model.frame != nil {
                DispatchQueue.main.async { self.zoomToFrame(animated: false) }
            } else {
                // Default Jawa Barat; frame langsung ikut tengah peta, lalu user cari/geser ke area yang diinginkan.
                let start = LatLon(lat: -6.8915, lon: 107.6107)
                let s = model.project.sheet
                let span = max(s.groundWidthM, s.groundHeightM) * 1.8
                mapView.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: start.lat, longitude: start.lon),
                                                     latitudinalMeters: span, longitudinalMeters: span), animated: false)
                DispatchQueue.main.async { self.model.setFrameCenter(start) }
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

            let geometryChanged = lastSheet != p.sheet || lastEPSG != p.crsEPSG
            if let zone = model.zone,
               force || geometryChanged || lastStrokesVersion != model.strokesVersion || lastSketchVisible != model.sketchVisible {
                lastStrokesVersion = model.strokesVersion
                lastSketchVisible = model.sketchVisible
                if let dirty = strokeOverlay.update(strokes: model.sketchVisible ? model.strokes : [], zone: zone, sheet: p.sheet) {
                    redraw(strokeRenderer, dirty)
                }
            }
            if let zone = model.zone, force || geometryChanged || lastFeaturesVersion != model.featuresVersion {
                lastFeaturesVersion = model.featuresVersion
                if let dirty = featureOverlay.update(features: model.features, zone: zone, sheet: p.sheet) {
                    redraw(featureRenderer, dirty)
                }
            }
            lastSheet = p.sheet
            lastEPSG = p.crsEPSG

            // Geometri (garis baru, tampil/sembunyi, skala, zona) → konversi ulang di background.
            // Gaya (opacity, warna, tebal) → cukup gambar ulang, tanpa konversi (slider opacity tetap lancar).
            let geometry = (model.contourVersion, p.contours.isEnabled, p.sheet, p.crsEPSG)
            if force || lastContourGeometry?.0 != geometry.0 || lastContourGeometry?.1 != geometry.1
                || lastContourGeometry?.2 != geometry.2 || lastContourGeometry?.3 != geometry.3 {
                lastContourGeometry = geometry
                lastContourStyle = p.contours
                contourOverlay.update(lines: model.contourLines, settings: p.contours, zone: model.zone, sheet: p.sheet) { [weak self] in
                    self?.contourRenderer?.setNeedsDisplay()
                }
            } else if lastContourStyle != p.contours, let zone = model.zone, let frame = model.frame {
                lastContourStyle = p.contours
                contourOverlay.setStyle(settings: p.contours, sheet: p.sheet, latitude: zone.unproject(frame.center).lat)
                contourRenderer?.setNeedsDisplay()
            }

            if force || lastGrid?.0 != p.grid || lastGrid?.1 != model.frame {
                lastGrid = (p.grid, model.frame)
                gridOverlay.update(grid: p.grid, frame: model.frame, zone: model.zone, sheet: p.sheet)
                gridRenderer?.setNeedsDisplay()
            }

            frameView.frameModel = model.frame
            frameView.zone = model.zone
            frameView.sheet = p.sheet
            frameView.snapStepM = p.snapStepM
            frameView.isLocked = p.areaLocked
            frameView.followsMapCenter = model.isSelectingArea
            frameView.redraw()

            applyCameraLimits(force: force)

            if model.showsMyLocation != lastShowsLocation {
                lastShowsLocation = model.showsMyLocation
                if model.showsMyLocation {
                    locationManager.requestWhenInUseAuthorization()
                    mapView.showsUserLocation = true
                    centerOnNextFix = true
                } else {
                    mapView.setUserTrackingMode(.none, animated: false)
                    mapView.showsUserLocation = false
                    DispatchQueue.main.async { self.model.live.myAccuracyM = nil }
                }
            }

            inkView.zone = model.zone
            inkView.sheet = p.sheet
            inkView.fingerDraws = model.fingerDraws
            inkView.penColor = UIColor(hexString: model.pen.colorHex)
            inkView.penWidthMM = model.pen.widthMM
            inkView.mode = (model.zone == nil || !p.areaLocked) ? .off : (model.tool == .pen ? .pen : (model.tool == .eraser ? .eraser : .off))

            vectorView.model = model
            vectorView.redraw()

            if let cmd = model.mapCommand, cmd.id != lastCommand {
                lastCommand = cmd.id
                run(cmd)
            }
        }

        /// Setelah area dikunci, peta tidak bisa digeser/zoom jauh dari frame.
        private func applyCameraLimits(force: Bool) {
            let target: MapFrame? = model.project.areaLocked ? model.frame : nil
            if !force, case let .some(last) = lastLimitFrame, last == target { return }
            lastLimitFrame = .some(target)
            guard let frame = target, let rect = mapRect(of: frame) else {
                mapView.setCameraBoundary(nil, animated: false)
                mapView.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: Self.minZoomDistance), animated: false)
                return
            }
            let pad = max(rect.width, rect.height) * 0.6
            mapView.setCameraBoundary(MKMapView.CameraBoundary(mapRect: rect.insetBy(dx: -pad, dy: -pad)), animated: false)
            mapView.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: Self.minZoomDistance,
                                                                 maxCenterCoordinateDistance: max(frame.widthM, frame.heightM) * 8), animated: false)
        }

        private func mapRect(of frame: MapFrame) -> MKMapRect? {
            guard let zone = model.zone else { return nil }
            let pts = frame.corners.map { p -> MKMapPoint in
                let ll = zone.unproject(p)
                return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return MKMapRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }

        private func run(_ cmd: MapCommand) {
            switch cmd.kind {
            case .zoomToFrame:
                zoomToFrame(animated: true)
            case let .center(c, span):
                mapView.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon),
                                                     latitudinalMeters: span, longitudinalMeters: span), animated: true)
            case .followUser:
                if let c = mapView.userLocation.location?.coordinate, model.showsMyLocation {
                    mapView.setCenter(c, animated: true)
                } else {
                    centerOnNextFix = true
                    DispatchQueue.main.async { self.model.showsMyLocation = true }
                }
            case let .zoom(factor):
                let cam = mapView.camera.copy() as! MKMapCamera
                cam.centerCoordinateDistance /= factor
                mapView.setCamera(cam, animated: true)
            case .northUp:
                setHeading(0, animated: true)
            case .followHeading:
                if let h = model.live.deviceHeading { setHeading(h, animated: true) }
            case let .zoomToExtent(r):
                let f = MapFrame(origin: Point2D(x: r.minX, y: r.minY), widthM: max(r.width, 10), heightM: max(r.height, 10))
                if let rect = mapRect(of: f) {
                    mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 160, left: 160, bottom: 220, right: model.showsInspector ? 400 : 160), animated: true)
                }
            case let .pan(dx, dy):
                let b = mapView.bounds
                let target = CGPoint(x: b.midX + dx * b.width * 0.25, y: b.midY + dy * b.height * 0.25)
                mapView.setCenter(mapView.convert(target, toCoordinateFrom: mapView), animated: true)
            }
        }

        /// Putar peta di sekitar titik tengah tanpa memindahkan lokasi.
        private func setHeading(_ heading: Double, animated: Bool) {
            let cam = mapView.camera.copy() as! MKMapCamera
            cam.heading = heading
            mapView.setCamera(cam, animated: animated)
        }

        /// Pas-kan frame ke layar. Di mode Pilih Area padding simetris, supaya tengah frame = tengah peta
        /// (frame mengikuti tengah peta, jadi padding miring akan menggeser frame).
        func zoomToFrame(animated: Bool) {
            guard let frame = model.frame, let rect = mapRect(of: frame) else { return }
            let insets = model.isSelectingArea
                ? UIEdgeInsets(top: 230, left: 100, bottom: 230, right: 100)
                : UIEdgeInsets(top: 80, left: 90, bottom: 110, right: model.showsInspector ? 340 : 90)
            mapView.setVisibleMapRect(rect, edgePadding: insets, animated: animated)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let o = overlay as? StrokeOverlay {
                let r = StrokeRenderer(overlay: o)
                strokeRenderer = r
                return r
            }
            if let o = overlay as? ContourOverlay {
                let r = ContourRenderer(overlay: o)
                contourRenderer = r
                return r
            }
            if let o = overlay as? GridOverlay {
                let r = GridRenderer(overlay: o)
                gridRenderer = r
                return r
            }
            if let o = overlay as? FeatureOverlay {
                let r = FeatureRenderer(overlay: o)
                featureRenderer = r
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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKUserLocation else { return nil }
            let v = (mapView.dequeueReusableAnnotationView(withIdentifier: UserRadarView.reuseID) as? UserRadarView)
                ?? UserRadarView(annotation: annotation, reuseIdentifier: UserRadarView.reuseID)
            v.annotation = annotation
            radarView = v
            updateRadar()
            return v
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            updateRadar()
            if let acc = userLocation.location?.horizontalAccuracy, acc >= 0 {
                DispatchQueue.main.async { self.model.live.myAccuracyM = acc }
            }
            if centerOnNextFix, let c = userLocation.location?.coordinate {
                centerOnNextFix = false
                if let frame = model.frame, let zone = model.zone, model.project.areaLocked,
                   !frame.extent.insetBy(-50).intersects(Rect2D(points: [zone.project(LatLon(lat: c.latitude, lon: c.longitude))])!) {
                    DispatchQueue.main.async { self.model.notice = "Posisi Anda di luar area terkunci." }
                } else {
                    mapView.setCenter(c, animated: true)
                }
            }
        }

        /// Lingkar akurasi dalam pt layar dan arah pandang relatif layar (arah hadap iPad − rotasi peta).
        private func updateRadar() {
            guard let v = radarView else { return }
            if let acc = mapView.userLocation.location?.horizontalAccuracy, acc > 0 {
                let a = mapView.convert(CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY), toCoordinateFrom: mapView)
                let b = mapView.convert(CGPoint(x: mapView.bounds.midX + 100, y: mapView.bounds.midY), toCoordinateFrom: mapView)
                let metersPerPoint = MKMapPoint(a).distance(to: MKMapPoint(b)) / 100
                v.accuracyRadius = CGFloat(acc / max(metersPerPoint, 1e-6))
            }
            v.screenHeading = model.live.deviceHeading.map { $0 - mapView.camera.heading }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            frameView.redraw()
            vectorView.redraw()
            updateRadar()
            let h = mapView.camera.heading
            if abs(h - model.live.mapHeading) > 0.5 {
                DispatchQueue.main.async { self.model.live.mapHeading = h }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            frameView.redraw()
            guard model.isSelectingArea, !mapView.bounds.isEmpty else { return }
            let c = mapView.centerCoordinate
            DispatchQueue.main.async { self.model.setFrameCenter(LatLon(lat: c.latitude, lon: c.longitude)) }
        }

        // MARK: Kompas

        nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            MainActor.assumeIsolated {
                model.live.deviceHeading = h
                if model.followsHeading { setHeading(h, animated: false) }
                updateRadar()
            }
        }

        // MARK: Gestur

        @objc func undoTapped() { model.undo() }
        @objc func redoTapped() { model.redo() }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            model.togglePenEraser()
        }
    }
}
