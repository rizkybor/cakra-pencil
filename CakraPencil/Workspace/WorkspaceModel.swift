import CakraCore
import CoreLocation
import Foundation
import MapKit

/// Alat setelah area dikunci. Pemilihan area adalah mode tersendiri (`isSelectingArea`).
/// `pen` = pensil sketsa bebas; `bezier` = pen tool vektor (gaya Illustrator).
enum Tool: String, CaseIterable, Identifiable {
    case navigate, select, node, measure, pen, eraser, point, bezier, freehand, rectangle, ellipse, control

    var id: String { rawValue }

    var label: String {
        switch self {
        case .navigate: return "Navigasi"
        case .select: return "Move Tool"
        case .node: return "Node Tool"
        case .measure: return "Measure Tool"
        case .pen: return "Pensil sketsa"
        case .eraser: return "Penghapus stroke"
        case .point: return "Simbol titik"
        case .bezier: return "Pen tool (bezier)"
        case .freehand: return "Gambar bebas"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .control: return "Kontrol lintasan"
        }
    }

    var symbol: String {
        switch self {
        case .navigate: return "hand.raised"
        case .select: return "cursorarrow"
        case .node: return "point.3.filled.connected.trianglepath.dotted"
        case .measure: return "ruler"
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .point: return "smallcircle.filled.circle"
        case .bezier: return "point.topleft.down.to.point.bottomright.curvepath"
        case .freehand: return "scribble"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .control: return "flag"
        }
    }

    var shortcut: Character {
        switch self {
        case .navigate: return "h"
        case .select: return "v"
        case .node: return "a"
        case .measure: return "r"
        case .pen: return "n"
        case .eraser: return "e"
        case .point: return "t"
        case .bezier: return "p"
        case .freehand: return "f"
        case .rectangle: return "m"
        case .ellipse: return "l"
        case .control: return "k"
        }
    }

    /// Alat yang memakai warna + tebal dari dock pena.
    var draws: Bool { self == .pen || self == .eraser || isVector && !selects }
    var isVector: Bool { selects || self == .point || self == .bezier || self == .freehand || self == .rectangle || self == .ellipse }

    /// Move Tool (pilih/pindah objek utuh) dan Node Tool (edit titik & handle) sama-sama memilih objek.
    var selects: Bool { self == .select || self == .node }

    /// Penjelasan singkat untuk tooltip.
    var hint: String? {
        switch self {
        case .select: return "pilih, pindah & duplikat objek; tarik di tempat kosong = kotak pilih"
        case .node: return "edit titik & handle objek"
        case .measure: return "tarik untuk mengukur jarak & azimut"
        default: return nil
        }
    }

