import CakraCore
import Foundation

/// Gabung objek, seperti OCAD (Merge) / OOM (Connect paths, Unify areas):
/// - Otomatis: ujung garis yang ditempelkan (snap) ke ujung garis bersimbol sama langsung menyatu; area yang
///   sisinya ditempelkan ke area bersimbol sama (≥ 2 titik di-snap) menyatu jadi satu area.
/// - Manual (tombol Gabungkan): garis dengan celah kecil di ujungnya, dan area yang bersentuhan atau
///   tumpang tindih.
extension WorkspaceModel {
    /// Titik yang di-snap berimpit persis; sedikit kelonggaran untuk pembulatan.
    private var snapToleranceM: Double { 0.01 }
    /// Celah ujung garis yang masih disambung tombol Gabungkan (2 mm di kertas).
    var manualJoinGapM: Double { project.sheet.groundMeters(forPaperMM: 2) }
    private var flattenToleranceM: Double { project.sheet.groundMeters(forPaperMM: 0.05) }

    private func mergeable(_ f: Feature, with o: Feature) -> Bool {
        o.isVisible && !o.isLocked && f.canMerge(with: o)
    }

    /// Gabung otomatis objek `id` dengan objek yang ditempelkan padanya. Objek yang lebih dulu ada
    /// mempertahankan identitas dan posisi urutnya. Kembalikan id objek hasil.
    @discardableResult
    func autoMerged(_ id: UUID, in list: inout [Feature]) -> UUID {
        let r = merge(id, in: &list, lineGap: snapToleranceM, allowOverlap: false, keepOlder: true)
        if r.count > 0 { notice = "Digabung dengan \(r.count) objek bersimbol sama." }
        return r.id
    }

    /// Inti penggabungan: ulangi sampai tidak ada lagi pasangan (garis bisa tersambung di kedua ujung).
    private func merge(_ id: UUID, in list: inout [Feature], lineGap: Double, allowOverlap: Bool,
                       keepOlder: Bool) -> (id: UUID, count: Int, flattened: Bool, holes: Bool) {
        var current = id, count = 0, flattened = false, holes = false
        for _ in 0..<64 {
            guard let i = list.firstIndex(where: { $0.id == current }), !list[i].isLocked else { break }
            let f = list[i]
            var found: (index: Int, merged: Feature)?
            switch f.kind {
            case .line:
                let candidates = list.indices
                    .filter { mergeable(f, with: list[$0]) && f.endpointGap(to: list[$0]) <= lineGap }
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
                for k in list.indices where mergeable(f, with: list[k]) {
                    let o = list[k]
                    guard let ob = o.bounds, ob.intersects(b) else { continue }
                    let older = keepOlder && o.createdAt < f.createdAt
                    let r = older
                        ? o.unitingArea(f, vertexTolerance: snapToleranceM, flattenTolerance: flattenToleranceM, allowOverlap: allowOverlap)
                        : f.unitingArea(o, vertexTolerance: snapToleranceM, flattenTolerance: flattenToleranceM, allowOverlap: allowOverlap)
                    if let r {
                        found = (k, r.feature)
                        flattened = flattened || r.flattenedCurves
                        holes = holes || r.droppedHoles
                        break
                    }
                }
            case .point:
                break
            }
            guard let (k, merged) = found else { break }
            // Hasil menempati posisi urut objek yang identitasnya dipakai; objek satunya dihapus.
            let keep = merged.id == f.id ? i : k, drop = keep == i ? k : i
            list[keep] = merged
            list.remove(at: drop)
            current = merged.id
            count += 1
        }
        return (current, count, flattened, holes)
    }

    // MARK: Tombol Gabungkan

    /// Jumlah objek yang mungkin digabung dengan objek terpilih (cek cepat untuk menampilkan tombol).
    var mergeCandidateCount: Int {
        guard let f = selectedFeature, !f.isLocked, f.kind != .point else { return 0 }
        switch f.kind {
        case .line:
            let gap = manualJoinGapM
            return features.filter { mergeable(f, with: $0) && f.endpointGap(to: $0) <= gap }.count
        case .area:
            guard let b = f.bounds?.insetBy(-snapToleranceM) else { return 0 }
            return features.filter { mergeable(f, with: $0) && ($0.bounds.map { $0.intersects(b) } ?? false) }.count
        case .point:
            return 0
        }
    }

    /// Gabung objek terpilih dengan semua objek bersimbol sama yang tersambung/bersentuhan (satu langkah undo).
    func mergeSelected() {
        guard let f = selectedFeature, !f.isLocked else { return }
        var result: (id: UUID, count: Int, flattened: Bool, holes: Bool) = (f.id, 0, false, false)
        editFeatures { list in
            result = merge(f.id, in: &list, lineGap: manualJoinGapM, allowOverlap: true, keepOlder: false)
        }
        selectedFeatureID = result.id
        selectedNodeIndex = nil
        guard result.count > 0 else {
            notice = f.kind == .line
                ? "Tidak ada ujung garis bersimbol sama dalam jarak 2 mm (di kertas)."
                : "Tidak ada area bersimbol sama yang bersentuhan atau tumpang tindih."
            return
        }
        var parts = ["\(result.count + 1) objek digabung jadi satu"]
        if result.flattened { parts.append("kurva di area yang tumpang tindih jadi titik lurus") }
        if result.holes { parts.append("lubang di tengah tidak disimpan") }
        notice = parts.joined(separator: " · ") + "."
    }

    // MARK: Edit titik

    /// Akhir geser titik: titik ujung garis yang ditempel ke ujung garis lain (atau titik area yang membuat
    /// sisi bersama) langsung digabung, dalam satu langkah undo dengan geseran titiknya.
    func commitNodeEdit(from before: [Feature], featureID: UUID) {
        var merged = 0
        if autoMerge, let i = features.firstIndex(where: { $0.id == featureID }), features[i].kind != .point {
            var list = features
            let id = merge(featureID, in: &list, lineGap: snapToleranceM, allowOverlap: false, keepOlder: true)
            if id.count > 0 {
                setFeaturesForMerge(list)
                selectedFeatureID = id.id
                selectedNodeIndex = nil
                merged = id.count
            }
        }
        commitFeatureEdit(from: before)
        if merged > 0 { notice = "Digabung dengan \(merged) objek bersimbol sama." }
    }
}

// MARK: - Isi garis dengan area (OCAD Fill)

extension WorkspaceModel {
    /// Buat area bersimbol `s` dari bentuk garis terpilih; garisnya tetap dan tetap terpilih. Area diletakkan
    /// tepat di bawah garis agar garis tepi tetap terlihat di atas isinya. Satu langkah undo.
    func fillSelected(with s: MapSymbol) {
        guard let line = selectedFeature, !line.isLocked else { return }
        let tolerance = project.sheet.groundMeters(forPaperMM: 0.3)
        guard var area = line.filledArea(with: s, closeTolerance: tolerance) else {
            notice = "Hanya garis dengan minimal 3 titik yang bisa diisi area."
            return
        }
        let n = features.filter { $0.symbolCode == s.code }.count + 1
        area.name = "\(s.code) \(s.name) \(n)"
        editFeatures { list in
            let i = list.firstIndex { $0.id == line.id } ?? list.count
            list.insert(area, at: i)
        }
        notice = line.isClosedLine(tolerance: tolerance)
            ? "Diisi \(s.code) \(s.name); garis \(line.symbolCode ?? "") tetap."
            : "Garis belum tertutup: area ditutup lurus dari ujung ke ujung. Garis tetap."
    }
}
