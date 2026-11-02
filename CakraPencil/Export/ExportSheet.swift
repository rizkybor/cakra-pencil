import CakraCore
import SwiftUI
import UIKit

/// Export raster sketsa + world file + .prj (FR-6.1, FR-6.2, FR-6.8).
/// Default sesuai mitigasi risiko MapKit: tanpa piksel Apple Maps.
struct ExportSheet: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    @State private var format = RasterFormat.tiff
    @State private var dpi: Int
    @State private var includePRJ = true
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
                                   format: format, strokes: model.strokes, includePRJ: includePRJ)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Raster") {
                    Picker("Format", selection: $format) {
                        ForEach(RasterFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Resolusi", selection: $dpi) {
                        ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                    }
                    Toggle("Sertakan .prj (WKT CRS)", isOn: $includePRJ)
                }

                if let req = request {
                    Section("Hasil") {
                        let d = req.pixelDimensions
                        LabeledContent("Dimensi") { Text(Fmt.pixels(d.width, d.height)).font(CP.mono(15)) }
                        LabeledContent("Piksel di tanah") { Text(Fmt.meters(req.pixelSize, decimals: 4)).font(CP.mono(15)) }
                        LabeledContent("Memori render") { Text(Fmt.bytes(req.estimatedBitmapBytes)).font(CP.mono(15)) }
                        LabeledContent("File") {
                            Text(([req.format.fileExtension, req.format.worldFileExtension] + (includePRJ ? ["prj"] : [])).map { ".\($0)" }.joined(separator: " + "))
                                .font(CP.mono(15))
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
                    Text("OOM: Templates → Open template → pilih file gambar. OCAD: Background map → Open. World file terbaca otomatis.")
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
                            .disabled(request == nil)
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
        guard let req = request else { return }
        running = true
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        Task.detached(priority: .userInitiated) {
            let result = Result { try RasterExporter.export(req, to: dir) }
            await MainActor.run {
                running = false
                switch result {
                case let .success(r): shareItems = ShareItems(urls: r.allFiles)
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
