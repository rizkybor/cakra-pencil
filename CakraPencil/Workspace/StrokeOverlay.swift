import CakraCore
import MapKit
import UIKit

/// Semua stroke yang sudah di-commit, dirender MapKit per tile (MapKit yang meng-cache tile per zoom).
/// Tebal digambar dalam meter tanah, jadi tampil berubah sesuai zoom tetapi ukuran cetak tetap (FR-3.2).
final class StrokeOverlay: NSObject, MKOverlay {
    struct Item {
        let points: [MKMapPoint]
        let bounds: MKMapRect
        let color: CGColor
        let widthMapPoints: Double
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _items: [Item] = []

    var items: [Item] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    /// Cache per stroke (id → item) untuk zona + skala yang sama: hanya stroke baru yang dikonversi.
    private var cache: [UUID: Item] = [:]
    private var cacheKey: (UTMZone, SheetSpec)?

    /// Kembalikan kotak gabungan stroke yang ditambah/dihapus (nil = tidak ada perubahan, atau gambar ulang semua
    /// bila zona/skala berganti).
    @discardableResult
    func update(strokes: [Stroke], zone: UTMZone, sheet: SheetSpec) -> MKMapRect? {
        var dirty: MKMapRect?
        func mark(_ r: MKMapRect) { dirty = dirty.map { $0.union(r) } ?? r }
        if cacheKey?.0 != zone || cacheKey?.1 != sheet {
            cache = [:]
            cacheKey = (zone, sheet)
            dirty = .world
        }
        var nextCache: [UUID: Item] = [:]
        let built = strokes.compactMap { s -> Item? in
            if let hit = cache[s.id] {
                nextCache[s.id] = hit
                return hit
            }
            guard let item = Self.item(for: s, zone: zone, sheet: sheet) else { return nil }
            nextCache[s.id] = item
            mark(item.bounds)
            return item
        }
        for (id, old) in cache where nextCache[id] == nil { mark(old.bounds) }
        cache = nextCache
        lock.lock()
        _items = built
        lock.unlock()
        return dirty
    }

    private static func item(for s: Stroke, zone: UTMZone, sheet: SheetSpec) -> Item? {
        do {
            let pts = s.points.map { p -> MKMapPoint in
                let ll = zone.unproject(p)
                return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
            guard let first = pts.first else { return nil }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in pts {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            let widthM = sheet.groundMeters(forPaperMM: s.widthMM)
            let widthMP = widthM / MKMetersPerMapPointAtLatitude(first.coordinate.latitude)
            let r = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -widthMP, dy: -widthMP)
            return Item(points: pts, bounds: r, color: UIColor(hexString: s.colorHex).cgColor, widthMapPoints: widthMP)
        }
    }
}

/// Lapisan warna kertas di atas citra dan di bawah sketsa. Alpha-nya = 1 − opacity basemap (FR-2.5),
/// jadi citra memudar ke kertas tetapi garis sketsa tetap pekat.
final class VeilOverlay: NSObject, MKOverlay {
    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }
}

final class VeilRenderer: MKOverlayRenderer {
    var color = UIColor(hex: 0xFAF7F2).cgColor

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setFillColor(color)
        context.fill(rect(for: mapRect))
    }
}

final class StrokeRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? StrokeOverlay else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // Batas bawah 0,5 pt layar supaya garis 0,05 mm tetap terlihat saat zoom jauh.
        let minWidth = 0.5 / zoomScale
        for item in overlay.items where item.bounds.intersects(mapRect) {
            let width = max(item.widthMapPoints, minWidth)
            if item.points.count == 1 {
                let c = point(for: item.points[0])
                context.setFillColor(item.color)
                context.fillEllipse(in: CGRect(x: c.x - width / 2, y: c.y - width / 2, width: width, height: width))
                continue
            }
            context.setStrokeColor(item.color)
            context.setLineWidth(width)
            context.beginPath()
            context.move(to: point(for: item.points[0]))
            for p in item.points.dropFirst() { context.addLine(to: point(for: p)) }
            context.strokePath()
        }
    }
}

