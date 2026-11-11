import CakraCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    /// "Other formats" (raster, OMAP, DXF, IOF XML, PNG) expanded; collapsed by default.
    @State private var showMoreFormats = false
    /// File name typed by the user; nil = the default for the mode.
    @State private var fileNameText: String?
    /// Files saved by the last export (shows the "Saved" screen).
    @State private var saved: [URL]?
    /// The same files in the temporary export folder, for Share… (no folder access needed).
    @State private var savedSources: [URL] = []
    /// Export folder picker, and the folder shown in Location (refreshed after a change).
    @State private var pickingFolder = false
    @State private var folderLabel = ExportDestination.displayPath
    @State private var customFolder = ExportDestination.customFolder != nil

    /// Default file name: project + scale for the map sheet, project for courses, project + interval for contours.
    private var defaultFileName: String {
        let p = model.project
        switch mode {
        case .sheet: return "\(safeName(p.name))_1-\(p.sheet.scaleDenominator)"
        case .courses: return safeName(p.name)
        case .contours:
            let i = model.contourSettings.intervalM
            let interval = Fmt.number(i, decimals: i.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1).replacingOccurrences(of: ".", with: "-")
            return "\(safeName(p.name))_contours_\(interval)m"
        }
    }

    /// The file name used for every exported file (extensions and course names are added).
    private var fileBase: String {
        let typed = ExportDestination.cleanFileName(fileNameText ?? "")
        return typed.isEmpty ? defaultFileName : typed
    }

    init(model: WorkspaceModel, mode: Mode = .sheet) {
        self.model = model
        _dpi = State(initialValue: model.project.sketchDPI)
        _mode = State(initialValue: mode)
        // Default on every plan: PDF only. Raster, vector, IOF XML and course PNG are optional extras (Pro).
        _includeRaster = State(initialValue: false)
        _vectorFormats = State(initialValue: [])
        _includeIOFXML = State(initialValue: false)
    }

    private var request: RasterExportRequest? {
        guard let frame = model.frame, let zone = model.zone else { return nil }
        let p = model.project
        return RasterExportRequest(baseName: fileBase, frame: frame, sheet: p.sheet, zone: zone, dpi: dpi,
                                   format: format, strokes: exportedStrokes, features: exportedFeatures, grid: model.project.grid,
                                   includePRJ: includePRJ)
    }

    private var vectorRequest: VectorExportRequest? {
        guard let frame = model.frame, let zone = model.zone else { return nil }
        let p = model.project
        return VectorExportRequest(baseName: fileBase, frame: frame,
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
                if let saved {
                    savedSections(saved)
                } else {
                // Course export has its own entry (Course panel); the workspace switches map sheet / contours.
                if mode != .courses {
                    Section {
                        Segmented("Export content", selection: $mode, [Mode.sheet, .contours].map { .init($0, $0.rawValue) })
                    }
                }
                fileNameSection
                switch mode {
                case .contours:
                    if license.isPro {
                        contourSections
                    } else {
                        Section {
                            proToggle("Contours (SHP, KML, KMZ)", isOn: .constant(false), .contours)
                        } footer: {
                            Text("Contour data export needs a Professional or Organization license.")
                        }
                    }
                case .courses: courseSections
                case .sheet: sheetSections
                }
                }
            }
            .navigationTitle(saved == nil ? "Export" : "Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Group {
                    if saved == nil { CloseIconButton { dismiss() } }
                }.buttonStyle(SecondaryButtonStyle(compact: true)) }.plainBar()
                ToolbarItem(placement: .sheetConfirm) { Group {
                    if saved != nil {
                        Button("Done") { dismiss() }
                    } else if running {
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
        .frame(minWidth: CP.isMac ? 620 : nil, minHeight: CP.isMac ? 760 : nil)
        .modifier(PageSizedSheet())
        #if DEBUG
        // Screenshots: `-cp-export-more` opens Other formats.
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-cp-export-more") { showMoreFormats = true } }
        // `-cp-export-run`: press Export once the sheet is up (checks saving + the Saved screen).
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-cp-export-run") else { return }
            try? await Task.sleep(for: .seconds(1))
            switch mode {
            case .contours: runContours()
            case .courses: runCourses()
            case .sheet: run()
            }
        }
        #endif
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
            Label("No issues", systemImage: "checkmark")
                .foregroundStyle(CP.sage.strong)
        }
    }

    // MARK: Layout

    /// File name for the export, saved in the device's Documents (OCCA › Exports).
    private var fileNameSection: some View {
        Section {
            HStack(spacing: CP.Space.s) {
                TextField(defaultFileName, text: Binding(get: { fileNameText ?? defaultFileName }, set: { fileNameText = $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(CP.mono(15))
                    .accessibilityIdentifier("exportFileName")
                if fileNameText != nil && fileNameText != defaultFileName {
                    Button("Reset") { fileNameText = nil }
                        .font(.system(size: CP.fs(13)))
                        .buttonStyle(.borderless)
                }
            }
            HStack(spacing: CP.Space.s) {
                Image(systemName: "folder")
                    .foregroundStyle(CP.inkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location")
                    Text(folderLabel)
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                if customFolder {
                    Button("Default") { setFolder(nil) }
                        .font(.system(size: CP.fs(13)))
                        .buttonStyle(.borderless)
                        .help("Back to \(ExportDestination.defaultDisplayPath)")
                }
                Button("Change…") { pickingFolder = true }
                    .font(.system(size: CP.fs(13)))
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("exportChangeFolder")
            }
        } header: {
            Text("Save as")
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { setFolder(url) }
        }
    }

    private func setFolder(_ url: URL?) {
        do {
            try ExportDestination.setCustomFolder(url)
        } catch {
            self.error = error.localizedDescription
        }
        folderLabel = ExportDestination.displayPath
        customFolder = ExportDestination.customFolder != nil
    }

    /// Map sheet: the georeferenced PDF (default), basemap, then the optional editing formats.
    @ViewBuilder
    private var sheetSections: some View {
        let sheet = model.project.sheet
        Section {
            formatToggle("Georeferenced PDF", icon: "doc.richtext", isOn: $includePDF,
                         detail: "\(sheet.paper.name) · 1:\(sheet.scaleDenominator) · vector",
                         hint: "Ready to print at scale. Georeferenced: positions read in Avenza Maps, QGIS and Adobe Acrobat.")
        } header: {
            Text("PDF")
        } footer: {
            if !license.isPro { Text(creditNote) }
        }
        basemapSection
        Section {
            moreFormatsRow(summary: sheetExtrasSummary,
                           hint: "For editing in other apps. Raster: a template in OOM or a background map in OCAD (lines become pixels). OMAP and DXF: every object stays editable with its ISOM code. OOM: open the .omap, then Templates › Open template for the image. OCAD: File › Import for DXF.")
            if showMoreFormats {
                proToggle("Raster + world file", isOn: $includeRaster, .rasterExport)
                if includeRaster && license.isPro {
                    Segmented("Format", selection: $format, RasterFormat.allCases.map { .init($0, $0.label) })
                    Picker("Resolution", selection: $dpi) {
                        ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                    }
                    Toggle("Include .prj (WKT CRS)", isOn: $includePRJ)
                }
                proToggle("OOM .omap", isOn: vectorBinding(.omap), .vectorExport)
                proToggle("DXF R12 (OCAD, QGIS)", isOn: vectorBinding(.dxf), .vectorExport)
            }
        }
        if let req = request {
            Section("Output") {
                LabeledContent("Files") {
                    Text(plannedFiles.isEmpty ? "Choose a format" : plannedFiles.map { fileBase + $0 }.joined(separator: "\n"))
                        .font(CP.mono(13))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(plannedFiles.isEmpty ? CP.butter.strong : CP.ink)
                }
                if includeRaster && license.isPro {
                    let d = req.pixelDimensions
                    LabeledContent("Raster size") { Text(Fmt.pixels(d.width, d.height)).font(CP.mono(13)) }
                    LabeledContent("Pixel on ground") { Text(Fmt.meters(req.pixelSize, decimals: 4)).font(CP.mono(13)) }
                }
                checkRows(ExportCheck(strokes: model.strokes, frame: req.frame), locked: model.project.areaLocked)
            }
        }
    }

    private var sheetExtrasSummary: String {
        var parts: [String] = []
        if includeRaster && license.isPro { parts.append(format.label) }
        parts += VectorFormat.allCases.filter(vectorFormats.contains).map { $0.fileExtension.uppercased() }
        return parts.isEmpty ? "Optional · raster image, OOM .omap, DXF" : parts.joined(separator: " · ")
    }

    /// Free plan note under the PDF option.
    private var creditNote: String {
        (LicenseManager.requiresKey ? "Without a license" : "Starter") + ": a small \"Made with \(AppInfo.name)\" credit in the corner."
    }

    /// Main format row: icon, title, one line of detail, switch.
    private func formatToggle(_ title: String, icon: String, isOn: Binding<Bool>, detail: String, hint: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .center, spacing: CP.Space.m) {
                Image(systemName: icon)
                    .font(.system(size: CP.fs(20)))
                    .foregroundStyle(CP.sky.strong)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text(title)
                        InfoHint(hint)
                    }
                    Text(detail)
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                }
            }
        }
        .accessibilityIdentifier(title)
    }

    /// Collapsed row for the optional formats; shows which are on.
    private func moreFormatsRow(summary: String, hint: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("Other formats").foregroundStyle(CP.ink)
                    InfoHint(hint)
                }
                Text(summary)
                    .font(.system(size: CP.fs(12)))
                    .foregroundStyle(CP.inkMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: CP.fs(13), weight: .semibold))
                .foregroundStyle(CP.inkMuted)
                .rotationEffect(.degrees(showMoreFormats ? 90 : 0))
        }
        .contentShape(Rectangle())
        // A tap gesture (not a Button) so the ⓘ inside stays its own button.
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showMoreFormats.toggle() } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("exportMoreFormats")
    }

    /// After saving: where the files are, open the folder, or share them.
    @ViewBuilder
    private func savedSections(_ urls: [URL]) -> some View {
        Section {
            HStack(spacing: CP.Space.m) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: CP.fs(28)))
                    .foregroundStyle(CP.sage.strong)
                VStack(alignment: .leading, spacing: 2) {
                    Text(urls.count == 1 ? "1 file saved" : "\(urls.count) files saved")
                        .font(.system(size: CP.fs(17), weight: .semibold))
                    Text(folderLabel)
                        .font(.system(size: CP.fs(13)))
                        .foregroundStyle(CP.inkMuted)
                }
            }
            .padding(.vertical, CP.Space.xs)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("exportSaved")
        }
        Section("Files") {
            ForEach(urls, id: \.self) { url in
                Text(url.lastPathComponent).font(CP.mono(13))
            }
        }
        Section {
            Button {
                ExportDestination.reveal()
            } label: {
                Label(CP.isMac ? "Show in Finder" : "Show in Files", systemImage: "folder")
            }
            Button {
                shareItems = ShareItems(urls: savedSources.isEmpty ? urls : savedSources)
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
    }

    /// Copies the exported files from the temporary folder into the export folder (default Documents › OCCA › Exports).
    private func save(_ urls: [URL]) {
        do {
            saved = try ExportDestination.save(urls)
            savedSources = urls
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Basemap in the export (off by default): the HD Apple Maps image or the GeoTIFF basemap in use.
    @ViewBuilder
    private var basemapSection: some View {
        let source = model.exportBackgroundSource
        Section {
            Toggle(isOn: $includeBasemap) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text("Include basemap")
                        InfoHint(source?.attribution != nil
                                 ? "Placed under the map in the PDF and raster at the current basemap opacity, with the \"\(source?.attribution ?? "")\" credit. OMAP/DXF get it as a separate image + world file. Apple Maps imagery is subject to Apple's terms; check them before publishing or selling maps that contain it."
                                 : "Placed under the map in the PDF and raster at the current basemap opacity. OMAP/DXF get it as a separate image + world file.")
                    }
                    Text(source?.label ?? "No basemap image yet")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                }
            }
            .disabled(source == nil)
            .accessibilityIdentifier("exportIncludeBasemap")
        } header: {
            Text("Basemap")
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
        let sheet = model.project.sheet
        Section {
            formatToggle("Race map PDF", icon: "doc.richtext", isOn: $includeCoursePDF,
                         detail: "One page per course · \(sheet.paper.name) · 1:\(sheet.scaleDenominator)",
                         hint: "Map with the purple overprint, control descriptions, title and scale, plus the text, shapes and images from the Objects tab. Set where the descriptions go in Descriptions › Print layout.")
        } header: {
            Text("PDF")
        } footer: {
            if !license.isPro { Text(creditNote) }
        }
        Section {
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
            Text("Courses to print")
        }
        basemapSection
        Section {
            moreFormatsRow(summary: courseExtrasSummary,
                           hint: "IOF XML: all controls and courses (codes, positions, order, leg lengths, climb) for MeOS, OE/SportSoftware, SI Config, Purple Pen or OCAD. PNG: map and overprint only, with a world file.")
            if showMoreFormats {
                proToggle("IOF XML 3.0 (CourseData)", isOn: $includeIOFXML, .courseExport)
                proToggle("Course map PNG + world file", isOn: $includeCoursePNG, .courseExport)
            }
        }
        let warnings = set.warnings()
        Section("Output") {
            LabeledContent("Files") {
                Text(coursePlannedFiles.isEmpty ? "Choose a format" : coursePlannedFiles.joined(separator: "\n"))
                    .font(CP.mono(13))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(coursePlannedFiles.isEmpty ? CP.butter.strong : CP.ink)
            }
            if set.controls.isEmpty {
                Label("No controls yet. Place them in the Course panel.", systemImage: "exclamationmark.triangle").foregroundStyle(CP.butter.strong)
            } else if warnings.isEmpty {
                Label("No issues", systemImage: "checkmark").foregroundStyle(CP.sage.strong)
            } else {
                ForEach(warnings.prefix(6), id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(CP.butter.strong) }
            }
        }
    }

    private var courseExtrasSummary: String {
        var parts: [String] = []
        if includeIOFXML && license.isPro { parts.append("IOF XML") }
        if includeCoursePNG && license.isPro { parts.append("PNG") }
        return parts.isEmpty ? "Optional · IOF XML 3.0, PNG + world file" : parts.joined(separator: " · ")
    }

    /// File names the course export writes (same names as in runCourses).
    private var coursePlannedFiles: [String] {
        let names = (printAllControls ? ["All controls"] : []) + selectedPrintCourses.map(\.name)
        var files: [String] = []
        if includeIOFXML && license.isPro { files.append("\(fileBase)_IOF3.xml") }
        for n in names {
            let file = "\(fileBase)_\(safeFileName(n))"
            if includeCoursePDF { files.append(file + ".pdf") }
            if includeCoursePNG && license.isPro { files += [file + ".png", file + ".pgw"] + (includePRJ ? [file + ".prj"] : []) }
        }
        return files
    }

    private func runCourses() {
        guard let frame = model.frame, let zone = model.zone, let base = request else { return }
        running = true
        let dir = TempExports.newDirectory()
        let set = model.courseSet, sheet = model.project.sheet
        let name = fileBase
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
                    let url = dir.appendingPathComponent("\(name)_IOF3.xml")
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
                        r.overprintLowerPriority = ColorHierarchy.lowerPurplePriority(for: sheet.mapStandard)
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
                case let .success(urls): save(urls)
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
            HStack(spacing: 0) {
                Text("Format")
                InfoHint("Shapefile uses the project's UTM coordinates (\(model.zone?.label ?? "UTM")) with ELEV, TYPE and ISOM attributes, plus .prj. KML/KMZ use WGS84 lon/lat for Google Earth and map apps.")
            }
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
        let base = fileBase
        Task.detached(priority: .userInitiated) {
            let result = Result { try ContourExporter.export(lines, formats: formats, zone: zone, settings: settings, baseName: base, title: title, to: dir) }
            await MainActor.run {
                running = false
                switch result {
                case let .success(urls): save(urls)
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
                case let .success(urls): save(urls)
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
