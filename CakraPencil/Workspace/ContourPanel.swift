import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Panel kontur (FR-8): sumber data, interval, indeks, form line, smoothing, tampilan, info relief,
/// dan "Jadikan objek vektor" untuk mengedit garis kontur.
struct ContourPanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var importing = false

    private var s: ContourSettings { model.contourSettings }

    private static let types: [UTType] = [
        UTType(filenameExtension: "tif") ?? .tiff, .tiff,
        UTType(filenameExtension: "asc", conformingTo: .data) ?? .data,
        UTType(filenameExtension: "geojson", conformingTo: .json) ?? .json, .json,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.l) {
                HStack {
                    Text("Tampilkan kontur").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
                    Spacer()
                    Toggle("Kontur", isOn: Binding(get: { s.isEnabled }, set: { on in model.updateContours { $0.isEnabled = on } }))
                        .labelsHidden()
                        .tint(CP.sage.strong)
                        .disabled(!model.hasContourData)
                }
                if model.hasContourData { opacityControl }
                status
                sourceSection
                if model.hasContourData {
                    Divider().overlay(CP.line)
                    intervalSection
                    Divider().overlay(CP.line)
                    styleSection
                    Divider().overlay(CP.line)
                    actions
                }
                Text("Data elevasi bawaan: Terrain Tiles (AWS Open Data; Mapzen, SRTM/NASA, dan sumber lain). Untuk peta detail pakai DEM sendiri, mis. DEMNAS (BIG) atau LiDAR.")
                    .font(.system(size: 11))
                    .foregroundStyle(CP.inkMuted)
            }
            .padding(CP.Space.l)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.types) { result in
            if case let .success(url) = result { Task { await model.importContourFile(url) } }
        }
    }

    // MARK: Opacity

    /// Naik/turun opacity 10% per ketukan, atau geser slider (5–100%). Hanya mengubah gaya gambar.
    private var opacityControl: some View {
        VStack(alignment: .leading, spacing: CP.Space.xs) {
            HStack(spacing: CP.Space.s) {
                Text("Opacity").font(.system(size: 15)).foregroundStyle(CP.ink)
                Spacer()
                Button { model.stepContourOpacity(by: -0.1) } label: { Image(systemName: "minus") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(s.opacity <= ContourSettings.opacityRange.lowerBound)
                    .accessibilityLabel("Turunkan opacity kontur")
                Text(verbatim: "\(Int((s.opacity * 100).rounded()))%")
                    .font(CP.mono(15, weight: .medium))
                    .foregroundStyle(CP.ink)
                    .frame(width: 52)
                Button { model.stepContourOpacity(by: 0.1) } label: { Image(systemName: "plus") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(s.opacity >= ContourSettings.opacityRange.upperBound)
                    .accessibilityLabel("Naikkan opacity kontur")
            }
            Slider(value: Binding(get: { s.opacity }, set: { v in model.updateContours { $0.opacity = v } }),
                   in: ContourSettings.opacityRange)
                .tint(Color(hexString: s.colorHex))
                .accessibilityLabel("Opacity kontur")
                .accessibilityValue("\(Int((s.opacity * 100).rounded())) persen")
        }
        .disabled(!s.isEnabled)
        .opacity(s.isEnabled ? 1 : 0.5)
    }

    // MARK: Status dan sumber

    @ViewBuilder
    private var status: some View {
        switch model.contourStatus {
        case let .downloading(done, total):
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("Mengunduh data elevasi \(done)/\(total) tile…").font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            }
        case .importing:
            HStack { ProgressView().controlSize(.small); Text("Membaca file…").font(.system(size: 12)).foregroundStyle(CP.inkMuted) }
        case .generating:
            HStack { ProgressView().controlSize(.small); Text("Menghitung kontur…").font(.system(size: 12)).foregroundStyle(CP.inkMuted) }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(CP.rose.strong)
        case .idle:
            EmptyView()
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Text("SUMBER").font(.system(size: 12, weight: .semibold)).tracking(0.6).foregroundStyle(CP.inkMuted)
            if let dem = model.dem {
                info("Data", dem.header.source)
                info("Resolusi", "±\(Fmt.number(dem.header.nativeResolutionM, decimals: 1)) m · grid \(Fmt.number(dem.cellSize, decimals: 1)) m")
            } else if let lines = model.importedContours {
                info("Data", "Garis kontur impor · \(lines.count) garis")
            } else {
                Text("Belum ada data kontur untuk area ini.")
                    .font(.system(size: 13))
                    .foregroundStyle(CP.inkMuted)
            }
            if let r = model.contourRelief {
                info("Elevasi", "\(Fmt.number(r.min, decimals: 0))–\(Fmt.number(r.max, decimals: 0)) m · beda \(Fmt.number(r.max - r.min, decimals: 0)) m")
                info("Garis", "\(model.contourLines.count) (\(model.contourLines.filter { $0.kind == .index }.count) indeks)")
            }
            HStack(spacing: CP.Space.s) {
                Button {
                    Task { await model.downloadBuiltInContours() }
                } label: {
                    Label(model.dem?.header.source.hasPrefix("Terrain") == true ? "Unduh ulang" : "Kontur bawaan", systemImage: "icloud.and.arrow.down")
                        .lineLimit(1)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button { importing = true } label: { Label("Upload", systemImage: "square.and.arrow.down").lineLimit(1) }
                    .buttonStyle(.bordered)
                    .tint(CP.ink)
            }
            .disabled(model.frame == nil || isBusy)
            Text("Upload: DEM GeoTIFF (.tif) atau ASCII Grid (.asc) → kontur dihitung di iPad; atau garis kontur GeoJSON dengan properti elev.")
                .font(.system(size: 11))
                .foregroundStyle(CP.inkMuted)
        }
    }

    private var isBusy: Bool {
        switch model.contourStatus {
        case .downloading, .importing: return true
        default: return false
        }
    }

    // MARK: Interval

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Text("INTERVAL").font(.system(size: 12, weight: .semibold)).tracking(0.6).foregroundStyle(CP.inkMuted)
            HStack(spacing: CP.Space.xs) {
                ForEach(ContourSettings.intervalPresetsM, id: \.self) { v in
                    Button { model.updateContours { $0.intervalM = v } } label: {
                        Text(verbatim: "\(Fmt.number(v, decimals: v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) m")
                            .font(CP.mono(12, weight: s.intervalM == v ? .semibold : .regular))
                            .foregroundStyle(s.intervalM == v ? CP.sage.strong : CP.ink)
                            .padding(.horizontal, CP.Space.s)
                            .frame(height: 28)
                            .background(s.intervalM == v ? CP.sage.fill : CP.paper2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            stepper("Interval", value: s.intervalM, step: 0.5, range: ContourSettings.intervalRangeM, text: "\(Fmt.number(s.intervalM, decimals: 1)) m") { v in
                model.updateContours { $0.intervalM = v }
            }
            if let res = model.dem?.header.nativeResolutionM, let warning = s.intervalWarning(nativeResolutionM: res) {
                Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(CP.butter.strong)
            }
            stepper("Indeks tiap", value: Double(s.indexEvery), step: 1, range: 2...10, text: "\(s.indexEvery) garis") { v in
                model.updateContours { $0.indexEvery = Int(v) }
            }
            stepper("Elevasi dasar", value: s.baseOffsetM, step: 0.5, range: -50...50, text: "\(Fmt.number(s.baseOffsetM, decimals: 1)) m") { v in
                model.updateContours { $0.baseOffsetM = v }
            }
            Toggle("Form line (½ interval, putus-putus)", isOn: Binding(get: { s.showFormLines }, set: { on in model.updateContours { $0.showFormLines = on } }))
                .font(.system(size: 13))
                .tint(CP.sage.strong)
            VStack(alignment: .leading, spacing: CP.Space.xs) {
                Text("Penghalusan").font(.system(size: 15)).foregroundStyle(CP.ink)
                Picker("Penghalusan", selection: Binding(get: { s.smoothing }, set: { v in model.updateContours { $0.smoothing = v } })) {
                    ForEach(0...3, id: \.self) { Text(verbatim: $0 == 0 ? "Mati" : "\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            stepper("Panjang minimum", value: s.minLengthMM, step: 0.5, range: 0...20, text: Fmt.mm(s.minLengthMM, decimals: 1)) { v in
                model.updateContours { $0.minLengthMM = v }
            }
        }
    }

    // MARK: Tampilan

    private static let colors: [(String, String)] = [("Coklat ISOM", "#D15C00"), ("Coklat tua", "#8E4A2F"), ("Hitam", "#000000"), ("Biru", "#00A0E6")]

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Text("TAMPILAN").font(.system(size: 12, weight: .semibold)).tracking(0.6).foregroundStyle(CP.inkMuted)
            HStack(spacing: CP.Space.s) {
                Text("Warna").font(.system(size: 15)).foregroundStyle(CP.ink)
                Spacer()
                ForEach(Self.colors, id: \.1) { name, hex in
                    Button { model.updateContours { $0.colorHex = hex } } label: {
                        Circle().fill(Color(hexString: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(s.colorHex == hex ? CP.peach.strong : CP.line, lineWidth: s.colorHex == hex ? 2 : 1).padding(-3))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Kontur \(name)")
                }
            }
            stepper("Tebal kontur", value: s.contourWidthMM, step: 0.01, range: 0.05...1, text: Fmt.mm(s.contourWidthMM)) { v in
                model.updateContours { $0.contourWidthMM = PenPreset.clampWidth(v) }
            }
            stepper("Tebal indeks", value: s.indexWidthMM, step: 0.01, range: 0.05...1.5, text: Fmt.mm(s.indexWidthMM)) { v in
                model.updateContours { $0.indexWidthMM = PenPreset.clampWidth(v) }
            }
            Button("Kembalikan ke standar ISOM (0,14 / 0,25 mm, coklat)") {
                model.updateContours {
                    $0.contourWidthMM = 0.14
                    $0.indexWidthMM = 0.25
                    $0.colorHex = "#D15C00"
                    $0.opacity = 1
                }
            }
            .font(.system(size: 12))
            Toggle("Ikut export (101.0 / 102.0 / 103.0)", isOn: Binding(get: { s.includeInExport }, set: { on in model.updateContours { $0.includeInExport = on } }))
                .font(.system(size: 13))
                .tint(CP.sage.strong)
        }
    }

    // MARK: Aksi

    private var actions: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Button { model.freezeContours() } label: {
                Label("Jadikan objek vektor (bisa diedit)", systemImage: "scribble.variable").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.contourLines.isEmpty || !s.isEnabled)
            Text("Garis kontur jadi objek di panel Layer: geser, hapus, atau edit titiknya dengan alat Pilih. Kontur otomatis disembunyikan agar tidak dobel.")
                .font(.system(size: 11))
                .foregroundStyle(CP.inkMuted)
            Button { model.exportContoursOnly = true } label: {
                Label("Export kontur saja (SHP, KML, KMZ)…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(CP.ink)
            .disabled(model.contourLines.isEmpty)
            Button(role: .destructive) { model.removeContourData() } label: {
                Label("Hapus data kontur proyek ini", systemImage: "trash")
            }
            .font(.system(size: 13))
        }
    }

    // MARK: Bantuan

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13)).foregroundStyle(CP.inkMuted)
            Spacer()
            Text(value).font(CP.mono(12)).foregroundStyle(CP.ink).multilineTextAlignment(.trailing)
        }
    }

    private func stepper(_ label: String, value: Double, step: Double, range: ClosedRange<Double>, text: String,
                         set: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: set), in: range, step: step) {
            HStack {
                Text(label).font(.system(size: 15)).foregroundStyle(CP.ink)
                Spacer()
                Text(verbatim: text).font(CP.mono(13)).foregroundStyle(CP.ink)
            }
        }
    }
}
