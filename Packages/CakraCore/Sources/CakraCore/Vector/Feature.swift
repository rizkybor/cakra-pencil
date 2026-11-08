import Foundation

/// Bezier node: position + in/out handles (absolute UTM coordinates). No handles = corner node.
public struct BezierNode: Codable, Hashable, Sendable {
    public var point: Point2D
    public var inHandle: Point2D?
    public var outHandle: Point2D?
    /// Smart node (Affinity "Smart"): handles are computed automatically from neighboring nodes and adjust
    /// when the node or its neighbors are moved. nil = not smart (not written to JSON).
    public var smart: Bool?

    public init(point: Point2D, inHandle: Point2D? = nil, outHandle: Point2D? = nil, smart: Bool? = nil) {
        self.point = point
        self.inHandle = inHandle
        self.outHandle = outHandle
        self.smart = smart
    }

    public var isSmooth: Bool { inHandle != nil || outHandle != nil }

    /// Both handles present and collinear (opposite directions) = smooth node. Non-collinear handles = corner (cusp).
    public var hasAlignedHandles: Bool {
        guard let a = inHandle, let b = outHandle else { return false }
        let u = a - point, v = b - point
        let lu = hypot(u.x, u.y), lv = hypot(v.x, v.y)
        guard lu > 0, lv > 0 else { return false }
        let cross = (u.x * v.y - u.y * v.x) / (lu * lv), dot = (u.x * v.x + u.y * v.y) / (lu * lv)
        return abs(cross) < 0.02 && dot < 0
    }

    /// Move the node together with both its handles.
    public func moved(by d: Point2D) -> BezierNode {
        BezierNode(point: point + d, inHandle: inHandle.map { $0 + d }, outHandle: outHandle.map { $0 + d }, smart: smart)
    }
}

/// Node type for Convert to Sharp / Smooth / Smart (as in Affinity Designer).
public enum NodeStyle: String, CaseIterable, Sendable {
    case sharp, smooth, smart
}

/// A single cubic segment p0 → p3 with control points c1, c2. Straight segment: c1 = p0, c2 = p3.
public struct CubicSegment: Hashable, Sendable {
    public var p0: Point2D
    public var c1: Point2D
    public var c2: Point2D
    public var p3: Point2D
    public var isCurve: Bool

    /// Point at parameter t. Straight segment: linear interpolation (t proportional to distance).
    public func point(at t: Double) -> Point2D {
        if !isCurve { return Point2D(x: p0.x + (p3.x - p0.x) * t, y: p0.y + (p3.y - p0.y) * t) }
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return Point2D(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }
}

public enum FeatureKind: String, Codable, CaseIterable, Sendable {
    case point
    case line
    case area

    public var label: String {
        switch self {
        case .point: return "Point"
        case .line: return "Line"
        case .area: return "Area"
        }
    }
}

/// Vector object (FR-4): a line or area made of bezier nodes, in project coordinates (UTM).
public struct Feature: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: FeatureKind
    public var colorHex: String
    public var widthMM: Double
    public var nodes: [BezierNode]
    public var isVisible: Bool
    public var isLocked: Bool
    public var createdAt: Date
    /// ISOM/ISSprOM symbol code (e.g. "101.0") and its name, if the object was drawn with a symbol from the symbol panel
    /// or imported from OCAD. Carried into .omap/DXF export.
    public var symbolCode: String?
    public var symbolName: String?
    /// Point symbol shape at standard size (paper mm). Only for `kind == .point`.
    public var pointElements: [PointElement]?
    /// Point symbol size multiplier (1 = IOF standard size from the symbol set).
    public var sizeFactor: Double?
    /// Double line: edge color and fill width (mm); `widthMM` = total width edge to edge.
    public var casingColorHex: String?
    public var innerWidthMM: Double?
    /// IOF standard width from its symbol, for the "Standard" button after the width has been changed.
    public var standardWidthMM: Double?
    /// Dash pattern [dash, gap] in paper mm (double line: applies to the edges).
    public var dashMM: [Double]?
    /// Dash pattern of the inner line on a layered line (paper mm), e.g. railway.
    public var innerDashMM: [Double]?
    /// false = flat caps + miter joins (walls, buildings); nil/true = round.
    public var roundCaps: Bool?
    /// Object angle 0–359.9° clockwise (nil = 0). Lines/areas: geometry is already rotated; points: the symbol shape is rotated when drawn.
    public var rotationDeg: Double?
    /// OCAD Color Hierarchy: position of the main color (and the double-line edge color) in its symbol set's color table,
    /// 0 = topmost. Filled from the symbol set when drawn/exported (see `withColorPriorities`);
    /// nil = not yet known.
    public var colorPriority: Int?
    public var casingPriority: Int?
    /// Area patterns and line decorations of its symbol (ISOM/ISSprOM marsh lines, tags, wall dots…). Filled from the
    /// symbol set when drawn/exported, like the color priorities; not needed in the saved file.
    public var patterns: [AreaPattern]?
    public var decoration: LineDecoration?