    /// Alat gambar yang cocok untuk jenis simbol.
    func accepts(_ kind: MapSymbol.Kind) -> Bool {
        switch self {
        case .point: return kind == .point
        case .bezier, .freehand: return kind == .line || kind == .area
        case .rectangle, .ellipse: return kind == .area
        case .control: return false
        default: return true
        }
    }
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
        /// Seluruh peta: frame + semua objek, sketsa, dan lintasan (termasuk yang di luar frame).
        case fitMap
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

/// State peta yang berubah setiap frame (rotasi, kompas, akurasi GPS). Objek terpisah agar hanya kompas dan tombol
/// lokasi yang dirender ulang, bukan seluruh workspace (uji performa: rotasi 34 → 60 fps).
@MainActor
final class LiveMapState: ObservableObject {
    /// Arah peta di layar (derajat dari utara, searah jarum jam). 0 = north-up.
    @Published var mapHeading: Double = 0
    /// Arah hadap iPad dari magnetometer (derajat true north); nil bila tidak tersedia (mis. simulator).
    @Published var deviceHeading: Double?
    /// Akurasi horizontal GPS terakhir (m).
    @Published var myAccuracyM: Double?
}

@MainActor
final class WorkspaceModel: ObservableObject {
    let live = LiveMapState()
    @Published private(set) var project: Project
    @Published private(set) var strokes: [Stroke]
    /// Naik setiap kali isi `strokes` berubah, agar overlay peta tahu kapan menggambar ulang.
    @Published private(set) var strokesVersion = 0
    /// Objek vektor; urutan = urutan gambar (terakhir = paling atas).
    /// Tidak @Published: perubahan diumumkan lewat `featuresVersion`, sehingga drag (updateFeatureLive) bisa
    /// memperbarui peta tanpa merender ulang SwiftUI tiap frame (uji performa: drag 18 → 60 fps).
    private(set) var features: [Feature]
    @Published private(set) var featuresVersion = 0
    /// Dipanggil tiap perubahan objek selama drag; overlay peta memperbarui objek itu saja.
    var onLiveFeatureChange: ((Feature) -> Void)?
    @Published var selectedFeatureID: UUID?
    @Published var selectedNodeIndex: Int?
    /// Objek lain yang ikut terpilih (pilih banyak); `selectedFeatureID` tetap objek utama. Lihat +Selection.
    @Published var extraSelectedIDs: Set<UUID> = []
    /// Titik pen tool yang sedang dibuat (belum jadi objek).
    @Published private(set) var draftNodes: [BezierNode] = []
    /// Layer sketsa pensil sebagai satu grup di panel layer.
    @Published var sketchVisible = true
    /// Simbol aktif dari panel simbol: pen tool/rectangle/ellipse menggambar dengan warna, tebal, dan kodenya.
    @Published private(set) var activeSymbol: MapSymbol?
    /// Cari simbol pustaka dari kode (diisi WorkspaceView), agar memilih objek ikut memilih simbolnya.
    /// Juga menentukan Color Hierarchy objek; saat dipasang, peta digambar ulang dengan urutan warnanya.
    var symbolLookup: ((String) -> MapSymbol?)? {
        didSet {
            featuresVersion += 1
            upgradeLineStylesFromSymbols()
        }
    }

    /// Objek garis yang dibuat sebelum gaya simbolnya terbaca lengkap (mis. 509.1 Railway tanpa lapisan hitam):
    /// perbarui gayanya dari set simbol. Hanya objek yang gayanya kurang; tanpa langkah undo.
    func upgradeLineStylesFromSymbols() {
        guard let lookup = symbolLookup else { return }
        var changed = false
        let next = features.map { f -> Feature in
            guard f.kind == .line, let code = f.symbolCode, let style = lookup(code)?.lineStyle, style.casing != nil,
                  f.casingColorHex == nil || (style.innerDashMM != nil && f.innerDashMM == nil) else { return f }
            var g = f
            g.apply(style)
            changed = true
            return g
        }
        if changed { setFeatures(next) }
    }
    /// Garis yang sedang dilanjutkan dengan pen tool (nil = menggambar objek baru).
    @Published private(set) var continuingFeatureID: UUID?
    /// Alat Potong (OCAD Cut) aktif untuk objek terpilih; area butuh dua ketukan (titik pertama disimpan).
    @Published var cutMode = false
    /// Hasil alat Ukur (Measure Tool); hilang saat ganti alat.
    @Published var measurement: MapMeasurement?
    @Published var cutStart: PathPosition?
    /// Objek yang ada jadi panduan saat menggambar (OCAD Follow): kursor menempel ke garis tepinya dan bentuk
    /// baru mengikuti objek itu. Disimpan per perangkat.
    /// Selalu aktif (tanpa tombol): ketukan pertama lalu ketukan kedua di objek yang sama = bentuk objek itu
    /// diikuti; kursor menempel ke garis tepi objek yang ada.
    var followGuides: Bool { true }
    /// Gabung otomatis objek bersimbol sama yang ditempelkan (lihat WorkspaceModel+Merge). Disimpan per perangkat.
    /// Selalu aktif (tanpa tombol).
    var autoMerge: Bool { true }
    // Kontur (FR-8): data elevasi di paket proyek + garis hasil hitung (lihat WorkspaceModel+Contours).
    @Published var dem: DEMGrid?
    @Published var importedContours: [ContourLine]?
    @Published var contourLines: [ContourLine] = []
    @Published var contourRelief: (min: Double, max: Double)?
    @Published var contourStatus: ContourStatus = .idle
    @Published private(set) var contourVersion = 0
    var contourTask: Task<Void, Never>?
    /// Panel Kontur → buka export sheet langsung di mode "Kontur saja".
    @Published var exportContoursOnly = false
    /// Panel Lintasan → buka export sheet langsung di mode "Lintasan".
    @Published var exportCourses = false

