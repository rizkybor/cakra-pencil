import CakraCore
import MapKit
import UIKit

/// All committed strokes, rendered by MapKit per tile (MapKit caches tiles per zoom level).
/// Width is drawn in ground meters, so it looks different with zoom but the printed size stays fixed (FR-3.2).
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

    /// Per-stroke cache (id → item) for the same zone + scale: only new strokes are converted.
    private var cache: [UUID: Item] = [:]
    private var cacheKey: (UTMZone, SheetSpec)?

    /// Returns the union rect of added/removed strokes (nil = no change, or redraw everything
    /// when the zone/scale changed).
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

/// Paper-colored layer above the imagery and below the sketch. Its alpha = 1 − basemap opacity (FR-2.5),
/// so the imagery fades to paper while sketch lines stay solid.
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
        // Lower bound of 0.5 screen pt so 0.05 mm lines stay visible when zoomed far out.
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

/// Vector objects (bezier lines/areas) are rendered per tile like strokes. Curves are drawn as cubic curves in
/// map point space: at A4 sheet scale, the difference from the UTM curve is far below one screen pixel.
final class FeatureOverlay: NSObject, MKOverlay {
    struct Item {
        let path: CGPath
        let bounds: MKMapRect
        let color: CGColor
        let fill: CGColor?
        let widthMapPoints: Double
        /// Double line: border color (drawn `widthMapPoints` wide) and the fill width on top of it.
        var casing: (color: CGColor, innerWidthMapPoints: Double)? = nil
        /// Dash pattern (map points) and flat/round caps, like OCAD symbols.
        var dash: [CGFloat]? = nil
        /// Dash pattern of the inner line (fill of a layered line, e.g. railway).
        var innerDash: [CGFloat]? = nil
        var roundCaps = true
        /// Symbol area: fill only, no border line.
        var fillOnly = false
        /// Point symbol: center (map point), scaled elements, and map points per paper mm.
        var point: (center: MKMapPoint, elements: [PointElement], mapPointsPerMM: Double)?
        /// ISOM area patterns (drawn per tile, clipped to the area); pattern-only areas have no fill.
        var patterns: [AreaPattern]? = nil
        var patternAlpha: CGFloat = 1
        var mapPointsPerMM: Double = 1
        /// ISOM line decorations (tags, wall dots…), in absolute map points.
        var decoration: [OrnamentMark] = []
        /// The decoration replaces the line (transparent double lines, 512.1 triangles, 107 taper): no main stroke.
        var hidesLine = false
        /// Seed of random area patterns (208 / 209), stable per object.
        var patternSeed: UInt64 = 0
    }