/// Objek vektor (garis/area bezier) dirender per tile seperti stroke. Kurva digambar sebagai kurva kubik di
/// ruang map point: pada skala lembar A4, selisihnya dengan kurva di UTM jauh di bawah satu piksel layar.
final class FeatureOverlay: NSObject, MKOverlay {
    struct Item {
        let path: CGPath
        let bounds: MKMapRect
        let color: CGColor
        let fill: CGColor?
        let widthMapPoints: Double
        /// Garis ganda: warna tepi (digambar selebar `widthMapPoints`) dan lebar isi di atasnya.
        var casing: (color: CGColor, innerWidthMapPoints: Double)? = nil
        /// Pola putus-putus (map point) dan ujung rata/bulat, seperti simbol OCAD.
        var dash: [CGFloat]? = nil
        var roundCaps = true
        /// Area bersimbol: isi saja, tanpa garis tepi.
        var fillOnly = false
        /// Simbol titik: pusat (map point), elemen terskala, dan map point per mm kertas.
        var point: (center: MKMapPoint, elements: [PointElement], mapPointsPerMM: Double)?
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _items: [Item] = []

    var items: [Item] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    /// Cache per objek: item dibangun ulang hanya bila objeknya berubah (dibandingkan nilai).
    private var cache: [UUID: (feature: Feature, item: Item?)] = [:]
    private var cacheKey: (UTMZone, SheetSpec, Double)?
    private var order: [UUID] = []

    /// Bangun daftar item; kembalikan kotak gabungan objek yang berubah (untuk menggambar ulang sebagian).
    @discardableResult
    func update(features: [Feature], zone: UTMZone, sheet: SheetSpec, areaOpacity: Double = 1) -> MKMapRect? {
        if cacheKey?.0 != zone || cacheKey?.1 != sheet || cacheKey?.2 != areaOpacity {
            cache = [:]
            cacheKey = (zone, sheet, areaOpacity)
        }
        var dirty: MKMapRect?
        func mark(_ r: MKMapRect?) { if let r { dirty = dirty.map { $0.union(r) } ?? r } }
        var next: [UUID: (feature: Feature, item: Item?)] = [:]
        for f in features {
            if let hit = cache[f.id], hit.feature == f {
                next[f.id] = hit
            } else {
                let item = Self.item(for: f, zone: zone, sheet: sheet, areaOpacity: areaOpacity)
                mark(cache[f.id]?.item?.bounds)
                mark(item?.bounds)
                next[f.id] = (f, item)
            }
        }
        for (id, old) in cache where next[id] == nil { mark(old.item?.bounds) }
        cache = next
        order = features.map(\.id)
        publish()
        return dirty
    }

