import CakraCore
import MapKit
import SwiftUI
import UIKit

/// MKMapView + FrameView + InkView in one container.
///
/// Fingers: pan (1 finger), zoom and rotate (2 fingers). Pencil: draw. Pitch is locked so the scale stays uniform.
struct MapCanvas: UIViewRepresentable {
    @ObservedObject var model: WorkspaceModel
    /// Mapping workspace, or the Course Planner page (course overprint + dimmed map).
    var role: Role = .workspace

    enum Role { case workspace, course }

    func makeCoordinator() -> Coordinator { Coordinator(model: model, role: role) }

    func makeUIView(context: Context) -> UIView {
        let c = context.coordinator
        let container = ResizeAwareView()
        // Canvas size changed (e.g. Mac: map starts below the toolbar strip): redraw all layers.
        container.onResize = { [weak c] in c?.canvasResized() }
        let map = c.mapView
        map.delegate = c
        map.isRotateEnabled = true
        map.isPitchEnabled = false
        map.showsCompass = false
        // Our own scale bar (ScaleBarView below): always visible, labeled, same look on iPad and Mac.
        map.showsScale = false
        // Legal link doesn't stick to the edge. iPad: the map sits below the top bar, so
        // the top margin adds that bar's height; Mac: the canvas already starts below the toolbar strip.
        map.insetsLayoutMarginsFromSafeArea = true
        map.layoutMargins = CP.isMac
            ? UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
            : UIEdgeInsets(top: 76, left: 16, bottom: 16, right: 16)
        map.pointOfInterestFilter = .excludingAll
        // Add order = draw order within one level: veil first, sketch on top.
        map.addOverlay(c.veilOverlay, level: .aboveLabels)
        // Color Hierarchy: map objects (color table order) at the bottom; brown contours above yellow/green areas,
        // north grid and pencil sketch above them, then the course overprint (same as export).
        map.addOverlay(c.featureOverlay, level: .aboveLabels)
        map.addOverlay(c.contourOverlay, level: .aboveLabels)
        map.addOverlay(c.gridOverlay, level: .aboveLabels)
        map.addOverlay(c.strokeOverlay, level: .aboveLabels)
        map.addOverlay(c.courseOverlay, level: .aboveLabels)
        map.addOverlay(c.fieldOverlay, level: .aboveLabels)      // field tracks and notes on top (not printed)

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
        let scale = ScaleBarView(mapView: map)
        c.scaleBar = scale
        container.addSubview(scale)
        // iPad: right of the floating tool rail (the Mac tools sit in the toolbar strip above the canvas).
        let margin = CP.isMac ? UIEdgeInsets(top: 12, left: 14, bottom: 0, right: 0) : UIEdgeInsets(top: 76, left: 84, bottom: 0, right: 0)
        NSLayoutConstraint.activate([
            scale.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: margin.left),
            scale.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: margin.top),
        ])
        c.frameView.mapView = map
        c.inkView.mapView = map
        c.vectorView.mapView = map
        c.vectorView.model = model

        // 2-finger tap = undo, 3-finger tap = redo.
        map.addGestureRecognizer(c.undoTap)
        map.addGestureRecognizer(c.redoTap)
        // On the container (parent of map + drawing layer), not the map: drawing tools capture trackpad scroll/pinch
        // events on the top layer, so 2-finger pan and pinch keep working in every tool (Mac & iPad + trackpad).
        container.addGestureRecognizer(c.scrollPan)
        container.addGestureRecognizer(c.trackpadPinch)
        c.container = container
        // MapKit's internal gestures are created after the first layout.
        DispatchQueue.main.async { c.resolveTapConflicts() }

        // Pencil double-tap = pen ↔ eraser.
        let pencil = UIPencilInteraction()
        pencil.delegate = c
        container.addInteraction(pencil)

        c.sync(force: true)
        c.initialCamera()
        #if DEBUG
        // `-cp-perf`: automated performance test, results in Documents/perf.txt.
        if role == .course { PerformanceProbe.courseMap = map }
        if role == .workspace, ProcessInfo.processInfo.arguments.contains("-cp-perf") {
            let probe = PerformanceProbe()
            c.perfProbe = probe
            Task { await probe.run(model: model, map: map) }
        }
        // `-cp-zoom-probe`: measures the closest camera distance MapKit allows, written to Documents/zoomprobe.txt.
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
        #if DEBUG
        let t = CACurrentMediaTime()
        context.coordinator.sync(force: false)
        PerformanceProbe.syncTime += CACurrentMediaTime() - t
        PerformanceProbe.syncCount += 1
        #else
        context.coordinator.sync(force: false)
        #endif
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIPencilInteractionDelegate, CLLocationManagerDelegate, UIGestureRecognizerDelegate {
        var model: WorkspaceModel
        let role: MapCanvas.Role
        /// The visible map holds the live callbacks (drag); the workspace map under the Course page stays idle.
        private var wasActive = false
        private var lastIntensity: Double?
        let mapView = MKMapView()
        let frameView = FrameView()
        let inkView = InkView()
        let vectorView = VectorEditView()
        let strokeOverlay = StrokeOverlay()
        let featureOverlay = FeatureOverlay()
        let gridOverlay = GridOverlay()
        let contourOverlay = ContourOverlay()
        let courseOverlay = CourseOverlay()
        private weak var courseRenderer: CourseRenderer?
        private var lastCourseState: (Int, UUID?, Bool, SheetSpec, Int?)?
        private weak var contourRenderer: ContourRenderer?
        private var lastContourGeometry: (Int, Bool, SheetSpec, Int?)?
        private var lastContourStyle: ContourSettings?
        private weak var gridRenderer: GridRenderer?
        private var lastGrid: (NorthGrid, MapFrame?)?
        let fieldOverlay = FieldOverlay()
        private weak var fieldRenderer: FieldRenderer?
        private var lastField: (FieldData, Int?, Bool)?
        let veilOverlay = VeilOverlay()
        let undoTap = UITapGestureRecognizer()
        let redoTap = UITapGestureRecognizer()
        /// Trackpad/mouse scroll = pan the view (like design apps); pinch still zooms, ⌘ + scroll = zoom.
        let scrollPan = UIPanGestureRecognizer()
        /// Trackpad pinch over the drawing layer (drawing tool active) = zoom the map.
        let trackpadPinch = UIPinchGestureRecognizer()
        weak var container: UIView?
        weak var scaleBar: ScaleBarView?
        private let locationManager = CLLocationManager()
        private weak var strokeRenderer: StrokeRenderer?
        private weak var veilRenderer: VeilRenderer?
        private weak var featureRenderer: FeatureRenderer?
        private var lastFeaturesVersion = -1
        private var lastAreaOpacity: Double?
        private var lastSketchVisible: Bool?
        private var lastOpacity: Double?
        private var lastStrokesVersion = -1
        private var lastSheet: SheetSpec?
        private var lastEPSG: Int?
        private var lastBasemap: Basemap?
        /// The image basemap (GeoTIFF or HD Apple Maps image) currently shown + its renderer (opacity changes without recreating it).
        private var basemapImageOverlay: BasemapImageOverlay?
        private weak var basemapImageRenderer: BasemapImageRenderer?
        private var lastCommand: UUID?
        private var lastLimitFrame: MapFrame?? = .none
        #if DEBUG
        var perfProbe: AnyObject?
        #endif
        private var lastShowsLocation = false
        private var centerOnNextFix = false
        private weak var radarView: UserRadarView?
        /// Closest requested camera distance (m). MapKit still limits it to the imagery's level of detail.
        static let minZoomDistance: CLLocationDistance = 5

        init(model: WorkspaceModel, role: MapCanvas.Role) {
            self.model = model
            self.role = role
            super.init()
            undoTap.numberOfTouchesRequired = 2
            undoTap.addTarget(self, action: #selector(undoTapped))
            redoTap.numberOfTouchesRequired = 3
            redoTap.addTarget(self, action: #selector(redoTapped))
            scrollPan.allowedScrollTypesMask = .all
            scrollPan.allowedTouchTypes = []   // scroll events only, not finger/Pencil
            scrollPan.addTarget(self, action: #selector(scrolled(_:)))
            scrollPan.delegate = self
            trackpadPinch.addTarget(self, action: #selector(pinched(_:)))
            trackpadPinch.delegate = self
            locationManager.delegate = self
            locationManager.headingFilter = 1
            if CLLocationManager.headingAvailable() { locationManager.startUpdatingHeading() }
        }

        /// Redraws only the changed area (plus a margin for line width).
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
            // Object drag: update the overlay for that object only, bypassing SwiftUI.
            model.onLiveFeatureChange = { [weak self] f in
                guard let self else { return }
                if let dirty = self.featureOverlay.updateOne(self.model.layered([f])[0]) { self.redraw(self.featureRenderer, dirty) }
                self.vectorView.redraw()
            }
            // Control drag: redraw the overprint only.
            model.onLiveCourseChange = { [weak self] in
                guard let self else { return }
                self.updateCourseOverlay()
                self.vectorView.redraw()
            }
            inkView.onStroke = { [weak self] pts in self?.model.addStroke(points: pts) }
            inkView.onErase = { [weak self] p, r in self?.model.erase(at: p, radiusM: r) }
            inkView.onEraseEnded = { [weak self] in self?.model.endErase() }
        }

        /// MapKit's built-in 2-finger tap = zoom out, which clashes with undo. Zoom out via the − button or pinch.
        /// When the initial camera was set; a canvas size change shortly after (Mac layout) = refit.
        private var initialCameraAt = Date.distantPast

        func canvasResized() {
            if Date().timeIntervalSince(initialCameraAt) < 2, model.frame != nil { zoomToFrame(animated: false) }
            redrawAllOverlays()
        }

        /// Adds/replaces/removes the image basemap overlay; only on the workspace map (Course page = white paper).
        /// GeoTIFF basemap when in use, otherwise the HD Apple Maps image of the locked area (live map while it downloads).
        private func syncBasemapImage() {
            var wanted: BasemapImageOverlay?
            if role == .workspace {
                if let image = model.project.basemapImage, image.isVisible, let fileURL = model.basemapImageURL {
                    wanted = BasemapImageOverlay(image: image, fileURL: fileURL)
                    wanted?.opacity = image.opacityValue
                } else if !model.isSelectingArea, model.showsImagerySnapshot, let s = model.imagerySnapshot,
                          let fileURL = model.imagerySnapshotURL {
                    wanted = BasemapImageOverlay(snapshot: s, fileURL: fileURL)
                    wanted?.opacity = model.project.basemapOpacityValue
                }
            }
            if let wanted, let current = basemapImageOverlay, current.key == wanted.key {
                current.opacity = wanted.opacity
                let alpha = CGFloat(wanted.opacity)
                if let r = basemapImageRenderer, r.alpha != alpha { r.alpha = alpha }
                return
            }
            if let old = basemapImageOverlay { mapView.removeOverlay(old) }
            basemapImageOverlay = nil
            guard let wanted else { return }
            basemapImageOverlay = wanted
            // Above the veil (live imagery fader) so only its own opacity applies; below map objects.
            mapView.insertOverlay(wanted, above: veilOverlay)
        }

        func redrawAllOverlays() {
            for r in [veilRenderer, featureRenderer, strokeRenderer, contourRenderer, gridRenderer, courseRenderer] as [MKOverlayRenderer?] {
                r?.setNeedsDisplay()
            }
            vectorView.redraw()
            frameView.redraw()
        }

        /// Trackpad/mouse scroll: pans the map by the scroll amount, same direction as document scrolling on Mac.
        @objc func scrolled(_ g: UIPanGestureRecognizer) {
            guard g.state == .changed else { return }
            let t = g.translation(in: mapView)
            g.setTranslation(.zero, in: mapView)
            guard t != .zero else { return }
            // Direction as tested on a Mac trackpad (all axes): map content moves opposite to the translation of
            // the Catalyst scroll event.
            let c = CGPoint(x: mapView.bounds.midX - t.x, y: mapView.bounds.midY - t.y)
            mapView.setCenter(mapView.convert(c, toCoordinateFrom: mapView), animated: false)
        }

        /// Trackpad pinch: zoom around the pinch point.
        @objc func pinched(_ g: UIPinchGestureRecognizer) {
            guard g.state == .changed, g.scale > 0 else { return }
            let anchor = g.location(in: mapView)
            let before = mapView.convert(anchor, toCoordinateFrom: mapView)
            let cam = mapView.camera.copy() as! MKMapCamera
            cam.centerCoordinateDistance /= Double(g.scale)
            mapView.setCamera(cam, animated: false)
            g.scale = 1
            // The point under the fingers stays put: shift the center by the difference.
            let after = mapView.convert(before, toPointTo: mapView)
            let c = CGPoint(x: mapView.bounds.midX + after.x - anchor.x, y: mapView.bounds.midY + after.y - anchor.y)
            mapView.setCenter(mapView.convert(c, toCoordinateFrom: mapView), animated: false)
        }

        /// ⌘ + scroll = MapKit's built-in zoom. Our pinch is only for the trackpad (no touches) over the drawing
        /// layer; finger pinch and pinch over the map are handled by MapKit itself.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            if g === scrollPan { return !g.modifierFlags.contains(.command) }
            if g === trackpadPinch {
                guard g.numberOfTouches == 0, let container else { return false }
                let hit = container.hitTest(g.location(in: container), with: nil)
                return hit != nil && !(hit!.isDescendant(of: mapView))
            }
            return true
        }

        func resolveTapConflicts() {
            func all(_ v: UIView) -> [UIGestureRecognizer] {
                (v.gestureRecognizers ?? []) + v.subviews.flatMap(all)
            }
            for g in all(mapView) {
                guard let tap = g as? UITapGestureRecognizer, tap !== undoTap, tap !== redoTap,
                      tap.numberOfTouchesRequired >= 2 else { continue }
                tap.require(toFail: tap.numberOfTouchesRequired == 2 ? undoTap : redoTap)
            }
            // MapKit's built-in scroll (= zoom) only runs when our scroll-pan didn't begin (⌘ held).
            for g in all(mapView) where g !== scrollPan {
                guard let pan = g as? UIPanGestureRecognizer, pan.allowedScrollTypesMask != [] else { continue }
                pan.require(toFail: scrollPan)
            }
        }

        func initialCamera() {
            initialCameraAt = Date()
            if model.frame != nil {
                DispatchQueue.main.async { self.zoomToFrame(animated: false) }
            } else {
                // Default West Java; the frame follows the map center right away, then the user searches/pans to the desired area.
                let start = LatLon(lat: -6.8915, lon: 107.6107)
                let s = model.project.sheet
                let span = max(s.groundWidthM, s.groundHeightM) * 1.8
                mapView.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: start.lat, longitude: start.lon),
                                                     latitudinalMeters: span, longitudinalMeters: span), animated: false)
                DispatchQueue.main.async { self.model.setFrameCenter(start) }
            }
        }

        private var isActive: Bool { role == .course || !model.showsCoursePlanner }

        /// Map content alpha: full in the workspace, the chosen intensity on the Course page.
        private var contentAlpha: CGFloat { role == .course ? CGFloat(model.courseMapIntensity) : 1 }
        /// Course page: imagery fully covered, background is only the drawn map (like an OCAD/OOM map in Purple Pen).
        /// Apple imagery fader: full on the Course page and when an image basemap (GeoTIFF) is in use (Apple imagery
        /// hidden); otherwise follows the basemap opacity.
        private var veilAlpha: CGFloat {
            // While selecting the area, Apple imagery stays visible so places outside the image can be found.
            if role == .course || (!model.isSelectingArea && (model.usesBasemapImage || model.showsImagerySnapshot)) { return 1 }
            return 1 - CGFloat(model.project.basemapOpacityValue)
        }

        func sync(force: Bool) {
            // Workspace map covered by the Course page: no update needed; fully refreshed when shown again.
            guard isActive else {
                wasActive = false
                return
            }
            let force = force || !wasActive
            if !wasActive {
                // Old camera commands (from another map or before this map appeared) are not replayed.
                lastCommand = model.mapCommand?.id
                wasActive = true
                wireCallbacks()
            }
            if force || lastIntensity != model.courseMapIntensity {
                lastIntensity = model.courseMapIntensity
                for r in [featureRenderer, strokeRenderer, contourRenderer, gridRenderer] as [MKOverlayRenderer?] { r?.alpha = contentAlpha }
                veilRenderer?.alpha = veilAlpha
            }
            let p = model.project
            syncBasemapImage()
            if force || lastBasemap != model.basemap {
                lastBasemap = model.basemap
                switch model.basemap {
                case .satellite: mapView.preferredConfiguration = MKImageryMapConfiguration()
                case .hybrid: mapView.preferredConfiguration = MKHybridMapConfiguration()
                case .standard: mapView.preferredConfiguration = MKStandardMapConfiguration()
                }
            }

            if let r = veilRenderer, force || lastOpacity != p.basemapOpacityValue || r.alpha != veilAlpha {
                lastOpacity = p.basemapOpacityValue
                r.alpha = veilAlpha
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
            if let zone = model.zone, force || geometryChanged || lastFeaturesVersion != model.featuresVersion
                || lastAreaOpacity != p.areaOpacityValue {
                lastFeaturesVersion = model.featuresVersion
                lastAreaOpacity = p.areaOpacityValue
                if let dirty = featureOverlay.update(features: model.layeredFeatures, zone: zone, sheet: p.sheet, areaOpacity: p.areaOpacityValue) {
                    redraw(featureRenderer, dirty)
                }
            }
            lastSheet = p.sheet
            lastEPSG = p.crsEPSG

            // Geometry (new lines, show/hide, scale, zone) → reconvert in the background.
            // Style (opacity, color, width) → just redraw, no conversion (opacity slider stays smooth).
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

            let courseState = (model.coursesVersion, model.selectedCourseID, role == .course, p.sheet, p.crsEPSG)
            if force || lastCourseState?.0 != courseState.0 || lastCourseState?.1 != courseState.1 || lastCourseState?.2 != courseState.2
                || lastCourseState?.3 != courseState.3 || lastCourseState?.4 != courseState.4 {
                lastCourseState = courseState
                updateCourseOverlay()
            }

            // Field data (tracks, notes) on the map page only, not in the Course Planner.
            let showField = role != .course
            if force || lastField?.0 != model.field || lastField?.1 != p.crsEPSG || lastField?.2 != showField {
                lastField = (model.field, p.crsEPSG, showField)
                fieldOverlay.update(field: showField ? model.field : FieldData(), zone: model.zone)
                fieldRenderer?.setNeedsDisplay()
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

        func updateCourseOverlay() {
            let dirty = courseOverlay.update(role == .course ? model.currentOverprint : nil, zone: model.zone, frame: model.frame,
                                             images: role == .course ? model.courseImages : [:])
            if let dirty { redraw(courseRenderer, dirty) }
        }

        /// Once the area is locked, the map can't be panned/zoomed far from the frame.
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
            case .fitMap:
                fitMap()
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

        /// Rotates the map around the center point without moving the location.
        private func setHeading(_ heading: Double, animated: Bool) {
            let cam = mapView.camera.copy() as! MKMapCamera
            cam.heading = heading
            mapView.setCamera(cam, animated: animated)
        }

        /// Shows the whole map: frame + all content, with room for panels and the dock.
        func fitMap() {
            guard !model.isSelectingArea, let r = model.mapContentExtent else { return zoomToFrame(animated: true) }
            let f = MapFrame(origin: Point2D(x: r.minX, y: r.minY), widthM: max(r.width, 20), heightM: max(r.height, 20))
            guard let rect = mapRect(of: f) else { return }
            let insets = UIEdgeInsets(top: 80, left: 90, bottom: 110, right: role == .course ? 450 : (model.showsInspector ? 400 : 110))
            mapView.setVisibleMapRect(rect, edgePadding: insets, animated: true)
        }

        /// Fits the frame to the screen. In Select Area mode the padding is symmetric, so frame center = map center
        /// (the frame follows the map center, so lopsided padding would shift the frame).
        func zoomToFrame(animated: Bool) {
            guard let frame = model.frame, let rect = mapRect(of: frame) else { return }
            let insets = model.isSelectingArea
                ? UIEdgeInsets(top: 230, left: 100, bottom: 230, right: 100)
                : UIEdgeInsets(top: 80, left: 90, bottom: 110, right: role == .course ? 450 : (model.showsInspector ? 340 : 90))
            mapView.setVisibleMapRect(rect, edgePadding: insets, animated: animated)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let o = overlay as? StrokeOverlay {
                let r = StrokeRenderer(overlay: o)
                r.alpha = contentAlpha
                strokeRenderer = r
                return r
            }
            if let o = overlay as? ContourOverlay {
                let r = ContourRenderer(overlay: o)
                r.alpha = contentAlpha
                contourRenderer = r
                return r
            }
            if let o = overlay as? CourseOverlay {
                let r = CourseRenderer(overlay: o)
                courseRenderer = r
                return r
            }
            if let o = overlay as? FieldOverlay {
                let r = FieldRenderer(overlay: o)
                fieldRenderer = r
                return r
            }
            if let o = overlay as? GridOverlay {
                let r = GridRenderer(overlay: o)
                r.alpha = contentAlpha
                gridRenderer = r
                return r
            }
            if let o = overlay as? FeatureOverlay {
                let r = FeatureRenderer(overlay: o)
                r.alpha = contentAlpha
                featureRenderer = r
                return r
            }
            if let o = overlay as? BasemapImageOverlay {
                let r = BasemapImageRenderer(overlay: o)
                r.alpha = CGFloat(o.opacity)
                basemapImageRenderer = r
                return r
            }
            if let o = overlay as? VeilOverlay {
                let r = VeilRenderer(overlay: o)
                r.alpha = veilAlpha
                // Course page: white paper like a printed course.
                if role == .course { r.color = UIColor.white.cgColor }
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
                    DispatchQueue.main.async { self.model.notice = "Your location is outside the locked area." }
                } else {
                    mapView.setCenter(c, animated: true)
                }
            }
        }

        /// Accuracy circle in screen pt and heading relative to the screen (iPad heading − map rotation).
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
            scaleBar?.update()
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
            model.live.mapCenter = LatLon(lat: mapView.centerCoordinate.latitude, lon: mapView.centerCoordinate.longitude)
            guard model.isSelectingArea, !mapView.bounds.isEmpty else { return }
            let c = mapView.centerCoordinate
            DispatchQueue.main.async { self.model.setFrameCenter(LatLon(lat: c.latitude, lon: c.longitude)) }
        }

        // MARK: Compass

        nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            MainActor.assumeIsolated {
                model.live.deviceHeading = h
                if model.followsHeading { setHeading(h, animated: false) }
                updateRadar()
            }
        }

        // MARK: Gestures

        @objc func undoTapped() { model.undo() }
        @objc func redoTapped() { model.redo() }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            model.togglePenEraser()
        }
    }
}

