import CakraCore
import CoreLocation
import Foundation
import MapKit

/// Alat setelah area dikunci. Pemilihan area adalah mode tersendiri (`isSelectingArea`).
/// `pen` = pensil sketsa bebas; `bezier` = pen tool vektor (gaya Illustrator).
enum Tool: String, CaseIterable, Identifiable {
    case navigate, select, pen, eraser, bezier, rectangle, ellipse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .navigate: return "Navigasi"
        case .select: return "Pilih & edit titik"
        case .pen: return "Pensil sketsa"
        case .eraser: return "Penghapus stroke"
        case .bezier: return "Pen tool (bezier)"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        }
    }

    var symbol: String {
        switch self {
        case .navigate: return "hand.raised"
        case .select: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .bezier: return "point.topleft.down.to.point.bottomright.curvepath"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        }
    }

    var shortcut: Character {
        switch self {
        case .navigate: return "h"
        case .select: return "a"
        case .pen: return "n"
        case .eraser: return "e"
        case .bezier: return "p"
        case .rectangle: return "m"
        case .ellipse: return "l"
        }
    }

    /// Alat yang memakai warna + tebal dari dock pena.
    var draws: Bool { self == .pen || self == .eraser || isVector && self != .select }
    var isVector: Bool { self == .select || self == .bezier || self == .rectangle || self == .ellipse }
}

enum Basemap: String, CaseIterable, Identifiable {
    case satellite, hybrid, standard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .satellite: return "Satelit"
        case .hybrid: return "Hybrid"
        case .standard: return "Standar"
        }
    }
}

enum SaveState: Equatable {
    case saved, saving, failed(String)
}

/// Perintah kamera satu-kali dari UI ke peta.
struct MapCommand: Equatable {
    enum Kind: Equatable {
        case zoomToFrame
        case center(LatLon, spanM: Double)
        case followUser
        /// Faktor > 1 = zoom in.
        case zoom(Double)
        case northUp
        /// Peta berputar mengikuti arah hadap iPad (FR-5.2).
        case followHeading
        /// Geser peta sepecahan layar (−1…1) ke kanan/bawah; dipakai tombol panah keyboard.
        case pan(dx: Double, dy: Double)
        /// Pas-kan kotak UTM ke layar (zoom ke objek dari panel layer).
        case zoomToExtent(Rect2D)
    }

    let id = UUID()
    let kind: Kind
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var project: Project
    @Published private(set) var strokes: [Stroke]
    /// Naik setiap kali isi `strokes` berubah, agar overlay peta tahu kapan menggambar ulang.
    @Published private(set) var strokesVersion = 0
    /// Objek vektor; urutan = urutan gambar (terakhir = paling atas).
    @Published private(set) var features: [Feature]
    @Published private(set) var featuresVersion = 0
    @Published var selectedFeatureID: UUID?
    @Published var selectedNodeIndex: Int?
    /// Titik pen tool yang sedang dibuat (belum jadi objek).
    @Published private(set) var draftNodes: [BezierNode] = []
    /// Layer sketsa pensil sebagai satu grup di panel layer.
    @Published var sketchVisible = true
    /// Simbol aktif dari panel simbol: pen tool/rectangle/ellipse menggambar dengan warna, tebal, dan kodenya.
    @Published private(set) var activeSymbol: MapSymbol?
    @Published var tool: Tool {
        didSet {
            guard oldValue != tool else { return }
            // Pindah alat di tengah pen tool: simpan draf sebagai garis bila cukup titik.
            if oldValue == .bezier {
                if draftNodes.count >= 2 { finishDraft(as: .line) } else { cancelDraft() }
            }
            if !tool.isVector { deselect() }
        }
    }
    @Published var pen = PenPreset.isom[0]
    @Published var basemap = Basemap.satellite
    @Published var fingerDraws = false
    @Published var showsInspector = true
    @Published private(set) var saveState = SaveState.saved
    @Published var mapCommand: MapCommand?
    @Published var notice: String?
    @Published var confirmUnlock = false
    /// Arah peta di layar (derajat dari utara grid layar, searah jarum jam). 0 = north-up.
    @Published var mapHeading: Double = 0
    /// Arah hadap iPad dari magnetometer (derajat true north); nil bila tidak tersedia (mis. simulator).
    @Published var deviceHeading: Double?
    @Published var followsHeading = false
    /// Penanda posisi GPS (radar + arah pandang) tampil di peta.
    @Published var showsMyLocation = false
    /// Akurasi horizontal GPS terakhir (m).
    @Published var myAccuracyM: Double?