    /// Perbarui satu objek (drag); kembalikan kotak yang perlu digambar ulang.
    func updateOne(_ f: Feature) -> MKMapRect? {
        guard let (zone, sheet, areaOpacity) = cacheKey else { return nil }
        let old = cache[f.id]?.item?.bounds
        let item = Self.item(for: f, zone: zone, sheet: sheet, areaOpacity: areaOpacity)
        cache[f.id] = (f, item)
        publish()
        switch (old, item?.bounds) {
        case let (a?, b?): return a.union(b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    private func publish() {
        let items = order.compactMap { cache[$0]?.item }
        lock.lock()
        _items = items
        lock.unlock()
    }

    private static func item(for f: Feature, zone: UTMZone, sheet: SheetSpec, areaOpacity: Double) -> Item? {
        func mp(_ p: Point2D) -> MKMapPoint {
            let ll = zone.unproject(p)
            return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
        }
        do {
            guard f.isVisible, let first = f.nodes.first, let b = f.bounds else { return nil }
            if f.kind == .point {
                let c = mp(first.point)
                let perMM = sheet.groundMeters(forPaperMM: 1) / MKMetersPerMapPointAtLatitude(c.coordinate.latitude)
                let r = f.pointRadiusM(sheet: sheet) / MKMetersPerMapPointAtLatitude(c.coordinate.latitude)
                return Item(path: CGMutablePath(), bounds: MKMapRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r),
                            color: UIColor.black.cgColor, fill: nil, widthMapPoints: 0,
                            point: (c, f.scaledPointElements, perMM))
            }
            // Path disimpan dalam map point absolut; renderer menggesernya ke koordinat overlay.
            let path = CGMutablePath()
            let start = mp(first.point)
            path.move(to: CGPoint(x: start.x, y: start.y))
            for s in f.segments {
                let p3 = mp(s.p3)
                if s.isCurve {
                    let c1 = mp(s.c1), c2 = mp(s.c2)
                    path.addCurve(to: CGPoint(x: p3.x, y: p3.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
                } else {
                    path.addLine(to: CGPoint(x: p3.x, y: p3.y))
                }
            }
            if f.isClosed { path.closeSubpath() }
            let lo = mp(Point2D(x: b.minX, y: b.maxY)), hi = mp(Point2D(x: b.maxX, y: b.minY))
            let widthMP = sheet.groundMeters(forPaperMM: f.widthMM) / MKMetersPerMapPointAtLatitude(start.coordinate.latitude)
            let rect = MKMapRect(x: min(lo.x, hi.x), y: min(lo.y, hi.y), width: abs(hi.x - lo.x), height: abs(hi.y - lo.y))
                .insetBy(dx: -widthMP * 2, dy: -widthMP * 2)
            let color = UIColor(hexString: f.colorHex)
            let mpPerMM = sheet.groundMeters(forPaperMM: 1) / MKMetersPerMapPointAtLatitude(start.coordinate.latitude)
            var item = Item(path: path, bounds: rect, color: color.cgColor,
                            fill: f.kind == .area ? color.withAlphaComponent(f.isSymbolArea ? areaOpacity : 0.35).cgColor : nil,
                            widthMapPoints: widthMP)
            item.fillOnly = f.isSymbolArea
            item.roundCaps = f.roundCaps != false
            item.dash = f.effectiveDashMM?.map { CGFloat($0 * mpPerMM) }
            if f.kind == .line, let casing = f.casingColorHex, let inner = f.innerWidthMM {
                item.casing = (UIColor(hexString: casing).cgColor, inner * mpPerMM)
            }
            return item
        }
    }
}

final class FeatureRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? FeatureOverlay else { return }
        let origin = point(for: MKMapPoint(x: 0, y: 0))
        context.translateBy(x: origin.x, y: origin.y)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let minWidth = 0.5 / zoomScale
        for item in overlay.items where item.bounds.intersects(mapRect) {
            if let p = item.point {
                // Map point: x ke timur, y ke selatan → offset mm (y atas) dibalik.
                PointSymbolRenderer.draw(p.elements, in: context, mmToUnits: p.mapPointsPerMM) {
                    CGPoint(x: p.center.x + $0.x * p.mapPointsPerMM, y: p.center.y - $0.y * p.mapPointsPerMM)
                }
                continue
            }
            if let fill = item.fill {
                context.addPath(item.path)
                context.setFillColor(fill)
                context.fillPath()
                if item.fillOnly { continue }
            }
            context.setLineCap(item.roundCaps ? .round : .butt)
            context.setLineJoin(item.roundCaps ? .round : .miter)
            context.setLineDash(phase: 0, lengths: item.dash ?? [])
            if let casing = item.casing {
                context.addPath(item.path)
                context.setStrokeColor(casing.color)
                context.setLineWidth(max(item.widthMapPoints, minWidth))
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
                context.addPath(item.path)
                context.setStrokeColor(item.color)
                context.setLineWidth(max(casing.innerWidthMapPoints, minWidth * 0.5))
                context.strokePath()
                continue
            }
            context.addPath(item.path)
            context.setStrokeColor(item.color)
            context.setLineWidth(max(item.widthMapPoints, minWidth))
            context.strokePath()
        }
        context.setLineDash(phase: 0, lengths: [])
    }
}

/// Grid garis utara di dalam frame (di atas citra, di bawah sketsa dan objek).
final class GridOverlay: NSObject, MKOverlay {
    struct State {
        var segments: [(MKMapPoint, MKMapPoint)] = []
        var color: CGColor = UIColor.black.cgColor
        var widthMapPoints: Double = 0
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _state = State()

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    func update(grid: NorthGrid, frame: MapFrame?, zone: UTMZone?, sheet: SheetSpec) {
        var next = State()
        if grid.isEnabled, let frame, let zone {
            func mp(_ p: Point2D) -> MKMapPoint {
                let ll = zone.unproject(p)
                return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
            }
            next.segments = grid.lines(in: frame).map { (mp($0.0), mp($0.1)) }
            next.color = UIColor(hexString: grid.colorHex).withAlphaComponent(grid.opacity).cgColor
            let lat = zone.unproject(frame.center).lat
            next.widthMapPoints = sheet.groundMeters(forPaperMM: grid.lineWidthMM) / MKMetersPerMapPointAtLatitude(lat)
        }
        lock.lock()
        _state = next
        lock.unlock()
    }
}

final class GridRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? GridOverlay else { return }
        let s = overlay.state
        guard !s.segments.isEmpty else { return }
        context.setStrokeColor(s.color)
        context.setLineWidth(max(s.widthMapPoints, 0.75 / zoomScale))
        for (a, b) in s.segments {
            context.move(to: point(for: a))
            context.addLine(to: point(for: b))
        }
        context.strokePath()
    }
}

/// Garis kontur (di atas citra, di bawah grid dan objek). Titik dikonversi ke map point di background.
final class ContourOverlay: NSObject, MKOverlay {
    struct Line {
        let points: [MKMapPoint]
        let bounds: MKMapRect
        let kind: ContourLine.Kind
    }

