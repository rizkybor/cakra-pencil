import CakraCore
import Foundation

/// Merge objects, like OCAD (Merge) / OOM (Connect paths, Unify areas):
/// - Automatic: a line end snapped to the end of a line with the same symbol joins immediately; an area whose
///   side is snapped to an area with the same symbol (≥ 2 snapped points) merges into one area.
/// - Manual (Merge button): lines with a small gap at their ends, and areas that touch or
///   overlap.
extension WorkspaceModel {
    /// Snapped points coincide exactly; a little tolerance for rounding.
    private var snapToleranceM: Double { 0.01 }
    /// Line end gap still joined by the Merge button (2 mm on paper).
    var manualJoinGapM: Double { project.sheet.groundMeters(forPaperMM: 2) }
    private var flattenToleranceM: Double { project.sheet.groundMeters(forPaperMM: 0.05) }

    /// Automatic line merge: ends that overlap (within the line width, min. 0.5 mm and max. 1.5 mm on
    /// paper) are joined too, not only exactly snapped ones.
    private func autoJoinGapM(_ id: UUID, in list: [Feature]) -> Double {
        guard let f = list.first(where: { $0.id == id }), f.kind == .line else { return snapToleranceM }
        return project.sheet.groundMeters(forPaperMM: min(max(f.widthMM, 0.5), 1.5))
    }

    private func allowed(_ o: Feature, _ among: Set<UUID>?) -> Bool { among?.contains(o.id) ?? true }

    private func mergeable(_ f: Feature, with o: Feature) -> Bool {
        o.isVisible && !o.isLocked && f.canMerge(with: o)
    }

    /// Automatically merge object `id` with the objects snapped to it. The object that existed first
    /// keeps its identity and order position. Returns the id of the resulting object.
    @discardableResult
    func autoMerged(_ id: UUID, in list: inout [Feature]) -> UUID {
        let r = merge(id, in: &list, lineGap: autoJoinGapM(id, in: list), allowOverlap: false, keepOlder: true)
        if r.count > 0 { notice = "Merged with \(r.count) objects with the same symbol." } else if r.closed { notice = "Line ends joined: line closed." }
        return r.id
    }

    /// Merge core: repeat until no pairs remain (a line can be joined at both ends).
    private func merge(_ id: UUID, in list: inout [Feature], lineGap: Double, allowOverlap: Bool,
                       keepOlder: Bool, among: Set<UUID>? = nil) -> (id: UUID, count: Int, flattened: Bool, holes: Bool, closed: Bool) {
        var current = id, count = 0, flattened = false, holes = false, closedRing = false
        for _ in 0..<64 {
            guard let i = list.firstIndex(where: { $0.id == current }), !list[i].isLocked else { break }
            let f = list[i]
            var found: (index: Int, merged: Feature)?
            switch f.kind {
            case .line:
                // Line end overlapping its own start: close the line.
                var closed = f
                if closed.closeLineIfEndsMeet(tolerance: lineGap) {
                    list[i] = closed
                    closedRing = true
                    continue
                }
                guard !f.isRingLine else { break }
                let candidates = list.indices
                    .filter { allowed(list[$0], among) && mergeable(f, with: list[$0]) && f.endpointGap(to: list[$0]) <= lineGap }
                    .sorted { f.endpointGap(to: list[$0]) < f.endpointGap(to: list[$1]) }
                for k in candidates {
                    let o = list[k]
                    let older = keepOlder && o.createdAt < f.createdAt
                    if let j = older ? o.joiningLine(f, tolerance: lineGap) : f.joiningLine(o, tolerance: lineGap) {
                        found = (k, j)
                        break
                    }
                }
            case .area:
                guard let b = f.bounds?.insetBy(-snapToleranceM) else { break }
                for k in list.indices where allowed(list[k], among) && mergeable(f, with: list[k]) {
                    let o = list[k]
                    guard let ob = o.bounds, ob.intersects(b) else { continue }
                    let older = keepOlder && o.createdAt < f.createdAt
                    let r = older
                        ? o.unitingArea(f, vertexTolerance: snapToleranceM, flattenTolerance: flattenToleranceM, allowOverlap: allowOverlap)
                        : f.unitingArea(o, vertexTolerance: snapToleranceM, flattenTolerance: flattenToleranceM, allowOverlap: allowOverlap)
                    if let r {
                        found = (k, r.feature)
                        flattened = flattened || r.flattenedCurves
                        holes = holes || r.formedHole
                        break
                    }
                }
            case .point:
                break
            }
            guard let (k, merged) = found else { break }
            // The result takes the order position of the object whose identity is kept; the other object is deleted.
            let keep = merged.id == f.id ? i : k, drop = keep == i ? k : i
            list[keep] = merged
            list.remove(at: drop)
            current = merged.id
            count += 1
        }
        return (current, count, flattened, holes, closedRing)
    }

    // MARK: Merge button

    /// Number of objects that could be merged with the selected object (quick check for showing the button).
    var mergeCandidateCount: Int {
        guard let f = selectedFeature, !f.isLocked, f.kind != .point else { return 0 }
        switch f.kind {
        case .line:
            let gap = manualJoinGapM
            var self_ = f
            let closes = self_.closeLineIfEndsMeet(tolerance: gap) ? 1 : 0
            return closes + features.filter { mergeable(f, with: $0) && f.endpointGap(to: $0) <= gap }.count
        case .area:
            guard let b = f.bounds?.insetBy(-snapToleranceM) else { return 0 }
            return features.filter { mergeable(f, with: $0) && ($0.bounds.map { $0.intersects(b) } ?? false) }.count
        case .point:
            return 0
        }
    }

