import CakraCore
import SwiftUI
import UIKit

/// Export sketch raster + world file + .prj (FR-6.1, FR-6.2), .omap / DXF vectors (FR-6.4, FR-6.5), and a
/// georeferenced PDF, shared via the Share Sheet (FR-6.8). Defaults follow the MapKit risk mitigation: no Apple Maps pixels.
struct ExportSheet: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var license = LicenseManager.shared

    @State private var includeRaster = true
    @State private var format = RasterFormat.tiff
    @State private var dpi: Int
    @State private var includePRJ = true
    @State private var vectorFormats: Set<VectorFormat> = [.omap, .dxf]
    @State private var includePDF = true
    /// Put the basemap in use (HD Apple Maps image or GeoTIFF) under the map in the export.
    @State private var includeBasemap = false
    @State private var mode: Mode
    @State private var contourFormats: Set<ContourExportFormat> = [.shp, .kmz]

    /// Full map sheet, or contour data only (SHP / KML / KMZ).
    enum Mode: String, CaseIterable {
        case sheet = "Map sheet"
        case contours = "Contours only"
        case courses = "Courses"
    }
    @State private var includeIOFXML = true
    @State private var includeCoursePDF = true
    @State private var includeCoursePNG = false
    /// Courses to print (PDF/PNG per course); default all.
    @State private var printCourses: Set<UUID>?
    /// Also print "All controls" (master: control codes, no legs) + its descriptions.
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
        // Free plan: PDF only (raster, vector, IOF XML, and course PNG are Pro).
        let pro = MainActor.assumeIsolated { LicenseManager.shared.isPro }
        _includeRaster = State(initialValue: pro)
        _vectorFormats = State(initialValue: pro ? [.omap, .dxf] : [])
        _includeIOFXML = State(initialValue: pro)
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

    /// A sketch layer hidden in the layer panel is not exported, just like hidden objects.
    private var exportedStrokes: [Stroke] { model.sketchVisible ? model.strokes : [] }

    /// Contours (when shown and included in export) are drawn at the bottom, then the project's vector objects.
    /// Drawing order follows the symbol set's Color Hierarchy (higher colors cover lower ones).
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
                    Segmented("Export content", selection: $mode, Mode.allCases.map { .init($0, $0.rawValue) })
                }
                if mode == .contours && !license.isPro {
                    Section {
                        proToggle("Contours (SHP, KML, KMZ)", isOn: .constant(false), .contours)
                    } footer: {
                        Text("Contour data export needs a Professional or Organization license.")
                    }
                } else if mode == .contours {
                    contourSections
                } else if mode == .courses {
                    courseSections
                    basemapSection
                } else {
                basemapSection
                Section {
                    proToggle("Raster + world file", isOn: $includeRaster, .rasterExport)
                    if includeRaster && license.isPro {
                        Segmented("Format", selection: $format, RasterFormat.allCases.map { .init($0, $0.label) })
                        Picker("Resolution", selection: $dpi) {
                            ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                        }
                        Toggle("Include .prj (WKT CRS)", isOn: $includePRJ)
                    }
                } header: {
                    Text("Raster")
                } footer: {
                    Text("Opens as a template (OOM) or background map (OCAD). Lines become pixels and can't be selected.")
                }

                Section {
                    proToggle("OOM .omap", isOn: vectorBinding(.omap), .vectorExport)
                    proToggle("DXF R12 (OCAD, QGIS)", isOn: vectorBinding(.dxf), .vectorExport)
                } header: {
                    Text("Vector")
                } footer: {
                    Text("Every object can be selected and edited. Symbol objects keep their original ISOM code; sketches without a symbol use 990.x per color + width.")
                }

                Section {
                    Toggle("Georeferenced PDF", isOn: $includePDF)
                } header: {
                    Text("PDF")
                } footer: {
                    Text((license.isPro ? "" : (LicenseManager.requiresKey ? "Without a license: a small" : "Starter plan: a small") + " \"Made with \(AppInfo.name)\" credit is printed in the map corner. ") + "Vectors at \(model.project.sheet.paper.name) paper size at 1:\(model.project.sheet.scaleDenominator), ready to print. Geospatial PDF georeferencing: positions read in Avenza Maps, QGIS, and Adobe Acrobat.")
                }

                if let req = request {
                    Section("Output") {
                        if includeRaster {
                            let d = req.pixelDimensions
                            LabeledContent("Dimensions") { Text(Fmt.pixels(d.width, d.height)).font(CP.mono(15)) }
                            LabeledContent("Pixel on ground") { Text(Fmt.meters(req.pixelSize, decimals: 4)).font(CP.mono(15)) }
                            LabeledContent("Render memory") { Text(Fmt.bytes(req.estimatedBitmapBytes)).font(CP.mono(15)) }
                        }
                        if let v = vectorRequest, !vectorFormats.isEmpty {
                            LabeledContent("Vector objects") {
                                Text(verbatim: "\(v.exportedFeatures.count) bezier + \(v.exportedStrokes.count) stroke").font(CP.mono(15))
                            }
                        }
                        LabeledContent("File") {
                            Text(plannedFiles.joined(separator: " + ")).font(CP.mono(15))
                        }
                    }
                    Section("Pre-export check") {
                        checkRows(ExportCheck(strokes: model.strokes, frame: req.frame), locked: model.project.areaLocked)
                    }
                }

                Section {
                    Text(includeBasemap && model.exportBackgroundSource != nil
                         ? "Layers: basemap image, map objects, Pencil sketch."
                         : "Layers: map objects, Pencil sketch, transparent background (JPEG: white). The basemap is only exported when Include basemap is on.")
                        .font(.system(size: CP.fs(13)))
                        .foregroundStyle(CP.inkMuted)
                    Text("OOM: open the .omap directly, then Templates → Open template for the image. OCAD: File → Import for DXF, Background map → Open for the image. The world file is read automatically.")
                        .font(.system(size: CP.fs(13)))
                        .foregroundStyle(CP.inkMuted)
                }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Group {
                    Button("Close") { dismiss() }
                }.buttonStyle(SecondaryButtonStyle(compact: true)) }.plainBar()
                ToolbarItem(placement: .sheetConfirm) { Group {
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
                }.buttonStyle(PrimaryButtonStyle(compact: true)) }.plainBar()
            }
            .alert("Export failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
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
            Label("Area not locked", systemImage: "exclamationmark.triangle")
                .foregroundStyle(CP.butter.strong)
        }
        if check.outside > 0 {
            Label("\(check.outside) strokes outside the frame, not exported", systemImage: "exclamationmark.triangle")
                .foregroundStyle(CP.butter.strong)
        }
        if check.partlyOutside > 0 {
            Label("\(check.partlyOutside) strokes clipped by the frame edge", systemImage: "scissors")
                .foregroundStyle(CP.butter.strong)
        }
        if locked && check.isClean {
            Label(model.strokes.isEmpty ? "No sketch yet; the raster will be empty" : "No issues", systemImage: "checkmark")
                .foregroundStyle(model.strokes.isEmpty ? CP.inkMuted : CP.sage.strong)
        }
    }

    /// Basemap in the export (off by default): the HD Apple Maps image or the GeoTIFF basemap in use.
    @ViewBuilder
    private var basemapSection: some View {
        let source = model.exportBackgroundSource
        Section {
            Toggle(isOn: $includeBasemap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include basemap")
                    Text(source?.label ?? "No basemap image yet (the HD image is downloaded once the area is locked)")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                }
            }
            .disabled(source == nil)
            .accessibilityIdentifier("exportIncludeBasemap")
        } header: {
            Text("Basemap")
        } footer: {
            Text(source?.attribution != nil
                 ? "Georeferenced under the map in PNG/TIFF/JPEG and PDF, at the current basemap opacity, with the \"\(source?.attribution ?? "")\" credit. OMAP/DXF get it as a separate image + world file (OOM template). Apple Maps imagery is subject to Apple's terms; check them before publishing or selling maps that contain it."
                 : "Georeferenced under the map in PNG/TIFF/JPEG and PDF, at the current basemap opacity. OMAP/DXF get it as a separate image + world file (OOM template).")
        }
    }

    private var exportDisabled: Bool {
        switch mode {
        case .contours: return !license.isPro || model.contourLines.isEmpty || contourFormats.isEmpty
        case .courses:
            return request == nil || model.courseSet.controls.isEmpty
                || (!includeIOFXML && ((!includeCoursePDF && !includeCoursePNG) || (selectedPrintCourses.isEmpty && !printAllControls)))
        case .sheet: return request == nil || plannedFiles.isEmpty
        }
    }

    // MARK: Courses

    /// Default: on when export is opened from the "All controls" view or there are no courses yet.
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
            proToggle("IOF XML 3.0 (CourseData)", isOn: $includeIOFXML, .courseExport)
        } header: {
            Text("Electronic punching")
        } footer: {
            Text("All controls and courses: codes, lat/lon and map mm positions, order, leg lengths, climb, number of competitors. Import into MeOS, OE/SportSoftware, SI Config, Purple Pen, or OCAD.")
        }
        Section {
            Toggle("Race map PDF (descriptions, title, scale)", isOn: $includeCoursePDF)
            proToggle("Course map PNG + world file", isOn: $includeCoursePNG, .courseExport)
            Toggle(isOn: Binding(get: { printAllControls }, set: { includeAllControls = $0 })) {
                HStack {
                    Text("All controls (master)")
                    Spacer()
                    Text(verbatim: "\(set.controls.filter { $0.kind == .control }.count) controls").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
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
            Text("Print per course")
        } footer: {
            Text("\(model.project.sheet.paper.name) map at 1:\(model.project.sheet.scaleDenominator) with purple overprint (start, numbered controls, legs, finish). PDF: one-page race map with control descriptions on the map, plus text, shapes, and images from the Objects tab (set the description position in Descriptions tab → Print layout). PNG: map + overprint only, with world file.")
        }
        let warnings = set.warnings()
        Section("Pre-export check") {
            if set.controls.isEmpty {
                Label("No controls yet. Place them in the Course panel.", systemImage: "exclamationmark.triangle").foregroundStyle(CP.butter.strong)
            } else if warnings.isEmpty {
                Label("No issues", systemImage: "checkmark").foregroundStyle(CP.sage.strong)
            } else {
                ForEach(warnings.prefix(6), id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(CP.butter.strong) }
            }
        }
    }

    private func runCourses() {
        guard let frame = model.frame, let zone = model.zone, let base = request else { return }
        running = true
        let dir = TempExports.newDirectory()
        let set = model.courseSet, sheet = model.project.sheet
        let name = safeName(model.project.name)
        // nil = "All controls" (master), printed first.
        let courses: [Course?] = (printAllControls ? [nil] : []) + selectedPrintCourses.map { Optional($0) }
        let pro = license.isPro
        let includeXML = includeIOFXML && pro, includePDF = includeCoursePDF, includePNG = includeCoursePNG && pro
        let watermark = pro ? nil : Self.freeCredit
        let allID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let pdfRequests = Dictionary(uniqueKeysWithValues: courses.compactMap { c in model.coursePDFRequest(for: c).map { (c?.id ?? allID, $0) } })
        let backgroundSource = includeBasemap ? model.exportBackgroundSource : nil
        Task.detached(priority: .userInitiated) {
            let result = Result { () -> [URL] in
                let background = try backgroundSource?.load()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var urls: [URL] = []
                if includeXML {
                    let url = dir.appendingPathComponent("\(name)_courses_IOF3.xml")
                    try IOFXMLExporter.courseData(set, frame: frame, sheet: sheet, zone: zone).write(to: url, options: .atomic)
                    urls.append(url)
                }
                for c in courses {
                    let overprint = CourseOverprint.make(set, course: c, sheet: sheet)
                    let key = c?.id ?? allID
                    let file = "\(name)_\(safeFileName(c?.name ?? "All controls"))"
                    if includePDF {
                        let url = dir.appendingPathComponent(file).appendingPathExtension("pdf")
                        guard var req = pdfRequests[key] else { continue }
                        req.background = background
                        req.watermark = watermark
                        try GeoPDFExporter.export(req, to: url)
                        urls.append(url)
                    }
                    if includePNG {
                        var r = base
                        r.baseName = file
                        r.format = .png
                        r.overprint = overprint
                        r.overprintImages = pdfRequests[key]?.images ?? [:]
                        r.background = background
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

    // MARK: Contours only

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
            Text("Shapefile uses the project's UTM coordinates (\(model.zone?.label ?? "UTM")) with ELEV, TYPE, and ISOM attributes, plus .prj. KML/KMZ use WGS84 lon/lat for Google Earth and map apps.")
        }
        Section("Data") {
            if model.contourLines.isEmpty {
                Label("No contours yet. Download built-in contours or upload a DEM in the Contours panel.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(CP.butter.strong)
            } else {
                let s = model.contourSettings
                LabeledContent("Lines") {
                    Text(verbatim: "\(model.contourLines.count) (\(model.contourLines.filter { $0.kind == .index }.count) index)").font(CP.mono(15))
                }
                LabeledContent("Interval") {
                    Text(verbatim: "\(Fmt.number(s.intervalM, decimals: 1)) m · index every \(s.indexEvery)").font(CP.mono(15))
                }
                if let r = model.contourRelief {
                    LabeledContent("Elevation") {
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
        let dir = TempExports.newDirectory()
        let lines = model.contourLines, formats = contourFormats, settings = model.contourSettings
        let title = "Contours \(model.project.name)"
        let base = "\(safeName(model.project.name))_contours_\(Fmt.number(settings.intervalM, decimals: settings.intervalM.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1).replacingOccurrences(of: ".", with: "-"))m"
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
        let dir = TempExports.newDirectory()
        let pro = license.isPro
        let includeRaster = includeRaster && pro
        let vectorFormats = pro ? vectorFormats : []
        let includePDF = includePDF
        let watermark = pro ? nil : Self.freeCredit
        let pdfURL = dir.appendingPathComponent(vector.baseName).appendingPathExtension("pdf")
        let backgroundSource = includeBasemap ? model.exportBackgroundSource : nil
        Task.detached(priority: .userInitiated) {
            let result = Result { () -> [URL] in
                let background = try backgroundSource?.load()
                var raster = raster, vector = vector, pdf = pdf
                raster.background = background
                vector.background = background
                pdf.background = background
                pdf.watermark = watermark
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

    /// Credit printed on PDFs exported on the Free plan.
    static var freeCredit: String { LicenseManager.requiresKey ? "Made with \(AppInfo.name)" : "Made with \(AppInfo.name) · Starter" }

    /// Toggle for a Pro export option; on the Free plan a locked row that opens the plans screen.
    @ViewBuilder
    private func proToggle(_ title: String, isOn: Binding<Bool>, _ feature: ProFeature) -> some View {
        if license.isPro {
            Toggle(title, isOn: isOn)
        } else {
            Button { license.require(feature) } label: {
                HStack {
                    Text(title).foregroundStyle(CP.inkMuted)
                    Spacer()
                    ProLockBadge()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), Pro feature")
            .accessibilityIdentifier("locked-\(feature.rawValue)")
        }
    }
}

/// Safe file name (letters, digits, - and _).
func safeFileName(_ s: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let cleaned = s.replacingOccurrences(of: " ", with: "-").unicodeScalars.filter { allowed.contains($0) }
    let out = String(String.UnicodeScalarView(cleaned))
    return out.isEmpty ? "cakra" : out
}

/// Share Sheet / AirDrop / Files for several files at once.
struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