/// Map container that reports when its size changes.
final class ResizeAwareView: UIView {
    var onResize: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        let first = lastSize == .zero
        lastSize = bounds.size
        if !first { DispatchQueue.main.async { [weak self] in self?.onResize?() } }
    }
}

/// Scale bar: ground distance at the current zoom (not the map's print scale, which is shown with the sheet,
/// e.g. 1:4000). Drawn by OCCA itself — always visible and identical on iPad and Mac (MapKit's own scale only
/// shows while zooming and its standalone view doesn't draw on Mac Catalyst). Blue with a white halo so it stays
/// readable on imagery.
final class ScaleBarView: UIView {
    static let blue = UIColor(red: 0.08, green: 0.40, blue: 0.80, alpha: 1)
    private static let maxBarWidth: CGFloat = 130
    private weak var mapView: MKMapView?
    /// Bar length (m) and its width on screen (pt); nil until the map has a size.
    private var length: (meters: Double, points: CGFloat)?

    init(mapView: MKMapView) {
        self.mapView = mapView
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.maxBarWidth + 40),
            heightAnchor.constraint(equalToConstant: 40),
        ])
        isAccessibilityElement = true
        accessibilityIdentifier = "scaleBar"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Recompute after the map moved or zoomed.
    func update() {
        guard let map = mapView, map.bounds.width > 10 else { return }
        // Meters per point across the middle of the map (independent of rotation: distance along a screen line).
        let y = map.bounds.midY, x0 = map.bounds.midX - 50, x1 = map.bounds.midX + 50
        let a = map.convert(CGPoint(x: x0, y: y), toCoordinateFrom: map), b = map.convert(CGPoint(x: x1, y: y), toCoordinateFrom: map)
        let metersPerPoint = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / Double(x1 - x0)
        guard metersPerPoint.isFinite, metersPerPoint > 0 else { return }
        let meters = Self.niceLength(maxMeters: metersPerPoint * Double(Self.maxBarWidth))
        let next = (meters, CGFloat(meters / metersPerPoint))
        if length?.meters != next.0 || abs((length?.points ?? 0) - next.1) > 0.5 {
            length = next
            accessibilityLabel = "Scale bar, ground distance \(Self.label(meters))"
            setNeedsDisplay()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        update()
    }

    /// Largest 1, 2, 5 × 10ⁿ meters not longer than `maxMeters`.
    static func niceLength(maxMeters: Double) -> Double {
        guard maxMeters > 0 else { return 1 }
        let p = pow(10, floor(log10(maxMeters)))
        return [5, 2, 1].map { $0 * p }.first { $0 <= maxMeters } ?? p
    }

    static func label(_ m: Double) -> String {
        if m >= 1000 { return "\(Fmt.number(m / 1000, decimals: m.truncatingRemainder(dividingBy: 1000) == 0 ? 0 : 1)) km" }
        return "\(Fmt.number(m, decimals: m < 1 ? 1 : 0)) m"
    }

    override func draw(_ rect: CGRect) {
        guard let (meters, width) = length, let ctx = UIGraphicsGetCurrentContext() else { return }
        let blue = Self.blue, halo = UIColor.white.withAlphaComponent(0.9)
        let x0: CGFloat = 1, barY: CGFloat = 31, barH: CGFloat = 5

        func text(_ s: String, at p: CGPoint, size: CGFloat, weight: UIFont.Weight, centered: Bool = false) {
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            let sz = (s as NSString).size(withAttributes: [.font: font])
            let origin = CGPoint(x: centered ? p.x - sz.width / 2 : p.x, y: p.y)
            // White outline first, then blue fill: readable on satellite imagery.
            (s as NSString).draw(at: origin, withAttributes: [.font: font, .strokeColor: halo, .strokeWidth: 5, .foregroundColor: halo])
            (s as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: blue])
        }

        text("Scale · ground distance", at: CGPoint(x: x0, y: 0), size: 10, weight: .semibold)
        // Tick labels: 0, half, full + unit.
        let half = meters / 2
        text("0", at: CGPoint(x: x0, y: 14), size: 10, weight: .medium)
        // Middle label in the end label's unit (km from 1 km), e.g. 0 · 250 · 500 m or 0 · 2.5 · 5 km.
        let mid = meters >= 1000 ? half / 1000 : half
        text(Fmt.number(mid, decimals: mid.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1),
             at: CGPoint(x: x0 + width / 2, y: 14), size: 10, weight: .medium, centered: true)
        text(Self.label(meters), at: CGPoint(x: x0 + width - 4, y: 14), size: 10, weight: .semibold)

        // Bar: halo, then left half blue / right half white, blue outline.
        let bar = CGRect(x: x0, y: barY, width: width, height: barH)
        ctx.setFillColor(halo.cgColor)
        ctx.fill(bar.insetBy(dx: -1.5, dy: -1.5))
        ctx.setFillColor(blue.cgColor)
        ctx.fill(CGRect(x: bar.minX, y: bar.minY, width: width / 2, height: barH))
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: bar.midX, y: bar.minY, width: width / 2, height: barH))
        ctx.setStrokeColor(blue.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(bar.insetBy(dx: 0.5, dy: 0.5))
        // End and middle ticks.
        for x in [bar.minX, bar.midX, bar.maxX] {
            ctx.move(to: CGPoint(x: x, y: barY - 3))
            ctx.addLine(to: CGPoint(x: x, y: barY))
        }
        ctx.strokePath()
    }
}