    public init(id: UUID = UUID(), name: String = "", kind: FeatureKind, colorHex: String, widthMM: Double,
                nodes: [BezierNode], isVisible: Bool = true, isLocked: Bool = false, createdAt: Date = Date(),
                symbolCode: String? = nil, symbolName: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.widthMM = widthMM
        self.nodes = nodes
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.createdAt = createdAt
        self.symbolCode = symbolCode
        self.symbolName = symbolName
    }

    /// Areas are always closed; lines are open.
    public var isClosed: Bool { kind == .area }

    /// A line whose end node lies exactly on its start node (closed line / ring).
    public var isRingLine: Bool {
        kind == .line && nodes.count >= 3 && nodes.first!.point.distance(to: nodes.last!.point) < 1e-6
    }

    /// Path is drawn closed (closePath): areas and closed lines, so the corner at the start node joins cleanly
    /// (rather than two overlapping line ends).
    public var closesPath: Bool { isClosed || isRingLine }

    /// Close the line if its end node overlaps its start node (within `tolerance` m): the end node
    /// is moved exactly onto the start node. false if unchanged.
    @discardableResult
    public mutating func closeLineIfEndsMeet(tolerance: Double) -> Bool {
        guard kind == .line, nodes.count >= 3, !isRingLine, let a = nodes.first?.point, let b = nodes.last?.point,
              a.distance(to: b) <= tolerance else { return false }
        let d = a - b
        let i = nodes.count - 1
        nodes[i].point = a
        nodes[i].inHandle = nodes[i].inHandle.map { $0 + d }
        nodes[i].outHandle = nil
        return true
    }

    public var segments: [CubicSegment] {
        guard nodes.count > 1 else { return [] }
        var out: [CubicSegment] = []
        let count = isClosed ? nodes.count : nodes.count - 1
        for i in 0..<count {
            let a = nodes[i], b = nodes[(i + 1) % nodes.count]
            out.append(CubicSegment(p0: a.point, c1: a.outHandle ?? a.point, c2: b.inHandle ?? b.point, p3: b.point,
                                    isCurve: a.outHandle != nil || b.inHandle != nil))
        }
        return out
    }

    /// Box guaranteed to contain the curve (a bezier curve always lies inside the hull of its control points).
    /// For points: a 1 m box; the actual drawn size depends on the scale (see `pointRadiusM`).
    public var bounds: Rect2D? {
        if kind == .point, let p = nodes.first?.point {
            return Rect2D(minX: p.x - 1, minY: p.y - 1, maxX: p.x + 1, maxY: p.y + 1)
        }
        return Rect2D(points: nodes.flatMap { [$0.point] + [$0.inHandle, $0.outHandle].compactMap { $0 } })
    }

    public var effectiveSizeFactor: Double { sizeFactor ?? 1 }

    /// Point symbol radius on the ground (m) at the sheet scale.
    public func pointRadiusM(sheet: SheetSpec) -> Double {
        sheet.groundMeters(forPaperMM: (pointElements ?? []).diameterMM / 2 * effectiveSizeFactor)
    }