    /// Merge the selected object with all connected/touching objects with the same symbol (one undo step).
    func mergeSelected() {
        guard let f = selectedFeature, !f.isLocked else { return }
        var result: (id: UUID, count: Int, flattened: Bool, holes: Bool, closed: Bool) = (f.id, 0, false, false, false)
        editFeatures { list in
            result = merge(f.id, in: &list, lineGap: manualJoinGapM, allowOverlap: true, keepOlder: false)
        }
        selectedFeatureID = result.id
        selectedNodeIndex = nil
        if result.count == 0, result.closed {
            notice = "Line ends joined: line closed."
            return
        }
        guard result.count > 0 else {
            notice = f.kind == .line
                ? "No line ends with the same symbol within 2 mm (on paper)."
                : "No areas with the same symbol touch or overlap."
            return
        }
        var parts = ["\(result.count + 1) objects merged into one"]
        if result.flattened { parts.append("curves in overlapping areas became straight points") }
        if result.holes { parts.append("the gap in the middle is kept as a hole") }
        notice = parts.joined(separator: " · ") + "."
    }

    // MARK: Merge multiple selection

    /// Kinds of selected objects with the same symbol that meet: lines (nearby ends → Join) and/or
    /// areas (touching → Merge). Empty = nothing can be merged.
    var selectionMergeKinds: Set<FeatureKind> {
        let sel = selection.filter { !$0.isLocked && $0.kind != .point }
        let gap = manualJoinGapM
        var kinds: Set<FeatureKind> = []
        for (n, f) in sel.enumerated() where !kinds.contains(f.kind) {
            for o in sel[(n + 1)...] where mergeable(f, with: o) {
                switch f.kind {
                case .line where f.endpointGap(to: o) <= gap: kinds.insert(.line)
                case .area:
                    if let a = f.bounds?.insetBy(-snapToleranceM), let b = o.bounds, a.intersects(b) { kinds.insert(.area) }
                default: break
                }
            }
        }
        return kinds
    }

    /// Merge the selected objects that meet, only with other selected objects (one undo step).
    func mergeSelection() {
        let ids = selectedIDs
        let before = ids.count
        var results: [UUID] = []
        var flattened = false, holes = false
        editFeatures { list in
            var remaining = list.filter { ids.contains($0.id) }.map(\.id)
            while let id = remaining.first {
                remaining.removeFirst()
                guard list.contains(where: { $0.id == id }) else { continue }
                let r = merge(id, in: &list, lineGap: manualJoinGapM, allowOverlap: true, keepOlder: false, among: ids)
                flattened = flattened || r.flattened
                holes = holes || r.holes
                results.append(r.id)
                let alive = Set(list.map(\.id))
                remaining.removeAll { !alive.contains($0) || $0 == r.id }
                results.removeAll { !alive.contains($0) }
            }
        }
        var unique: [UUID] = []
        for id in results where !unique.contains(id) { unique.append(id) }
        let after = unique.count
        selectedFeatureID = unique.first
        selectedNodeIndex = nil
        extraSelectedIDs = Set(unique.dropFirst())
        guard after < before else {
            notice = "No selected objects with the same symbol meet."
            return
        }
        var parts = ["\(before) objects merged into \(after)"]
        if flattened { parts.append("curves in overlapping areas became straight points") }
        if holes { parts.append("the gap in the middle is kept as a hole") }
        notice = parts.joined(separator: " · ") + "."
    }

    // MARK: Point editing

    /// End of a point move: a line end point snapped to the end of another line (or an area point that creates
    /// a shared side) is merged right away, in one undo step together with the point move.
    func commitNodeEdit(from before: [Feature], featureID: UUID) {
        var merged = 0, closed = false
        if autoMerge, let i = features.firstIndex(where: { $0.id == featureID }), features[i].kind != .point {
            var list = features
            let id = merge(featureID, in: &list, lineGap: autoJoinGapM(featureID, in: list), allowOverlap: false, keepOlder: true)
            if id.count > 0 || id.closed {
                setFeaturesForMerge(list)
                selectedFeatureID = id.id
                selectedNodeIndex = nil
                merged = id.count
                closed = id.closed
            }
        }
        commitFeatureEdit(from: before)
        if merged > 0 { notice = "Merged with \(merged) objects with the same symbol." } else if closed { notice = "Line ends joined: line closed." }
    }
}

// MARK: - Fill line with area (OCAD Fill)

extension WorkspaceModel {
    /// Create an area with symbol `s` from the selected line's shape; the line stays and remains selected. The area is placed
    /// right below the line so the outline stays visible above its fill. One undo step.
    func fillSelected(with s: MapSymbol) {
        guard let line = selectedFeature, !line.isLocked else { return }
        let tolerance = project.sheet.groundMeters(forPaperMM: 0.3)
        guard var area = line.filledArea(with: s, closeTolerance: tolerance) else {
            notice = "Only lines with at least 3 points can be filled with an area."
            return
        }
        let n = features.filter { $0.symbolCode == s.code }.count + 1
        area.name = "\(s.code) \(s.name) \(n)"
        editFeatures { list in
            let i = list.firstIndex { $0.id == line.id } ?? list.count
            list.insert(area, at: i)
        }
        notice = line.isClosedLine(tolerance: tolerance)
            ? "Filled with \(s.code) \(s.name); line \(line.symbolCode ?? "") kept."
            : "Line not closed: area closed straight from end to end. Line kept."
    }
}
