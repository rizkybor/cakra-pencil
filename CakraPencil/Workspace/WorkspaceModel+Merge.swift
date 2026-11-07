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

    /// Gabung otomatis garis: ujung yang bertumpuk (dalam selebar garisnya, min. 0,5 mm dan maks. 1,5 mm di
    /// kertas) ikut disambung, tidak hanya yang di-snap persis.
    private func autoJoinGapM(_ id: UUID, in list: [Feature]) -> Double {
        guard let f = list.first(where: { $0.id == id }), f.kind == .line else { return snapToleranceM }
        return project.sheet.groundMeters(forPaperMM: min(max(f.widthMM, 0.5), 1.5))
    }

    private func allowed(_ o: Feature, _ among: Set<UUID>?) -> Bool { among?.contains(o.id) ?? true }

    private func mergeable(_ f: Feature, with o: Feature) -> Bool {
        o.isVisible && !o.isLocked && f.canMerge(with: o)
    }

    /// Gabung otomatis objek `id` dengan objek yang ditempelkan padanya. Objek yang lebih dulu ada
    /// mempertahankan identitas dan posisi urutnya. Kembalikan id objek hasil.
    @discardableResult
    func autoMerged(_ id: UUID, in list: inout [Feature]) -> UUID {
        let r = merge(id, in: &list, lineGap: autoJoinGapM(id, in: list), allowOverlap: false, keepOlder: true)
        if r.count > 0 { notice = "Digabung dengan \(r.count) objek bersimbol sama." } else if r.closed { notice = "Ujung garis disatukan: garis tertutup." }
        return r.id
    }

    /// Inti penggabungan: ulangi sampai tidak ada lagi pasangan (garis bisa tersambung di kedua ujung).
    private func merge(_ id: UUID, in list: inout [Feature], lineGap: Double, allowOverlap: Bool,
                       keepOlder: Bool, among: Set<UUID>? = nil) -> (id: UUID, count: Int, flattened: Bool, holes: Bool, closed: Bool) {
        var current = id, count = 0, flattened = false, holes = false, closedRing = false
        for _ in 0..<64 {
            guard let i = list.firstIndex(where: { $0.id == current }), !list[i].isLocked else { break }
            let f = list[i]
            var found: (index: Int, merged: Feature)?
            switch f.kind {
            case .line:
                // Ujung garis yang bertumpuk dengan ujung awalnya sendiri: tutup garisnya.
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
        return (current, count, flattened, holes, closedRing)
    }

    // MARK: Tombol Gabungkan

    /// Jumlah objek yang mungkin digabung dengan objek terpilih (cek cepat untuk menampilkan tombol).
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

    /// Gabung objek terpilih dengan semua objek bersimbol sama yang tersambung/bersentuhan (satu langkah undo).
    func mergeSelected() {
        guard let f = selectedFeature, !f.isLocked else { return }
        var result: (id: UUID, count: Int, flattened: Bool, holes: Bool, closed: Bool) = (f.id, 0, false, false, false)
        editFeatures { list in
            result = merge(f.id, in: &list, lineGap: manualJoinGapM, allowOverlap: true, keepOlder: false)
        }
        selectedFeatureID = result.id
        selectedNodeIndex = nil
        if result.count == 0, result.closed {
            notice = "Ujung garis disatukan: garis tertutup."
            return
        }
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

    // MARK: Gabungkan pilihan banyak

    /// Jenis objek terpilih yang bersimbol sama dan bertemu: garis (ujung berdekatan → Join) dan/atau
    /// area (bersentuhan → Gabungkan). Kosong = tidak ada yang bisa digabung.
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

    /// Gabung objek-objek terpilih yang bertemu, hanya dengan sesama objek terpilih (satu langkah undo).
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
            notice = "Tidak ada objek terpilih bersimbol sama yang bertemu."
            return
        }
        var parts = ["\(before) objek digabung jadi \(after)"]
        if flattened { parts.append("kurva di area yang tumpang tindih jadi titik lurus") }
        if holes { parts.append("lubang di tengah tidak disimpan") }
        notice = parts.joined(separator: " · ") + "."
    }

    // MARK: Edit titik

    /// Akhir geser titik: titik ujung garis yang ditempel ke ujung garis lain (atau titik area yang membuat
    /// sisi bersama) langsung digabung, dalam satu langkah undo dengan geseran titiknya.
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
        if merged > 0 { notice = "Digabung dengan \(merged) objek bersimbol sama." } else if closed { notice = "Ujung garis disatukan: garis tertutup." }
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