    /// Point elements scaled by `sizeFactor` and rotated by `rotationDeg` (coordinates + diameter + width).
    public var scaledPointElements: [PointElement] {
        let k = effectiveSizeFactor
        let origin = Point2D(x: 0, y: 0)
        return (pointElements ?? []).map { e in
            var e = e
            e.points = e.points.map { Feature.rotate(Point2D(x: $0.x * k, y: $0.y * k), around: origin, degrees: rotationDegrees) }
            e.diameterMM *= k
            e.lineWidthMM *= k
            return e
        }
    }

    /// Point symbol object at position `p` with standard size × `sizeFactor`.
    public static func point(at p: Point2D, elements: [PointElement], sizeFactor: Double = 1, name: String = "",
                             symbolCode: String? = nil, symbolName: String? = nil) -> Feature {
        var f = Feature(name: name, kind: .point, colorHex: elements.drawingOrder.last?.colorHex ?? "#000000",
                        widthMM: elements.diameterMM * sizeFactor, nodes: [BezierNode(point: p)],
                        symbolCode: symbolCode, symbolName: symbolName)
        f.pointElements = elements
        f.sizeFactor = sizeFactor == 1 ? nil : sizeFactor
        return f
    }

    /// Polyline approximation of the curve; maximum deviation ≤ `tolerance` meters.
    public func flattened(tolerance: Double) -> [Point2D] {
        guard let first = nodes.first else { return [] }
        var pts = [first.point]
        for s in segments {
            if !s.isCurve {
                pts.append(s.p3)
                continue
            }
            // Step count from the control polygon length: enough for the tolerance at map scale.
            let hull = s.p0.distance(to: s.c1) + s.c1.distance(to: s.c2) + s.c2.distance(to: s.p3)
            let steps = max(4, min(256, Int((hull / max(tolerance, 1e-6)).squareRoot().rounded(.up)) * 2))
            for k in 1...steps { pts.append(s.point(at: Double(k) / Double(steps))) }
        }
        return pts
    }

    public func distance(to p: Point2D, tolerance: Double) -> Double {
        let pts = flattened(tolerance: tolerance)
        guard pts.count > 1 else { return pts.first.map(p.distance) ?? .infinity }
        var best = Double.infinity
        for i in 1..<pts.count { best = min(best, p.distance(toSegment: pts[i - 1], pts[i])) }
        return best
    }

    /// Display name in the panel: the user's name, or kind + short number.
    public var displayName: String {
        name.isEmpty ? "\(kind.label) \(id.uuidString.prefix(4))" : name
    }
}

// MARK: - Basic shapes

extension Feature {
    /// Cubic constant for a quarter circle (max radius error ≈ 0.03%).
    public static let ellipseKappa = 0.5522847498

    /// Rectangle from 4 corners clockwise from upper-left (may be skewed if the map is rotated).
    public static func rectangle(corners c: [Point2D], colorHex: String, widthMM: Double) -> Feature {
        Feature(name: "", kind: .area, colorHex: colorHex, widthMM: widthMM, nodes: c.prefix(4).map { BezierNode(point: $0) })
    }

    /// Ellipse inscribed in the parallelogram given by 4 corners (upper-left, upper-right, lower-right, lower-left):
    /// 4 smooth nodes at the middle of each side with kappa handles.
    public static func ellipse(corners c: [Point2D], colorHex: String, widthMM: Double) -> Feature {
        precondition(c.count >= 4)
        let center = Point2D(x: (c[0].x + c[2].x) / 2, y: (c[0].y + c[2].y) / 2)
        func half(_ a: Point2D, _ b: Point2D) -> Point2D { Point2D(x: (b.x - a.x) / 2, y: (b.y - a.y) / 2) }
        func scaled(_ p: Point2D, _ k: Double) -> Point2D { Point2D(x: p.x * k, y: p.y * k) }
        let u = half(c[0], c[1]) // half width, to the right
        let v = half(c[0], c[3]) // half height, downward
        let k = ellipseKappa
        let top = center - v, right = center + u, bottom = center + v, left = center - u
        return Feature(name: "", kind: .area, colorHex: colorHex, widthMM: widthMM, nodes: [
            BezierNode(point: top, inHandle: top - scaled(u, k), outHandle: top + scaled(u, k)),
            BezierNode(point: right, inHandle: right - scaled(v, k), outHandle: right + scaled(v, k)),
            BezierNode(point: bottom, inHandle: bottom + scaled(u, k), outHandle: bottom - scaled(u, k)),
            BezierNode(point: left, inHandle: left + scaled(v, k), outHandle: left - scaled(v, k)),
        ])
    }