    let url: URL
    private let writer: ProjectWriter
    private var undoStack: [Edit] = []
    private var redoStack: [Edit] = []
    private var eraseBuffer: [Stroke] = []
    static let undoLimit = 200

    enum Edit {
        case add([Stroke])
        case remove([Stroke])
        case project(before: Project, after: Project)
        /// Snapshot seluruh daftar objek vektor: cukup kecil, dan menangani tambah/hapus/ubah/urutan sekaligus.
        case features(before: [Feature], after: [Feature])
    }

    init(document: ProjectDocument, url: URL) {
        self.project = document.project
        self.strokes = document.strokes
        self.features = document.features
        self.url = url
        self.writer = ProjectWriter(url: url)
        self.tool = .pen
        #if DEBUG
        // Untuk screenshot/UI test: `-cp-select-first` memilih objek paling atas dengan alat Pilih.
        // `-cp-show-location` menyalakan radar posisi; `-cp-fake-heading <derajat>` meniru kompas (simulator tidak punya).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-cp-show-location") { self.showsMyLocation = true }
        if let i = args.firstIndex(of: "-cp-fake-heading"), i + 1 < args.count { self.deviceHeading = Double(args[i + 1]) }
        if ProcessInfo.processInfo.arguments.contains("-cp-select-first"), let f = document.features.last {
            self.tool = .select
            self.selectedFeatureID = f.id
            self.selectedNodeIndex = 1
        }
        #endif
    }

    /// Selama area belum dikunci, workspace ada di mode Pilih Area: frame diam di tengah layar,
    /// peta yang digeser di bawahnya.
    var isSelectingArea: Bool { !project.areaLocked }

    var frame: MapFrame? { project.frame }
    var zone: UTMZone? { project.zone }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Frame (FR-1.3 – FR-1.10)

    /// Frame ikut titik tengah peta selama mode Pilih Area (dipanggil saat peta selesai bergerak).
    /// CRS UTM dipilih otomatis dari lokasi (FR-1.2); pojok di-snap ke kelipatan (FR-1.7).
    /// Tidak masuk riwayat undo: menggeser peta bukan suntingan data.
    func setFrameCenter(_ c: LatLon) {
        guard !project.areaLocked else { return }
        let zone = UTMZone(containing: c)
        var next = project
        next.crsEPSG = zone.epsg
        next.frameOrigin = MapFrame(center: zone.project(c), sheet: project.sheet).snapped(toStep: project.snapStepM).origin
        apply(next, recordUndo: false)
    }

    /// Ubah lembar (skala, orientasi, margin) dengan titik tengah tetap (FR-1.4, FR-1.5).
    func updateSheet(_ change: (inout SheetSpec) -> Void) {
        var next = project
        change(&next.sheet)
        if let frame, !project.areaLocked {
            next.frameOrigin = frame.resized(to: next.sheet).snapped(toStep: next.snapStepM).origin
        } else if project.areaLocked {
            // Setelah dikunci, extent tidak boleh berubah diam-diam; hanya skala/orientasi sebelum kunci.
            notice = "Buka kunci area untuk mengubah ukuran frame."
            return
        }
        apply(next)
    }

    func setSnapStep(_ step: Int) {
        var next = project
        next.snapStepM = step
        if let frame, !project.areaLocked { next.frameOrigin = frame.snapped(toStep: step).origin }
        apply(next)
    }

    /// Pengaturan grid garis utara; tampilan, jadi tidak masuk riwayat undo.
    func updateGrid(_ change: (inout NorthGrid) -> Void) {
        var next = project
        var g = project.grid
        change(&g)
        g.spacingM = min(max(g.spacingM, NorthGrid.spacingRangeM.lowerBound), NorthGrid.spacingRangeM.upperBound)
        g.opacity = min(max(g.opacity, 0.05), 1)
        g.declinationDeg = min(max(g.declinationDeg, -30), 30)
        next.northGrid = g
        apply(next, recordUndo: false)
    }

    /// Tampilan saja, jadi tidak masuk riwayat undo.
    func setBasemapOpacity(_ value: Double) {
        var next = project
        next.basemapOpacity = (min(max(value, 0), 1) * 100).rounded() / 100
        apply(next, recordUndo: false)
    }

