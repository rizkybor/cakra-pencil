import CakraCore
import Foundation

/// Select multiple objects (like OCAD/OOM: Shift + click, selection box, Select all) and duplicate.
/// `selectedFeatureID` stays the primary object (point editing, properties panel); `extraSelectedIDs` are the other selected objects.
extension WorkspaceModel {
    /// All selected ids (primary + extra).
    var selectedIDs: Set<UUID> {
        var ids = extraSelectedIDs
        if let id = selectedFeatureID { ids.insert(id) }
        return ids
    }

    /// Selected objects, in drawing order.
    var selection: [Feature] {
        let ids = selectedIDs
        guard !ids.isEmpty else { return [] }
        return features.filter { ids.contains($0.id) }
    }

    /// More than one object selected: point/shape editing is disabled; move, duplicate, and delete are available.
    var isMultiSelection: Bool { selectedFeatureID != nil && !extraSelectedIDs.isEmpty }

    func isSelected(_ id: UUID) -> Bool { selectedFeatureID == id || extraSelectedIDs.contains(id) }

    /// Add an object to the selection, or deselect it if already selected.
    func toggleSelection(_ f: Feature) {
        selectedNodeIndex = nil
        cutMode = false
        if selectedFeatureID == f.id {
            // Deselect the primary object: the next extra object becomes primary.
            let next = features.first { extraSelectedIDs.contains($0.id) }
            selectedFeatureID = next?.id
            if let next { extraSelectedIDs.remove(next.id) }
        } else if extraSelectedIDs.contains(f.id) {
            extraSelectedIDs.remove(f.id)
        } else if selectedFeatureID == nil {
            select(f)
        } else {
            extraSelectedIDs.insert(f.id)
        }
    }

    /// Replace/extend the selection with these objects (selection box). Locked/hidden objects are skipped.
    func addToSelection(_ list: [Feature]) {
        let usable = list.filter { $0.isVisible && !$0.isLocked }
        guard !usable.isEmpty else { return }
        selectedNodeIndex = nil
        for f in usable where !isSelected(f.id) {
            if selectedFeatureID == nil { selectedFeatureID = f.id } else { extraSelectedIDs.insert(f.id) }
        }
    }

    /// Select all visible, unlocked objects.
    func selectAll() {
        let usable = features.filter { $0.isVisible && !$0.isLocked }
        guard let first = usable.last else { return }
        tool = .select
        selectedFeatureID = first.id
        selectedNodeIndex = nil
        extraSelectedIDs = Set(usable.dropLast().map(\.id))
    }

    // MARK: Move together

    /// During a drag: all selected objects (original shapes `originals`) are moved by `d`, without undo.
    func moveSelectionLive(_ originals: [Feature], by d: Point2D) {
        for o in originals where !o.isLocked {
            var f = o
            f.nodes = o.nodes.map { $0.moved(by: d) }
            updateFeatureLive(f)
        }
    }

    // MARK: Duplicate / delete

    /// Offset of the copy from the original: 3 mm on paper to the lower right, so the copy is visible right away.
    var duplicateOffset: Point2D {
        let m = project.sheet.groundMeters(forPaperMM: 3)
        return Point2D(x: m, y: -m)
    }

    /// Duplicate the selected objects (one undo step). Copies are placed right above the originals and become the new selection.
    func duplicateSelection() {
        let originals = selection
        guard !originals.isEmpty else { return }
        let d = duplicateOffset
        var copies: [Feature] = []
        editFeatures { list in
            // From the back so the insertion indices stay correct.
            for o in originals.reversed() {
                guard let i = list.firstIndex(where: { $0.id == o.id }) else { continue }
                var c = o
                c.id = UUID()
                c.createdAt = Date()
                c.isLocked = false
                c.name = o.displayName + " copy"
                c.nodes = o.nodes.map { $0.moved(by: d) }
                list.insert(c, at: i + 1)
                copies.insert(c, at: 0)
            }
        }
        guard let first = copies.first else { return }
        tool = .select
        selectedFeatureID = first.id
        selectedNodeIndex = nil
        extraSelectedIDs = Set(copies.dropFirst().map(\.id))
        notice = copies.count == 1 ? "\(originals[0].displayName) duplicated." : "\(copies.count) objects duplicated."
    }

    /// Delete all selected objects (one undo step).
    func deleteSelection() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        editFeatures { $0.removeAll { ids.contains($0.id) } }
        deselect()
        if ids.count > 1 { notice = "\(ids.count) objects deleted." }
    }
}