    /// Turn node i into a corner (no handles) or smooth (handles along the neighbors, length ⅓ of the nearest distance).
    public mutating func toggleSmooth(at i: Int) {
        guard nodes.indices.contains(i) else { return }
        if nodes[i].isSmooth {
            nodes[i].inHandle = nil
            nodes[i].outHandle = nil
            nodes[i].smart = nil
            return
        }
        let n = nodes.count
        let p = nodes[i].point
        let prev = (i > 0 || isClosed) ? nodes[(i - 1 + n) % n].point : p
        let next = (i < n - 1 || isClosed) ? nodes[(i + 1) % n].point : p
        var dir = next - prev
        let len = hypot(dir.x, dir.y)
        guard len > 0 else { return }
        dir = Point2D(x: dir.x / len, y: dir.y / len)
        let reach = min(p.distance(to: prev) == 0 ? .infinity : p.distance(to: prev),
                        p.distance(to: next) == 0 ? .infinity : p.distance(to: next)) / 3
        guard reach.isFinite else { return }
        nodes[i].inHandle = p - Point2D(x: dir.x * reach, y: dir.y * reach)
        nodes[i].outHandle = p + Point2D(x: dir.x * reach, y: dir.y * reach)
    }

    /// Node type: smart, smooth (collinear handles; or an open line end that has a handle), or sharp
    /// (no handles, or non-collinear handles such as a corner produced by dragging a segment).
    public func nodeStyle(at i: Int) -> NodeStyle {
        guard nodes.indices.contains(i) else { return .sharp }
        let n = nodes[i]
        if n.smart == true { return .smart }
        if n.hasAlignedHandles { return .smooth }
        let isEnd = !isClosed && (i == 0 || i == nodes.count - 1)
        return isEnd && n.isSmooth ? .smooth : .sharp
    }

    /// Convert to Sharp / Smooth / Smart.
    /// - Sharp: handles removed (sharp corner).
    /// - Smooth: collinear handles; existing handles keep their length, missing ones are created from the neighbors.
    /// - Smart: automatic handles from the neighbors (see `refreshSmartNodes`).
    public mutating func convertNode(at i: Int, to style: NodeStyle) {
        guard nodes.indices.contains(i) else { return }
        switch style {
        case .sharp:
            nodes[i].inHandle = nil
            nodes[i].outHandle = nil
            nodes[i].smart = nil
        case .smooth:
            nodes[i].smart = nil
            guard let dir = tangent(at: i) else { return }
            let p = nodes[i].point
            let (prevLen, nextLen) = neighborReach(at: i)
            let inLen = nodes[i].inHandle.map { $0.distance(to: p) }.flatMap { $0 > 0 ? $0 : nil } ?? prevLen
            let outLen = nodes[i].outHandle.map { $0.distance(to: p) }.flatMap { $0 > 0 ? $0 : nil } ?? nextLen
            nodes[i].inHandle = inLen > 0 ? p - dir * inLen : nil
            nodes[i].outHandle = outLen > 0 ? p + dir * outLen : nil
        case .smart:
            nodes[i].smart = true
            applySmartHandles(at: i)
        }
    }

    /// Recompute the handles of all smart nodes (called after nodes are moved/added/deleted).
    public mutating func refreshSmartNodes() {
        for i in nodes.indices where nodes[i].smart == true { applySmartHandles(at: i) }
    }

    /// Smart handles: along the previous → next neighbor line, length ⅓ of the distance to each neighbor.
    /// Open line ends have no curve direction → no handles.
    private mutating func applySmartHandles(at i: Int) {
        let p = nodes[i].point
        let n = nodes.count
        let isEnd = !isClosed && (i == 0 || i == n - 1)
        guard !isEnd, let dir = tangent(at: i) else {
            nodes[i].inHandle = nil
            nodes[i].outHandle = nil
            return
        }
        let (prevLen, nextLen) = neighborReach(at: i)
        nodes[i].inHandle = p - dir * prevLen
        nodes[i].outHandle = p + dir * nextLen
    }