    func setDPI(_ dpi: Int) {
        var next = project
        next.sketchDPI = dpi
        apply(next)
    }

    func lockArea() {
        guard frame != nil else { return }
        var next = project
        next.areaLocked = true
        apply(next)
        tool = .pen
        mapCommand = MapCommand(kind: .zoomToFrame)
    }

    /// FR-1.10: setelah ada sketsa, buka kunci perlu konfirmasi. Data di luar frame disembunyikan, tidak dihapus.
    func requestUnlock() {
        if strokes.isEmpty { unlockArea() } else { confirmUnlock = true }
    }

    func unlockArea() {
        var next = project
        next.areaLocked = false
        apply(next)
        mapCommand = MapCommand(kind: .zoomToFrame)
    }

    // MARK: Sketsa (FR-3)

    func addStroke(points: [Point2D]) {
        guard !points.isEmpty else { return }
        let s = Stroke(colorHex: pen.colorHex, widthMM: pen.widthMM, points: points)
        strokes.append(s)
        strokesChanged()
        record(.add([s]))
    }

    /// Hapus stroke yang tersentuh penghapus; satu gestur = satu langkah undo.
    func erase(at p: Point2D, radiusM: Double) {
        let halfWidth = { (s: Stroke) in self.project.sheet.groundMeters(forPaperMM: s.widthMM) / 2 }
        let hit = strokes.filter { s in
            guard let b = s.bounds else { return false }
            let r = radiusM + halfWidth(s)
            guard p.x >= b.minX - r, p.x <= b.maxX + r, p.y >= b.minY - r, p.y <= b.maxY + r else { return false }
            return s.distance(to: p) <= r
        }
        guard !hit.isEmpty else { return }
        let ids = Set(hit.map(\.id))
        strokes.removeAll { ids.contains($0.id) }
        eraseBuffer.append(contentsOf: hit)
        strokesChanged()
    }

    func endErase() {
        guard !eraseBuffer.isEmpty else { return }
        record(.remove(eraseBuffer))
        eraseBuffer = []
    }

    func setPenWidth(_ mm: Double) {
        pen.widthMM = PenPreset.clampWidth(mm)
    }

    func togglePenEraser() {
        tool = tool == .eraser ? .pen : .eraser
    }

    // MARK: Objek vektor (FR-4)

    var selectedFeature: Feature? {
        selectedFeatureID.flatMap { id in features.first { $0.id == id } }
    }

    private func setFeatures(_ next: [Feature]) {
        features = next
        if let id = selectedFeatureID, !next.contains(where: { $0.id == id }) {
            selectedFeatureID = nil
            selectedNodeIndex = nil
        }
        featuresVersion += 1
        scheduleSave()
    }

    /// Ubah daftar objek sebagai satu langkah undo.
    func editFeatures(_ change: (inout [Feature]) -> Void) {
        let before = features
        var next = features
        change(&next)
        guard next != before else { return }
        setFeatures(next)
        record(.features(before: before, after: next))
    }

    func addFeature(_ f: Feature) {
        var f = f
        if f.name.isEmpty {
            if let code = f.symbolCode {
                let n = features.filter { $0.symbolCode == code }.count + 1
                f.name = "\(code) \(f.symbolName ?? "") \(n)"
            } else {
                let n = features.filter { $0.kind == f.kind }.count + 1
                f.name = "\(f.kind.label) \(n)"
            }
        }
        editFeatures { $0.append(f) }
        selectedFeatureID = f.id
        selectedNodeIndex = nil
    }

    /// Ubah satu objek selama drag tanpa mencatat undo; `commitFeatureEdit` mencatat satu langkah di akhir gestur.
    func updateFeatureLive(_ f: Feature) {
        guard let i = features.firstIndex(where: { $0.id == f.id }), features[i] != f else { return }
        var next = features
        next[i] = f
        features = next
        featuresVersion += 1
    }

    func commitFeatureEdit(from before: [Feature]) {
        guard before != features else { return }
        record(.features(before: before, after: features))
        scheduleSave()
    }

    func updateFeature(_ id: UUID, _ change: (inout Feature) -> Void) {
        editFeatures { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            change(&list[i])
        }
    }

    func deleteFeature(_ id: UUID) {
        editFeatures { $0.removeAll { $0.id == id } }
    }

