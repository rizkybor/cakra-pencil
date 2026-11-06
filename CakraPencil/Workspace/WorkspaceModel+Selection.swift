import CakraCore
import Foundation

/// Pilih banyak objek (seperti OCAD/OOM: Shift + klik, kotak pilih, Pilih semua) dan duplikat.
/// `selectedFeatureID` tetap objek utama (edit titik, panel properti); `extraSelectedIDs` objek lain yang ikut.
extension WorkspaceModel {
    /// Semua id terpilih (utama + tambahan).
    var selectedIDs: Set<UUID> {
        var ids = extraSelectedIDs
        if let id = selectedFeatureID { ids.insert(id) }
        return ids
    }

    /// Objek terpilih, urut sesuai urutan gambar.
    var selection: [Feature] {
        let ids = selectedIDs
        guard !ids.isEmpty else { return [] }
        return features.filter { ids.contains($0.id) }
    }

    /// Lebih dari satu objek terpilih: edit titik/bentuk dimatikan, yang tersedia geser, duplikat, hapus.
    var isMultiSelection: Bool { selectedFeatureID != nil && !extraSelectedIDs.isEmpty }

    func isSelected(_ id: UUID) -> Bool { selectedFeatureID == id || extraSelectedIDs.contains(id) }

    /// Tambah objek ke pilihan, atau lepas bila sudah terpilih.
    func toggleSelection(_ f: Feature) {
        selectedNodeIndex = nil
        cutMode = false
        if selectedFeatureID == f.id {
            // Lepas objek utama: objek tambahan berikutnya jadi utama.
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

    /// Ganti/tambah pilihan dengan objek-objek ini (kotak pilih). Objek terkunci/tersembunyi dilewati.
    func addToSelection(_ list: [Feature]) {
        let usable = list.filter { $0.isVisible && !$0.isLocked }
        guard !usable.isEmpty else { return }
        selectedNodeIndex = nil
        for f in usable where !isSelected(f.id) {
            if selectedFeatureID == nil { selectedFeatureID = f.id } else { extraSelectedIDs.insert(f.id) }
        }
    }

    /// Pilih semua objek yang tampil dan tidak terkunci.
    func selectAll() {
        let usable = features.filter { $0.isVisible && !$0.isLocked }
        guard let first = usable.last else { return }
        tool = .select
        selectedFeatureID = first.id
        selectedNodeIndex = nil
        extraSelectedIDs = Set(usable.dropLast().map(\.id))
    }

    // MARK: Geser bersama

    /// Selama drag: semua objek terpilih (bentuk awal `originals`) digeser `d`, tanpa undo.
    func moveSelectionLive(_ originals: [Feature], by d: Point2D) {
        for o in originals where !o.isLocked {
            var f = o
            f.nodes = o.nodes.map { $0.moved(by: d) }
            updateFeatureLive(f)
        }
    }

    // MARK: Duplikat / hapus

    /// Jarak salinan dari aslinya: 3 mm di kertas ke kanan bawah, agar salinan langsung terlihat.
    var duplicateOffset: Point2D {
        let m = project.sheet.groundMeters(forPaperMM: 3)
        return Point2D(x: m, y: -m)
    }

    /// Duplikat objek terpilih (satu langkah undo). Salinan ditaruh tepat di atas aslinya dan jadi pilihan baru.
    func duplicateSelection() {
        let originals = selection
        guard !originals.isEmpty else { return }
        let d = duplicateOffset
        var copies: [Feature] = []
        editFeatures { list in
            // Dari belakang agar indeks sisipan tetap benar.
            for o in originals.reversed() {
                guard let i = list.firstIndex(where: { $0.id == o.id }) else { continue }
                var c = o
                c.id = UUID()
                c.createdAt = Date()
                c.isLocked = false
                c.name = o.displayName + " salinan"
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
        notice = copies.count == 1 ? "\(originals[0].displayName) diduplikat." : "\(copies.count) objek diduplikat."
    }

    /// Hapus semua objek terpilih (satu langkah undo).
    func deleteSelection() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        editFeatures { $0.removeAll { ids.contains($0.id) } }
        deselect()
        if ids.count > 1 { notice = "\(ids.count) objek dihapus." }
    }
}
