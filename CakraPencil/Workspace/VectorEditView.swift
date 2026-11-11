import CakraCore
import MapKit
import GameController
import UIKit

/// Touch + drawing layer for the vector tools, above the map. All geometry is stored in UTM; this view only
/// converts to/from the screen, so it stays correct when the map is zoomed or rotated.
///
/// - Pen tool: tap = corner point, drag = smooth point (symmetric handles), tap the first point = close into an area.
/// - Rectangle / Ellipse: drag from corner to corner.
/// - Select: tap an object to select it; drag points, handles, or the whole object; double-tap a point = corner ↔ smooth;
///   drag on empty space = selection box (several objects moved/duplicated together).
///
/// Pencil and a single finger both work (the simulator has no Pencil). Two fingers fall through to the map.
final class VectorEditView: UIView {
    weak var mapView: MKMapView?
    weak var model: WorkspaceModel?

    private let selectionLayer = CAShapeLayer()
    /// White outline under the rotation and scale handles, so they stay visible on any map colour. (Not under the
    /// selection outline: it would cover the selected object itself, e.g. a fence line under its tags.)
    private let selectionHaloLayer = CAShapeLayer()
    private let handleLineLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let nodeLayer = CAShapeLayer()
    private let activeNodeLayer = CAShapeLayer()
    private let previewLayer = CAShapeLayer()
    /// Course: a small see-through purple dot on the exact centre of the selected (or dragged) start, control or
    /// finish, as a placement guide.
    private let controlCenterLayer = CAShapeLayer()
    /// Cursor guide: the followed object is highlighted + a ring at the snap point.
    private let guideLayer = CAShapeLayer()
    private let guideCursorLayer = CAShapeLayer()
    private let measureLayer = CAShapeLayer()
    private let rotateHandleLayer = CAShapeLayer()
    /// Move Tool: box around the selected object with round handles (corners + edge midpoints) to scale it.
    private let scaleBoxLayer = CAShapeLayer()
    private let scaleHandleLayer = CAShapeLayer()
    /// Size and percentage while scaling.
    private let scaleLabel = CATextLayer()
    /// Last precise rotation angle (for haptics when snapping to a new angle).
    private var lastRotationSnap: Double?

    static let nodeHit: CGFloat = 22
    /// Scale handles: a little tighter than points, so dragging the object near its box still moves it.
    static let scaleHit: CGFloat = 16
    static let pathHit: CGFloat = 14

    private enum Drag {
        case none
        case draftHandle(start: CGPoint)
        case shape(start: CGPoint)
        case freehand
        case node(index: Int, start: Point2D, original: Feature)
        /// Node Tool: several selected points moved together. `collapseTo`: a plain tap (no drag) on one of them
        /// selects only that point.
        case nodes(indices: [Int], start: Point2D, original: Feature, collapseTo: Int?)
        /// Node Tool: selection box on empty space, selecting points of the selected object.
        case nodeMarquee(start: CGPoint, additive: Bool)
        case handle(index: Int, isIn: Bool, original: Feature)
        case whole(start: Point2D, original: Feature)
        /// Control tool: touch an existing control (tap = use/select, drag = move).
        case control(id: UUID, start: Point2D, original: Point2D, before: CourseSet)
        /// Course page: move an object (text/shape/image).
        case courseItem(original: CourseItem, start: Point2D, before: CourseSet)
        /// Course page: drag a new rectangle/ellipse/line.
        case courseShape(kind: CourseItem.Kind, start: CGPoint)
        /// Move all selected objects. Without moving (tap): `tap` runs at the end.
        case group(start: Point2D, originals: [Feature], tap: GroupTap)
        /// Selection box (drag on empty space). `additive`: add to the selection (Shift),
        /// otherwise replace the selection.
        case marquee(start: CGPoint, additive: Bool)
        /// Measure Tool: drag from the start point (UTM, already snapped to an object).
        case measure(start: Point2D)
        /// Node Tool: dragging a segment of the selected object = bend that segment.
        case segment(ring: Int, index: Int, t: Double, start: Point2D, original: Feature)
        /// Move Tool: drag the rotation handle. Shift = precise (snaps to straight edges of other objects / multiples of 15°).
        case rotate(pivot: CGPoint, startAngle: Double, base: Double, edges: [RotationSnap.Edge], references: [RotationSnap.Edge])
        /// Move Tool: drag a scale handle. `handle` 0…7 clockwise from top-left (even = corner); `anchor` = the
        /// opposite handle (stays put); `box` = the object's screen box at the start.
        case scale(handle: Int, anchor: CGPoint, box: CGRect, original: Feature)
        /// Course page, Cut leg: drag along a leg to set the gap's extent (tap = default gap / remove).
        case legGap(leg: WorkspaceModel.LegHit, startT: Double)
        /// Line cut: a drag = box whose contents are cut out of the selected line; a tap on the line (`tap`) = cut in two.
        case cutBox(start: CGPoint, tap: PathPosition?)
        /// A tap that places something (control, course text or symbol, point symbol) runs on touch-up, not
        /// touch-down: a second finger (pinch) cancels it, and dragging turns it into panning the map.
        case placeOnTap(start: CGPoint, at: Point2D, action: TapPlacement)
        /// One finger dragged on empty map with a placing tool: pans the map.
        case panMap(last: CGPoint)
    }

    private enum TapPlacement {
        case point, control, text, courseSymbol(CourseItem.Kind)
    }

    /// Tap action on an object already in a multi-selection (if it ends up not moved).
    private enum GroupTap {
        case none
        /// Shift: remove this object from the selection.
        case toggle(Feature)
        /// Plain tap: select only this object.
        case single(Feature)
    }

    private var drag = Drag.none
    /// Screen points of the freehand stroke.
    private var freehandPoints: [CGPoint] = []
    private let haptic = UISelectionFeedbackGenerator()
    static let snapRadius: CGFloat = 14
    private var lastSnap: Point2D?
    /// Guide object at the last pen tool draft point.
    private var lastGuide: Guide?

    // MARK: Snap (like OCAD/OOM)

    /// A point of another object within the snap radius: returns its exact UTM position so joins are precise.
    private func snapTarget(_ pt: CGPoint, excluding id: UUID? = nil) -> Point2D? {
        guard let model else { return nil }
        var best: (Point2D, CGFloat)?
        for f in model.features where f.isVisible && f.id != id && f.kind != .point {
            for n in f.allNodes {   // hole corners too
                let d = dist(pt, toScreen(n.point))
                if d <= Self.snapRadius, d < (best?.1 ?? .infinity) { best = (n.point, d) }
            }
        }
        // Vibrate once when snapping to a new point (not every frame during the drag).
        if let p = best?.0, p != lastSnap { haptic.selectionChanged() }
        lastSnap = best?.0
        return best?.0
    }

    /// Snap point on the guide object (OCAD Follow). `ring`: 0 = outer edge, 1… = a hole edge of an area.
    private struct Guide {
        var featureID: UUID
        var ring: Int = 0
        var position: PathPosition
        var point: Point2D
    }

    /// Visible line/area outlines as snap and follow targets: every hole edge of an area counts as its own outline.
    private func guideRings(excluding id: UUID?) -> [(ring: Int, feature: Feature)] {
        guard let model else { return [] }
        return model.features.filter { $0.isVisible && $0.id != id && $0.kind != .point }
            .flatMap { f in f.ringFeatures.enumerated().map { (ring: $0.offset, feature: $0.element) } }
    }

    /// Measure line end: point symbol center, then corners/ends/edges of other objects (like the drawing tools).
    private func measureSnap(_ pt: CGPoint) -> Point2D? {
        guard let model else { return nil }
        let center = model.features
            .filter { $0.isVisible && $0.kind == .point }
            .compactMap { $0.nodes.first?.point }
            .map { ($0, dist(pt, toScreen($0))) }
            .filter { $0.1 <= Self.snapRadius }
            .min { $0.1 < $1.1 }?.0
        return center ?? guideSnap(pt)?.point
    }

