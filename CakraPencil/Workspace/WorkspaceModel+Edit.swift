import CakraCore
import Foundation

/// Alat edit objek seperti OCAD: tambah titik (reshape), potong garis/area, skala, garis paralel, balik arah.
/// Rotasi, geser/hapus titik, dan gabung ada di WorkspaceModel / WorkspaceModel+Merge.
extension WorkspaceModel {
    // MARK: Reshape: tambah titik

    /// Tambah titik di garis tepi objek terpilih, di posisi terdekat `p` (bentuk tidak berubah).
    func insertNode(near p: Point2D) {
        guard let f = selectedFeature, !f.isLocked, let r = f.nearestPathPosition(to: p) else { return }
        var index: Int?
        updateFeature(f.id) { index = $0.insertNode(at: r.position) }
        if let index { selectedNodeIndex = index } else { notice = "Titik sudah ada di situ." }
    }

    // MARK: Potong (OCAD Cut)

    func startCut() {
        guard let f = selectedFeature, !f.isLocked, f.kind != .point else { return }
        cutMode = true
        cutStart = nil
        selectedNodeIndex = nil
    }

    func cancelCut() {
        cutMode = false
        cutStart = nil
    }

    /// Ketukan alat Potong di posisi path objek terpilih. Garis: langsung dipotong jadi dua. Area: ketukan
    /// pertama = titik awal garis potong, ketukan kedua = belah area jadi dua.
    func cutSelected(at pos: PathPosition) {
        guard let f = selectedFeature, !f.isLocked else { return cancelCut() }
        switch f.kind {
        case .line:
            guard let (a, b) = f.splitLine(at: pos) else {
                notice = "Ketuk di tengah garis, bukan di ujungnya."
                return
            }
            replace(f, with: [a, b])
            notice = "Garis dipotong jadi dua."
            cancelCut()
        case .area:
            guard let start = cutStart else {
                cutStart = pos
                return
            }
            guard let (a, b) = f.splitArea(from: start, to: pos) else {
                notice = "Titik kedua harus di sisi lain area."
                cutStart = nil
                return
            }
            replace(f, with: [a, b])
            notice = "Area dibelah jadi dua."
            cancelCut()
        case .point:
            cancelCut()
        }
    }

    /// Ganti satu objek dengan beberapa bagian di posisi urut yang sama (bagian baru diberi nama berurutan).
    private func replace(_ f: Feature, with parts: [Feature]) {
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
        selectedNodeIndex = nil
    }

    // MARK: Skala

    /// Selama slider digeser: skala dari bentuk awal `original` (bukan kumulatif), tanpa undo.
    func scaleLive(_ original: Feature, by k: Double) {
        guard let c = original.rotationPivot else { return }
        updateFeatureLive(original.scaled(by: k, around: c))
    }

    func scaleSelected(by k: Double) {
        guard let f = selectedFeature, !f.isLocked, let c = f.rotationPivot else { return }
        updateFeature(f.id) { $0 = $0.scaled(by: k, around: c) }
    }

    // MARK: Paralel (OCAD Move parallel)

    enum ParallelSide: String, CaseIterable, Identifiable {
        case left = "Kiri", right = "Kanan", both = "Kedua sisi"
        var id: String { rawValue }
    }

    /// Garis/area sejajar sejauh `meters`. `copy`: buat salinan (garis asli tetap); selain itu geser objeknya.
    /// Sisi kiri/kanan mengikuti arah gambar garis; untuk area: kiri = ke dalam, kanan = ke luar.
    func parallelSelected(meters: Double, side: ParallelSide, copy: Bool) {
        guard let f = selectedFeature, !f.isLocked, f.kind != .point, meters > 0 else { return }
        // Area: arah titik bisa searah jarum jam; normalkan agar kiri = ke dalam.
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
                    c.name = f.name.isEmpty ? "" : "\(f.name) paralel\(offsets.count > 1 ? " \(k + 1)" : "")"
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
        notice = copy ? "\(made.count) garis paralel dibuat, \(distance) dari aslinya." : "Objek digeser sejajar \(distance)."
    }

    // MARK: Balik arah

    func reverseSelected() {
        guard let f = selectedFeature, !f.isLocked, f.kind == .line else { return }
        updateFeature(f.id) { $0.reverse() }
        notice = "Arah garis dibalik (penting untuk tebing, pagar, dan simbol berarah lain)."
    }
}