    struct State {
        var lines: [Line] = []
        var color: CGColor = UIColor.brown.cgColor
        var contourWidth: Double = 0
        var indexWidth: Double = 0
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _state = State()
    private var generation = 0

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    /// Ganti gaya gambar saja (warna, opacity, tebal) tanpa mengonversi ulang titik.
    func setStyle(settings: ContourSettings, sheet: SheetSpec, latitude: Double) {
        let mpp = MKMetersPerMapPointAtLatitude(latitude)
        lock.lock()
        _state.color = UIColor(hexString: settings.colorHex).withAlphaComponent(settings.opacity).cgColor
        _state.contourWidth = sheet.groundMeters(forPaperMM: settings.contourWidthMM) / mpp
        _state.indexWidth = sheet.groundMeters(forPaperMM: settings.indexWidthMM) / mpp
        lock.unlock()
    }

    func update(lines: [ContourLine], settings: ContourSettings, zone: UTMZone?, sheet: SheetSpec, completion: @escaping @MainActor () -> Void) {
        lock.lock()
        generation += 1
        let token = generation
        lock.unlock()
        guard settings.isEnabled, let zone, !lines.isEmpty else {
            lock.lock(); _state = State(); lock.unlock()
            Task { @MainActor in completion() }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let converted = lines.map { l -> Line in
                let pts = l.points.map { p -> MKMapPoint in
                    let ll = zone.unproject(p)
                    return MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
                }
                let xs = pts.map(\.x), ys = pts.map(\.y)
                let rect = MKMapRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
                return Line(points: pts, bounds: rect, kind: l.kind)
            }
            let lat = lines.first.flatMap { $0.points.first }.map { zone.unproject($0).lat } ?? 0
            let mpp = MKMetersPerMapPointAtLatitude(lat)
            let next = State(lines: converted,
                             color: UIColor(hexString: settings.colorHex).withAlphaComponent(settings.opacity).cgColor,
                             contourWidth: sheet.groundMeters(forPaperMM: settings.contourWidthMM) / mpp,
                             indexWidth: sheet.groundMeters(forPaperMM: settings.indexWidthMM) / mpp)
            guard let self else { return }
            self.lock.lock()
            let current = token == self.generation
            if current { self._state = next }
            self.lock.unlock()
            if current { Task { @MainActor in completion() } }
        }
    }
}

final class ContourRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? ContourOverlay else { return }
        let s = overlay.state
        guard !s.lines.isEmpty else { return }
        context.setStrokeColor(s.color)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let minWidth = 0.6 / zoomScale
        for kind in [ContourLine.Kind.form, .contour, .index] {
            let width = max(kind == .index ? s.indexWidth : s.contourWidth, minWidth)
            context.setLineWidth(width)
            // Form line: putus-putus (ISOM 103: garis 2,5 mm, jeda 0,25 mm di kertas → skala ikut tebal garis).
            context.setLineDash(phase: 0, lengths: kind == .form ? [width * 18, width * 2.5] : [])
            for line in s.lines where line.kind == kind && line.bounds.intersects(mapRect.insetBy(dx: -width, dy: -width)) {
                guard let first = line.points.first else { continue }
                context.move(to: point(for: first))
                for p in line.points.dropFirst() { context.addLine(to: point(for: p)) }
            }
            context.strokePath()
        }
    }
}

/// Overprint lintasan (ungu, paling atas): lingkaran kontrol, segitiga start, finish, leg, dan nomor.
/// Bentuk dikonversi ke map point sekali saat data berubah (bukan per tile), jadi rotasi/pan/tarik kontrol lancar.
final class CourseOverlay: NSObject, MKOverlay {
    struct State {
        /// Overprint dalam ruang map point (x, y = MKMapPoint; jari-jari/tebal/tinggi huruf dalam map point).
        var overprint = CourseOverprint(marks: [], lineWidthM: 0, colorHex: "#A626FF")
        var bounds: MKMapRect?
        /// Gambar objek lintasan menurut nama file.
        var images: [String: CGImage] = [:]
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    private var _state = State()

