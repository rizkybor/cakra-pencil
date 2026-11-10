import CakraCore
import Foundation

/// OCAD-style object edit tools: add point (reshape), cut line/area, scale, parallel line, reverse direction.
/// Rotate, move/delete point, and merge live in WorkspaceModel / WorkspaceModel+Merge.
extension WorkspaceModel {
    // MARK: Reshape: add point

    /// Add a point on the outline of the selected object (outer edge or a hole edge), at the position nearest `p`
    /// (shape unchanged).
    func insertNode(near p: Point2D) {
        guard let f = selectedFeature, !f.isLocked, let r = f.nearestRingPosition(to: p) else { return }
        var index: Int?
        updateFeature(f.id) { index = $0.insertNode(ring: r.ring, at: r.position) }
        if let index { selectedNodeIndex = index } else { notice = "There is already a point there." }
    }

    // MARK: Cut (OCAD Cut)

    func startCut() {
        guard let f = selectedFeature, !f.isLocked, f.kind != .point else { return }
        cutMode = true
        cutStart = nil
        cutReturnTool = nil
        selectedNodeIndex = nil
    }

    /// End the cut (Esc / ✕ or after cutting); a drawing tool picked for the cut returns to the Move/Node Tool.
    func cancelCut() {
        cutMode = false
        cutStart = nil
        if let t = cutReturnTool {
            cutReturnTool = nil
            cancelDraft()
            tool = t
        }
    }

    /// A drawing tool (rectangle, ellipse, pen, freehand) is drawing the cut for the selected area.
    var isDrawingCut: Bool { cutMode && cutReturnTool != nil }

    /// Points closer than this count as the same point when cutting (≈ 0.001 mm on paper, at least 0.1 mm).
    var cutTolerance: Double { max(1e-4, project.sheet.groundMeters(forPaperMM: 0.001)) }

    /// Split area: cut away the part of the selected area inside a closed shape (rectangle, ellipse, closed pen path).
    func cutSelectedArea(withShape shape: [BezierNode]) {
        guard let f = selectedFeature, !f.isLocked, f.kind == .area else { return cancelCut() }
        guard shape.count >= 3 else {
            cancelDraft()
            notice = "Draw a larger shape across the area's edge."
            return
        }
        applyAreaCut(f, f.subtractingShape(shape, eps: cutTolerance), path: false)
    }

    /// Split area along an open path (pen tool or freehand).
    func cutSelectedArea(alongPath path: [BezierNode]) {
        guard let f = selectedFeature, !f.isLocked, f.kind == .area else { return cancelCut() }
        guard path.count >= 2 else {
            cancelDraft()
            notice = "Draw a path across the area: it must cross the edge at least twice."
            return
        }
        applyAreaCut(f, f.splittingArea(along: path, eps: cutTolerance), path: true)
    }

    /// Freehand stroke drawn while cutting: simplified like a freehand line, then split along it.
    func cutSelectedArea(alongFreehand points: [Point2D]) {
        let tolerance = project.sheet.groundMeters(forPaperMM: 0.1)
        let simple = points.count > 2 ? ContourGenerator.simplify(points, tolerance: tolerance) : points
        cutSelectedArea(alongPath: simple.map { BezierNode(point: $0) })
    }

    private func applyAreaCut(_ f: Feature, _ result: Result<[Feature], ShapeCutFailure>, path: Bool) {
        cancelDraft()
        switch result {
        case let .success(parts):
            cancelCut()   // back to the Move/Node Tool first, so the pieces stay selected
            replace(f, with: parts, selectAll: true)
            let newHole = parts.count == 1 && parts[0].holeRings.count > f.holeRings.count
                && parts[0].nodes.count == f.nodes.count
            notice = parts.isEmpty ? "Area removed: the shape covered all of it."
                : newHole ? "Hole cut in the area."
                : parts.count == 1 ? "Shape cut out of the area."
                : "Area cut into \(parts.count) pieces."
        case .failure(.insideHole):
            notice = "The shape is inside a hole."
        case .failure(.noOverlap):
            notice = path ? "The path doesn't touch the area." : "The shape doesn't touch the area."
        case .failure(.notCrossing):
            notice = f.hasHoles
                ? "Draw the path across the area so it cuts off a piece (edge to edge, or through a hole)."
                : "Draw the path across the area: it must cross the edge at least twice."
        case .failure(.unresolved):
            notice = path ? "This path can't split the area (does it cross itself?)." : "This shape can't cut the area."
        }
    }

    /// Line cut: remove the parts of the selected line inside a box (`polygon` = the box corners as map coordinates).
    func cutSelectedLine(outside polygon: [Point2D]) {
        guard let f = selectedFeature, !f.isLocked, f.kind == .line else { return cancelCut() }
        guard let parts = f.cuttingOut(polygon, eps: cutTolerance) else {
            notice = "The box doesn't cover any part of the line."
            return
        }
        cancelCut()
        replace(f, with: parts, selectAll: true)
        notice = parts.isEmpty ? "Line removed: the box covered all of it."
            : parts.count == 1 ? "Part of the line cut out."
            : "Line cut into \(parts.count) pieces."
    }