    /// Object points first (corners/ends), then its outline when the object guide is on.
    private func guideSnap(_ pt: CGPoint, excluding id: UUID? = nil, haptics: Bool = true) -> Guide? {
        guard let model else { return nil }
        var best: (Guide, CGFloat)?
        let targets = guideRings(excluding: id)
        for (k, f) in targets {
            for (i, n) in f.nodes.enumerated() {
                let d = dist(pt, toScreen(n.point))
                if d <= Self.snapRadius, d < (best?.1 ?? .infinity) {
                    best = (Guide(featureID: f.id, ring: k, position: f.pathPosition(ofNode: i), point: n.point), d)
                }
            }
        }
        if best == nil, model.followGuides, let p = toUTM(pt) {
            let radius = Double(Self.snapRadius) * metersPerPoint
            var bestM: (Guide, Double)?
            for (k, f) in targets {
                guard let b = f.bounds, p.x >= b.minX - radius, p.x <= b.maxX + radius,
                      p.y >= b.minY - radius, p.y <= b.maxY + radius,
                      let r = f.nearestPathPosition(to: p), r.distance <= radius,
                      r.distance < (bestM?.1 ?? .infinity) else { continue }
                bestM = (Guide(featureID: f.id, ring: k, position: r.position, point: r.point), r.distance)
            }
            if let g = bestM?.0 { best = (g, 0) }
        }
        if haptics, let p = best?.0.point, p != lastSnap { haptic.selectionChanged() }
        if haptics { lastSnap = best?.0.point }
        return best?.0
    }

    /// Shape of the guide object from the last draft point to `g` (OCAD Follow), whatever the object kind and symbol:
    /// line ↔ line, line ↔ area, area ↔ area. Tries the second tap's object, the first tap's object, then other
    /// objects both points lie on (e.g. a line lying exactly on an area edge). nil = not on the same object.
    private func followPath(to g: Guide) -> [BezierNode]? {
        guard let model, model.followGuides, let last = lastGuide,
              let lastNode = model.draftNodes.last, lastNode.point.distance(to: last.point) < 1e-6 else { return nil }
        // "Point is on the object" tolerance: 5 cm on the ground (fixed, not zoom-dependent). Tap points are already snapped
        // exactly to the object, so overlapping edges (a line on an area edge) are ≈ 0 apart.
        let tol = 0.05
        // Candidate outlines: the two tapped rings first, then every other outline (hole edges are outlines of their own).
        let tapped = [(id: g.featureID, ring: g.ring), (id: last.featureID, ring: last.ring)]
        var candidates: [(feature: Feature, ring: Int)] = []
        for t in tapped where !candidates.contains(where: { $0.feature.id == t.id && $0.ring == t.ring }) {
            if let f = model.features.first(where: { $0.id == t.id }) { candidates.append((f.ringFeature(t.ring), t.ring)) }
        }
        candidates += guideRings(excluding: nil)
            .filter { c in !tapped.contains { $0.id == c.feature.id && $0.ring == c.ring } }
            .map { ($0.feature, $0.ring) }
        for (f, k) in candidates {
            let from: PathPosition, to: PathPosition
            if f.id == last.featureID, k == last.ring { from = last.position } else {
                guard let r = f.nearestPathPosition(to: last.point), r.distance <= tol else { continue }
                from = r.position
            }
            if f.id == g.featureID, k == g.ring { to = g.position } else {
                guard let r = f.nearestPathPosition(to: g.point), r.distance <= tol else { continue }
                to = r.position
            }
            var nodes = f.followNodes(from: from, to: to)
            guard nodes.count >= 2 else { continue }
            // End exactly at the tap point (not its projection onto another overlapping object).
            nodes[0].point = last.point
            nodes[nodes.count - 1].point = g.point
            return nodes
        }
        return nil
    }