    /// Pindah urutan dari sudut pandang panel layer (indeks 0 = paling atas).
    func moveFeatures(fromLayerOffsets source: IndexSet, toLayerOffset destination: Int) {
        editFeatures { list in
            var reversed = Array(list.reversed())
            reversed.move(fromOffsets: source, toOffset: destination)
            list = Array(reversed.reversed())
        }
    }

    func deleteSelectedNode() {
        guard let id = selectedFeatureID, let i = selectedNodeIndex, let f = selectedFeature else { return }
        guard f.nodes.count > (f.kind == .area ? 3 : 2) else {
            notice = "\(f.kind.label) butuh minimal \(f.kind == .area ? 3 : 2) titik."
            return
        }
        updateFeature(id) { $0.nodes.remove(at: i) }
        selectedNodeIndex = nil
    }

    func applyPenStyleToSelection() {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { f in
            f.colorHex = pen.colorHex
            f.widthMM = pen.widthMM
        }
    }

    func deselect() {
        selectedFeatureID = nil
        selectedNodeIndex = nil
    }

    // MARK: Import OCAD

    /// Baca .ocd di background, tambahkan garis/area sebagai objek vektor (satu langkah undo).
    func importOcad(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let result = await Task.detached(priority: .userInitiated) { () -> Result<([Feature], OcadImportReport), Error> in
            Result {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                // Batas ukuran sesuai kebijakan import file (PRD: Keamanan).
                guard (attrs[.size] as? Int ?? 0) <= 200_000_000 else { throw OcadReadError.corrupt("file lebih dari 200 MB") }
                return try OcadReader.read(Data(contentsOf: url)).features()
            }
        }.value
        switch result {
        case let .failure(error):
            notice = (error as? LocalizedError)?.errorDescription ?? "Import gagal: \(error.localizedDescription)"
        case let .success((imported, report)):
            guard !imported.isEmpty else {
                notice = "Tidak ada garis atau area di file ini."
                return
            }
            editFeatures { $0.append(contentsOf: imported) }
            var parts = ["\(report.imported) objek dari \(url.lastPathComponent) diimpor"]
            if report.skippedPoints > 0 { parts.append("\(report.skippedPoints) objek titik dilewati") }
            if report.skippedText > 0 { parts.append("\(report.skippedText) teks dilewati") }
            if report.droppedHoles > 0 { parts.append("\(report.droppedHoles) lubang area diabaikan") }
            let bounds = Rect2D(points: imported.compactMap(\.bounds).flatMap { [Point2D(x: $0.minX, y: $0.minY), Point2D(x: $0.maxX, y: $0.maxY)] })
            if let b = bounds, let frame, !frame.extent.intersects(b) {
                let km = frame.center.distance(to: b.center) / 1000
                parts.append(String(format: "objek berada %.1f km dari area terkunci — Pilih ulang area untuk melihatnya", km))
            } else if let b = bounds {
                mapCommand = MapCommand(kind: .zoomToExtent(b))
            }
            notice = parts.joined(separator: " · ")
        }
    }

    // MARK: Simbol

    /// Pakai simbol untuk objek vektor berikutnya. Pensil sketsa tetap memakai preset pena biasa.
    func useSymbol(_ s: MapSymbol) {
        activeSymbol = s
        pen = PenPreset(name: s.name, colorHex: s.colorHex, widthMM: PenPreset.clampWidth(s.drawingWidthMM))
        if !tool.isVector || tool == .select { tool = .bezier }
    }

    func clearSymbol() {
        activeSymbol = nil
    }

    /// Tempel kode + nama simbol aktif ke objek yang baru dibuat.
    func stampActiveSymbol(_ f: inout Feature) {
        guard let s = activeSymbol else { return }
        f.symbolCode = s.code
        f.symbolName = s.name
    }

    // MARK: Pen tool (bezier)

    func appendDraftNode(_ n: BezierNode) {
        draftNodes.append(n)
    }

    func updateLastDraftNode(_ n: BezierNode) {
        guard !draftNodes.isEmpty else { return }
        draftNodes[draftNodes.count - 1] = n
    }

    func removeLastDraftNode() {
        _ = draftNodes.popLast()
    }

    func cancelDraft() {
        draftNodes = []
    }

