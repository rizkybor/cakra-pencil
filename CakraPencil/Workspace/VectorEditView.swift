import CakraCore
import MapKit
import UIKit

/// Lapisan sentuh + gambar untuk alat vektor, di atas peta. Semua geometri disimpan di UTM; view ini hanya
/// mengonversi ke/dari layar, jadi tetap benar saat peta di-zoom atau diputar.
///
/// - Pen tool: ketuk = titik sudut, tarik = titik halus (handle simetris), ketuk titik pertama = tutup jadi area.
/// - Rectangle / Ellipse: tarik dari pojok ke pojok.
/// - Pilih: ketuk objek untuk memilih; geser titik, handle, atau seluruh objek; ketuk dua kali titik = sudut ↔ halus.
///
/// Pencil dan satu jari sama-sama bekerja (simulator tidak punya Pencil). Dua jari jatuh ke peta.
final class VectorEditView: UIView {
    weak var mapView: MKMapView?
    weak var model: WorkspaceModel?

    private let selectionLayer = CAShapeLayer()
    private let handleLineLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let nodeLayer = CAShapeLayer()
    private let activeNodeLayer = CAShapeLayer()
    private let previewLayer = CAShapeLayer()

    static let nodeHit: CGFloat = 22
    static let pathHit: CGFloat = 14

    private enum Drag {
        case none
        case draftHandle(start: CGPoint)
        case shape(start: CGPoint)
        case freehand
        case node(index: Int, start: Point2D, original: Feature)
        case handle(index: Int, isIn: Bool, original: Feature)
        case whole(start: Point2D, original: Feature)
    }

    private var drag = Drag.none
    /// Titik layar goresan gambar bebas.
    private var freehandPoints: [CGPoint] = []
    private let haptic = UISelectionFeedbackGenerator()
    static let snapRadius: CGFloat = 14

    // MARK: Snap (seperti OCAD/OOM)

    /// Titik objek lain dalam radius snap: kembalikan posisi UTM tepatnya agar sambungan presisi.
    private func snapTarget(_ pt: CGPoint, excluding id: UUID? = nil) -> Point2D? {
        guard let model else { return nil }
        var best: (Point2D, CGFloat)?
        for f in model.features where f.isVisible && f.id != id && f.kind != .point {
            for n in f.nodes {
                let d = dist(pt, toScreen(n.point))
                if d <= Self.snapRadius, d < (best?.1 ?? .infinity) { best = (n.point, d) }
            }
        }
        if best != nil { haptic.selectionChanged() }
        return best?.0
    }

    /// Ujung garis bersimbol sama (atau warna + tebal sama bila tanpa simbol) di dekat titik → (objek, mulai dari titik awal?).
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
        let sky = UIColor(hex: 0x315E85)
        selectionLayer.strokeColor = sky.cgColor
        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.lineWidth = 1.5
        selectionLayer.lineDashPattern = [6, 3]
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
        for l in [previewLayer, selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { layer.addSublayer(l) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Konversi

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
        case .point, .bezier, .freehand, .rectangle, .ellipse:
            return self
        case .select:
            // Hanya ambil sentuhan yang mengenai objek; sentuhan di tempat kosong menggeser peta.
            return target(at: point) != nil ? self : nil
        default:
            return nil
        }
    }

    private enum Target {
        case node(Int), handle(Int, isIn: Bool), selectedPath, other(Feature)
    }

    private func target(at pt: CGPoint) -> Target? {
        guard let model else { return nil }
        if let f = model.selectedFeature, !f.isLocked {
            for (i, n) in f.nodes.enumerated() {
                if let h = n.inHandle, dist(pt, toScreen(h)) <= Self.nodeHit { return .handle(i, isIn: true) }
                if let h = n.outHandle, dist(pt, toScreen(h)) <= Self.nodeHit { return .handle(i, isIn: false) }
            }
            for (i, n) in f.nodes.enumerated() where dist(pt, toScreen(n.point)) <= Self.nodeHit { return .node(i) }
            if let p = toUTM(pt), f.distance(to: p, tolerance: metersPerPoint) <= Double(Self.pathHit) * metersPerPoint {
                return .selectedPath
            }
        }
        guard let p = toUTM(pt) else { return nil }
        let tol = Double(Self.pathHit) * metersPerPoint
        // Paling atas dulu.
        for f in model.features.reversed() where f.isVisible && !f.isLocked {
            if f.kind == .point, let c = f.nodes.first?.point {
                if c.distance(to: p) <= max(tol, f.pointRadiusM(sheet: model.project.sheet)) { return .other(f) }
                continue
            }
            guard let b = f.bounds, p.x >= b.minX - tol, p.x <= b.maxX + tol, p.y >= b.minY - tol, p.y <= b.maxY + tol else { continue }
            if f.distance(to: p, tolerance: metersPerPoint) <= tol || (f.kind == .area && contains(f, p)) { return .other(f) }
        }
        return nil
    }