    let boundingMapRect = MKMapRect.world
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }

    private let lock = NSLock()
    /// Color Hierarchy drawing order: lowest color first; double lines may be split into border and fill.
    private var _items: [(item: Item, part: ColorHierarchy.Part)] = []

    var items: [(item: Item, part: ColorHierarchy.Part)] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    /// Per-object cache: an item is rebuilt only when its object changed (compared by value).
    private var cache: [UUID: (feature: Feature, item: Item?)] = [:]
    private var cacheKey: (UTMZone, SheetSpec, Double)?
    private var order: [UUID] = []

    /// Builds the item list; returns the union rect of changed objects (for partial redraw).
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

    /// Updates one object (drag); returns the rect that needs redrawing.
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
        let entries = order.compactMap { cache[$0] }
        let items = ColorHierarchy.paintOrder(entries.map(\.feature)).compactMap { paint in
            entries[paint.index].item.map { (item: $0, part: paint.part) }
        }
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
            // Paths are stored in absolute map points; the renderer offsets them to overlay coordinates.
            // Areas: the outer ring and every hole are subpaths (filled and clipped with the even-odd rule).
            let path = CGMutablePath()
            let start = mp(first.point)
            for ring in f.ringFeatures {
                guard let r0 = ring.nodes.first else { continue }
                let s0 = mp(r0.point)
                path.move(to: CGPoint(x: s0.x, y: s0.y))
                for s in ring.segments {
                    let p3 = mp(s.p3)
                    if s.isCurve {
                        let c1 = mp(s.c1), c2 = mp(s.c2)
                        path.addCurve(to: CGPoint(x: p3.x, y: p3.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
                    } else {
                        path.addLine(to: CGPoint(x: p3.x, y: p3.y))
                    }
                }
                if f.closesPath { path.closeSubpath() }
            }
            let lo = mp(Point2D(x: b.minX, y: b.maxY)), hi = mp(Point2D(x: b.maxX, y: b.minY))
            let widthMP = sheet.groundMeters(forPaperMM: f.widthMM) / MKMetersPerMapPointAtLatitude(start.coordinate.latitude)
            let mpPerMM = sheet.groundMeters(forPaperMM: 1) / MKMetersPerMapPointAtLatitude(start.coordinate.latitude)
            // Decorations (tags) reach beyond the line width.
            let reach = max(widthMP * 2, ((f.decoration?.sizeMM ?? 0) + f.widthMM) * mpPerMM)
            let rect = MKMapRect(x: min(lo.x, hi.x), y: min(lo.y, hi.y), width: abs(hi.x - lo.x), height: abs(hi.y - lo.y))
                .insetBy(dx: -reach, dy: -reach)
            let color = UIColor(hexString: f.colorHex)
            let patternOnly = f.isSymbolArea && SymbolOrnaments.isPatternOnly(fillHex: f.colorHex, patterns: f.patterns)
            var item = Item(path: path, bounds: rect, color: color.cgColor,
                            fill: f.kind == .area && !patternOnly ? color.withAlphaComponent(f.isSymbolArea ? areaOpacity : 0.35).cgColor : nil,
                            widthMapPoints: widthMP)
            item.mapPointsPerMM = mpPerMM
            if f.kind == .area, f.isSymbolArea, let p = f.patterns, !p.isEmpty {
                item.patterns = p
                item.patternAlpha = areaOpacity
                item.patternSeed = f.patternSeed
            }
            if f.kind == .line, let deco = f.decoration {
                let pts = SymbolOrnaments.polyline(f) { let m = mp($0); return Point2D(x: m.x, y: m.y) }
                item.decoration = SymbolOrnaments.decorationMarks(deco, along: pts, unitsPerMM: mpPerMM, lineWidthMM: f.widthMM,
                                                                  colorHex: f.colorHex, yUp: false, dashMM: f.effectiveDashMM)
                item.hidesLine = f.hidesMainLine
            }
            item.fillOnly = f.isSymbolArea
            item.roundCaps = f.roundCaps != false
            item.dash = f.effectiveDashMM?.map { CGFloat($0 * mpPerMM) }
            if f.kind == .line, let casing = f.casingColorHex, let inner = f.innerWidthMM {
                item.casing = (UIColor(hexString: casing).cgColor, inner * mpPerMM)
                item.innerDash = f.effectiveInnerDashMM?.map { CGFloat($0 * mpPerMM) }
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
        for (item, part) in overlay.items where item.bounds.intersects(mapRect) {
            if let p = item.point {
                // Map point: x east, y south → mm offset (y up) is flipped. Each element at its own color level.
                var level: Int?
                if case let .elements(l) = part { level = l }
                PointSymbolRenderer.draw(p.elements, in: context, mmToUnits: p.mapPointsPerMM, level: level) {
                    CGPoint(x: p.center.x + $0.x * p.mapPointsPerMM, y: p.center.y - $0.y * p.mapPointsPerMM)
                }
                continue
            }
            if let fill = item.fill {
                context.addPath(item.path)
                context.setFillColor(fill)
                context.fillPath(using: .evenOdd)
            }
            if let patterns = item.patterns {
                let r = mapRect.intersection(item.bounds)
                context.saveGState()
                context.setAlpha(item.patternAlpha)
                OrnamentRenderer.drawPatterns(patterns, outline: item.path, rect: Rect2D(minX: r.minX, minY: r.minY, maxX: r.maxX, maxY: r.maxY),
                                              in: context, unitsPerMM: item.mapPointsPerMM, yUp: false,
                                              minSpacing: 1.5 / zoomScale, minWidth: 0.4 / zoomScale, seed: item.patternSeed)
                context.restoreGState()
            }
            if item.fill != nil || item.patterns != nil, item.fillOnly { continue }
            context.setLineCap(item.roundCaps ? .round : .butt)
            context.setLineJoin(item.roundCaps ? .round : .miter)
            context.setLineDash(phase: 0, lengths: item.dash ?? [])
            if let casing = item.casing {
                // Double line: border and fill each on their own color layer (Color Hierarchy).
                if part != .main {
                    context.addPath(item.path)
                    context.setStrokeColor(casing.color)
                    context.setLineWidth(max(item.widthMapPoints, minWidth))
                    context.strokePath()
                }
                context.setLineDash(phase: 0, lengths: item.innerDash ?? [])
                if part != .casing {
                    context.addPath(item.path)
                    context.setStrokeColor(item.color)
                    context.setLineWidth(max(casing.innerWidthMapPoints, minWidth * 0.5))
                    context.strokePath()
                }
                continue
            }
            if !item.hidesLine {
                context.addPath(item.path)
                context.setStrokeColor(item.color)
                context.setLineWidth(max(item.widthMapPoints, minWidth))
                context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [])
            if !item.decoration.isEmpty {
                OrnamentRenderer.draw(item.decoration, in: context, unitsPerMM: item.mapPointsPerMM, minWidth: minWidth * 0.6)
            }
        }
        context.setLineDash(phase: 0, lengths: [])
    }
}

/// North-line grid inside the frame (above imagery, below sketch and objects).
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

/// Contour lines (above imagery, below grid and objects). Points are converted to map points in the background.
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

    /// Changes only the drawing style (color, opacity, width) without reconverting points.
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
            let base = kind == .index ? s.indexWidth : kind == .form ? s.contourWidth * MapStandard.formLineWidthRatio : s.contourWidth
            let width = max(base, minWidth)
            context.setLineWidth(width)
            // Form line (ISOM / ISSprOM 103): thinner than contours, dash 20× and gap 2× its width
            // (ISOM 0.1 mm: 2.0 / 0.2 mm; ISSprOM 0.15 mm: 3.0 / 0.3 mm).
            context.setLineDash(phase: 0, lengths: kind == .form
                                ? [width * MapStandard.formLineDashPerWidth, width * MapStandard.formLineGapPerWidth] : [])
            for line in s.lines where line.kind == kind && line.bounds.intersects(mapRect.insetBy(dx: -width, dy: -width)) {
                guard let first = line.points.first else { continue }
                context.move(to: point(for: first))
                for p in line.points.dropFirst() { context.addLine(to: point(for: p)) }
            }
            context.strokePath()
        }
    }
}

/// Course overprint (purple, topmost): control circles, start triangle, finish, legs, and numbers.
/// Shapes are converted to map points once when data changes (not per tile), so rotating/panning/dragging controls stays smooth.
final class CourseOverlay: NSObject, MKOverlay {
    struct State {
        /// Overprint in map point space (x, y = MKMapPoint; radius/width/text height in map points).
        var overprint = CourseOverprint(marks: [], lineWidthM: 0, colorHex: "#A626FF")
        var bounds: MKMapRect?
        /// Course object images by file name.
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

    /// Replaces contents; returns the area that needs redrawing (union of old + new), nil if both are empty.
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
                case let .width(w): return .width(w.map { $0 / mpp })
                case .color, .font, .level: return mark
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
        // On screen the course is a layer above the whole map, so it can't sit inside the colour order like the export
        // (lower purple below black / blue / brown): multiply keeps that detail readable while planning.
        CourseOverprintRenderer.draw(s.overprint, in: context, unitsPerMeter: 1, flipped: true,
                                     minLineWidth: 1.2 / zoomScale, alpha: 0.9, images: s.images, blendMode: .multiply) { p in
            self.point(for: MKMapPoint(x: p.x, y: p.y))
        }
    }
}
