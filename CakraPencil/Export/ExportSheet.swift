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
    @State private var running = false
    @State private var error: String?
    @State private var shareItems: ShareItems?

    struct ShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    init(model: WorkspaceModel) {
        self.model = model
        _dpi = State(initialValue: model.project.sketchDPI)
    }

    private var request: RasterExportRequest? {
        guard let frame = model.frame, let zone = model.zone else { return nil }
        let p = model.project
        let base = "\(safeName(p.name))_1-\(p.sheet.scaleDenominator)_\(dpi)dpi"
        return RasterExportRequest(baseName: base, frame: frame, sheet: p.sheet, zone: zone, dpi: dpi,
                                   format: format, strokes: exportedStrokes, features: model.features, grid: model.project.grid,
                                   includePRJ: includePRJ)
    }

    private var vectorRequest: VectorExportRequest? {
        guard let frame = model.frame, let zone = model.zone else { return nil }
        let p = model.project
        return VectorExportRequest(baseName: "\(safeName(p.name))_1-\(p.sheet.scaleDenominator)", frame: frame,
                                   sheet: p.sheet, zone: zone, strokes: exportedStrokes, features: model.features, grid: model.project.grid)
    }

    private var pdfRequest: GeoPDFRequest? {
        guard let frame = model.frame, let zone = model.zone else { return nil }
        return GeoPDFRequest(title: model.project.name, frame: frame, sheet: model.project.sheet, zone: zone,
                             strokes: exportedStrokes, features: model.features, grid: model.project.grid)
    }

    /// Layer sketsa yang disembunyikan di panel layer tidak ikut export, sama seperti objek tersembunyi.
    private var exportedStrokes: [Stroke] { model.sketchVisible ? model.strokes : [] }

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
                        Button("Export") { run() }
                            .disabled(request == nil || plannedFiles.isEmpty)
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

    private func safeName(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = s.replacingOccurrences(of: " ", with: "-").unicodeScalars.filter { allowed.contains($0) }
        let out = String(String.UnicodeScalarView(cleaned))
        return out.isEmpty ? "cakra" : out
    }
}

/// Share Sheet / AirDrop / Files untuk beberapa file sekaligus.
struct ActivityView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
