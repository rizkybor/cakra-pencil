import CakraCore
import MapKit
import GameController
import UIKit

/// Lapisan sentuh + gambar untuk alat vektor, di atas peta. Semua geometri disimpan di UTM; view ini hanya
/// mengonversi ke/dari layar, jadi tetap benar saat peta di-zoom atau diputar.
///
/// - Pen tool: ketuk = titik sudut, tarik = titik halus (handle simetris), ketuk titik pertama = tutup jadi area.
/// - Rectangle / Ellipse: tarik dari pojok ke pojok.
/// - Pilih: ketuk objek untuk memilih; geser titik, handle, atau seluruh objek; ketuk dua kali titik = sudut ↔ halus;
///   tarik di tempat kosong = kotak pilih (beberapa objek digeser/diduplikat bersama).
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
    /// Panduan kursor: objek yang diikuti disorot + cincin di titik tempel.
    private let guideLayer = CAShapeLayer()
    private let guideCursorLayer = CAShapeLayer()
    private let measureLayer = CAShapeLayer()
    private let rotateHandleLayer = CAShapeLayer()
    /// Sudut rotasi presisi terakhir (untuk getaran saat menempel ke sudut baru).
    private var lastRotationSnap: Double?

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
        /// Alat Kontrol: sentuh kontrol yang ada (ketuk = pakai/pilih, tarik = pindah).
        case control(id: UUID, start: Point2D, original: Point2D, before: CourseSet)
        /// Halaman Course: geser objek (teks/bentuk/gambar).
        case courseItem(original: CourseItem, start: Point2D, before: CourseSet)
        /// Halaman Course: tarik persegi/ellipse/garis baru.
        case courseShape(kind: CourseItem.Kind, start: CGPoint)
        /// Geser semua objek terpilih. Tanpa geser (ketuk): `tap` dijalankan di akhir.
        case group(start: Point2D, originals: [Feature], tap: GroupTap)
        /// Kotak pilih (tarik di tempat kosong). `additive`: tambah ke pilihan (Shift),
        /// selain itu ganti pilihan.
        case marquee(start: CGPoint, additive: Bool)
        /// Measure Tool: tarik dari titik awal (UTM, sudah ditempel ke objek).
        case measure(start: Point2D)
        /// Node Tool: tarik segmen objek terpilih = lengkungkan segmen itu.
        case segment(index: Int, t: Double, start: Point2D, original: Feature)
        /// Move Tool: tarik pegangan rotasi. Shift = presisi (menempel ke sisi lurus objek lain / kelipatan 15°).
        case rotate(pivot: CGPoint, startAngle: Double, base: Double, edges: [RotationSnap.Edge], references: [RotationSnap.Edge])
    }

    /// Aksi ketukan pada objek yang sudah ikut pilihan banyak (bila tidak jadi digeser).
    private enum GroupTap {
        case none
        /// Shift: lepas objek ini dari pilihan.
        case toggle(Feature)
        /// Ketuk biasa: pilih objek ini saja.
        case single(Feature)
    }

    private var drag = Drag.none
    /// Titik layar goresan gambar bebas.
    private var freehandPoints: [CGPoint] = []
    private let haptic = UISelectionFeedbackGenerator()
    static let snapRadius: CGFloat = 14
    private var lastSnap: Point2D?
    /// Objek panduan di titik draf pen tool terakhir.
    private var lastGuide: Guide?

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
        // Getar sekali saat menempel ke titik baru (bukan tiap frame selama drag).
        if let p = best?.0, p != lastSnap { haptic.selectionChanged() }
        lastSnap = best?.0
        return best?.0
    }

    /// Titik tempel pada objek panduan (OCAD Follow).
    private struct Guide {
        var featureID: UUID
        var position: PathPosition
        var point: Point2D
    }

    /// Ujung garis ukur: pusat simbol titik, lalu sudut/ujung/tepi objek lain (seperti alat gambar).
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

    /// Titik objek dulu (sudut/ujung), lalu garis tepinya bila panduan objek aktif.
    private func guideSnap(_ pt: CGPoint, excluding id: UUID? = nil, haptics: Bool = true) -> Guide? {
        guard let model else { return nil }
        var best: (Guide, CGFloat)?
        for f in model.features where f.isVisible && f.id != id && f.kind != .point {
            for (i, n) in f.nodes.enumerated() {
                let d = dist(pt, toScreen(n.point))
                if d <= Self.snapRadius, d < (best?.1 ?? .infinity) {
                    best = (Guide(featureID: f.id, position: f.pathPosition(ofNode: i), point: n.point), d)
                }
            }
        }
        if best == nil, model.followGuides, let p = toUTM(pt) {
            let radius = Double(Self.snapRadius) * metersPerPoint
            var bestM: (Guide, Double)?
            for f in model.features where f.isVisible && f.id != id && f.kind != .point {
                guard let b = f.bounds, p.x >= b.minX - radius, p.x <= b.maxX + radius,
                      p.y >= b.minY - radius, p.y <= b.maxY + radius,
                      let r = f.nearestPathPosition(to: p), r.distance <= radius,
                      r.distance < (bestM?.1 ?? .infinity) else { continue }
                bestM = (Guide(featureID: f.id, position: r.position, point: r.point), r.distance)
            }
            if let g = bestM?.0 { best = (g, 0) }
        }
        if haptics, let p = best?.0.point, p != lastSnap { haptic.selectionChanged() }
        if haptics { lastSnap = best?.0.point }
        return best?.0
    }

    /// Bentuk objek panduan dari titik draf terakhir ke `g` (OCAD Follow), apa pun jenis objek dan simbolnya:
    /// garis ↔ garis, garis ↔ area, area ↔ area. Dicoba objek ketukan kedua, objek ketukan pertama, lalu objek
    /// lain yang dilewati kedua titik (mis. garis yang menumpuk tepat di tepi area). nil = bukan di objek yang sama.
    private func followPath(to g: Guide) -> [BezierNode]? {
        guard let model, model.followGuides, let last = lastGuide,
              let lastNode = model.draftNodes.last, lastNode.point.distance(to: last.point) < 1e-6 else { return nil }
        // Toleransi "titik ada di objek": 5 cm di tanah (tetap, tidak ikut zoom). Titik ketukan sudah menempel
        // tepat ke objek, jadi tepi yang bertumpuk (garis di atas tepi area) jaraknya ≈ 0.
        let tol = 0.05
        let ids = [g.featureID, last.featureID]
        let ordered = ids.compactMap { id in model.features.first { $0.id == id } }
            + model.features.filter { $0.isVisible && $0.kind != .point && !ids.contains($0.id) }
        for f in ordered {
            let from: PathPosition, to: PathPosition
            if f.id == last.featureID { from = last.position } else {
                guard let r = f.nearestPathPosition(to: last.point), r.distance <= tol else { continue }
                from = r.position
            }
            if f.id == g.featureID { to = g.position } else {
                guard let r = f.nearestPathPosition(to: g.point), r.distance <= tol else { continue }
                to = r.position
            }
            var nodes = f.followNodes(from: from, to: to)
            guard nodes.count >= 2 else { continue }
            // Ujung tepat di titik ketukan (bukan proyeksinya di objek lain yang menumpuk).
            nodes[0].point = last.point
            nodes[nodes.count - 1].point = g.point
            return nodes
        }
        return nil
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
        rotateHandleLayer.lineWidth = 1.5
        for l in [guideLayer, previewLayer, selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer, guideCursorLayer, measureLayer, rotateHandleLayer] {
            layer.addSublayer(l)
        }
        // Apple Pencil hover / trackpad: panduan kursor tampil sebelum menyentuh layar.
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
    }

    /// Ukuran berubah (keyboard, rotasi layar, panel): posisi layar titik ikut berubah tanpa event region peta.
    private var lastLayoutSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize else { return }
        lastLayoutSize = bounds.size
        redraw()
    }

    @objc private func hovered(_ g: UIHoverGestureRecognizer) {
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

    /// Sorot objek panduan + cincin di titik tempel; pen tool juga menampilkan bentuk yang akan diikuti.
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
        case .point, .bezier, .freehand, .rectangle, .ellipse, .control, .measure:
            return self
        case .select, .node:
            // Alat Potong: ketukan di dekat objek terpilih diambil; selain itu peta tetap bisa digeser.
            if model.cutMode { return cutPosition(at: point) != nil ? self : nil }
            // Klik lalu tarik di tempat kosong = kotak pilih (seperti OCAD/OOM); geser peta dengan dua jari
            // atau alat Navigasi.
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
            for (i, n) in f.nodes.enumerated() {
                if let h = n.inHandle, dist(pt, toScreen(h)) <= Self.nodeHit { return .handle(i, isIn: true) }
                if let h = n.outHandle, dist(pt, toScreen(h)) <= Self.nodeHit { return .handle(i, isIn: false) }
            }
            for (i, n) in f.nodes.enumerated() where dist(pt, toScreen(n.point)) <= Self.nodeHit { return .node(i) }
            if let p = toUTM(pt), f.distance(to: p, tolerance: metersPerPoint) <= Double(Self.pathHit) * metersPerPoint {
                return .selectedPath
            }
        }
        return topFeature(at: pt).map { .other($0) }
    }

    /// Objek paling atas di titik layar ini (tampil, tidak terkunci).
    private func topFeature(at pt: CGPoint) -> Feature? {
        guard let model, let p = toUTM(pt) else { return nil }
        let tol = Double(Self.pathHit) * metersPerPoint
        // Paling atas dulu.
        // Paling atas dulu, menurut Color Hierarchy (yang terlihat di atas yang terpilih).
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

    /// Objek yang terkena kotak pilih (layar): titik objek di dalam kotak, atau kotak di dalam area.
    private func features(in rect: CGRect) -> [Feature] {
        guard let model else { return [] }
        return model.features.filter { f in
            guard f.isVisible, !f.isLocked else { return false }
            if f.flattened(tolerance: metersPerPoint * 2).contains(where: { rect.contains(toScreen($0)) }) { return true }
            if f.kind == .area, let c = toUTM(CGPoint(x: rect.midX, y: rect.midY)) { return contains(f, c) }
            return false
        }
    }

    /// Posisi potong di garis tepi objek terpilih (titik objek lebih diutamakan, agar potongan tepat di titik).
    private func cutPosition(at pt: CGPoint) -> PathPosition? {
        guard let model, let f = model.selectedFeature else { return nil }
        for (i, n) in f.nodes.enumerated() where dist(pt, toScreen(n.point)) <= Self.nodeHit { return f.pathPosition(ofNode: i) }
        guard let p = toUTM(pt), let r = f.nearestPathPosition(to: p), r.distance <= Double(Self.nodeHit) * metersPerPoint else { return nil }
        return r.position
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
            // Simbol titik bisa ditempatkan tepat di garis/sudut objek lain.
            model.placePoint(at: guideSnap(pt)?.point ?? p)
            drag = .none
        case .bezier:
            if touch.tapCount >= 2, model.draftNodes.count >= 2 {
                // Ketuk dua kali = selesai (OCAD/OOM: double-click). Ketukan pertama sudah menambah titik di sini,
                // jadi titik itu menjadi titik akhir; ketukan kedua tidak menambah titik lagi.
                model.finishDraftForActiveSymbol()
                drag = .none
            } else if model.draftNodes.count >= 3, let first = model.draftNodes.first, dist(pt, toScreen(first.point)) <= Self.nodeHit {
                // Kembali ke titik awal: simbol area → area; simbol garis → garis tertutup (tetap garis).
                if model.activeSymbol?.kind == .area {
                    model.finishDraft(as: .area)
                } else {
                    model.appendDraftNode(BezierNode(point: first.point))
                    model.finishDraft(as: .line)
                }
                drag = .none
            } else if model.draftNodes.isEmpty, !(model.autoMerge && model.followGuides), let (f, fromStart) = continuationTarget(pt) {
                // Dengan gabung otomatis + ikuti objek, mulai di ujung garis = garis baru yang bisa mengikuti
                // garis itu; bila tidak menumpuk, ujungnya tetap tersambung lewat gabung otomatis.
                model.beginContinuation(of: f, fromStart: fromStart)
                lastGuide = nil
                haptic.selectionChanged()
                drag = .none
            } else {
                if model.draftNodes.isEmpty { lastGuide = nil }
                let g = guideSnap(pt, excluding: model.continuingFeatureID)
                if let g, let follow = followPath(to: g) {
                    // OCAD Follow: dua titik berurutan di objek yang sama → bentuk objek di antaranya ikut disalin.
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
            // Pojok menempel ke titik/garis objek lain.
            drag = .shape(start: guideSnap(pt).map { toScreen($0.point) } ?? pt)
        case .control:
            // Kena kontrol yang ada (minimal 22 pt di layar) → tunggu: ketuk atau tarik. Selain itu: kontrol baru.
            if let c = model.control(near: p, radiusM: metersPerPoint * Double(Self.nodeHit)) {
                drag = .control(id: c.id, start: p, original: c.position, before: model.courseSet)
                model.selectedControlID = c.id
                model.selectedCourseItemID = nil
            } else if let item = model.courseItem(near: p, radiusM: metersPerPoint * Double(Self.pathHit)) {
                // Objek lintasan: ketuk = pilih, tarik = pindah.
                drag = .courseItem(original: item, start: p, before: model.courseSet)
                model.selectedCourseItemID = item.id
                model.selectedControlID = nil
            } else if let kind = model.courseItemTool {
                switch kind {
                case .text:
                    model.placeCourseText(at: p)
                    haptic.selectionChanged()
                    drag = .none
                case .rectangle, .ellipse, .line:
                    drag = .courseShape(kind: kind, start: pt)
                case .image:
                    drag = .none
                }
            } else {
                model.placeControl(at: p)
                model.selectedCourseItemID = nil
                haptic.selectionChanged()
                drag = .none
            }
        case .measure:
            let a = measureSnap(pt) ?? p
            model.measurement = MapMeasurement(start: a, end: a)
            drag = .measure(start: a)
        case .select where !model.cutMode && rotateHandle().map({ dist($0, pt) <= Self.nodeHit + 6 }) == true:
            // Pegangan rotasi di atas objek terpilih.
            if let f = model.selectedFeature, let c = model.selectedFeature?.rotationPivot.map(toScreen) {
                let mpp = metersPerPoint
                let edges = f.straightEdges(minLength: 8 * mpp)
                drag = .rotate(pivot: c, startAngle: screenAngle(from: c, to: pt), base: f.rotationDegrees,
                               edges: edges, references: rotationReferences(for: f, minLength: 8 * mpp))
                lastRotationSnap = nil
            }
        case .select where model.cutMode, .node where model.cutMode:
            if let pos = cutPosition(at: pt) {
                model.cutSelected(at: pos)
                haptic.selectionChanged()
            }
            drag = .none
        case .select where shiftHeld(event):
            // Shift (pilih banyak): ketuk = tambah/lepas, tarik objek terpilih = geser semua, tarik kosong = kotak pilih.
            if let f = topFeature(at: pt) {
                let wasSelected = model.isSelected(f.id)
                if !wasSelected { model.toggleSelection(f) }
                drag = .group(start: p, originals: model.selection, tap: wasSelected ? .toggle(f) : .none)
            } else {
                drag = .marquee(start: pt, additive: true)
            }
        case .select:
            // Move Tool: bekerja pada objek utuh (tanpa titik/handle).
            if let f = topFeature(at: pt) {
                if model.isMultiSelection && model.isSelected(f.id) {
                    // Tarik salah satu objek terpilih = geser semuanya; ketuk = pilih objek itu saja.
                    drag = .group(start: p, originals: model.selection, tap: .single(f))
                } else if touch.tapCount == 2, model.selectedFeatureID == f.id {
                    // Ketuk dua kali objek terpilih = masuk Node Tool untuk mengedit titiknya (seperti Illustrator).
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
            // Node Tool: titik, handle, dan garis objek terpilih; ketuk objek lain = pilih objek itu.
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
                if touch.tapCount == 2 {
                    // Reshape (OCAD): ketuk dua kali di garis objek terpilih = tambah titik di situ.
                    model.insertNode(near: p)
                    haptic.selectionChanged()
                    drag = .none
                } else if let f = model.selectedFeature, let r = f.nearestPathPosition(to: p),
                          r.distance <= Double(Self.pathHit) * metersPerPoint {
                    // Tarik garis di antara dua titik = lengkungkan segmen itu (seperti Affinity/Illustrator).
                    model.selectedNodeIndex = nil
                    drag = .segment(index: r.position.segment, t: r.position.t, start: p, original: f)
                } else if let f = model.selectedFeature {
                    drag = .whole(start: p, original: f)   // isi area: geser objek
                }
            case let .other(f)?:
                model.select(f)
                drag = .none
            case nil:
                model.deselect()   // ketuk tempat kosong = lepas pilihan
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
            previewLayer.strokeColor = UIColor(hexString: model.pen.colorHex).cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = 2
        case let .node(i, start, original):
            var f = original
            // Titik menempel ke titik objek lain (ujung garis/sudut area) agar bisa digabung otomatis.
            let target = snapTarget(pt, excluding: original.id) ?? original.nodes[i].point + (p - start)
            f.nodes[i] = original.nodes[i].moved(by: target - original.nodes[i].point)
            f.refreshSmartNodes()   // titik smart (ini dan tetangganya) ikut menyesuaikan lengkungnya
            model.updateFeatureLive(f)
            moved = true
        case let .handle(i, isIn, original):
            var f = original
            f.moveHandle(node: i, isIn: isIn, to: p)
            model.updateFeatureLive(f)
            moved = true
        case let .rotate(pivot, startAngle, base, edges, references):
            let raw = base + screenAngle(from: pivot, to: pt) - startAngle
            if shiftHeld(event) {
                // Rotasi presisi: sisi lurus menempel sejajar/tegak lurus ke sisi objek lain, atau kelipatan 15°.
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
        case let .segment(i, t, start, original):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 2 || moved else { break }
            model.updateFeatureLive(original.bendingSegment(i, at: t, by: d))
            moved = true
        case let .whole(start, original):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 3 || moved else { break }
            var f = original
            f.nodes = original.nodes.map { $0.moved(by: d) }
            model.updateFeatureLive(f)
            moved = true
        case let .group(start, originals, _):
            let d = p - start
            guard d.distance(to: Point2D(x: 0, y: 0)) > metersPerPoint * 3 || moved else { break }
            model.moveSelectionLive(originals, by: d)
            moved = true
        case let .measure(start):
            let b = measureSnap(pt) ?? p
            model.measurement = MapMeasurement(start: start, end: b)
        case let .marquee(start, _):
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
                if kind != .line { path.close() }
            }
            previewLayer.path = path.cgPath
            previewLayer.strokeColor = UIColor(hexString: "#A626FF").cgColor
            previewLayer.fillColor = UIColor.clear.cgColor
            previewLayer.lineWidth = 2
        case .none:
            break
        }
        redraw()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model, let touch = touches.first else { return }
        let pt = touch.location(in: self)
        if case let .shape(start) = drag {
            finishShape(from: start, to: guideSnap(pt, haptics: false).map { toScreen($0.point) } ?? pt)
        }
        if case .freehand = drag {
            // Ujung akhir juga di-snap; bagian yang menyusuri objek lain mengikuti bentuk objek itu.
            var pts = freehandPoints.compactMap(toUTM)
            if let end = guideSnap(pt, haptics: false)?.point, !pts.isEmpty { pts[pts.count - 1] = end }
            model.addFreehand(pts, guideRadiusM: Double(Self.snapRadius) * metersPerPoint)
            freehandPoints = []
        }
        clearGuideCursor()
        if case let .marquee(start, additive) = drag {
            let r = CGRect(x: min(start.x, pt.x), y: min(start.y, pt.y), width: abs(start.x - pt.x), height: abs(start.y - pt.y))
            if r.width < 8 && r.height < 8 {
                model.deselect()   // ketuk tempat kosong = lepas semua pilihan
            } else {
                let hit = features(in: r)
                if !additive { model.deselect() }
                if !additive, hit.count == 1 { model.select(hit[0]) } else { model.addToSelection(hit) }
                haptic.selectionChanged()
            }
            previewLayer.lineDashPattern = nil
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
        if case let .courseItem(_, _, before) = drag {
            if moved { model.commitCourseEdit(from: before) }
        } else if case let .control(id, _, _, before) = drag {
            if moved { model.commitCourseEdit(from: before) } else { model.tapControl(id) }
        } else if moved, case let .node(_, _, original) = drag {
            model.commitNodeEdit(from: featuresBefore, featureID: original.id)
        } else if moved {
            model.commitFeatureEdit(from: featuresBefore)
        }
        drag = .none
        lastSnap = nil
        previewLayer.path = nil
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
        model.addFeature(f, merge: true)
    }

    // MARK: Gambar

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let model, zone != nil else {
            for l in [selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer, measureLayer] { l.path = nil }
            return
        }
        drawMeasurement()
        rotateHandleLayer.path = nil

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
        case .shape, .freehand, .courseShape, .marquee: break
        default: previewLayer.path = nil
        }

        // Alat Kontrol: cincin biru di kontrol terpilih.
        if model.tool == .control {
            for l in [handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
            if let id = model.selectedControlID, let c = model.courseSet.control(id) {
                let center = toScreen(c.position)
                let r = max(CGFloat(model.controlHitRadiusM * 1.45 / metersPerPoint), 16)
                selectionLayer.path = UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)).cgPath
            } else if let item = model.selectedCourseItem, let b = item.bounds(sheet: model.project.sheet) {
                // Kotak putus-putus di sekeliling objek lintasan terpilih (sedikit lebih besar).
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

        guard model.tool.selects, let f = model.selectedFeature else {
            for l in [selectionLayer, handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
            return
        }
        if model.isMultiSelection || (model.tool == .select && !model.cutMode) {
            // Move Tool / pilih banyak: sorot objek terpilih, tanpa titik/handle.
            let all = UIBezierPath()
            for g in model.selection { all.append(path(for: g)) }
            selectionLayer.path = all.cgPath
            for l in [handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
            if let h = rotateHandle(), let top = rotateHandleStem() {
                // Pegangan rotasi: tangkai dari tepi atas objek + lingkaran kecil.
                let p = UIBezierPath()
                p.move(to: top)
                p.addLine(to: CGPoint(x: h.x, y: h.y + 6))
                p.append(UIBezierPath(ovalIn: CGRect(x: h.x - 6, y: h.y - 6, width: 12, height: 12)))
                rotateHandleLayer.path = p.cgPath
            }
            return
        }
        selectionLayer.path = path(for: f).cgPath
        // Titik awal garis potong area.
        if model.cutMode, let start = model.cutStart, let q = f.point(at: start) {
            let c = toScreen(q)
            guideCursorLayer.path = UIBezierPath(ovalIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)).cgPath
        } else if !drawsWithGuides {
            guideCursorLayer.path = nil
        }
        if f.isLocked {
            for l in [handleLineLayer, handleLayer, nodeLayer, activeNodeLayer] { l.path = nil }
        } else {
            drawDecorations(nodes: f.nodes, active: model.selectedNodeIndex, showAllHandles: true, firstIsTarget: false)
        }
    }

    /// Shift ditahan (keyboard fisik): dari event sentuh/pointer, atau langsung dari status keyboard karena
    /// event sentuh tidak selalu membawa modifier.
    private func shiftHeld(_ event: UIEvent?) -> Bool {
        if event?.modifierFlags.contains(.shift) == true { return true }
        #if DEBUG
        // UI test: XCUITest tidak bisa menahan Shift selama gestur sentuh di iOS.
        if ProcessInfo.processInfo.arguments.contains("-cp-force-shift") { return true }
        #endif
        guard let kb = GCKeyboard.coalesced?.keyboardInput else { return false }
        return kb.button(forKeyCode: .leftShift)?.isPressed == true || kb.button(forKeyCode: .rightShift)?.isPressed == true
    }

    // MARK: Rotasi (Move Tool)

    /// Pegangan rotasi: di atas kotak objek terpilih (Move Tool, satu objek, tidak terkunci).
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

    /// Sudut layar searah jarum jam dari atas (derajat); sama arahnya dengan rotasi objek di peta.
    private func screenAngle(from c: CGPoint, to p: CGPoint) -> Double {
        atan2(Double(p.x - c.x), Double(c.y - p.y)) * 180 / .pi
    }

    /// Sisi lurus objek lain (tampil) di sekitar objek yang diputar: acuan rotasi presisi.
    private func rotationReferences(for f: Feature, minLength: Double) -> [RotationSnap.Edge] {
        guard let model, let b = f.bounds else { return [] }
        let pad = max(b.maxX - b.minX, b.maxY - b.minY, 30 * metersPerPoint)
        let area = b.insetBy(-pad)
        return model.features
            .filter { $0.id != f.id && $0.isVisible && ($0.bounds.map { $0.intersects(area) } ?? false) }
            .flatMap { $0.straightEdges(minLength: minLength) }
            .filter { Rect2D(points: [$0.a, $0.b]).map { $0.intersects(area) } ?? false }
    }

    /// Sorot sisi acuan saat objek menempel lurus dengannya.
    private func showRotationReference(_ e: RotationSnap.Edge?) {
        guard let e else { guideLayer.path = nil; return }
        let p = UIBezierPath()
        p.move(to: toScreen(e.a))
        p.addLine(to: toScreen(e.b))
        guideLayer.path = p.cgPath
    }

    /// Garis ukur putus-putus + lingkaran di kedua ujung.
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