    /// Unit tangent direction at node i, from the previous neighbor to the next.
    private func tangent(at i: Int) -> Point2D? {
        let n = nodes.count
        guard n >= 2 else { return nil }
        let p = nodes[i].point
        let prev = (i > 0 || isClosed) ? nodes[(i - 1 + n) % n].point : p
        let next = (i < n - 1 || isClosed) ? nodes[(i + 1) % n].point : p
        let d = next - prev
        let len = hypot(d.x, d.y)
        guard len > 0 else { return nil }
        return Point2D(x: d.x / len, y: d.y / len)
    }

    /// ⅓ of the distance to the previous and next neighbors (0 if none).
    private func neighborReach(at i: Int) -> (Double, Double) {
        let n = nodes.count
        let p = nodes[i].point
        let prev = (i > 0 || isClosed) ? p.distance(to: nodes[(i - 1 + n) % n].point) / 3 : 0
        let next = (i < n - 1 || isClosed) ? p.distance(to: nodes[(i + 1) % n].point) / 3 : 0
        return (prev, next)
    }

    /// Move one handle. On a smooth node, the opposite handle rotates along (collinear) with unchanged length.
    /// On a corner (non-collinear handles) the opposite handle does not follow.
    public mutating func moveHandle(node i: Int, isIn: Bool, to h: Point2D) {
        guard nodes.indices.contains(i) else { return }
        let p = nodes[i].point
        // The opposite handle rotates along only on smooth/smart nodes; corner (cusp) handles are independent.
        let linked = nodes[i].smart == true || nodes[i].hasAlignedHandles
        nodes[i].smart = nil   // smart handle edited by hand = becomes smooth (as in Affinity)
        if isIn { nodes[i].inHandle = h } else { nodes[i].outHandle = h }
        guard linked, let other = isIn ? nodes[i].outHandle : nodes[i].inHandle else { return }
        let d = h - p
        let len = hypot(d.x, d.y)
        guard len > 0 else { return }
        let otherLen = other.distance(to: p)
        let mirrored = p - Point2D(x: d.x / len * otherLen, y: d.y / len * otherLen)
        if isIn { nodes[i].outHandle = mirrored } else { nodes[i].inHandle = mirrored }
    }
}

// MARK: - Line style

extension Feature {
    /// Apply the IOF line style (width, color, double-line edges) and store its standard width.
    public mutating func apply(_ style: LineStyle) {
        colorHex = style.colorHex
        widthMM = style.widthMM
        casingColorHex = style.casing?.colorHex
        innerWidthMM = style.casing?.innerWidthMM
        standardWidthMM = style.widthMM
        dashMM = style.dashMM
        innerDashMM = style.innerDashMM
        roundCaps = style.roundCaps
    }

    /// Symbolized areas are drawn like OCAD/OOM: full-color fill without an outline.
    /// Sketch areas without a symbol: transparent fill + outline.
    public var isSymbolArea: Bool { kind == .area && symbolCode != nil }

    /// Dash pattern for drawing, scaled by the width (paper mm).
    public var effectiveDashMM: [Double]? {
        guard let d = dashMM, d.count == 2, d[0] > 0, d[1] > 0 else { return nil }
        let k = (standardWidthMM ?? widthMM) > 0 ? widthMM / (standardWidthMM ?? widthMM) : 1
        return d.map { $0 * k }
    }

    /// Inner-line dash pattern for drawing, scaled by the width.
    public var effectiveInnerDashMM: [Double]? {
        guard let d = innerDashMM, d.count == 2, d[0] > 0, d[1] > 0 else { return nil }
        let k = (standardWidthMM ?? widthMM) > 0 ? widthMM / (standardWidthMM ?? widthMM) : 1
        return d.map { $0 * k }
    }

    public var isDoubleLine: Bool { casingColorHex != nil && innerWidthMM != nil }

