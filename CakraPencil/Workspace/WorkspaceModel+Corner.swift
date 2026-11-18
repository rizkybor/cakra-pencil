import CakraCore
import Foundation

/// Corner Tool session of one object (like Affinity Designer's Corner Tool): the object's shape with its corners still
/// sharp, the radius given to each corner, and the selected corners. The map shows `result`; the handles sit on the
/// sharp corners of `base`, so a rounded corner can be changed again (or set back to 0) as long as the session lives.
struct CornerEdit: Equatable {
    /// The object with its corners sharp. Corners are Node Tool indices of `base.allNodes` (holes included).
    var base: Feature
    /// Requested radius per corner (metres on the ground). The geometry clamps it where the edges are too short.
    var radii: [Int: Double] = [:]
    var selected: Set<Int> = []
    var style: CornerStyle = .rounded
    /// `base` with the roundings applied: what the object on the map looks like while this session is valid.
    private(set) var result: Feature

    init(base: Feature, style: CornerStyle) {
        self.base = base
        self.style = style
        result = base
    }

    /// Selected corners that can be rounded (not line ends, not straight-through or smooth nodes).
    var roundableSelection: [Int] { selected.sorted().filter { base.corner(at: $0) != nil } }

    /// Every selected corner gets radius `r`.
    mutating func setRadius(_ r: Double) {
        for i in roundableSelection { radii[i] = r > 0 ? r : nil }
        update()
    }

    mutating func setStyle(_ s: CornerStyle) {
        style = s
        update()
    }

    private mutating func update() {
        result = base.roundingCorners(radii: radii, style: style)
    }
}

/// How a corner selection (tap, box, lasso, polygon) combines with the current one.
enum CornerSelectMode {
    case replace, add, remove, toggle
}

extension WorkspaceModel {
    /// The session for object `id`: the stored one while the object still looks as the session left it; otherwise
    /// (first use, undo, an edit with another tool) a fresh one that takes the current shape as sharp.
    func cornerEdit(for id: UUID) -> CornerEdit? {
        guard let f = features.first(where: { $0.id == id }), f.kind != .point, f.isVisible, !f.isLocked else { return nil }
        if let e = cornerLive?[id], e.result == f { return e }
        if let e = cornerEdits[id], e.result == f { return e }
        return CornerEdit(base: f, style: cornerStyle)
    }

    /// Sessions of the selected objects (lines and areas), in drawing order.
    var cornerSessions: [(id: UUID, edit: CornerEdit)] {
        selection.compactMap { f in cornerEdit(for: f.id).map { (f.id, $0) } }
    }

    /// Number of selected corners that can be rounded, over all selected objects.
    var selectedCornerCount: Int { cornerSessions.reduce(0) { $0 + $1.edit.roundableSelection.count } }

    /// Radius of the selected corners (the first one's when they differ; 0 when none is rounded yet).
    var selectedCornerRadius: Double {
        for (_, e) in cornerSessions {
            for i in e.roundableSelection { return e.radii[i] ?? 0 }
        }
        return 0
    }

    /// Largest radius any selected corner can take (half of its shorter edge, through its angle).
    var selectedCornerMaxRadius: Double {
        cornerSessions.flatMap { s in s.edit.roundableSelection.compactMap { s.edit.base.corner(at: $0)?.maxRadius } }.max() ?? 0
    }

    /// Click on an object: select it (Shift: add it / remove it) with all its corners.
    func cornerSelectObject(_ f: Feature, additive: Bool) {
        if additive {
            toggleSelection(f)
        } else if !(selectedFeatureID == f.id && !isMultiSelection) {
            select(f)
        }
        pruneCornerEdits()
        guard isSelected(f.id), var e = cornerEdit(for: f.id) else { return }
        e.selected = Set(e.base.roundableCornerIndices)
        cornerEdits[f.id] = e
    }

    /// Change the corner selection: `hits` = corners (base node indices) per object, combined by `mode`. Objects not in
    /// `hits` lose their corner selection on `replace`.
    func selectCorners(_ hits: [UUID: Set<Int>], mode: CornerSelectMode) {
        // Objects hit while nothing (or something else) was selected become selected.
        for id in hits.keys where !isSelected(id) && !(hits[id]?.isEmpty ?? true) {
            if let f = features.first(where: { $0.id == id }) {
                if selectedFeatureID == nil { select(f) } else { extraSelectedIDs.insert(f.id) }
            }
        }
        pruneCornerEdits()
        var next = cornerEdits
        for id in selectedIDs {
            guard var e = cornerEdit(for: id) else { continue }
            let h = hits[id] ?? []
            switch mode {
            case .replace: e.selected = h
            case .add: e.selected.formUnion(h)
            case .remove: e.selected.subtract(h)
            case .toggle: e.selected.formSymmetricDifference(h)
            }
            next[id] = e
        }
        cornerEdits = next
    }

