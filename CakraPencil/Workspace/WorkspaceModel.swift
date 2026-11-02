import CakraCore
import CoreLocation
import Foundation
import MapKit

enum Tool: String, CaseIterable, Identifiable {
    case area, navigate, pen, eraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .area: return "Frame A4"
        case .navigate: return "Navigasi"
        case .pen: return "Pena"
        case .eraser: return "Penghapus stroke"
        }
    }

    var symbol: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .navigate: return "hand.raised"
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        }
    }

    var shortcut: Character {
        switch self {
        case .area: return "a"
        case .navigate: return "v"
        case .pen: return "p"
        case .eraser: return "e"
        }
    }

    var draws: Bool { self == .pen || self == .eraser }
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
    @Published var tool: Tool
    @Published var pen = PenPreset.isom[0]
    @Published var basemap = Basemap.satellite
    @Published var fingerDraws = false
    @Published var showsInspector = true
    @Published private(set) var saveState = SaveState.saved
    @Published var mapCommand: MapCommand?
    @Published var notice: String?
    @Published var confirmUnlock = false

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
    }

    init(document: ProjectDocument, url: URL) {
        self.project = document.project
        self.strokes = document.strokes
        self.url = url
        self.writer = ProjectWriter(url: url)
        self.tool = document.project.areaLocked ? .pen : .area
    }

    var frame: MapFrame? { project.frame }
    var zone: UTMZone? { project.zone }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Frame (FR-1.3 – FR-1.10)

    /// Tempatkan frame berpusat di koordinat; CRS UTM dipilih otomatis dari lokasi (FR-1.2).
    func placeFrame(centeredAt c: LatLon, recordUndo: Bool = true) {
        guard !project.areaLocked else { return }
        let zone = UTMZone(containing: c)
        var next = project
        next.crsEPSG = zone.epsg
        next.frameOrigin = MapFrame(center: zone.project(c), sheet: project.sheet).snapped(toStep: project.snapStepM).origin
        apply(next, recordUndo: recordUndo)
    }

    /// Geser frame selama drag; zona dievaluasi ulang di `finishFrameDrag`.
    func moveFrame(origin: Point2D) {
        guard !project.areaLocked else { return }
        var next = project
        next.frameOrigin = origin
        apply(next, recordUndo: false)
    }

    private var dragStart: Project?

    func beginFrameDrag() { dragStart = project }

    func finishFrameDrag() {
        guard let start = dragStart, let frame, let zone else { return }
        dragStart = nil
        let centerLL = zone.unproject(frame.center)
        if UTMZone(containing: centerLL) != zone {
            placeFrame(centeredAt: centerLL, recordUndo: false)
        } else {
            var next = project
            next.frameOrigin = frame.snapped(toStep: project.snapStepM).origin
            apply(next, recordUndo: false)
        }
        record(.project(before: start, after: project))
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
        tool = .area
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
        let doc = ProjectDocument(project: project, strokes: strokes)
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
            arrive(at: c)
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
            arrive(at: LatLon(lat: c.latitude, lon: c.longitude))
        } catch {
            notice = "Pencarian butuh internet. Masukkan koordinat lat, lon atau UTM (mis. 48S 787500 9234500)."
        }
    }

    /// Terbang ke lokasi; frame ikut pindah bila area belum dikunci dan belum ada sketsa.
    private func arrive(at c: LatLon) {
        if !project.areaLocked && strokes.isEmpty {
            placeFrame(centeredAt: c)
            mapCommand = MapCommand(kind: .zoomToFrame)
        } else {
            mapCommand = MapCommand(kind: .center(c, spanM: 1500))
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