    /// Cut tool tap at a position on the selected object's path. Line: cut in two right away. Area: the first
    /// tap = start point of the cut line, the second tap = split the area in two.
    func cutSelected(at pos: PathPosition) {
        guard let f = selectedFeature, !f.isLocked else { return cancelCut() }
        switch f.kind {
        case .line:
            guard let (a, b) = f.splitLine(at: pos) else {
                notice = "Tap in the middle of the line, not at its end."
                return
            }
            replace(f, with: [a, b])
            notice = "Line cut in two."
            cancelCut()
        case .area:
            guard let start = cutStart else {
                cutStart = pos
                return
            }
            if f.hasHoles, let pa = f.point(at: start), let pb = f.point(at: pos) {
                // With holes: a straight cut line from edge to edge through the exact cut engine (holes go to their
                // piece, a hole on the line is split).
                cutStart = nil
                applyAreaCut(f, f.splittingArea(along: [BezierNode(point: pa), BezierNode(point: pb)], eps: cutTolerance), path: true)
                return
            }
            guard let (a, b) = f.splitArea(from: start, to: pos) else {
                notice = "The second point must be on the other side of the area."
                cutStart = nil
                return
            }
            replace(f, with: [a, b])
            notice = "Area split in two."
            cancelCut()
        case .point:
            cancelCut()
        }
    }

    /// Replace one object with several parts at the same order position (new parts get sequential names).
    /// `selectAll`: all parts become the selection (a multi-selection when several); otherwise the first part.
    private func replace(_ f: Feature, with parts: [Feature], selectAll: Bool = false) {
        editFeatures { list in
            guard let i = list.firstIndex(where: { $0.id == f.id }) else { return }
            var named = parts
            for k in named.indices where named[k].name.isEmpty {
                let base = f.symbolCode.map { "\($0) \(f.symbolName ?? "")" } ?? f.kind.label
                named[k].name = "\(base) \(list.filter { $0.symbolCode == f.symbolCode && $0.kind == f.kind }.count + k)"
            }
            list.replaceSubrange(i...i, with: named)
        }
        selectedFeatureID = parts.first?.id
        extraSelectedIDs = selectAll ? Set(parts.dropFirst().map(\.id)) : []
        selectedNodeIndex = nil
    }

    // MARK: Scale

    /// While the slider is dragged: scale from the original shape `original` (not cumulative), without undo.
    func scaleLive(_ original: Feature, by k: Double) {
        guard let c = original.rotationPivot else { return }
        updateFeatureLive(original.scaled(by: k, around: c))
    }

    func scaleSelected(by k: Double) {
        guard let f = selectedFeature, !f.isLocked, let c = f.rotationPivot else { return }
        updateFeature(f.id) { $0 = $0.scaled(by: k, around: c) }
    }

    // MARK: Parallel (OCAD Move parallel)

    enum ParallelSide: String, CaseIterable, Identifiable {
        case left = "Left", right = "Right", both = "Both sides"
        var id: String { rawValue }
    }

    /// Parallel line/area at a distance of `meters`. `copy`: make a copy (original line stays); otherwise move the object.
    /// Left/right side follows the line's drawing direction; for areas: left = inward, right = outward.
    func parallelSelected(meters: Double, side: ParallelSide, copy: Bool) {
        guard let f = selectedFeature, !f.isLocked, f.kind != .point, meters > 0 else { return }
        // Area: point order may be clockwise; normalize so that left = inward.
        let sign: Double = f.kind == .area && f.signedArea < 0 ? -1 : 1
        let offsets: [Double]
        switch side {
        case .left: offsets = [meters * sign]
        case .right: offsets = [-meters * sign]
        case .both: offsets = [meters * sign, -meters * sign]
        }
        var made: [Feature] = []
        editFeatures { list in
            guard let i = list.firstIndex(where: { $0.id == f.id }) else { return }
            if copy || side == .both {
                for (k, d) in offsets.enumerated() {
                    var c = f.parallel(offset: d)
                    c.id = UUID()
                    c.createdAt = Date()
                    c.name = f.name.isEmpty ? "" : "\(f.name) parallel\(offsets.count > 1 ? " \(k + 1)" : "")"
                    made.append(c)
                }
                if !copy { list.remove(at: i) }
                list.insert(contentsOf: made, at: copy ? i + 1 : i)
            } else {
                list[i] = f.parallel(offset: offsets[0])
            }
        }
        if let first = made.first, !copy { selectedFeatureID = first.id }
        let distance = Fmt.meters(meters, decimals: meters < 10 ? 1 : 0)
        notice = copy ? "\(made.count) parallel lines created, \(distance) from the original." : "Object moved parallel by \(distance)."
    }

    // MARK: Reverse direction

    func reverseSelected() {
        guard let f = selectedFeature, !f.isLocked, f.kind == .line else { return }
        updateFeature(f.id) { $0.reverse() }
        notice = "Line direction reversed (important for cliffs, fences, and other directional symbols)."
    }
}