    func selectAllCorners() {
        var next: [UUID: CornerEdit] = [:]
        for (id, var e) in cornerSessions {
            e.selected = Set(e.base.roundableCornerIndices)
            next[id] = e
        }
        cornerEdits = next
    }

    /// Sessions of objects that are no longer selected are dropped (their roundings stay on the map, now sharp nodes
    /// of the shape).
    func pruneCornerEdits() {
        let ids = selectedIDs
        if cornerEdits.keys.contains(where: { !ids.contains($0) }) { cornerEdits = cornerEdits.filter { ids.contains($0.key) } }
    }

    /// Current sessions of the selected objects that have corners selected (the start of a radius change).
    var cornerEditsForRadius: [UUID: CornerEdit] {
        Dictionary(uniqueKeysWithValues: cornerSessions.filter { !$0.edit.roundableSelection.isEmpty }.map { ($0.id, $0.edit) })
    }

    /// During a drag: every selected corner gets radius `r` (from the sessions `start`), shown on the map without undo.
    func setCornerRadiusLive(_ r: Double, from start: [UUID: CornerEdit]) {
        var live = cornerLive ?? cornerEdits
        for (id, var e) in start {
            e.setRadius(max(0, r))
            updateFeatureLive(e.result)
            live[id] = e
        }
        cornerLive = live
    }

    /// A radius drag that turned into a two-finger map gesture: the objects go back to how they were.
    func cancelCornerRadiusLive(from start: [UUID: CornerEdit]) {
        for e in start.values { updateFeatureLive(e.result) }
        cornerLive = nil
    }

    /// End of a drag: keep radius `r` in the sessions and record one undo step from `before`.
    func commitCornerRadius(_ r: Double, from start: [UUID: CornerEdit], before: [Feature]) {
        var next = cornerEdits
        for (id, var e) in start {
            e.setRadius(max(0, r))
            updateFeatureLive(e.result)
            next[id] = e
        }
        cornerLive = nil
        cornerEdits = next
        commitFeatureEdit(from: before)
    }

    /// Radius typed in the contextual bar (Apply): one undo step.
    func applyCornerRadius(_ r: Double) {
        let start = cornerEditsForRadius
        guard !start.isEmpty else { return }
        commitCornerRadius(r, from: start, before: features)
    }

    /// Radius slider: live while dragging, one undo step when released.
    func cornerSliderChanged(_ r: Double) {
        if cornerLiveStart == nil { cornerLiveStart = (cornerEditsForRadius, features) }
        guard let s = cornerLiveStart else { return }
        setCornerRadiusLive(r, from: s.edits)
    }

    func cornerSliderEnded(_ r: Double) {
        guard let s = cornerLiveStart else { return }
        cornerLiveStart = nil
        commitCornerRadius(r, from: s.edits, before: s.features)
    }

    /// Rounded ↔ Straight (chamfer) for the selected objects: their corners are redrawn (one undo step).
    func setCornerStyle(_ style: CornerStyle) {
        cornerStyle = style
        let before = features
        var next = cornerEdits
        for (id, var e) in cornerSessions {
            e.setStyle(style)
            updateFeatureLive(e.result)
            next[id] = e
        }
        cornerEdits = next
        commitFeatureEdit(from: before)
    }
}

#if DEBUG
extension WorkspaceModel {
    /// `-cp-corner-demo`: a square area in the middle of the frame, Corner Tool on, its top-right corner selected and
    /// rounded (screenshots of the Corner Tool without UI automation). Uses the active symbol when it is an area symbol.
    func debugCornerDemo() async {
        guard project.areaLocked, let e = frame?.extent else { return }
        let cx = (e.minX + e.maxX) / 2, cy = (e.minY + e.maxY) / 2, h = (e.maxX - e.minX) / 12
        let corners = [Point2D(x: cx - h, y: cy + h), Point2D(x: cx + h, y: cy + h), Point2D(x: cx + h, y: cy - h), Point2D(x: cx - h, y: cy - h)]
        var f = Feature.rectangle(corners: corners, colorHex: pen.colorHex, widthMM: pen.widthMM)
        if activeSymbol?.kind == .area { stampActiveSymbol(&f) }
        addFeature(f)
        tool = .corner
        cornerSelectObject(f, additive: false)
        selectCorners([f.id: [1]], mode: .replace)   // top-right corner
        applyCornerRadius(h * 0.6)
        try? await Task.sleep(for: .seconds(3))
        mapCommand = MapCommand(kind: .zoomToExtent(Rect2D(minX: cx - 1.6 * h, minY: cy - 1.6 * h, maxX: cx + 1.6 * h, maxY: cy + 1.6 * h)))
    }
}
#endif
