import CakraCore
import SwiftUI
import UIKit

/// Export raster sketsa + world file + .prj (FR-6.1, FR-6.2), vektor .omap / DXF (FR-6.4, FR-6.5), dan PDF
/// ter-georeferensi, dibagikan lewat Share Sheet (FR-6.8). Default sesuai mitigasi risiko MapKit: tanpa piksel Apple Maps.
struct ExportSheet: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    @State private var includeRaster = true
    @State private var format = RasterFormat.tiff
    @State private var dpi: Int
    @State private var includePRJ = true
    @State private var vectorFormats: Set<VectorFormat> = [.omap, .dxf]
    @State private var includePDF = true
    @State private var mode: Mode
    @State private var contourFormats: Set<ContourExportFormat> = [.shp, .kmz]

    /// Lembar peta lengkap, atau data kontur saja (SHP / KML / KMZ).
    enum Mode: String, CaseIterable {
        case sheet = "Lembar peta"
        case contours = "Kontur saja"
        case courses = "Lintasan"
    }
    @State private var includeIOFXML = true
    @State private var includeCoursePDF = true
    @State private var includeCoursePNG = false
    /// Lintasan yang dicetak (PDF/PNG per lintasan); default semua.
    @State private var printCourses: Set<UUID>?
    /// Juga cetak "Semua kontrol" (master: kode kontrol, tanpa leg) + deskripsinya.
    @State private var includeAllControls: Bool?
    @State private var running = false
    @State private var error: String?
    @State private var shareItems: ShareItems?

    struct ShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    init(model: WorkspaceModel, mode: Mode = .sheet) {
        self.model = model
        _dpi = State(initialValue: model.project.sketchDPI)
        _mode = State(initialValue: mode)
    }

    private var request: RasterExportRequest? {
        guard let frame = model.frame, let zone = model.zone else { return nil }
        let p = model.project
        let base = "\(safeName(p.name))_1-\(p.sheet.scaleDenominator)_\(dpi)dpi"
        return RasterExportRequest(baseName: base, frame: frame, sheet: p.sheet, zone: zone, dpi: dpi,
                                   format: format, strokes: exportedStrokes, features: exportedFeatures, grid: model.project.grid,
                                   includePRJ: includePRJ)
    }

    private var vectorRequest: VectorExportRequest? {
        guard let frame = model.frame, let zone = model.zone else { return nil }
        let p = model.project
        return VectorExportRequest(baseName: "\(safeName(p.name))_1-\(p.sheet.scaleDenominator)", frame: frame,
                                   sheet: p.sheet, zone: zone, strokes: exportedStrokes, features: exportedFeatures, grid: model.project.grid)
    }

    private var pdfRequest: GeoPDFRequest? {
        guard let frame = model.frame, let zone = model.zone else { return nil }
        return GeoPDFRequest(title: model.project.name, frame: frame, sheet: model.project.sheet, zone: zone,
                             strokes: exportedStrokes, features: exportedFeatures, grid: model.project.grid)
    }

    /// Layer sketsa yang disembunyikan di panel layer tidak ikut export, sama seperti objek tersembunyi.
    private var exportedStrokes: [Stroke] { model.sketchVisible ? model.strokes : [] }

    /// Kontur (bila tampil dan ikut export) digambar paling bawah, lalu objek vektor proyek.
    /// Urutan gambar mengikuti Color Hierarchy set simbol (warna lebih atas menimpa yang di bawah).
    private var exportedFeatures: [Feature] { model.layered(model.contourExportFeatures + model.features) }

    private var plannedFiles: [String] {
        var files: [String] = []
        if includeRaster {
            files += [format.fileExtension, format.worldFileExtension] + (includePRJ ? ["prj"] : [])
        }
        files += VectorFormat.allCases.filter(vectorFormats.contains).map(\.fileExtension)
        if includePDF { files.append("pdf") }
        return files.map { ".\($0)" }
    }

    private func vectorBinding(_ f: VectorFormat) -> Binding<Bool> {
        Binding(get: { vectorFormats.contains(f) }, set: { on in
            if on { vectorFormats.insert(f) } else { vectorFormats.remove(f) }
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Isi export", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if mode == .contours {
                    contourSections
                } else if mode == .courses {
                    courseSections
                } else {
                Section {
                    Toggle("Raster + world file", isOn: $includeRaster)
                    if includeRaster {
                        Picker("Format", selection: $format) {
                            ForEach(RasterFormat.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Resolusi", selection: $dpi) {
                            ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                        }
                        Toggle("Sertakan .prj (WKT CRS)", isOn: $includePRJ)
                    }
                } header: {
                    Text("Raster")
                } footer: {
                    Text("Dibuka sebagai template (OOM) atau background map (OCAD). Garis jadi piksel, tidak bisa dipilih.")
                }

                Section {
                    Toggle("OOM .omap", isOn: vectorBinding(.omap))
                    Toggle("DXF R12 (OCAD, QGIS)", isOn: vectorBinding(.dxf))
                } header: {
                    Text("Vektor")
                } footer: {
                    Text("Setiap objek bisa dipilih dan diedit. Objek bersimbol membawa kode ISOM aslinya; sketsa tanpa simbol memakai 990.x per warna + tebal.")
                }

                Section {
                    Toggle("PDF ter-georeferensi", isOn: $includePDF)
                } header: {
                    Text("PDF")
                } footer: {
                    Text("Vektor seukuran kertas \(model.project.sheet.paper.name) pada 1:\(model.project.sheet.scaleDenominator), siap cetak. Georeferensi Geospatial PDF: posisi terbaca di Avenza Maps, QGIS, dan Adobe Acrobat.")
                }

                if let req = request {
                    Section("Hasil") {
                        if includeRaster {
                            let d = req.pixelDimensions
                            LabeledContent("Dimensi") { Text(Fmt.pixels(d.width, d.height)).font(CP.mono(15)) }
                            LabeledContent("Piksel di tanah") { Text(Fmt.meters(req.pixelSize, decimals: 4)).font(CP.mono(15)) }
                            LabeledContent("Memori render") { Text(Fmt.bytes(req.estimatedBitmapBytes)).font(CP.mono(15)) }
                        }
                        if let v = vectorRequest, !vectorFormats.isEmpty {
                            LabeledContent("Objek vektor") {
                                Text(verbatim: "\(v.exportedFeatures.count) bezier + \(v.exportedStrokes.count) stroke").font(CP.mono(15))
                            }
                        }
                        LabeledContent("File") {
                            Text(plannedFiles.joined(separator: " + ")).font(CP.mono(15))
                        }
                    }
                    Section("Cek sebelum export") {
                        checkRows(ExportCheck(strokes: model.strokes, frame: req.frame), locked: model.project.areaLocked)
                    }
                }

                Section {
                    Text("Lapisan: sketsa Pencil, latar transparan (JPEG: putih). Citra Apple Maps tidak ikut di-export.")
                        .font(.system(size: 13))
                        .foregroundStyle(CP.inkMuted)
                    Text("OOM: buka .omap langsung, lalu Templates → Open template untuk gambar. OCAD: File → Import untuk DXF, Background map → Open untuk gambar. World file terbaca otomatis.")
                        .font(.system(size: 13))
                        .foregroundStyle(CP.inkMuted)
                }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if running {
                        ProgressView()
                    } else {
                        Button("Export") {
                            switch mode {
                            case .contours: runContours()
                            case .courses: runCourses()
                            case .sheet: run()
                            }
                        }
                        .disabled(exportDisabled)
                    }
                }
            }
            .alert("Export gagal", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .sheet(item: $shareItems) { items in
                ActivityView(items: items.urls)
            }
        }
    }

    @ViewBuilder
    private func checkRows(_ check: ExportCheck, locked: Bool) -> some View {
        if !locked {
            Label("Area belum dikunci", systemImage: "exclamationmark.triangle")
                .foregroundStyle(CP.butter.strong)
        }
        if check.outside > 0 {
            Label("\(check.outside) stroke di luar frame, tidak ikut ter-export", systemImage: "exclamationmark.triangle")
                .foregroundStyle(CP.butter.strong)
        }
        if check.partlyOutside > 0 {
            Label("\(check.partlyOutside) stroke terpotong tepi frame", systemImage: "scissors")
                .foregroundStyle(CP.butter.strong)
        }
        if locked && check.isClean {
            Label(model.strokes.isEmpty ? "Belum ada sketsa; raster akan kosong" : "Tidak ada masalah", systemImage: "checkmark")
                .foregroundStyle(model.strokes.isEmpty ? CP.inkMuted : CP.sage.strong)
        }
    }

    private var exportDisabled: Bool {
        switch mode {
        case .contours: return model.contourLines.isEmpty || contourFormats.isEmpty
        case .courses:
            return request == nil || model.courseSet.controls.isEmpty
                || (!includeIOFXML && ((!includeCoursePDF && !includeCoursePNG) || (selectedPrintCourses.isEmpty && !printAllControls)))
        case .sheet: return request == nil || plannedFiles.isEmpty
        }
    }

    // MARK: Lintasan

    /// Bawaan: aktif bila export dibuka dari tampilan "Semua kontrol" atau belum ada lintasan.
    private var printAllControls: Bool {
        includeAllControls ?? (model.selectedCourseID == nil || model.courseSet.courses.isEmpty)
    }

    private var selectedPrintCourses: [Course] {
        model.courseSet.courses.filter { printCourses?.contains($0.id) ?? true }
    }

    private func printBinding(_ c: Course) -> Binding<Bool> {
        Binding(get: { printCourses?.contains(c.id) ?? true }, set: { on in
            var s = printCourses ?? Set(model.courseSet.courses.map(\.id))
            if on { s.insert(c.id) } else { s.remove(c.id) }
            printCourses = s
        })
    }

    @ViewBuilder
    private var courseSections: some View {
        let set = model.courseSet
        Section {
            Toggle("IOF XML 3.0 (CourseData)", isOn: $includeIOFXML)
        } header: {
            Text("Punching elektronik")
        } footer: {
            Text("Semua kontrol dan lintasan: kode, posisi lat/lon dan mm peta, urutan, panjang leg, tanjakan, jumlah peserta. Impor ke MeOS, OE/SportSoftware, SI Config, Purple Pen, atau OCAD.")
        }
        Section {
            Toggle("PDF peta lomba (deskripsi, judul, skala)", isOn: $includeCoursePDF)
            Toggle("PNG peta lintasan + world file", isOn: $includeCoursePNG)
            Toggle(isOn: Binding(get: { printAllControls }, set: { includeAllControls = $0 })) {
                HStack {
                    Text("Semua kontrol (master)")
                    Spacer()
                    Text(verbatim: "\(set.controls.filter { $0.kind == .control }.count) kontrol").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                }
            }
            .accessibilityIdentifier("exportAllControls")
            ForEach(set.courses) { c in
                Toggle(isOn: printBinding(c)) {
                    HStack {
                        Text(c.name)
                        Spacer()
                        Text(verbatim: c.kind == .score ? "Score" : Fmt.km(set.length(of: c))).font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                    }
                }
            }
        } header: {
            Text("Cetak per lintasan")
        } footer: {
            Text("Peta \(model.project.sheet.paper.name) 1:\(model.project.sheet.scaleDenominator) dengan overprint ungu (start, kontrol bernomor, leg, finish). PDF: peta lomba satu halaman dengan deskripsi kontrol di atas peta, plus teks, bentuk, dan gambar dari tab Objek (atur posisi deskripsi di tab Deskripsi → Tata letak cetak). PNG: peta + overprint saja, ber-world file.")
        }
        let warnings = set.warnings()
        Section("Cek sebelum export") {
            if set.controls.isEmpty {
                Label("Belum ada kontrol. Tempatkan di panel Lintasan.", systemImage: "exclamationmark.triangle").foregroundStyle(CP.butter.strong)
            } else if warnings.isEmpty {
                Label("Tidak ada masalah", systemImage: "checkmark").foregroundStyle(CP.sage.strong)
            } else {
                ForEach(warnings.prefix(6), id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(CP.butter.strong) }
            }
        }
    }

    private func runCourses() {
        guard let frame = model.frame, let zone = model.zone, let base = request else { return }
        running = true
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        let set = model.courseSet, sheet = model.project.sheet
        let name = safeName(model.project.name)
        // nil = "Semua kontrol" (master), dicetak lebih dulu.
        let courses: [Course?] = (printAllControls ? [nil] : []) + selectedPrintCourses.map { Optional($0) }
        let includeXML = includeIOFXML, includePDF = includeCoursePDF, includePNG = includeCoursePNG
        let allID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let pdfRequests = Dictionary(uniqueKeysWithValues: courses.compactMap { c in model.coursePDFRequest(for: c).map { (c?.id ?? allID, $0) } })
        Task.detached(priority: .userInitiated) {
            let result = Result { () -> [URL] in
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var urls: [URL] = []
                if includeXML {
                    let url = dir.appendingPathComponent("\(name)_lintasan_IOF3.xml")
                    try IOFXMLExporter.courseData(set, frame: frame, sheet: sheet, zone: zone).write(to: url, options: .atomic)
                    urls.append(url)
                }
                for c in courses {
                    let overprint = CourseOverprint.make(set, course: c, sheet: sheet)
                    let key = c?.id ?? allID
                    let file = "\(name)_\(safeFileName(c?.name ?? "Semua kontrol"))"
                    if includePDF {
                        let url = dir.appendingPathComponent(file).appendingPathExtension("pdf")
                        guard let req = pdfRequests[key] else { continue }
                        try GeoPDFExporter.export(req, to: url)
                        urls.append(url)
                    }
                    if includePNG {
                        var r = base
                        r.baseName = file
                        r.format = .png
                        r.overprint = overprint
                        r.overprintImages = pdfRequests[key]?.images ?? [:]
                        urls += try RasterExporter.export(r, to: dir).allFiles
                    }
                }
                return urls
            }
            await MainActor.run {
                running = false
                switch result {
                case let .success(urls): shareItems = ShareItems(urls: urls)
                case let .failure(e): error = e.localizedDescription
                }
            }
        }
    }

    // MARK: Kontur saja

    private func contourBinding(_ f: ContourExportFormat) -> Binding<Bool> {
        Binding(get: { contourFormats.contains(f) }, set: { on in
            if on { contourFormats.insert(f) } else { contourFormats.remove(f) }
        })
    }

    @ViewBuilder
    private var contourSections: some View {
        Section {
            ForEach(ContourExportFormat.allCases) { f in
                Toggle(f.label, isOn: contourBinding(f))
            }
        } header: {
            Text("Format")
        } footer: {
            Text("Shapefile memakai koordinat UTM proyek (\(model.zone?.label ?? "UTM")) dengan atribut ELEV, TYPE, dan ISOM, plus .prj. KML/KMZ memakai lon/lat WGS84 untuk Google Earth dan aplikasi peta.")
        }
        Section("Data") {
            if model.contourLines.isEmpty {
                Label("Belum ada kontur. Unduh kontur bawaan atau upload DEM di panel Kontur.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(CP.butter.strong)
            } else {
                let s = model.contourSettings
                LabeledContent("Garis") {
                    Text(verbatim: "\(model.contourLines.count) (\(model.contourLines.filter { $0.kind == .index }.count) indeks)").font(CP.mono(15))
                }
                LabeledContent("Interval") {
                    Text(verbatim: "\(Fmt.number(s.intervalM, decimals: 1)) m · indeks tiap \(s.indexEvery)").font(CP.mono(15))
                }
                if let r = model.contourRelief {
                    LabeledContent("Elevasi") {
                        Text(verbatim: "\(Fmt.number(r.min, decimals: 0))–\(Fmt.number(r.max, decimals: 0)) m").font(CP.mono(15))
                    }
                }
                LabeledContent("File") {
                    Text(contourPlannedFiles.joined(separator: " + ")).font(CP.mono(13))
                }
            }
        }
    }

    private var contourPlannedFiles: [String] {
        ContourExportFormat.allCases.filter(contourFormats.contains).flatMap { f -> [String] in
            f == .shp ? [".shp", ".shx", ".dbf", ".prj", ".cpg"] : [".\(f.rawValue)"]
        }
    }

    private func runContours() {
        guard let zone = model.zone, !model.contourLines.isEmpty else { return }
        running = true
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        let lines = model.contourLines, formats = contourFormats, settings = model.contourSettings
        let title = "Kontur \(model.project.name)"
        let base = "\(safeName(model.project.name))_kontur_\(Fmt.number(settings.intervalM, decimals: settings.intervalM.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1).replacingOccurrences(of: ",", with: "-"))m"
        Task.detached(priority: .userInitiated) {
            let result = Result { try ContourExporter.export(lines, formats: formats, zone: zone, settings: settings, baseName: base, title: title, to: dir) }
            await MainActor.run {
                running = false
                switch result {
                case let .success(urls): shareItems = ShareItems(urls: urls)
                case let .failure(e): error = e.localizedDescription
                }
            }
        }
    }

    private func run() {
        guard let raster = request, let vector = vectorRequest, let pdf = pdfRequest else { return }
        running = true
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        let includeRaster = includeRaster
        let vectorFormats = vectorFormats
        let includePDF = includePDF
        let pdfURL = dir.appendingPathComponent(vector.baseName).appendingPathExtension("pdf")
        Task.detached(priority: .userInitiated) {
            let result = Result { () -> [URL] in
                var urls: [URL] = []
                if includeRaster { urls += try RasterExporter.export(raster, to: dir).allFiles }
                urls += try VectorExporter.export(vector, formats: vectorFormats, to: dir)
                if includePDF {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try GeoPDFExporter.export(pdf, to: pdfURL)
                    urls.append(pdfURL)
                }
                return urls
            }
            await MainActor.run {
                running = false
                switch result {
                case let .success(urls): shareItems = ShareItems(urls: urls)
                case let .failure(e): error = e.localizedDescription
                }
            }
        }
    }

    private func safeName(_ s: String) -> String { safeFileName(s) }
}

/// Nama file aman (huruf, angka, - dan _).
func safeFileName(_ s: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let cleaned = s.replacingOccurrences(of: " ", with: "-").unicodeScalars.filter { allowed.contains($0) }
    let out = String(String.UnicodeScalarView(cleaned))
    return out.isEmpty ? "cakra" : out
}

/// Share Sheet / AirDrop / Files untuk beberapa file sekaligus.
struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