    var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    /// Ganti isi; kembalikan area yang perlu digambar ulang (gabungan lama + baru), nil bila kosong keduanya.
    @discardableResult
    func update(_ overprint: CourseOverprint?, zone: UTMZone?, frame: MapFrame?, images: [String: CGImage] = [:]) -> MKMapRect? {
        var next = State()
        next.images = images
        if let overprint, let zone, !overprint.isEmpty {
            let mpp = MKMetersPerMapPointAtLatitude(zone.unproject(frame?.center ?? Point2D(x: 500_000, y: 0)).lat)
            func mp(_ p: Point2D) -> Point2D {
                let ll = zone.unproject(p)
                let m = MKMapPoint(CLLocationCoordinate2D(latitude: ll.lat, longitude: ll.lon))
                return Point2D(x: m.x, y: m.y)
            }
            let marks = overprint.marks.map { mark -> CourseMark in
                switch mark {
                case let .circle(c, r): return .circle(center: mp(c), radiusM: r / mpp)
                case let .polyline(pts, closed): return .polyline(pts.map(mp), closed: closed)
                case let .text(t, c, h): return .text(t, center: mp(c), heightM: h / mpp)
                case let .fill(pts, op): return .fill(pts.map(mp), opacity: op)
                case let .image(n, c, w, h): return .image(n, center: mp(c), widthM: w / mpp, heightM: h / mpp)
                }
            }
            next.overprint = CourseOverprint(marks: marks, lineWidthM: overprint.lineWidthM / mpp, colorHex: overprint.colorHex)
            next.bounds = next.overprint.bounds.map { b in
                let pad = next.overprint.lineWidthM * 2
                return MKMapRect(x: b.minX - pad, y: b.minY - pad, width: b.width + 2 * pad, height: b.height + 2 * pad)
            }
        }
        lock.lock()
        let old = _state.bounds
        _state = next
        lock.unlock()
        switch (old, next.bounds) {
        case let (a?, b?): return a.union(b)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }
}

final class CourseRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? CourseOverlay else { return }
        let s = overlay.state
        guard let b = s.bounds, b.intersects(mapRect), !s.overprint.isEmpty else { return }
        CourseOverprintRenderer.draw(s.overprint, in: context, unitsPerMeter: 1, flipped: true,
                                     minLineWidth: 1.2 / zoomScale, alpha: 0.9, images: s.images) { p in
            self.point(for: MKMapPoint(x: p.x, y: p.y))
        }
    }
}