    /// End of a line with the same symbol (or same color + width if no symbol) near the point → (object, starts at the first point?).
    private func continuationTarget(_ pt: CGPoint) -> (Feature, Bool)? {
        guard let model else { return nil }
        for f in model.features.reversed() where f.isVisible && !f.isLocked && f.kind == .line && f.nodes.count >= 2 {
            let sameSymbol = model.activeSymbol.map { $0.code == f.symbolCode } ?? (f.symbolCode == nil && f.colorHex == model.pen.colorHex)
            guard sameSymbol else { continue }
            if dist(pt, toScreen(f.nodes.last!.point)) <= Self.snapRadius { return (f, false) }
            if dist(pt, toScreen(f.nodes.first!.point)) <= Self.snapRadius { return (f, true) }
        }
        return nil
    }
    private var featuresBefore: [Feature] = []
    private var moved = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        // Selection colour: a bright blue that no ISOM/ISSprOM symbol colour uses, over a white halo.
        let sky = UIColor(hex: 0x0A7AFF)
        selectionLayer.strokeColor = sky.cgColor
        selectionLayer.fillColor = UIColor.clear.cgColor
        // Thin dashed outline: the object stays visible through it and between the dashes.
        selectionLayer.lineWidth = 1.5
        selectionLayer.lineDashPattern = [6, 4]
        selectionLayer.lineJoin = .round
        selectionHaloLayer.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        selectionHaloLayer.fillColor = UIColor.clear.cgColor
        selectionHaloLayer.lineWidth = 5
        selectionHaloLayer.lineJoin = .round
        selectionHaloLayer.lineCap = .round
        handleLineLayer.strokeColor = sky.cgColor
        handleLineLayer.lineWidth = 1
        handleLineLayer.fillColor = UIColor.clear.cgColor
        handleLayer.fillColor = UIColor.white.cgColor
        handleLayer.strokeColor = sky.cgColor
        handleLayer.lineWidth = 1.5
        nodeLayer.fillColor = UIColor.white.cgColor
        nodeLayer.strokeColor = sky.cgColor
        nodeLayer.lineWidth = 1.5
        activeNodeLayer.fillColor = sky.cgColor
        previewLayer.fillColor = UIColor.clear.cgColor
        previewLayer.lineCap = .round
        previewLayer.lineJoin = .round
        guideLayer.strokeColor = UIColor.systemCyan.withAlphaComponent(0.55).cgColor
        guideLayer.fillColor = UIColor.clear.cgColor
        guideLayer.lineWidth = 5
        guideLayer.lineCap = .round
        guideLayer.lineJoin = .round
        guideCursorLayer.strokeColor = UIColor.systemCyan.cgColor
        guideCursorLayer.fillColor = UIColor.white.withAlphaComponent(0.6).cgColor
        guideCursorLayer.lineWidth = 2
        measureLayer.strokeColor = UIColor.systemOrange.cgColor
        measureLayer.fillColor = UIColor.white.cgColor
        measureLayer.lineWidth = 2
        measureLayer.lineDashPattern = [6, 4]
        measureLayer.lineCap = .round
        rotateHandleLayer.strokeColor = sky.cgColor
        rotateHandleLayer.fillColor = UIColor.white.cgColor
        rotateHandleLayer.lineWidth = 2
        scaleBoxLayer.strokeColor = sky.withAlphaComponent(0.7).cgColor
        scaleBoxLayer.fillColor = UIColor.clear.cgColor
        scaleBoxLayer.lineWidth = 1
        scaleBoxLayer.lineDashPattern = [4, 3]
        scaleHandleLayer.strokeColor = sky.cgColor
        scaleHandleLayer.fillColor = UIColor.white.cgColor
        scaleHandleLayer.lineWidth = 2
        scaleLabel.fontSize = 11
        scaleLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        scaleLabel.foregroundColor = UIColor.white.cgColor
        scaleLabel.backgroundColor = sky.cgColor
        scaleLabel.cornerRadius = 5
        scaleLabel.alignmentMode = .center
        scaleLabel.contentsScale = UIScreen.main.scale
        scaleLabel.isHidden = true
        controlCenterLayer.fillColor = UIColor(hexString: "#A626FF").withAlphaComponent(0.5).cgColor
        controlCenterLayer.strokeColor = nil
        for l in [guideLayer, previewLayer, selectionHaloLayer, selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer, guideCursorLayer, measureLayer, scaleBoxLayer, rotateHandleLayer, scaleHandleLayer, controlCenterLayer] {
            layer.addSublayer(l)
        }
        layer.addSublayer(scaleLabel)
        #if DEBUG
        // UI tests read the selected object's box size (scale handles) from the value.
        isAccessibilityElement = true
        accessibilityIdentifier = "vectorEditOverlay"
        #endif
        // Apple Pencil hover / trackpad: the cursor guide shows before touching the screen.
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
    }

    /// Size changed (keyboard, screen rotation, panel): points' screen positions change without a map region event.
    private var lastLayoutSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        redraw()
    }

    @objc private func hovered(_ g: UIHoverGestureRecognizer) {
        // Mac: the keys held while the pointer moves over the map (Shift + click to add to the selection).
        if g.state == .began || g.state == .changed { ModifierKeys.hover = g.modifierFlags }
        switch g.state {
        case .began, .changed: showGuideCursor(at: g.location(in: self))
        default: clearGuideCursor()
        }
    }

    private var drawsWithGuides: Bool {
        guard let model else { return false }
        switch model.tool {
        case .bezier, .freehand, .rectangle, .ellipse, .point, .measure: return model.project.areaLocked
        default: return false
        }
    }

    /// Highlights the guide object + a ring at the snap point; the pen tool also shows the shape to be followed.
    private func showGuideCursor(at pt: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard drawsWithGuides, let model,
              let g = guideSnap(pt, excluding: model.tool == .bezier ? model.continuingFeatureID : nil, haptics: false),
              let f = model.features.first(where: { $0.id == g.featureID }) else {
            guideLayer.path = nil
            guideCursorLayer.path = nil
            return
        }
        if model.tool == .bezier, let follow = followPath(to: g) {
            guideLayer.path = path(for: Feature(kind: .line, colorHex: "#000000", widthMM: 0, nodes: follow)).cgPath
        } else {
            guideLayer.path = path(for: f).cgPath
        }
        let c = toScreen(g.point)
        guideCursorLayer.path = UIBezierPath(ovalIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)).cgPath
    }

    private func clearGuideCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideLayer.path = nil
        guideCursorLayer.path = nil
        CATransaction.commit()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Conversion

    private var zone: UTMZone? { model?.zone }

    private func toUTM(_ pt: CGPoint) -> Point2D? {
        guard let mapView, let zone else { return nil }
        let c = mapView.convert(pt, toCoordinateFrom: self)
        return zone.project(LatLon(lat: c.latitude, lon: c.longitude))
    }

    private func toScreen(_ p: Point2D) -> CGPoint {
        guard let mapView, let zone else { return .zero }
        let ll = zone.unproject(p)
        return mapView.convert(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon), toPointTo: self)
    }

    private var metersPerPoint: Double {
        guard let a = toUTM(CGPoint(x: bounds.midX, y: bounds.midY)), let b = toUTM(CGPoint(x: bounds.midX + 100, y: bounds.midY)) else { return 1 }
        return a.distance(to: b) / 100
    }

    // MARK: Hit test

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let model, model.project.areaLocked, self.point(inside: point, with: event) else { return nil }
        if (event?.allTouches?.count ?? 1) > 1 { return nil }
        switch model.tool {
        case .point, .bezier, .freehand, .rectangle, .ellipse, .control, .measure:
            return self
        case .select, .node:
            // Line cut: taps and box drags anywhere. Area split: taps near the selected object are taken;
            // otherwise the map can still be panned.
            if model.cutMode {
                if model.selectedFeature?.kind == .line { return self }
                return cutPosition(at: point) != nil ? self : nil
            }
            // Click and drag on empty space = selection box (like OCAD/OOM); pan the map with two fingers
            // or the Navigate tool.
            return self
        default:
            return nil
        }
    }

    private enum Target {
        case node(Int), handle(Int, isIn: Bool), selectedPath, other(Feature)
    }

    private func target(at pt: CGPoint) -> Target? {
        guard let model else { return nil }
        if !model.isMultiSelection, let f = model.selectedFeature, !f.isLocked {
            // Hole points continue after the outer ring's points (Feature.allNodes).
            let all = f.allNodes
            for (i, n) in all.enumerated() {
                if let h = n.inHandle, dist(pt, toScreen(h)) <= Self.nodeHit { return .handle(i, isIn: true) }
                if let h = n.outHandle, dist(pt, toScreen(h)) <= Self.nodeHit { return .handle(i, isIn: false) }
            }
            for (i, n) in all.enumerated() where dist(pt, toScreen(n.point)) <= Self.nodeHit { return .node(i) }
            if let p = toUTM(pt), f.distance(to: p, tolerance: metersPerPoint) <= Double(Self.pathHit) * metersPerPoint {
                return .selectedPath
            }
        }
        return topFeature(at: pt).map { .other($0) }
    }

    /// Topmost object at this screen point (visible, not locked).
    private func topFeature(at pt: CGPoint) -> Feature? {
        guard let model, let p = toUTM(pt) else { return nil }
        let tol = Double(Self.pathHit) * metersPerPoint
        // Topmost first.
        // Topmost first, by Color Hierarchy (what's visible on top gets selected).
        for f in model.featuresTopDown where f.isVisible && !f.isLocked {
            if f.kind == .point, let c = f.nodes.first?.point {
                if c.distance(to: p) <= max(tol, f.pointRadiusM(sheet: model.project.sheet)) { return f }
                continue
            }
            guard let b = f.bounds, p.x >= b.minX - tol, p.x <= b.maxX + tol, p.y >= b.minY - tol, p.y <= b.maxY + tol else { continue }
            if f.distance(to: p, tolerance: metersPerPoint) <= tol || (f.kind == .area && contains(f, p)) { return f }
        }
        return nil
    }

    /// Objects hit by the selection box (screen): an object point inside the box, or the box inside an area.
    private func features(in rect: CGRect) -> [Feature] {
        guard let model else { return [] }
        return model.features.filter { f in
            guard f.isVisible, !f.isLocked else { return false }
            if f.flattenedRings(tolerance: metersPerPoint * 2).joined().contains(where: { rect.contains(toScreen($0)) }) { return true }
            if f.kind == .area, let c = toUTM(CGPoint(x: rect.midX, y: rect.midY)) { return contains(f, c) }
            return false
        }
    }

    /// Cut position on the selected object's outline (object points preferred, so the cut lands exactly on a point).
    private func cutPosition(at pt: CGPoint) -> PathPosition? {
        guard let model, let f = model.selectedFeature else { return nil }
        for (i, n) in f.nodes.enumerated() where dist(pt, toScreen(n.point)) <= Self.nodeHit { return f.pathPosition(ofNode: i) }
        guard let p = toUTM(pt), let r = f.nearestPathPosition(to: p), r.distance <= Double(Self.nodeHit) * metersPerPoint else { return nil }
        return r.position
    }

    /// Point inside the filled part of the area (even-odd over the outer ring and its holes: a tap in a hole misses).
    private func contains(_ f: Feature, _ p: Point2D) -> Bool {
        f.containsPoint(p, tolerance: metersPerPoint)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model, let touch = touches.first, let p = toUTM(touch.location(in: self)) else { return }
        let pt = touch.location(in: self)
        featuresBefore = model.features
        moved = false
        switch model.tool {
        case .point:
            // Point symbols can be placed exactly on lines/corners of other objects (placed on touch-up).
            drag = .placeOnTap(start: pt, at: guideSnap(pt)?.point ?? p, action: .point)
        case .bezier:
            if touch.tapCount >= 2, model.draftNodes.count >= 2 {
                // Double-tap = finish (OCAD/OOM: double-click). The first tap already added a point here,
                // so that point becomes the end point; the second tap adds no further point.
                model.finishDraftForActiveSymbol()
                drag = .none
            } else if model.draftNodes.count >= 3, let first = model.draftNodes.first, dist(pt, toScreen(first.point)) <= Self.nodeHit {
                // Back to the start point: area symbol → area; line symbol → closed line (still a line).
                // Cutting an area: a closed path = cut its shape away.
                if model.activeSymbol?.kind == .area || model.isDrawingCut {
                    model.finishDraft(as: .area)
                } else {
                    model.appendDraftNode(BezierNode(point: first.point))
                    model.finishDraft(as: .line)
                }
                drag = .none
            } else if model.draftNodes.isEmpty, !model.isDrawingCut, !(model.autoMerge && model.followGuides),
                      let (f, fromStart) = continuationTarget(pt) {
                // With auto-join + follow object, starting at a line end = a new line that can follow
                // that line; if it doesn't overlap, its end is still connected via auto-join.
                model.beginContinuation(of: f, fromStart: fromStart)
                lastGuide = nil
                haptic.selectionChanged()
                drag = .none
            } else {
                if model.draftNodes.isEmpty { lastGuide = nil }
                let g = guideSnap(pt, excluding: model.continuingFeatureID)
                if let g, let follow = followPath(to: g) {
                    // OCAD Follow: two consecutive points on the same object → the object's shape between them is copied.
                    model.appendFollowedDraft(follow)
                } else {
                    model.appendDraftNode(BezierNode(point: g?.point ?? p))
                }
                lastGuide = g
                drag = g == nil ? .draftHandle(start: pt) : .none
            }
        case .freehand:
            freehandPoints = [guideSnap(pt).map { toScreen($0.point) } ?? pt]
            drag = .freehand
        case .rectangle, .ellipse:
            // Corners snap to points/lines of other objects.
            drag = .shape(start: guideSnap(pt).map { toScreen($0.point) } ?? pt)
        case .control where model.courseEditMode == .legGap:
            // Cut leg: tap a leg = gap there (tap a gap = remove it); drag along a leg = gap of that length.
            if let leg = model.legHit(at: p, toleranceM: metersPerPoint * Double(Self.pathHit)) {
                drag = .legGap(leg: leg, startT: leg.t)
            } else {
                model.toggleLegGap(at: p, toleranceM: metersPerPoint * Double(Self.pathHit))   // shows the "open a course" hint
                drag = .none
            }
        case .control where model.courseEditMode == .move:
            // Course Move Tool: select and move controls and objects; tap empty space = deselect, nothing is placed.
            if let c = model.control(near: p, radiusM: metersPerPoint * Double(Self.nodeHit)) {
                drag = .control(id: c.id, start: p, original: c.position, before: model.courseSet)
                model.selectedControlID = c.id
                model.selectedCourseItemID = nil
            } else if let item = model.courseItem(near: p, radiusM: metersPerPoint * Double(Self.pathHit)) {
                drag = .courseItem(original: item, start: p, before: model.courseSet)
                model.selectedCourseItemID = item.id
                model.selectedControlID = nil
            } else {
                model.selectedControlID = nil
                model.selectedCourseItemID = nil
                drag = .none
            }
        case .control:
            // Hit an existing control (at least 22 pt on screen) → wait: tap or drag. Otherwise: new control.
            if let c = model.control(near: p, radiusM: metersPerPoint * Double(Self.nodeHit)) {
                drag = .control(id: c.id, start: p, original: c.position, before: model.courseSet)
                model.selectedControlID = c.id
                model.selectedCourseItemID = nil
            } else if let item = model.courseItem(near: p, radiusM: metersPerPoint * Double(Self.pathHit)) {
                // Course object: tap = select, drag = move.
                drag = .courseItem(original: item, start: p, before: model.courseSet)
                model.selectedCourseItemID = item.id
                model.selectedControlID = nil
            } else if let kind = model.courseItemTool {
                switch kind {
                case .text:
                    drag = .placeOnTap(start: pt, at: p, action: .text)
                case .image:
                    drag = .none
                default:
                    // IOF point symbols: tap; lines and areas (and plain shapes): drag.
                    if kind.placement == .tap {
                        drag = .placeOnTap(start: pt, at: p, action: .courseSymbol(kind))
                    } else {
                        drag = .courseShape(kind: kind, start: pt)
                    }
                }
            } else {
                drag = .placeOnTap(start: pt, at: p, action: .control)
            }
        case .measure:
            let a = measureSnap(pt) ?? p
            model.measurement = MapMeasurement(start: a, end: a)
            drag = .measure(start: a)
        case .select where !model.cutMode && scaleHandle(at: pt) != nil:
            // Scale handle (round point on the box): corner = proportional, edge = one direction; Shift = the other.
            if let i = scaleHandle(at: pt), let handles = scaleHandles(), let box = scaleBox(),
               let anchor = handles[(i + 4) % 8] ?? Self.oppositePoint(i, in: box), let f = model.selectedFeature {
                // Point symbols grow from their center; lines/areas from the opposite handle.
                drag = .scale(handle: i, anchor: f.kind == .point ? CGPoint(x: box.midX, y: box.midY) : anchor, box: box, original: f)
            }
        case .select where !model.cutMode && rotateHandle().map({ dist($0, pt) <= Self.nodeHit + 6 }) == true:
            // Rotation handle above the selected object.
            if let f = model.selectedFeature, let c = model.selectedFeature?.rotationPivot.map(toScreen) {
                let mpp = metersPerPoint
                let edges = f.straightEdges(minLength: 8 * mpp)
                drag = .rotate(pivot: c, startAngle: screenAngle(from: c, to: pt), base: f.rotationDegrees,
                               edges: edges, references: rotationReferences(for: f, minLength: 8 * mpp))
                lastRotationSnap = nil
            }
        case .select where model.cutMode && model.selectedFeature?.kind == .line,
             .node where model.cutMode && model.selectedFeature?.kind == .line:
            // Decided at the end: a tap cuts in two, a drag cuts out what the box covers.
            drag = .cutBox(start: pt, tap: cutPosition(at: pt))
        case .select where model.cutMode, .node where model.cutMode:
            if let pos = cutPosition(at: pt) {
                model.cutSelected(at: pos)
                haptic.selectionChanged()
            }
            drag = .none
        case .select where shiftHeld(event):
            // Shift (multi-select): tap = add/remove, drag a selected object = move all, drag empty space = selection box.
            if let f = topFeature(at: pt) {
                let wasSelected = model.isSelected(f.id)
                if !wasSelected { model.toggleSelection(f) }
                drag = .group(start: p, originals: model.selection, tap: wasSelected ? .toggle(f) : .none)
            } else {
                drag = .marquee(start: pt, additive: true)
            }
        case .select:
            // Move Tool: works on whole objects (no points/handles).
            if let f = topFeature(at: pt) {
                if model.isMultiSelection && model.isSelected(f.id) {
                    // Dragging one of the selected objects = move them all; tap = select only that object.
                    drag = .group(start: p, originals: model.selection, tap: .single(f))
                } else if touch.tapCount == 2, model.selectedFeatureID == f.id {
                    // Double-tap a selected object = enter Node Tool to edit its points (like Illustrator).
                    model.tool = .node
                    haptic.selectionChanged()
                    drag = .none
                } else {
                    if model.selectedFeatureID != f.id || model.isMultiSelection { model.select(f) }
                    drag = .whole(start: p, original: f)
                }
            } else {
                drag = .marquee(start: pt, additive: false)
            }
        case .node:
            // Node Tool: points, handles, and outline of the selected object; tap another object = select it.
            switch target(at: pt) {
            case let .node(i)? where multiSelectHeld(event):
                // Shift/⌘-click: add/remove the point; dragging then moves all selected points.
                model.toggleNodeSelection(i)
                if model.selectedNodeIndices.contains(i), let f = model.selectedFeature {
                    drag = .nodes(indices: model.selectedNodeIndices.sorted(), start: p, original: f, collapseTo: nil)
                } else {
                    drag = .none
                }
                haptic.selectionChanged()
            case let .node(i)? where model.selectedNodeIndices.count > 1 && model.selectedNodeIndices.contains(i) && touch.tapCount < 2:
                // Drag one of several selected points = move them all; a plain tap selects only that point.
                model.selectedNodeIndex = i
                if let f = model.selectedFeature {
                    drag = .nodes(indices: model.selectedNodeIndices.sorted(), start: p, original: f, collapseTo: i)
                }
            case let .node(i)?:
                model.selectedNodeIndices = [i]
                model.selectedNodeIndex = i
                if touch.tapCount == 2, let id = model.selectedFeatureID {
                    model.updateFeature(id) { $0.toggleSmooth(at: i) }
                    drag = .none
                } else if let f = model.selectedFeature {
                    drag = .node(index: i, start: p, original: f)
                }
            case let .handle(i, isIn)?:
                if let f = model.selectedFeature { drag = .handle(index: i, isIn: isIn, original: f) }
            case .selectedPath?:
                if touch.tapCount == 2 {
                    // Reshape (OCAD): double-tap on the selected object's line = add a point there.
                    model.insertNode(near: p)
                    haptic.selectionChanged()
                    drag = .none
                } else if let f = model.selectedFeature, let r = f.nearestRingPosition(to: p),
                          r.distance <= Double(Self.pathHit) * metersPerPoint {
                    // Dragging the line between two points = bend that segment (like Affinity/Illustrator); hole edges too.
                    model.selectedNodeIndex = nil
                    drag = .segment(ring: r.ring, index: r.position.segment, t: r.position.t, start: p, original: f)
                } else if let f = model.selectedFeature {
                    drag = .whole(start: p, original: f)   // area fill: move the object
                }
            case let .other(f)?:
                model.select(f)
                drag = .none
            case nil:
                // Drag on empty space = selection box for points (Shift/⌘ adds); a tap deselects.
                drag = .nodeMarquee(start: pt, additive: multiSelectHeld(event))
            }
        default:
            drag = .none
        }
        redraw()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model, let touch = touches.first else { return }
        let pt = touch.location(in: self)
        guard let p = toUTM(pt) else { return }
        switch drag {
        case .freehand, .shape, .measure: showGuideCursor(at: pt)
        default: break
        }
        switch drag {
        case let .draftHandle(start):
            guard dist(start, pt) > 4, var n = model.draftNodes.last else { break }
            n.outHandle = p
            n.inHandle = n.point - (p - n.point)
            model.updateLastDraftNode(n)
        case let .shape(start):
            showShapePreview(from: start, to: pt)
        case .freehand:
            freehandPoints += (event?.coalescedTouches(for: touch) ?? [touch]).map { $0.preciseLocation(in: self) }
            let path = UIBezierPath()
            path.move(to: freehandPoints[0])
            for q in freehandPoints.dropFirst() { path.addLine(to: q) }
            previewLayer.path = path.cgPath
            previewLayer.strokeColor = model.isDrawingCut ? UIColor.systemBlue.cgColor : UIColor(hexString: model.pen.colorHex).cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = 2
            previewLayer.lineDashPattern = model.isDrawingCut ? [5, 3] : nil
        case let .node(i, start, original):
            var f = original
            // Points snap to other objects' points (line ends/area corners) so they can be auto-joined.
            let all = original.allNodes
            guard all.indices.contains(i) else { break }
            let target = snapTarget(pt, excluding: original.id) ?? all[i].point + (p - start)
            var next = all
            next[i] = all[i].moved(by: target - all[i].point)
            f.allNodes = next
            f.refreshSmartNodes()   // smart points (this one and its neighbors) adjust their curves too
            model.updateFeatureLive(f)
            moved = true
        case let .nodes(indices, start, original, _):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 3 || moved else { break }
            var f = original
            var all = original.allNodes
            for i in indices where all.indices.contains(i) { all[i] = all[i].moved(by: d) }
            f.allNodes = all
            f.refreshSmartNodes()
            model.updateFeatureLive(f)
            moved = true
        case let .handle(i, isIn, original):
            var f = original
            f.moveHandle(node: i, isIn: isIn, to: p)
            model.updateFeatureLive(f)
            moved = true
        case let .legGap(leg, startT):
            let t = leg.fraction(of: p)
            guard dist(toScreen(leg.point(startT)), toScreen(leg.point(t))) > 6 || moved else { break }
            // Preview: the part of the leg that will be cut.
            let path = UIBezierPath()
            path.move(to: toScreen(leg.point(startT)))
            path.addLine(to: toScreen(leg.point(t)))
            previewLayer.path = path.cgPath
            previewLayer.strokeColor = UIColor.systemRed.withAlphaComponent(0.8).cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = 6
            previewLayer.lineDashPattern = [4, 3]
            moved = true
        case let .scale(handle, anchor, box, original):
            applyScale(handle: handle, anchor: anchor, box: box, original: original, to: pt, free: shiftHeld(event))
            moved = true
        case let .rotate(pivot, startAngle, base, edges, references):
            let raw = base + screenAngle(from: pivot, to: pt) - startAngle
            if shiftHeld(event) {
                // Precise rotation: straight edges snap parallel/perpendicular to other objects' edges, or to multiples of 15°.
                let snap = RotationSnap.snap(raw: raw, base: base, edges: edges, references: references)
                model.rotateSelectedLive(to: snap.degrees, exactly: true)
                if snap.degrees != lastRotationSnap { haptic.selectionChanged() }
                lastRotationSnap = snap.degrees
                showRotationReference(snap.reference)
            } else {
                model.rotateSelectedLive(to: raw)
                lastRotationSnap = nil
                showRotationReference(nil)
            }
            moved = true
        case let .segment(ring, i, t, start, original):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 2 || moved else { break }
            model.updateFeatureLive(original.replacingRing(ring) { $0.bendingSegment(i, at: t, by: d) })
            moved = true
        case let .whole(start, original):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 3 || moved else { break }
            model.updateFeatureLive(original.moved(by: d))   // holes move along
            moved = true
        case let .group(start, originals, _):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 3 || moved else { break }
            model.moveSelectionLive(originals, by: d)
            moved = true
        case let .measure(start):
            let b = measureSnap(pt) ?? p
            model.measurement = MapMeasurement(start: start, end: b)
        case .marquee(start: let start, additive: _), .nodeMarquee(start: let start, additive: _), .cutBox(start: let start, tap: _):
            let r = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y), width: abs(start.x - pt.x), height: abs(start.y - pt.y))
            previewLayer.path = UIBezierPath(rect: r).cgPath
            previewLayer.strokeColor = UIColor.systemBlue.cgColor
            previewLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
            previewLayer.lineWidth = 1
            previewLayer.lineDashPattern = [5, 3]
        case let .control(id, start, original, _):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 3 || moved else { break }
            model.moveControlLive(id, to: original + d)
            moved = true
        case let .courseItem(original, start, _):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 3 || moved else { break }
            model.moveCourseItemLive(original, by: d)
            moved = true
        case let .courseShape(kind, start):
            guard let a = toUTM(start) else { break }
            let outline = CourseItem(kind: kind, points: [a, p]).outline.map(toScreen)
            let path = UIBezierPath()
            if let first = outline.first {
                path.move(to: first)
                for q in outline.dropFirst() { path.addLine(to: q) }
                if kind.placement == .area { path.close() }
            }
            previewLayer.path = path.cgPath
            previewLayer.strokeColor = UIColor(hexString: "#A626FF").cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = 2
        case let .placeOnTap(start, _, _):
            // Dragged instead of tapped: nothing is placed, the map pans with the finger.
            guard dist(pt, start) > 10 else { break }
            panMap(from: start, to: pt)
            drag = .panMap(last: pt)
        case let .panMap(last):
            panMap(from: last, to: pt)
            drag = .panMap(last: pt)
        case .none:
            break
        }
        redraw()
    }

    /// Moves the map with the finger (the point under the finger stays under it).
    private func panMap(from a: CGPoint, to b: CGPoint) {
        guard let mapView else { return }
        let c = CGPoint(x: mapView.bounds.midX - (b.x - a.x), y: mapView.bounds.midY - (b.y - a.y))
        mapView.setCenter(mapView.convert(c, toCoordinateFrom: mapView), animated: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model, let touch = touches.first else { return }
        let pt = touch.location(in: self)
        if case let .shape(start) = drag {
            finishShape(from: start, to: guideSnap(pt, haptics: false).map { toScreen($0.point) } ?? pt)
        }
        if case .freehand = drag {
            // The end point is snapped too; parts running along another object follow that object's shape.
            var pts = freehandPoints.compactMap(toUTM)
            if let end = guideSnap(pt, haptics: false)?.point, !pts.isEmpty { pts[pts.count - 1] = end }
            if model.isDrawingCut {
                model.cutSelectedArea(alongFreehand: pts)
            } else {
                model.addFreehand(pts, guideRadiusM: Double(Self.snapRadius) * metersPerPoint)
            }
            freehandPoints = []
        }
        if case let .cutBox(start, tap) = drag {
            let r = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y), width: abs(start.x - pt.x), height: abs(start.y - pt.y))
            if r.width < 8 && r.height < 8 {
                if let tap {
                    model.cutSelected(at: tap)
                    haptic.selectionChanged()
                }
            } else {
                // The box is drawn on screen: its corners as map coordinates (a rotated map gives a rotated box).
                let corners = screenCorners(start, pt).compactMap(toUTM)
                if corners.count == 4 {
                    model.cutSelectedLine(outside: corners)
                    haptic.selectionChanged()
                }
            }
            previewLayer.lineDashPattern = nil
            moved = false
        }
        clearGuideCursor()
        if case let .marquee(start, additive) = drag {
            let r = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y), width: abs(start.x - pt.x), height: abs(start.y - pt.y))
            if r.width < 8 && r.height < 8 {
                model.deselect()   // tap empty space = deselect all
            } else {
                let hit = features(in: r)
                if !additive { model.deselect() }
                if !additive, hit.count == 1 { model.select(hit[0]) } else { model.addToSelection(hit) }
                haptic.selectionChanged()
            }
            previewLayer.lineDashPattern = nil
        }
        if case let .legGap(leg, startT) = drag {
            if moved, let p = toUTM(pt) {
                model.setLegGap(leg, from: startT, to: leg.fraction(of: p))
            } else {
                model.toggleLegGap(at: leg.point(startT), toleranceM: metersPerPoint * Double(Self.pathHit))
            }
            haptic.selectionChanged()
            previewLayer.lineDashPattern = nil
            drag = .none
            moved = false
        }
        if case let .nodeMarquee(start, additive) = drag {
            let r = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y), width: abs(start.x - pt.x), height: abs(start.y - pt.y))
            if r.width < 8 && r.height < 8 {
                if !additive { model.deselect() }   // tap empty space = deselect
            } else if let f = model.selectedFeature {
                let all = f.allNodes
                let hit = Set(all.indices.filter { r.contains(toScreen(all[$0].point)) })
                model.selectNodes(hit, additive: additive)
                if !hit.isEmpty { haptic.selectionChanged() }
            }
            previewLayer.lineDashPattern = nil
        }
        if case let .nodes(_, _, _, collapse) = drag, !moved, let i = collapse {
            model.selectedNodeIndices = [i]
            model.selectedNodeIndex = i
        }
        if case let .group(_, _, tap) = drag, !moved {
            switch tap {
            case let .toggle(f): model.toggleSelection(f)
            case let .single(f): model.select(f)
            case .none: break
            }
        }
        if case let .courseShape(kind, start) = drag, let a = toUTM(start), let b = toUTM(pt) {
            model.addCourseShape(kind, from: a, to: b)
        }
        if case let .placeOnTap(_, at, action) = drag {
            switch action {
            case .point: model.placePoint(at: at)
            case .control:
                model.placeControl(at: at)
                model.selectedCourseItemID = nil
            case .text: model.placeCourseText(at: at)
            case let .courseSymbol(kind): model.placeCourseSymbol(kind, at: at)
            }
            haptic.selectionChanged()
        }
        if case let .courseItem(_, _, before) = drag {
            if moved { model.commitCourseEdit(from: before) }
        } else if case let .control(id, _, _, before) = drag {
            if moved { model.commitCourseEdit(from: before) } else { model.tapControl(id) }
        } else if moved, case let .node(_, _, original) = drag {
            model.commitNodeEdit(from: featuresBefore, featureID: original.id)
        } else if moved, case let .nodes(_, _, original, _) = drag {
            model.commitNodeEdit(from: featuresBefore, featureID: original.id)
        } else if moved {
            model.commitFeatureEdit(from: featuresBefore)
        }
        drag = .none
        lastSnap = nil
        previewLayer.path = nil
        previewLayer.lineDashPattern = nil
        scaleLabel.isHidden = true
        redraw()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        clearGuideCursor()
        previewLayer.lineDashPattern = nil
        if case let .courseItem(_, _, before) = drag {
            if moved, let model { model.commitCourseEdit(from: before) }
        } else if case let .control(_, _, _, before) = drag {
            if moved, let model { model.commitCourseEdit(from: before) }
        } else if moved, let model { model.commitFeatureEdit(from: featuresBefore) }
        drag = .none
        previewLayer.path = nil
        redraw()
    }

    // MARK: Rectangle / ellipse

    /// Corners clockwise from top-left, in screen space (so they follow map rotation).
    private func screenCorners(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
        return [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }

    private func showShapePreview(from a: CGPoint, to b: CGPoint) {
        guard let model else { return }
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        previewLayer.path = (model.tool == .ellipse ? UIBezierPath(ovalIn: r) : UIBezierPath(rect: r)).cgPath
        if model.isDrawingCut {
            // Cutting shape: the selection-box look (dashed blue), not the symbol colour.
            previewLayer.strokeColor = UIColor.systemBlue.cgColor
            previewLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
            previewLayer.lineWidth = 1.5
            previewLayer.lineDashPattern = [5, 3]
            return
        }
        previewLayer.lineDashPattern = nil
        let color = UIColor(hexString: model.pen.colorHex)
        previewLayer.strokeColor = color.cgColor
        previewLayer.fillColor = color.withAlphaComponent(0.2).cgColor
        previewLayer.lineWidth = 2
    }

    private func finishShape(from a: CGPoint, to b: CGPoint) {
        guard let model, abs(a.x - b.x) >= 8, abs(a.y - b.y) >= 8 else { return }
        let corners = screenCorners(a, b).compactMap(toUTM)
        guard corners.count == 4 else { return }
        if model.isDrawingCut {
            let shape = model.tool == .ellipse
                ? Feature.ellipse(corners: corners, colorHex: "#000000", widthMM: 0)
                : Feature.rectangle(corners: corners, colorHex: "#000000", widthMM: 0)
            model.cutSelectedArea(withShape: shape.nodes)
            return
        }
        var f = model.tool == .ellipse
            ? Feature.ellipse(corners: corners, colorHex: model.pen.colorHex, widthMM: model.pen.widthMM)
            : Feature.rectangle(corners: corners, colorHex: model.pen.colorHex, widthMM: model.pen.widthMM)
        model.stampActiveSymbol(&f)
        model.addFeature(f, merge: true)
    }

    // MARK: Drawing

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            // The halo follows the selection outline and the rotation handle.
            let halo = CGMutablePath()
            if let p = rotateHandleLayer.path { halo.addPath(p) }
            if let p = scaleHandleLayer.path { halo.addPath(p) }
            selectionHaloLayer.path = halo.isEmpty ? nil : halo
            CATransaction.commit()
        }
        controlCenterLayer.path = nil
        guard let model, zone != nil else {
            for l in [selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer, measureLayer] { l.path = nil }
            return
        }
        drawMeasurement()
        rotateHandleLayer.path = nil
        scaleBoxLayer.path = nil
        scaleHandleLayer.path = nil

        // Pen tool draft: path + points + handles of the last point.
        if model.tool == .bezier, !model.draftNodes.isEmpty {
            let draft = Feature(kind: .line, colorHex: model.pen.colorHex, widthMM: model.pen.widthMM, nodes: model.draftNodes)
            previewLayer.path = path(for: draft).cgPath
            previewLayer.strokeColor = model.isDrawingCut ? UIColor.systemBlue.cgColor : UIColor(hexString: model.pen.colorHex).cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = 2
            previewLayer.lineDashPattern = model.isDrawingCut ? [5, 3] : nil
            drawDecorations(nodes: model.draftNodes, active: model.draftNodes.count - 1, showAllHandles: false, firstIsTarget: model.draftNodes.count >= 3)
            // Cutting an area with the pen: the area stays outlined.
            selectionLayer.path = model.isDrawingCut ? model.selectedFeature.map { path(for: $0).cgPath } : nil
            return
        }
        // Rectangle/ellipse preview only lives while dragging.
        switch drag {
        case .shape, .freehand, .courseShape, .marquee, .nodeMarquee, .legGap, .cutBox: break
        default: previewLayer.path = nil
        }

        // Control tool: blue ring on the selected control.
        if model.tool == .control {
            #if DEBUG
            accessibilityValue = "legGaps \(model.selectedCourse?.legGaps?.count ?? 0)"   // UI tests: Cut leg
            #endif
            for l in [handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
            if let id = model.selectedControlID, let c = model.courseSet.control(id) {
                let center = toScreen(c.position)
                let r = max(CGFloat(model.controlHitRadiusM * 1.45 / metersPerPoint), 16)
                selectionLayer.path = UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)).cgPath
                let dot: CGFloat = 2.5
                controlCenterLayer.path = UIBezierPath(ovalIn: CGRect(x: center.x - dot, y: center.y - dot, width: 2 * dot, height: 2 * dot)).cgPath
            } else if let item = model.selectedCourseItem, let b = item.bounds(sheet: model.project.sheet) {
                // Dashed box around the selected course object (slightly larger).
                let pad = metersPerPoint * 6
                let corners = [Point2D(x: b.minX - pad, y: b.minY - pad), Point2D(x: b.maxX + pad, y: b.minY - pad),
                               Point2D(x: b.maxX + pad, y: b.maxY + pad), Point2D(x: b.minX - pad, y: b.maxY + pad)].map(toScreen)
                let path = UIBezierPath()
                path.move(to: corners[0])
                for q in corners.dropFirst() { path.addLine(to: q) }
                path.close()
                selectionLayer.path = path.cgPath
            } else {
                selectionLayer.path = nil
            }
            return
        }

        guard model.tool.selects || model.isDrawingCut, let f = model.selectedFeature else {
            for l in [selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
            return
        }
        if model.isMultiSelection || (model.tool == .select && !model.cutMode) {
            // Move Tool / multi-select: highlight selected objects, without points/handles.
            let all = UIBezierPath()
            for g in model.selection { all.append(path(for: g)) }
            selectionLayer.path = all.cgPath
            for l in [handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
            if let h = rotateHandle(), let top = rotateHandleStem() {
                // Rotation handle: stem from the object's top edge + a small circle.
                let p = UIBezierPath()
                p.move(to: top)
                p.addLine(to: CGPoint(x: h.x, y: h.y + 6))
                p.append(UIBezierPath(ovalIn: CGRect(x: h.x - 6, y: h.y - 6, width: 12, height: 12)))
                rotateHandleLayer.path = p.cgPath
            }
            #if DEBUG
            accessibilityValue = scaleBox().map { "box \(Int(($0.width - 12).rounded()))x\(Int(($0.height - 12).rounded()))" }
            #endif
            if let handles = scaleHandles(), let box = scaleBox() {
                scaleBoxLayer.path = UIBezierPath(rect: box).cgPath
                let dots = UIBezierPath()
                for h in handles.compactMap({ $0 }) { dots.append(UIBezierPath(ovalIn: CGRect(x: h.x - 5.5, y: h.y - 5.5, width: 11, height: 11))) }
                scaleHandleLayer.path = dots.cgPath
            }
            return
        }
        selectionLayer.path = path(for: f).cgPath
        // Start point of the area cut line.
        if model.cutMode, let start = model.cutStart, let q = f.point(at: start) {
            let c = toScreen(q)
            guideCursorLayer.path = UIBezierPath(ovalIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)).cgPath
        } else if !drawsWithGuides {
            guideCursorLayer.path = nil
        }
        if f.isLocked || !model.tool.selects {
            for l in [handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
        } else {
            drawDecorations(nodes: f.allNodes, active: model.selectedNodeIndex, selected: model.selectedNodeIndices, showAllHandles: true, firstIsTarget: false)
        }
    }

    /// Shift or ⌘ held (hardware keyboard): add/remove points in the Node Tool.
    private func multiSelectHeld(_ event: UIEvent?) -> Bool {
        if shiftHeld(event) || event?.modifierFlags.contains(.command) == true { return true }
        if ModifierKeys.pressed.contains(.command) || ModifierKeys.hover.contains(.command) { return true }
        guard let kb = GCKeyboard.coalesced?.keyboardInput else { return false }
        return kb.button(forKeyCode: .leftGUI)?.isPressed == true || kb.button(forKeyCode: .rightGUI)?.isPressed == true
    }

    /// Shift held (hardware keyboard): from the touch/pointer event, or directly from the keyboard state because
    /// touch events don't always carry modifiers.
    private func shiftHeld(_ event: UIEvent?) -> Bool {
        if event?.modifierFlags.contains(.shift) == true { return true }
        // Mac clicks don't always carry modifiers: the keys tracked from key presses and pointer hovering.
        if ModifierKeys.pressed.contains(.shift) || ModifierKeys.hover.contains(.shift) { return true }
        #if DEBUG
        // UI test: XCUITest can't hold Shift during a touch gesture on iOS.
        if ProcessInfo.processInfo.arguments.contains("-cp-force-shift") { return true }
        #endif
        guard let kb = GCKeyboard.coalesced?.keyboardInput else { return false }
        return kb.button(forKeyCode: .leftShift)?.isPressed == true || kb.button(forKeyCode: .rightShift)?.isPressed == true
    }

    // MARK: Scale (Move Tool)

    /// Screen box of the selected object (Move Tool, one unlocked object): the drawn outline without curve handles;
    /// for point symbols the symbol circle.
    private func scaleBox() -> CGRect? {
        guard let model, model.tool == .select, !model.isMultiSelection, !model.cutMode,
              let f = model.selectedFeature, !f.isLocked else { return nil }
        if f.kind == .point {
            guard let c = f.nodes.first.map({ toScreen($0.point) }) else { return nil }
            let r = max(CGFloat(f.pointRadiusM(sheet: model.project.sheet) / metersPerPoint), 10)
            return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        }
        let b = path(for: f).cgPath.boundingBoxOfPath.insetBy(dx: -6, dy: -6)
        guard !b.isNull, b.width.isFinite, b.height.isFinite else { return nil }
        return b
    }

    /// Handle positions 0…7 clockwise from top-left (corners even, edge midpoints odd). Edge handles are left out
    /// (nil) when that side is too short to grab them apart from the corners; point symbols only get corners.
    private func scaleHandles() -> [CGPoint?]? {
        guard let b = scaleBox(), let f = model?.selectedFeature else { return nil }
        // Edge handles only on a box big enough in both directions: on a thin line they would sit on the line itself
        // and take the drag that should move the object.
        let edges = f.kind != .point && b.width >= 44 && b.height >= 44
        let wide = edges, tall = edges
        return [CGPoint(x: b.minX, y: b.minY), wide ? CGPoint(x: b.midX, y: b.minY) : nil,
                CGPoint(x: b.maxX, y: b.minY), tall ? CGPoint(x: b.maxX, y: b.midY) : nil,
                CGPoint(x: b.maxX, y: b.maxY), wide ? CGPoint(x: b.midX, y: b.maxY) : nil,
                CGPoint(x: b.minX, y: b.maxY), tall ? CGPoint(x: b.minX, y: b.midY) : nil]
    }

    private static func oppositePoint(_ i: Int, in b: CGRect) -> CGPoint? {
        [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.midX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.midY),
         CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.midX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.minX, y: b.midY)][(i + 4) % 8]
    }

    /// Scale handle under the finger/pointer; the rotation handle wins when it is closer.
    private func scaleHandle(at pt: CGPoint) -> Int? {
        guard let handles = scaleHandles() else { return nil }
        let hits = handles.enumerated().compactMap { i, h in h.map { (i, dist($0, pt)) } }.filter { $0.1 <= Self.scaleHit }
        guard let best = hits.min(by: { $0.1 < $1.1 }) else { return nil }
        if let r = rotateHandle(), dist(r, pt) < best.1 { return nil }
        return best.0
    }

    /// Scale from the original shape. Corner: proportional, rounded to whole percent (precise); edge: that direction
    /// only. Shift switches (corner = free width/height, edge = proportional). Point symbols change their size.
    private func applyScale(handle i: Int, anchor a: CGPoint, box: CGRect, original: Feature, to pt: CGPoint, free: Bool) {
        guard let model else { return }
        let start = Self.oppositePoint((i + 4) % 8, in: box) ?? a
        let ox = start.x - a.x, oy = start.y - a.y
        let nx = pt.x - a.x, ny = pt.y - a.y
        let corner = i % 2 == 0, horizontal = i == 3 || i == 7
        let minK = 0.02
        func ratio(_ n: CGFloat, _ o: CGFloat) -> Double { abs(o) < 1 ? 1 : max(Double(n / o), minK) }
        var sx: Double, sy: Double
        let uniform = corner != free || original.kind == .point
        if uniform {
            // Proportional: projection on the handle's direction, whole percent.
            let k: Double
            if corner {
                let dot = Double(nx * ox + ny * oy), len = Double(ox * ox + oy * oy)
                k = len > 1 ? max(dot / len, minK) : 1
            } else {
                k = horizontal ? ratio(nx, ox) : ratio(ny, oy)
            }
            let rounded = max((k * 100).rounded() / 100, minK)
            sx = rounded; sy = rounded
        } else if corner {
            sx = ratio(nx, ox); sy = ratio(ny, oy)
        } else {
            sx = horizontal ? ratio(nx, ox) : 1
            sy = horizontal ? 1 : ratio(ny, oy)
        }

        if original.kind == .point {
            let range = WorkspaceModel.sizeFactorRange
            let k = min(max(original.effectiveSizeFactor * sx, range.lowerBound), range.upperBound)
            var f = original
            f.sizeFactor = abs(k - 1) < 0.001 ? nil : (k * 100).rounded() / 100
            f.widthMM = (f.pointElements ?? []).diameterMM * f.effectiveSizeFactor
            model.updateFeatureLive(f)
            showScaleLabel("\(Int((f.effectiveSizeFactor * 100).rounded()))%", near: pt)
            return
        }
        // Scale on screen (follows the box as drawn, also when the map is rotated), then back to map coordinates.
        let scaledFeature = original.mapped { p in
            let s = toScreen(p)
            let t = CGPoint(x: a.x + (s.x - a.x) * sx, y: a.y + (s.y - a.y) * sy)
            return toUTM(t) ?? p
        }
        model.updateFeatureLive(scaledFeature)
        let mpp = metersPerPoint
        let w = Double(box.width - 12) * sx * mpp, h = Double(box.height - 12) * sy * mpp
        let pct = abs(sx - sy) < 0.0001 ? "\(Int((sx * 100).rounded()))%" : "\(Int((sx * 100).rounded()))% × \(Int((sy * 100).rounded()))%"
        showScaleLabel("\(Fmt.meters(max(w, 0), decimals: 1)) × \(Fmt.meters(max(h, 0), decimals: 1)) · \(pct)", near: pt)
    }

    private func showScaleLabel(_ text: String, near pt: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = (text as NSString).size(withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)])
        let w = ceil(size.width) + 14, h: CGFloat = 20
        var x = pt.x + 16, y = pt.y + 16
        if x + w > bounds.maxX - 8 { x = pt.x - 16 - w }
        if y + h > bounds.maxY - 8 { y = pt.y - 16 - h }
        scaleLabel.string = text
        scaleLabel.frame = CGRect(x: x, y: y, width: w, height: h)
        scaleLabel.isHidden = false
        CATransaction.commit()
    }

    // MARK: Rotation (Move Tool)

    /// Rotation handle: above the selected object's box (Move Tool, one object, not locked).
    private func rotateHandle() -> CGPoint? {
        guard let top = rotateHandleStem() else { return nil }
        return CGPoint(x: top.x, y: top.y - 28)
    }

    private func rotateHandleStem() -> CGPoint? {
        guard let model, model.tool == .select, !model.isMultiSelection, !model.cutMode,
              let f = model.selectedFeature, !f.isLocked else { return nil }
        let b = path(for: f).bounds
        guard !b.isNull, b.width.isFinite else { return nil }
        return CGPoint(x: b.midX, y: b.minY)
    }

    /// Screen angle clockwise from up (degrees); same direction as object rotation on the map.
    private func screenAngle(from c: CGPoint, to p: CGPoint) -> Double {
        atan2(Double(p.x - c.x), Double(c.y - p.y)) * 180 / .pi
    }

    /// Straight edges of other (visible) objects around the rotated object: references for precise rotation.
    private func rotationReferences(for f: Feature, minLength: Double) -> [RotationSnap.Edge] {
        guard let model, let b = f.bounds else { return [] }
        let pad = max(b.maxX - b.minX, b.maxY - b.minY, 30 * metersPerPoint)
        let area = b.insetBy(-pad)
        return model.features
            .filter { $0.id != f.id && $0.isVisible && ($0.bounds.map { $0.intersects(area) } ?? false) }
            .flatMap { $0.straightEdges(minLength: minLength) }
            .filter { Rect2D(points: [$0.a, $0.b]).map { $0.intersects(area) } ?? false }
    }

    /// Highlights the reference edge when the object snaps straight to it.
    private func showRotationReference(_ e: RotationSnap.Edge?) {
        guard let e else { guideLayer.path = nil; return }
        let p = UIBezierPath()
        p.move(to: toScreen(e.a))
        p.addLine(to: toScreen(e.b))
        guideLayer.path = p.cgPath
    }

    /// Dashed measure line + circles at both ends.
    private func drawMeasurement() {
        guard let model, model.tool == .measure, let m = model.measurement else {
            measureLayer.path = nil
            return
        }
        let a = toScreen(m.start), b = toScreen(m.end)
        let path = UIBezierPath()
        path.move(to: a)
        path.addLine(to: b)
        for c in [a, b] { path.append(UIBezierPath(ovalIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))) }
        measureLayer.path = path.cgPath
    }

    private func path(for f: Feature) -> UIBezierPath {
        let p = UIBezierPath()
        guard let first = f.nodes.first else { return p }
        if f.kind == .point, let model {
            // Marker circle slightly larger than its symbol (at least 14 pt so it's visible).
            let c = toScreen(first.point)
            let r = max(CGFloat(f.pointRadiusM(sheet: model.project.sheet) / metersPerPoint) + 4, 14)
            return UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        // Areas: the outer ring and each hole (selection outline, guide highlight).
        for ring in f.ringFeatures {
            guard let r0 = ring.nodes.first else { continue }
            p.move(to: toScreen(r0.point))
            for s in ring.segments {
                if s.isCurve {
                    p.addCurve(to: toScreen(s.p3), controlPoint1: toScreen(s.c1), controlPoint2: toScreen(s.c2))
                } else {
                    p.addLine(to: toScreen(s.p3))
                }
            }
            if f.isClosed { p.close() }
        }
        return p
    }

    private func drawDecorations(nodes: [BezierNode], active: Int?, selected: Set<Int> = [], showAllHandles: Bool, firstIsTarget: Bool) {
        let lines = UIBezierPath(), handles = UIBezierPath(), squares = UIBezierPath(), activeSquare = UIBezierPath()
        for (i, n) in nodes.enumerated() {
            let c = toScreen(n.point)
            if showAllHandles || i == active {
                for h in [n.inHandle, n.outHandle].compactMap({ $0 }) {
                    let hp = toScreen(h)
                    lines.move(to: c); lines.addLine(to: hp)
                    handles.append(UIBezierPath(ovalIn: CGRect(x: hp.x - 4, y: hp.y - 4, width: 8, height: 8)))
                }
            }
            let size: CGFloat = (i == 0 && firstIsTarget) ? 12 : 8
            let r = CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
            if i == active || selected.contains(i) { activeSquare.append(UIBezierPath(rect: r)) } else { squares.append(UIBezierPath(rect: r)) }
        }
        handleLineLayer.path = lines.cgPath
        handleLayer.path = handles.cgPath
        nodeLayer.path = squares.cgPath
        activeNodeLayer.path = activeSquare.cgPath
    }
}