    /// Change the total width; on double lines the fill width changes in the same proportion.
    public mutating func setWidth(_ mm: Double) {
        let next = PenPreset.clampWidth(mm)
        if let inner = innerWidthMM, widthMM > 0 { innerWidthMM = inner * next / widthMM }
        widthMM = next
    }
}

// MARK: - Rotation

extension Feature {
    public var rotationDegrees: Double { rotationDeg ?? 0 }

    /// Rotation center: the point's position, or the mean of the line/area nodes (unchanged after rotating,
    /// so repeated rotations do not shift the object).
    public var rotationPivot: Point2D? {
        guard !nodes.isEmpty else { return nil }
        let n = Double(nodes.count)
        return Point2D(x: nodes.reduce(0) { $0 + $1.point.x } / n, y: nodes.reduce(0) { $0 + $1.point.y } / n)
    }

    /// Rotate a point clockwise (y axis north).
    public static func rotate(_ p: Point2D, around c: Point2D, degrees: Double) -> Point2D {
        guard degrees != 0 else { return p }
        let a = degrees * .pi / 180
        let dx = p.x - c.x, dy = p.y - c.y
        return Point2D(x: c.x + dx * cos(a) + dy * sin(a), y: c.y - dx * sin(a) + dy * cos(a))
    }

    /// Normalize to 0 ≤ angle < 360.
    public static func normalizedDegrees(_ d: Double) -> Double {
        let r = d.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Set the absolute angle. Lines/areas: nodes + handles are rotated by the difference around the object's center.
    public mutating func setRotation(_ degrees: Double) {
        let target = (Feature.normalizedDegrees(degrees) * 10).rounded() / 10
        let delta = target - rotationDegrees
        if kind != .point, delta != 0, let c = rotationPivot {
            nodes = nodes.map { n in
                BezierNode(point: Feature.rotate(n.point, around: c, degrees: delta),
                           inHandle: n.inHandle.map { Feature.rotate($0, around: c, degrees: delta) },
                           outHandle: n.outHandle.map { Feature.rotate($0, around: c, degrees: delta) })
            }
        }
        rotationDeg = target == 0 ? nil : target
    }
}

// MARK: - Change symbol (OCAD "Change symbol" / OOM "Switch symbol")

extension Feature {
    /// Can it switch to symbol `s`? Point ↔ point (that has a shape). Line ↔ area both ways,
    /// as in OOM; becoming an area needs at least 3 nodes.
    public func canSwitch(to s: MapSymbol) -> Bool {
        switch (kind, s.kind) {
        case (.point, .point): return !(s.pointElements ?? []).isEmpty
        case (.line, .line), (.area, .area): return true
        case (.line, .area): return nodes.count >= 3
        case (.area, .line): return true
        default: return false
        }
    }

    /// Change symbol: geometry, rotation, and point size are kept; color, IOF standard width, double line,
    /// dashes, and point shape follow the new symbol. The default name (“101.0 Contour 3”) is replaced too.
    /// Returns `false` if the kind does not match (object unchanged).
    @discardableResult
    public mutating func switchSymbol(to s: MapSymbol) -> Bool {
        guard canSwitch(to: s) else { return false }
        let oldPrefix = symbolCode.map { "\($0) " }
        symbolCode = s.code
        symbolName = s.name
        colorHex = s.colorHex
        casingColorHex = nil
        innerWidthMM = nil
        dashMM = nil
        innerDashMM = nil
        roundCaps = nil
        switch s.kind {
        case .point:
            pointElements = s.pointElements
            widthMM = (s.pointElements ?? []).diameterMM * effectiveSizeFactor
        case .line:
            kind = .line
            if let style = s.lineStyle { apply(style) } else { widthMM = s.drawingWidthMM; standardWidthMM = s.drawingWidthMM }
        case .area:
            kind = .area
            widthMM = s.drawingWidthMM
            standardWidthMM = s.drawingWidthMM
        case .text:
            break
        }
        if let oldPrefix, name.hasPrefix(oldPrefix) {
            // Keep the sequence number at the end of the name if present (“… 3”).
            let suffix = name.split(separator: " ").last.flatMap { Int($0) }.map { " \($0)" } ?? ""
            name = "\(s.code) \(s.name)\(suffix)"
        }
        return true
    }
}