    // Course planner (lihat WorkspaceModel+Course).
    /// Kontrol + lintasan. Tidak @Published: perubahan diumumkan lewat `coursesVersion` (drag kontrol tetap lancar).
    var courseSet: CourseSet
    @Published var coursesVersion = 0
    /// Dipanggil selama kontrol ditarik; overlay peta menggambar ulang tanpa lewat SwiftUI.
    var onLiveCourseChange: (() -> Void)?
    /// Lintasan yang tampil + diedit; nil = "Semua kontrol".
    @Published var selectedCourseID: UUID?
    @Published var selectedControlID: UUID?
    /// Jenis titik yang ditempatkan alat Kontrol.
    @Published var controlPlacement: ControlKind = .control
    /// Halaman Course Planner terbuka (layar penuh di atas workspace pemetaan).
    @Published var showsCoursePlanner = false
    /// Intensitas isi peta di halaman Course (seperti "map intensity" Purple Pen): 0,2–1.
    @Published var courseMapIntensity: Double = 0.6
    /// Alat workspace sebelum membuka Course Planner (dikembalikan saat ditutup).
    var toolBeforeCourses: Tool?
    /// Alat objek lintasan aktif di halaman Course (teks/bentuk); nil = menempatkan kontrol.
    @Published var courseItemTool: CourseItem.Kind?
    @Published var selectedCourseItemID: UUID?
    /// Gambar objek lintasan yang sudah dibaca (nama file → gambar), untuk overlay peta.
    var courseImageCache: [String: CGImage] = [:]

    enum ContourStatus: Equatable {
        case idle, downloading(done: Int, total: Int), importing, generating, failed(String)
    }

    func contoursChanged() { contourVersion += 1 }