    /// Jadikan draf objek: garis (≥ 2 titik) atau area tertutup (≥ 3 titik).
    func finishDraft(as kind: FeatureKind) {
        let minimum = kind == .area ? 3 : 2
        guard draftNodes.count >= minimum else {
            notice = "\(kind.label) butuh minimal \(minimum) titik."
            return
        }
        var f = Feature(kind: kind, colorHex: pen.colorHex, widthMM: pen.widthMM, nodes: draftNodes)
        stampActiveSymbol(&f)
        addFeature(f)
        draftNodes = []
    }

    /// Selesai sesuai simbol aktif: simbol area menutup path, selain itu jadi garis.
    func finishDraftForActiveSymbol() {
        finishDraft(as: activeSymbol?.kind == .area ? .area : .line)
    }

    // MARK: Undo / redo

    func undo() {
        guard let edit = undoStack.popLast() else { return }
        invert(edit)
        redoStack.append(edit)
        objectWillChange.send()
    }

    func redo() {
        guard let edit = redoStack.popLast() else { return }
        replay(edit)
        undoStack.append(edit)
        objectWillChange.send()
    }

    private func invert(_ edit: Edit) {
        switch edit {
        case let .add(s):
            let ids = Set(s.map(\.id))
            strokes.removeAll { ids.contains($0.id) }
            strokesChanged()
        case let .remove(s):
            strokes.append(contentsOf: s)
            strokesChanged()
        case let .project(before, _):
            apply(before, recordUndo: false)
        case let .features(before, _):
            setFeatures(before)
        }
    }

    private func replay(_ edit: Edit) {
        switch edit {
        case let .add(s):
            strokes.append(contentsOf: s)
            strokesChanged()
        case let .remove(s):
            let ids = Set(s.map(\.id))
            strokes.removeAll { ids.contains($0.id) }
            strokesChanged()
        case let .project(_, after):
            apply(after, recordUndo: false)
        case let .features(_, after):
            setFeatures(after)
        }
    }

    private func record(_ edit: Edit) {
        undoStack.append(edit)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
    }

    private func apply(_ next: Project, recordUndo: Bool = true) {
        guard next != project else { return }
        let before = project
        project = next
        if recordUndo { record(.project(before: before, after: next)) }
        scheduleSave()
    }

    private func strokesChanged() {
        strokesVersion += 1
        scheduleSave()
    }

    // MARK: Simpan otomatis

    private func scheduleSave() {
        project.updatedAt = Date()
        saveState = .saving
        let doc = ProjectDocument(project: project, strokes: strokes, features: features)
        let writer = writer
        Task { [weak self] in
            await writer.schedule(doc) { [weak self] result in
                Task { @MainActor [weak self] in
                    switch result {
                    case .success: self?.saveState = .saved
                    case let .failure(error): self?.saveState = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    func flush() async {
        await writer.flushNow()
    }

    // MARK: Cari lokasi

    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if let c = CoordinateParser.parse(query) {
            goTo(c)
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                notice = "Lokasi \"\(query)\" tidak ditemukan."
                return
            }
            let c = item.placemark.coordinate
            goTo(LatLon(lat: c.latitude, lon: c.longitude))
        } catch {
            notice = "Pencarian butuh internet. Masukkan koordinat lat, lon atau UTM (mis. 48S 787500 9234500)."
        }
    }

    /// Terbang ke lokasi. Di mode Pilih Area frame ikut ke tengah peta; setelah dikunci,
    /// peta dibatasi ke area sehingga lokasi di luar frame ditolak.
    func goTo(_ c: LatLon) {
        if let frame, let zone, project.areaLocked {
            guard frame.extent.insetBy(-50).intersects(Rect2D(points: [zone.project(c)])!) else {
                notice = "Lokasi di luar area terkunci. Buka kunci area untuk pindah lokasi."
                return
            }
            mapCommand = MapCommand(kind: .center(c, spanM: 400))
        } else {
            let s = project.sheet
            mapCommand = MapCommand(kind: .center(c, spanM: max(s.groundWidthM, s.groundHeightM) * 1.8))
        }
    }

    // MARK: Info frame (FR-1.9)

    struct CornerInfo: Identifiable {
        let id: String
        let utm: Point2D
        let latLon: LatLon
    }

    var cornerInfo: [CornerInfo] {
        guard let frame, let zone else { return [] }
        let names = ["Kiri atas", "Kanan atas", "Kanan bawah", "Kiri bawah"]
        return zip(names, frame.corners).map { CornerInfo(id: $0, utm: $1, latLon: zone.unproject($1)) }
    }
}
