import CakraCore
import SwiftUI

/// Inspector kanan: pengaturan frame, info frame (FR-1.9), dan basemap.
struct InspectorPanel: View {
    @ObservedObject var model: WorkspaceModel

    @State private var tab = InspectorPanel.initialTab

    enum Tab: String, CaseIterable {
        case layers = "Layer"
        case symbols = "Simbol"
        case contours = "Kontur"
        case courses = "Course"
        case map = "Peta"
    }

    private static var initialTab: Tab {
        #if DEBUG
        // Untuk screenshot/UI test: `-cp-inspector-tab Simbol`.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-cp-inspector-tab"), i + 1 < args.count, let t = Tab(rawValue: args[i + 1]) { return t }
        #endif
        return .layers
    }

    private var sheet: SheetSpec { model.project.sheet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Panel", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], CP.Space.l)
            .padding(.bottom, CP.Space.s)

            switch tab {
            case .layers:
                LayerPanel(model: model)
                    .padding(.horizontal, CP.Space.m)
                    .padding(.bottom, CP.Space.m)
            case .symbols:
                SymbolPanel(model: model)
                    .padding(.horizontal, CP.Space.m)
                    .padding(.bottom, CP.Space.m)
            case .contours:
                ContourPanel(model: model)
            case .courses:
                CoursePanel(model: model)
            case .map:
                ScrollView {
                    VStack(alignment: .leading, spacing: CP.Space.l) {
                        frameSection
                        Divider().overlay(CP.line)
                        basemapSection
                        Divider().overlay(CP.line)
                        gridSection
                        Divider().overlay(CP.line)
                        infoSection
                    }
                    .padding(CP.Space.l)
                }
            }
        }
        .frame(height: 600)
        .cpPanel()
    }

    private var frameSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            SectionTitle("Area terkunci")
            Mono("Lembar", "\(sheet.paper.name) \(sheet.orientation == .portrait ? "Portrait" : "Landscape") · 1:\(sheet.scaleDenominator)")
            Row("Resolusi") {
                Picker("dpi", selection: Binding(get: { model.project.sketchDPI }, set: { model.setDPI($0) })) {
                    ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                }
            }

            Button { model.requestUnlock() } label: {
                Label("Pilih ulang area", systemImage: "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Grid garis utara

    private static let gridColors: [(String, String)] = [
        ("Biru", "#00A0E6"), ("Hitam", "#000000"), ("Ungu", "#A626FF"), ("Merah", "#E30613"), ("Abu", "#7F7F7F"),
    ]

    private var gridSection: some View {
        let g = model.project.grid
        return VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack {
                SectionTitle("Grid garis utara")
                Spacer()
                Toggle("Grid", isOn: Binding(get: { g.isEnabled }, set: { on in model.updateGrid { $0.isEnabled = on } }))
                    .labelsHidden()
                    .tint(CP.sage.strong)
            }
            if g.isEnabled {
                Picker("Acuan", selection: Binding(get: { g.reference }, set: { r in model.updateGrid { $0.reference = r } })) {
                    ForEach(NorthGrid.Reference.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if g.reference == .magnetic {
                    Stepper(value: Binding(get: { g.declinationDeg }, set: { v in model.updateGrid { $0.declinationDeg = (v * 10).rounded() / 10 } }),
                            in: -30...30, step: 0.1) {
                        HStack {
                            Text("Deklinasi").font(.system(size: 15)).foregroundStyle(CP.ink)
                            Spacer()
                            Text(verbatim: String(format: "%+.1f° %@", g.declinationDeg, g.declinationDeg >= 0 ? "T" : "B"))
                                .font(CP.mono(13)).foregroundStyle(CP.ink)
                        }
                    }
                    Text("Isi dari peta deklinasi resmi atau kalkulator NOAA untuk lokasi dan tanggal survei.")
                        .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                }
                Row("Jarak") {
                    Menu {
                        ForEach(NorthGrid.spacingPresetsM, id: \.self) { m in
                            Button { model.updateGrid { $0.spacingM = m } } label: {
                                Text(verbatim: "\(Int(m)) m · \(Fmt.mm(m / Double(sheet.scaleDenominator) * 1000, decimals: 1)) di kertas")
                            }
                        }
                    } label: {
                        Text(verbatim: "\(Int(g.spacingM)) m").font(CP.mono(15)).foregroundStyle(CP.sage.strong)
                    }
                    Stepper("", value: Binding(get: { g.spacingM }, set: { v in model.updateGrid { $0.spacingM = v } }),
                            in: NorthGrid.spacingRangeM, step: 10)
                        .labelsHidden()
                }
                Text(verbatim: "= \(Fmt.mm(g.spacingPaperMM(scale: sheet.scaleDenominator), decimals: 1)) di kertas pada 1:\(sheet.scaleDenominator)")
                    .font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                HStack(spacing: CP.Space.s) {
                    Text("Warna").font(.system(size: 15)).foregroundStyle(CP.ink)
                    Spacer()
                    ForEach(Self.gridColors, id: \.1) { name, hex in
                        Button { model.updateGrid { $0.colorHex = hex } } label: {
                            Circle().fill(Color(hexString: hex)).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(g.colorHex == hex ? CP.peach.strong : CP.line, lineWidth: g.colorHex == hex ? 2 : 1).padding(-3))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Grid \(name)")
                    }
                    ColorPicker("Warna lain", selection: Binding(get: { Color(hexString: g.colorHex) }, set: { c in
                        model.updateGrid { $0.colorHex = UIColor(c).hexString }
                    }), supportsOpacity: false)
                    .labelsHidden()
                }
                HStack(spacing: CP.Space.s) {
                    Text("Opacity").font(.system(size: 15)).foregroundStyle(CP.ink)
                    Slider(value: Binding(get: { g.opacity }, set: { v in model.updateGrid { $0.opacity = (v * 100).rounded() / 100 } }), in: 0.05...1)
                    Text(verbatim: "\(Int((g.opacity * 100).rounded()))%").font(CP.mono(13)).frame(width: 40, alignment: .trailing)
                }
                Stepper(value: Binding(get: { g.lineWidthMM }, set: { v in model.updateGrid { $0.lineWidthMM = PenPreset.clampWidth(v) } }),
                        in: PenPreset.widthRange, step: 0.01) {
                    HStack {
                        Text("Tebal").font(.system(size: 15)).foregroundStyle(CP.ink)
                        Spacer()
                        Text(Fmt.mm(g.lineWidthMM)).font(CP.mono(13)).foregroundStyle(CP.ink)
                    }
                }
                Toggle("Ikut export (raster, PDF, .omap 601.0)", isOn: Binding(get: { g.includeInExport }, set: { on in model.updateGrid { $0.includeInExport = on } }))
                    .font(.system(size: 13))
                    .tint(CP.sage.strong)
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            SectionTitle("Info frame")
            if let zone = model.zone {
                Mono("CRS", "EPSG:\(zone.epsg) · \(zone.label)")
            }
            Mono("Tanah", "\(Fmt.meters(sheet.groundWidthM, decimals: 1)) × \(Fmt.meters(sheet.groundHeightM, decimals: 1))")
            Mono("Kertas", "\(Fmt.mm(sheet.mappingWidthMM, decimals: 0)) × \(Fmt.mm(sheet.mappingHeightMM, decimals: 0))")
            let d = sheet.pixelDimensions(dpi: model.project.sketchDPI)
            Mono("Raster", Fmt.pixels(d.width, d.height))
            Mono("Piksel", Fmt.meters(sheet.pixelSizeM(dpi: model.project.sketchDPI), decimals: 4))
            ForEach(model.cornerInfo) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.id).font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                    Text(Fmt.utm(c.utm)).font(CP.mono(12)).foregroundStyle(CP.ink)
                    Text(Fmt.latLon(c.latLon)).font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                }
                .textSelection(.enabled)
            }
        }
    }

    private var basemapSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            SectionTitle("Basemap")
            Picker("Basemap", selection: $model.basemap) {
                ForEach(Basemap.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: CP.Space.s) {
                Text("Opacity").font(.system(size: 15)).foregroundStyle(CP.ink)
                Slider(value: Binding(get: { model.project.basemapOpacityValue }, set: { model.setBasemapOpacity($0) }), in: 0...1)
                    .accessibilityLabel("Opacity basemap")
                Text(verbatim: "\(Int((model.project.basemapOpacityValue * 100).rounded()))%")
                    .font(CP.mono(13))
                    .foregroundStyle(CP.ink)
                    .frame(width: 40, alignment: .trailing)
            }
            HStack(spacing: CP.Space.s) {
                ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { v in
                    Button(v == 0 ? "Sembunyikan" : "\(Int(v * 100))%") { model.setBasemapOpacity(v) }
                        .font(.system(size: 13))
                        .buttonStyle(.bordered)
                        .tint(model.project.basemapOpacityValue == v ? CP.sage.strong : CP.inkMuted)
                }
            }
            HStack(spacing: CP.Space.s) {
                Text("Area").font(.system(size: 15)).foregroundStyle(CP.ink)
                Slider(value: Binding(get: { model.project.areaOpacityValue }, set: { model.setAreaOpacity($0) }), in: 0.1...1)
                    .accessibilityLabel("Opacity area bersimbol")
                Text(verbatim: "\(Int((model.project.areaOpacityValue * 100).rounded()))%")
                    .font(CP.mono(13)).foregroundStyle(CP.ink).frame(width: 40, alignment: .trailing)
            }
            Text("Opacity isi area bersimbol (vegetasi, open land) agar citra tetap terlihat saat tracing. Export tetap warna penuh seperti OCAD/OOM.")
                .font(.system(size: 12))
                .foregroundStyle(CP.inkMuted)
            Text("Citra Apple Maps hanya acuan gambar dan tidak ikut di-export.")
                .font(.system(size: 13))
                .foregroundStyle(CP.inkMuted)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(CP.inkMuted)
    }
}

private struct Row<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(CP.ink)
            Spacer()
            content
        }
    }
}

private struct Mono: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13)).foregroundStyle(CP.inkMuted)
            Spacer()
            Text(value).font(CP.mono(13)).foregroundStyle(CP.ink).textSelection(.enabled)
        }
    }
}