    /// Pengali ukuran simbol aktif; 1 = ukuran standar IOF dari set simbol. Kembali ke 1 tiap ganti simbol.
    @Published private(set) var symbolSizeFactor: Double = 1
    static let sizeFactorRange: ClosedRange<Double> = 0.25...4
    @Published var tool: Tool {
        didSet {
            guard oldValue != tool else { return }
            cutMode = false
            cutStart = nil
            // Pindah alat di tengah pen tool: simpan draf sebagai garis bila cukup titik.
            if oldValue == .bezier {
                if draftNodes.count >= 2 { finishDraft(as: .line) } else { cancelDraft() }
            }
            if !tool.isVector { deselect() }
            if tool != .measure { measurement = nil }
            // Node Tool mengedit satu objek: pilihan banyak dikurangi ke objek utama.
            if tool == .node { extraSelectedIDs = [] }
            // Simbol yang tidak cocok dengan alat gambar baru dilepas (mis. simbol titik + pen tool).
            if let s = activeSymbol, tool != .control, !tool.accepts(s.kind) {
                activeSymbol = nil
                notice = "\(s.code) \(s.name) adalah simbol \(s.kind.label.lowercased()); dilepas untuk alat \(tool.label)."
            }
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
    /// Alat sebelum "Pilih ulang area" (dipakai lagi saat Batal).
    var toolBeforeReselect: Tool?
    /// Basemap gambar yang baru diimpor tidak menyentuh frame: tawarkan pindahkan frame ke gambar.
    @Published var confirmMoveFrameToBasemap = false
    @Published var followsHeading = false
    /// Penanda posisi GPS (radar + arah pandang) tampil di peta.
    @Published var showsMyLocation = false

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
        case courses(before: CourseSet, after: CourseSet)
    }

    init(document: ProjectDocument, url: URL) {
        self.project = document.project
        self.strokes = document.strokes
        self.features = document.features
        self.courseSet = document.courses
        self.selectedCourseID = document.courses.courses.first?.id
        self.url = url
        self.writer = ProjectWriter(url: url)
        self.tool = .pen
        loadContourData()
        // Gambar objek lintasan yang tidak dirujuk lagi oleh courses.json tersimpan (dihapus di sesi sebelumnya).
        CourseImages.removeUnused(keeping: Set(document.courses.allItems.compactMap(\.imageName)), in: url)
        #if DEBUG
        // Untuk screenshot/UI test: `-cp-select-first` memilih objek paling atas dengan alat Pilih.
        // `-cp-show-location` menyalakan radar posisi; `-cp-fake-heading <derajat>` meniru kompas (simulator tidak punya).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-cp-show-location") { self.showsMyLocation = true }
        // `-cp-open-course`: langsung buka Course Planner (screenshot tata letak).
        if args.contains("-cp-open-course"), project.areaLocked { DispatchQueue.main.async { self.openCoursePlanner() } }
        if let i = args.firstIndex(of: "-cp-fake-heading"), i + 1 < args.count { self.live.deviceHeading = Double(args[i + 1]) }
        if ProcessInfo.processInfo.arguments.contains("-cp-select-first"), let f = document.features.last {
            self.tool = .node
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

    /// Opacity isi area bersimbol di peta (tampilan; export tetap warna penuh). Tidak masuk undo.
    func setAreaOpacity(_ value: Double) {
        var next = project
        next.areaOpacity = (min(max(value, 0.1), 1) * 100).rounded() / 100
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

    /// Kotak yang memuat frame peta dan semua isi yang terlihat (UTM).
    var mapContentExtent: Rect2D? {
        var pts: [Point2D] = frame?.corners ?? []
        for f in features where f.isVisible {
            if let b = f.bounds { pts += [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.maxY)] }
        }
        if sketchVisible { for s in strokes { pts += s.points } }
        pts += courseSet.controls.map(\.position)
        for item in courseSet.allItems {
            if let b = item.bounds(sheet: project.sheet) { pts += [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.maxY)] }
        }
        return Rect2D(points: pts)
    }

    func lockArea() {
        guard frame != nil else { return }
        var next = project
        next.areaLocked = true
        next.areaBackup = nil
        apply(next)
        tool = .pen
        mapCommand = MapCommand(kind: .zoomToFrame)
    }

    /// Batal pilih ulang area: kembali ke area terkunci sebelumnya (CRS, frame, lembar, snap); basemap dan
    /// pengaturan lain tidak berubah.
    func cancelReselectArea() {
        guard let saved = project.areaBackup else { return }
        var next = project
        saved.restore(into: &next)
        apply(next)
        tool = toolBeforeReselect ?? .pen
        mapCommand = MapCommand(kind: .zoomToFrame)
        notice = "Pilih ulang area dibatalkan; area sebelumnya dipakai lagi."
    }

    /// FR-1.10: setelah ada sketsa, buka kunci perlu konfirmasi. Data di luar frame disembunyikan, tidak dihapus.
    func requestUnlock() {
        if strokes.isEmpty { unlockArea() } else { confirmUnlock = true }
    }

    func unlockArea() {
        // Simpan area terkunci saat ini: selama area baru belum dikunci, user bisa kembali (Batal).
        var next = project
        if project.areaLocked {
            next.areaBackup = AreaBackup(of: project)
            toolBeforeReselect = tool
        }
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
        if !extraSelectedIDs.isEmpty {
            let ids = Set(next.map(\.id))
            extraSelectedIDs.formIntersection(ids)
            if selectedFeatureID == nil, let first = next.first(where: { extraSelectedIDs.contains($0.id) }) {
                selectedFeatureID = first.id
                extraSelectedIDs.remove(first.id)
            }
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

    /// `merge`: objek hasil gambar yang ujungnya/sisinya ditempelkan ke objek bersimbol sama langsung digabung
    /// (satu langkah undo bersama penambahannya).
    func addFeature(_ f: Feature, merge: Bool = false) {
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
        var result = f.id
        editFeatures { list in
            list.append(f)
            if merge, autoMerge { result = autoMerged(f.id, in: &list) }
        }
        selectedFeatureID = result
        selectedNodeIndex = nil
        extraSelectedIDs = []
    }

    /// Ubah satu objek selama drag tanpa mencatat undo; `commitFeatureEdit` mencatat satu langkah di akhir gestur.
    func updateFeatureLive(_ f: Feature) {
        guard let i = features.firstIndex(where: { $0.id == f.id }), features[i] != f else { return }
        features[i] = f
        onLiveFeatureChange?(f)
    }

    /// Ganti daftar objek tanpa mencatat undo (penggabungan di akhir gestur; `commitFeatureEdit` mencatatnya).
    func setFeaturesForMerge(_ list: [Feature]) {
        features = list
    }

    /// Akhir gestur: satu langkah undo, lalu umumkan perubahan ke SwiftUI (panel layer, bar alat) sekali saja.
    func commitFeatureEdit(from before: [Feature]) {
        guard before != features else { return }
        record(.features(before: before, after: features))
        featuresVersion += 1
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
        updateFeature(id) {
            $0.nodes.remove(at: i)
            $0.refreshSmartNodes()
        }
        selectedNodeIndex = nil
    }

    /// Convert to Sharp / Smooth / Smart untuk titik aktif.
    func convertSelectedNode(to style: NodeStyle) {
        guard let id = selectedFeatureID, let i = selectedNodeIndex, selectedFeature?.isLocked == false else { return }
        updateFeature(id) { $0.convertNode(at: i, to: style) }
    }

    func applyPenStyleToSelection() {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { f in
            f.colorHex = pen.colorHex
            f.widthMM = pen.widthMM
        }
    }

    func deselect() {
        cutMode = false
        cutStart = nil
        selectedFeatureID = nil
        selectedNodeIndex = nil
        extraSelectedIDs = []
    }

    // MARK: Import OCAD

    /// Baca peta OCAD (.ocd) atau OOM (.omap/.xmap) di background, tambahkan objeknya sebagai objek vektor
    /// (satu langkah undo). Dipakai di workspace dan sebagai peta latar di halaman Course.
    func importOcad(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let zone = self.zone
        let result = await Task.detached(priority: .userInitiated) { () -> Result<([Feature], OcadImportReport), Error> in
            Result {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                // Batas ukuran sesuai kebijakan import file (PRD: Keamanan).
                guard (attrs[.size] as? Int ?? 0) <= 200_000_000 else { throw OcadReadError.corrupt("file lebih dari 200 MB") }
                let data = try Data(contentsOf: url)
                switch url.pathExtension.lowercased() {
                case "omap", "xmap":
                    guard let zone else { throw OmapReadError.notGeoreferenced }
                    return try OmapReader.read(data, zone: zone)
                default:
                    return try OcadReader.read(data).features()
                }
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
        symbolSizeFactor = 1
        pen = PenPreset(name: s.name, colorHex: s.colorHex, widthMM: PenPreset.clampWidth(s.drawingWidthMM))
        // Alat mengikuti jenis simbol: titik → ketuk, garis → pen tool, area → pen tool (atau rectangle/ellipse).
        switch s.kind {
        case .point: tool = .point
        case .line: tool = .bezier
        case .area: if !(tool == .bezier || tool == .rectangle || tool == .ellipse) { tool = .bezier }
        case .text: break
        }
    }

    /// Ubah ukuran simbol aktif (garis/area: tebal pena ikut berubah).
    func setSymbolSize(_ factor: Double) {
        symbolSizeFactor = (min(max(factor, Self.sizeFactorRange.lowerBound), Self.sizeFactorRange.upperBound) * 100).rounded() / 100
        if let s = activeSymbol, s.kind != .point {
            pen.widthMM = PenPreset.clampWidth(s.drawingWidthMM * symbolSizeFactor)
        }
    }

    /// Tempatkan simbol titik aktif di posisi `p` (UTM).
    func placePoint(at p: Point2D) {
        guard let s = activeSymbol, s.kind == .point, let elements = s.pointElements, !elements.isEmpty else {
            notice = "Pilih simbol titik dulu di panel Simbol (mis. 204.0 Boulder)."
            return
        }
        addFeature(Feature.point(at: p, elements: elements, sizeFactor: symbolSizeFactor, symbolCode: s.code, symbolName: s.name))
    }

    /// Ubah ukuran objek terpilih: titik lewat sizeFactor, garis/area lewat tebal.
    func resizeSelected(by step: Double) {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { f in
            if f.kind == .point {
                let k = min(max(f.effectiveSizeFactor * step, Self.sizeFactorRange.lowerBound), Self.sizeFactorRange.upperBound)
                f.sizeFactor = abs(k - 1) < 0.001 ? nil : (k * 100).rounded() / 100
                f.widthMM = (f.pointElements ?? []).diameterMM * f.effectiveSizeFactor
            } else {
                f.setWidth(f.widthMM * step)
            }
        }
    }

    // MARK: Rotasi objek (0–360°)

    /// Satu langkah undo (tombol ±, preset).
    func setSelectedRotation(_ degrees: Double) {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { $0.setRotation(degrees) }
    }

    /// Selama slider digeser: perbarui peta langsung; `commitFeatureEdit(from:)` mencatat undo di akhir.
    /// `exactly`: tanpa pembulatan 0,1° (rotasi presisi agar sisi benar-benar sejajar dengan objek lain).
    func rotateSelectedLive(to degrees: Double, exactly: Bool = false) {
        guard var f = selectedFeature else { return }
        if exactly { f.setRotationExactly(degrees) } else { f.setRotation(degrees) }
        updateFeatureLive(f)
    }

    /// Ubah tebal garis/area terpilih dalam mm (mis. ±0,01).
    func adjustSelectedWidth(by deltaMM: Double) {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { $0.setWidth($0.widthMM + deltaMM) }
    }

    /// Kembali ke ukuran standar IOF: titik = 100%, garis/area = tebal standar simbolnya.
    func resetSelectedSize() {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { f in
            if f.kind == .point {
                f.sizeFactor = nil
                f.widthMM = (f.pointElements ?? []).diameterMM
            } else if let std = f.standardWidthMM {
                f.setWidth(std)
            }
        }
    }

    func clearSymbol() {
        activeSymbol = nil
    }

    /// Tempel kode + nama simbol aktif ke objek yang baru dibuat.
    func stampActiveSymbol(_ f: inout Feature) {
        guard let s = activeSymbol else { return }
        f.symbolCode = s.code
        f.symbolName = s.name
        // Garis: gaya IOF (termasuk tepi garis ganda), lalu tebal pilihan user; tebal standar disimpan.
        if f.kind == .line, let style = s.lineStyle {
            f.apply(style)
            f.setWidth(pen.widthMM)
        } else if f.kind != .point {
            f.standardWidthMM = s.drawingWidthMM
        }
    }

    /// Tebal standar IOF simbol garis/area aktif.
    var activeStandardWidthMM: Double? {
        guard let s = activeSymbol, s.kind != .point else { return nil }
        return PenPreset.clampWidth(s.drawingWidthMM)
    }

    /// Ubah tebal simbol garis aktif (mm); faktor ukuran ikut untuk tampilan persen.
    func setSymbolLineWidth(_ mm: Double) {
        pen.widthMM = PenPreset.clampWidth(mm)
        if let std = activeStandardWidthMM, std > 0 { symbolSizeFactor = (pen.widthMM / std * 100).rounded() / 100 }
    }

    // MARK: Pen tool (bezier)

    func appendDraftNode(_ n: BezierNode) {
        draftNodes.append(n)
    }

    /// Pen tool mengikuti objek panduan: `nodes` dimulai di titik draf terakhir (handle keluarnya dipakai).
    func appendFollowedDraft(_ nodes: [BezierNode]) {
        guard let first = nodes.first else { return }
        if let last = draftNodes.indices.last, draftNodes[last].point.distance(to: first.point) < 1e-6 {
            draftNodes[last].outHandle = first.outHandle
            draftNodes += nodes.dropFirst()
        } else {
            draftNodes += nodes
        }
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
        continuingFeatureID = nil
    }

    /// Seperti OCAD/OOM: mulai menggambar di ujung garis bersimbol sama → garis itu dilanjutkan, bukan objek baru.
    /// `fromStart` = mulai di titik awal: urutan titik dibalik agar ujung yang disentuh jadi titik terakhir draf.
    func beginContinuation(of f: Feature, fromStart: Bool) {
        draftNodes = fromStart
            ? f.nodes.reversed().map { BezierNode(point: $0.point, inHandle: $0.outHandle, outHandle: $0.inHandle) }
            : f.nodes
        continuingFeatureID = f.id
        notice = "Melanjutkan \(f.displayName)"
    }

    /// Jadikan draf objek: garis (≥ 2 titik) atau area tertutup (≥ 3 titik).
    func finishDraft(as kind: FeatureKind) {
        let minimum = kind == .area ? 3 : 2
        guard draftNodes.count >= minimum else {
            notice = "\(kind.label) butuh minimal \(minimum) titik."
            return
        }
        if let id = continuingFeatureID {
            let nodes = draftNodes
            var result = id
            editFeatures { list in
                guard let i = list.firstIndex(where: { $0.id == id }) else { return }
                list[i].nodes = nodes
                if kind == .area { list[i].kind = .area }
                if autoMerge { result = autoMerged(id, in: &list) }
            }
            selectedFeatureID = result
            draftNodes = []
            continuingFeatureID = nil
            return
        }
        var f = Feature(kind: kind, colorHex: pen.colorHex, widthMM: pen.widthMM, nodes: draftNodes)
        stampActiveSymbol(&f)
        addFeature(f, merge: true)
        draftNodes = []
    }

    /// Gambar bebas: goresan disederhanakan (toleransi 0,1 mm kertas) lalu jadi garis, atau area bila simbolnya area.
    /// `guideRadiusM`: bagian goresan yang menyusuri objek lain sejauh ini menempel ke bentuk objek itu
    /// (bila panduan objek aktif).
    func addFreehand(_ points: [Point2D], guideRadiusM: Double = 0) {
        let tolerance = project.sheet.groundMeters(forPaperMM: 0.1)
        var nodes: [BezierNode]
        if followGuides, guideRadiusM > 0 {
            let guides = features.filter { $0.isVisible && $0.kind != .point }
            nodes = GuideTrace.trace(points, guides: guides, radius: guideRadiusM, simplifyTolerance: tolerance)
        } else {
            nodes = ContourGenerator.simplify(points, tolerance: tolerance).map { BezierNode(point: $0) }
        }
        let asArea = activeSymbol?.kind == .area && nodes.count >= 3
        guard nodes.count >= 2 else { return }
        // Area: titik akhir yang dekat titik awal tidak diulang (area menutup sendiri).
        if asArea, let first = nodes.first, let last = nodes.last, first.point.distance(to: last.point) < tolerance * 20 { nodes.removeLast() }
        var f = Feature(kind: asArea ? .area : .line, colorHex: pen.colorHex, widthMM: pen.widthMM, nodes: nodes)
        stampActiveSymbol(&f)
        addFeature(f, merge: true)
    }

    // MARK: Simbol ↔ objek (seperti OCAD/OOM)

    /// Pilih objek; simbolnya ikut terpilih di panel (tanpa mengganti alat).
    func select(_ f: Feature) {
        selectedFeatureID = f.id
        selectedNodeIndex = nil
        extraSelectedIDs = []
        if let code = f.symbolCode, let s = symbolLookup?(code) {
            activeSymbol = s
            symbolSizeFactor = 1
        }
    }

    /// Simbol dipilih di panel saat ada objek terpilih: simpan sebagai kandidat "Ganti simbol", alat tidak berubah.
    func chooseSymbolForSelection(_ s: MapSymbol) {
        activeSymbol = s
        symbolSizeFactor = 1
    }

    /// Ganti simbol objek terpilih dengan simbol aktif (OOM: Switch symbol). Jenis harus cocok.
    func switchSelectedSymbol() {
        guard let s = activeSymbol else { return }
        switchSelectedSymbol(to: s)
    }

    /// Ganti simbol objek terpilih ke `s` (satu langkah undo). `allSame`: semua objek yang tidak dikunci dan
    /// bersimbol sama ikut diganti (OCAD: Change symbol untuk semua objek simbol itu).
    func switchSelectedSymbol(to s: MapSymbol, allSame: Bool = false) {
        guard let f = selectedFeature, !f.isLocked, f.canSwitch(to: s) else { return }
        let code = f.symbolCode
        var changed = 0, skipped = 0
        editFeatures { list in
            for i in list.indices {
                let target = list[i].id == f.id
                    || (allSame && code != nil && list[i].symbolCode == code && !list[i].isLocked)
                guard target else { continue }
                if list[i].switchSymbol(to: s) { changed += 1 } else { skipped += 1 }
            }
        }
        activeSymbol = s
        symbolSizeFactor = 1
        if allSame {
            notice = "\(changed) objek diganti ke \(s.code) \(s.name)"
                + (skipped > 0 ? " · \(skipped) dilewati (jenis tidak cocok)." : ".")
        }
    }

    /// Jumlah objek (tidak dikunci) yang memakai simbol objek terpilih, termasuk objek itu sendiri.
    var sameSymbolCount: Int {
        guard let code = selectedFeature?.symbolCode else { return 0 }
        return features.filter { $0.symbolCode == code && !$0.isLocked }.count
    }

    func canSwitch(_ f: Feature, to s: MapSymbol) -> Bool { f.canSwitch(to: s) }

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
        case let .courses(before, _):
            setCourses(before)
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
        case let .courses(_, after):
            setCourses(after)
        }
    }

    func record(_ edit: Edit) {
        undoStack.append(edit)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
    }

    func apply(_ next: Project, recordUndo: Bool = true) {
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

    /// Tanggal ubah hanya ditulis ke file (tidak mengubah `project` yang @Published), dan status simpan hanya
    /// diumumkan bila berubah: tiap edit tidak lagi memicu dua kali render seluruh layar (uji performa).
    func scheduleSave() {
        var saved = project
        saved.updatedAt = Date()
        if saveState != .saving { saveState = .saving }
        let doc = ProjectDocument(project: saved, strokes: strokes, features: features, courses: courseSet)
        let writer = writer
        Task { [weak self] in
            await writer.schedule(doc) { [weak self] result in
                Task { @MainActor [weak self] in
                    switch result {
                    case .success: if self?.saveState != .saved { self?.saveState = .saved }
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