    /// Titik di dalam area (even-odd pada polyline hasil perataan).
    private func contains(_ f: Feature, _ p: Point2D) -> Bool {
        let pts = f.flattened(tolerance: metersPerPoint)
        var inside = false
        var j = pts.count - 1
        for i in 0..<pts.count {
            let a = pts[i], b = pts[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Sentuhan

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model, let touch = touches.first, let p = toUTM(touch.location(in: self)) else { return }
        let pt = touch.location(in: self)
        featuresBefore = model.features
        moved = false
        switch model.tool {
        case .point:
            model.placePoint(at: p)
            drag = .none
        case .bezier:
            if touch.tapCount >= 2, model.draftNodes.count >= 2 {
                // Ketuk dua kali = selesai (OCAD/OOM: double-click). Ketukan pertama sudah menambah titik di sini,
                // jadi titik itu menjadi titik akhir; ketukan kedua tidak menambah titik lagi.
                model.finishDraftForActiveSymbol()
                drag = .none
            } else if model.draftNodes.count >= 3, let first = model.draftNodes.first, dist(pt, toScreen(first.point)) <= Self.nodeHit {
                model.finishDraft(as: .area)
                drag = .none
            } else if model.draftNodes.isEmpty, let (f, fromStart) = continuationTarget(pt) {
                model.beginContinuation(of: f, fromStart: fromStart)
                haptic.selectionChanged()
                drag = .none
            } else {
                let snapped = snapTarget(pt, excluding: model.continuingFeatureID)
                model.appendDraftNode(BezierNode(point: snapped ?? p))
                drag = snapped == nil ? .draftHandle(start: pt) : .none
            }
        case .freehand:
            freehandPoints = [snapTarget(pt).map(toScreen) ?? pt]
            drag = .freehand
        case .rectangle, .ellipse:
            drag = .shape(start: pt)
        case .select:
            switch target(at: pt) {
            case let .node(i)?:
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
                if let f = model.selectedFeature { drag = .whole(start: p, original: f) }
            case let .other(f)?:
                model.select(f)
                drag = .whole(start: p, original: f)
            case nil:
                drag = .none
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
            previewLayer.strokeColor = UIColor(hexString: model.pen.colorHex).cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = 2
        case let .node(i, start, original):
            var f = original
            f.nodes[i] = original.nodes[i].moved(by: p - start)
            model.updateFeatureLive(f)
            moved = true
        case let .handle(i, isIn, original):
            var f = original
            f.moveHandle(node: i, isIn: isIn, to: p)
            model.updateFeatureLive(f)
            moved = true
        case let .whole(start, original):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 3 || moved else { break }
            var f = original
            f.nodes = original.nodes.map { $0.moved(by: d) }
            model.updateFeatureLive(f)
            moved = true
        case .none:
            break
        }
        redraw()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model, let touch = touches.first else { return }
        let pt = touch.location(in: self)
        if case let .shape(start) = drag {
            finishShape(from: start, to: pt)
        }
        if case .freehand = drag {
            // Ujung akhir juga di-snap agar garis tersambung tepat ke objek lain.
            var pts = freehandPoints.compactMap(toUTM)
            if let end = snapTarget(pt), !pts.isEmpty { pts[pts.count - 1] = end }
            model.addFreehand(pts)
            freehandPoints = []
        }
        if moved { model.commitFeatureEdit(from: featuresBefore) }
        drag = .none
        previewLayer.path = nil
        redraw()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if moved, let model { model.commitFeatureEdit(from: featuresBefore) }
        drag = .none
        previewLayer.path = nil
        redraw()
    }

    // MARK: Rectangle / ellipse

    /// Pojok searah jarum jam mulai kiri atas, dalam ruang layar (jadi ikut rotasi peta).
    private func screenCorners(_ a: CGPoint, _ b: CGPoint) -> [CGPoint] {
        let minX = min(a.x, b.x), maxX = max(a.x, b.x), minY = min(a.y, b.y), maxY = max(a.y, b.y)
        return [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }

    private func showShapePreview(from a: CGPoint, to b: CGPoint) {
        guard let model else { return }
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        previewLayer.path = (model.tool == .ellipse ? UIBezierPath(ovalIn: r) : UIBezierPath(rect: r)).cgPath
        let color = UIColor(hexString: model.pen.colorHex)
        previewLayer.strokeColor = color.cgColor
        previewLayer.fillColor = color.withAlphaComponent(0.2).cgColor
        previewLayer.lineWidth = 2
    }

    private func finishShape(from a: CGPoint, to b: CGPoint) {
        guard let model, abs(a.x - b.x) >= 8, abs(a.y - b.y) >= 8 else { return }
        let corners = screenCorners(a, b).compactMap(toUTM)
        guard corners.count == 4 else { return }
        var f = model.tool == .ellipse
            ? Feature.ellipse(corners: corners, colorHex: model.pen.colorHex, widthMM: model.pen.widthMM)
            : Feature.rectangle(corners: corners, colorHex: model.pen.colorHex, widthMM: model.pen.widthMM)
        model.stampActiveSymbol(&f)
        model.addFeature(f)
    }

    // MARK: Gambar

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let model, zone != nil else {
            for l in [selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
            return
        }

        // Draf pen tool: path + titik + handle titik terakhir.
        if model.tool == .bezier, !model.draftNodes.isEmpty {
            let draft = Feature(kind: .line, colorHex: model.pen.colorHex, widthMM: model.pen.widthMM, nodes: model.draftNodes)
            previewLayer.path = path(for: draft).cgPath
            previewLayer.strokeColor = UIColor(hexString: model.pen.colorHex).cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = 2
            drawDecorations(nodes: model.draftNodes, active: model.draftNodes.count - 1, showAllHandles: false, firstIsTarget: model.draftNodes.count >= 3)
            selectionLayer.path = nil
            return
        }
        // Pratinjau rectangle/ellipse hanya hidup selama ditarik.
        switch drag {
        case .shape, .freehand: break
        default: previewLayer.path = nil
        }

        guard model.tool == .select, let f = model.selectedFeature else {
            for l in [selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
            return
        }
        selectionLayer.path = path(for: f).cgPath
        if f.isLocked {
            for l in [handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
        } else {
            drawDecorations(nodes: f.nodes, active: model.selectedNodeIndex, showAllHandles: true, firstIsTarget: false)
        }
    }

    private func path(for f: Feature) -> UIBezierPath {
        let p = UIBezierPath()
        guard let first = f.nodes.first else { return p }
        if f.kind == .point, let model {
            // Lingkaran penanda sedikit lebih besar dari simbolnya (minimal 14 pt agar terlihat).
            let c = toScreen(first.point)
            let r = max(CGFloat(f.pointRadiusM(sheet: model.project.sheet) / metersPerPoint) + 4, 14)
            return UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        p.move(to: toScreen(first.point))
        for s in f.segments {
            if s.isCurve {
                p.addCurve(to: toScreen(s.p3), controlPoint1: toScreen(s.c1), controlPoint2: toScreen(s.c2))
            } else {
                p.addLine(to: toScreen(s.p3))
            }
        }
        if f.isClosed { p.close() }
        return p
    }

    private func drawDecorations(nodes: [BezierNode], active: Int?, showAllHandles: Bool, firstIsTarget: Bool) {
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
            if i == active { activeSquare.append(UIBezierPath(rect: r)) } else { squares.append(UIBezierPath(rect: r)) }
        }
        handleLineLayer.path = lines.cgPath
        handleLayer.path = handles.cgPath
        nodeLayer.path = squares.cgPath
        activeNodeLayer.path = activeSquare.cgPath
    }
}
