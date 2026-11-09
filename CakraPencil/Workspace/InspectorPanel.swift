import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Right inspector: frame settings, frame info (FR-1.9), and basemap.
struct InspectorPanel: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject private var license = LicenseManager.shared

    @State private var tab = InspectorPanel.initialTab
    @State private var importingBasemap = false

    /// Tabs in display order, left to right: Symbols, Contours, Map, Layers, Field.
    enum Tab: String, CaseIterable {
        case symbols = "Symbols"
        case contours = "Contours"
        case map = "Map"
        case layers = "Layers"
        case field = "Field"
    }

    private static var initialTab: Tab {
        #if DEBUG
        // For screenshots/UI tests: `-cp-inspector-tab Symbols`.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-cp-inspector-tab"), i + 1 < args.count, let t = Tab(rawValue: args[i + 1]) { return t }
        #endif
        // Opening a project starts on Symbols: pick a symbol, then draw.
        return .symbols
    }

    private var sheet: SheetSpec { model.project.sheet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorTabStrip(selection: $tab)
                .padding([.horizontal, .top], CP.Space.l)
            .padding(.bottom, CP.Space.s)
            // A note pin tapped on the map: show it in the Field tab.
            .onChange(of: model.openFieldNoteID) { _, id in if id != nil { tab = .field } }

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
            case .field:
                FieldPanel(model: model)
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
        // At most 600 pt; in landscape on small screens it may be shorter (the list inside scrolls) so the map
        // control bar below still fits.
        .modifier(SidePanelChrome(maxHeight: 600, minHeight: 280))
        .fileImporter(isPresented: $importingBasemap, allowedContentTypes: [.tiff]) { result in
            if case let .success(url) = result { Task { await model.importBasemapImage(from: url) } }
        }
    }

    private var frameSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            SectionTitle("Locked area")
            Mono("Sheet", "\(sheet.paper.name) \(sheet.orientation == .portrait ? "Portrait" : "Landscape") · 1:\(sheet.scaleDenominator)")
            Row("Resolution") {
                Picker("dpi", selection: Binding(get: { model.project.sketchDPI }, set: { model.setDPI($0) })) {
                    ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                }
            }

            Button { model.requestUnlock() } label: {
                Label("Reselect area", systemImage: "lock.open")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: North line grid

    private static let gridColors: [(String, String)] = [
        ("Blue", "#00A0E6"), ("Black", "#000000"), ("Purple", "#A626FF"), ("Red", "#E30613"), ("Gray", "#7F7F7F"),
    ]

    private var gridSection: some View {
        let g = model.project.grid
        return VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack {
                SectionTitle("North line grid")
                Spacer()
                Toggle("Grid", isOn: Binding(get: { g.isEnabled }, set: { on in model.updateGrid { $0.isEnabled = on } }))
                    .labelsHidden()
                    .tint(CP.sage.strong)
            }
            if g.isEnabled {
                Segmented("Reference", selection: Binding(get: { g.reference }, set: { r in model.updateGrid { $0.reference = r } }),
                          NorthGrid.Reference.allCases.map { .init($0, $0.label) })
                if g.reference == .magnetic {
                    Stepper(value: Binding(get: { g.declinationDeg }, set: { v in model.updateGrid { $0.declinationDeg = (v * 10).rounded() / 10 } }),
                            in: -30...30, step: 0.1) {
                        HStack {
                            Text("Declination").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                            Spacer()
                            Text(verbatim: String(format: "%+.1f° %@", g.declinationDeg, g.declinationDeg >= 0 ? "E" : "W"))
                                .font(CP.mono(13)).foregroundStyle(CP.ink)
                        }
                    }
                    Text("Take it from an official declination map or the NOAA calculator for the survey location and date.")
                        .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                }
                Row("Spacing") {
                    SolidMenu(items: NorthGrid.spacingPresetsM.map { m in
                        .action("\(Int(m)) m · \(Fmt.mm(m / Double(sheet.scaleDenominator) * 1000, decimals: 1)) on paper",
                                checked: abs(m - g.spacingM) < 0.01) { model.updateGrid { $0.spacingM = m } }
                    }, width: 240) {
                        Text(verbatim: "\(Int(g.spacingM)) m").font(CP.mono(15)).foregroundStyle(CP.sage.strong)
                    }
                    Stepper("", value: Binding(get: { g.spacingM }, set: { v in model.updateGrid { $0.spacingM = v } }),
                            in: NorthGrid.spacingRangeM, step: 10)
                        .labelsHidden()
                }
                Text(verbatim: "= \(Fmt.mm(g.spacingPaperMM(scale: sheet.scaleDenominator), decimals: 1)) on paper at 1:\(sheet.scaleDenominator)")
                    .font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                HStack(spacing: CP.Space.s) {
                    Text("Color").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                    Spacer()
                    ForEach(Self.gridColors, id: \.1) { name, hex in
                        Button { model.updateGrid { $0.colorHex = hex } } label: {
                            Circle().fill(Color(hexString: hex)).frame(width: 22, height: 22)
                                .overlay(Circle().strokeBorder(g.colorHex == hex ? CP.peach.strong : CP.line, lineWidth: g.colorHex == hex ? 2 : 1).padding(-3))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Grid \(name)")
                        .help("Grid \(name)")
                    }
                    ColorPicker("Other color", selection: Binding(get: { Color(hexString: g.colorHex) }, set: { c in
                        model.updateGrid { $0.colorHex = UIColor(c).hexString }
                    }), supportsOpacity: false)
                    .labelsHidden()
                }
                HStack(spacing: CP.Space.s) {
                    Text("Opacity").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                    Slider(value: Binding(get: { g.opacity }, set: { v in model.updateGrid { $0.opacity = (v * 100).rounded() / 100 } }), in: 0.05...1)
                    Text(verbatim: "\(Int((g.opacity * 100).rounded()))%").font(CP.mono(13)).frame(width: 40, alignment: .trailing)
                }
                Stepper(value: Binding(get: { g.lineWidthMM }, set: { v in model.updateGrid { $0.lineWidthMM = PenPreset.clampWidth(v) } }),
                        in: PenPreset.widthRange, step: 0.01) {
                    HStack {
                        Text("Width").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                        Spacer()
                        Text(Fmt.mm(g.lineWidthMM)).font(CP.mono(13)).foregroundStyle(CP.ink)
                    }
                }
                Toggle("Include in export (raster, PDF, .omap 601.0)", isOn: Binding(get: { g.includeInExport }, set: { on in model.updateGrid { $0.includeInExport = on } }))
                    .font(.system(size: CP.fs(13)))
                    .tint(CP.sage.strong)
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            SectionTitle("Frame info")
            if let zone = model.zone {
                Mono("CRS", "EPSG:\(zone.epsg) · \(zone.label)")
            }
            Mono("Ground", "\(Fmt.meters(sheet.groundWidthM, decimals: 1)) × \(Fmt.meters(sheet.groundHeightM, decimals: 1))")
            Mono("Paper", "\(Fmt.mm(sheet.mappingWidthMM, decimals: 0)) × \(Fmt.mm(sheet.mappingHeightMM, decimals: 0))")
            let d = sheet.pixelDimensions(dpi: model.project.sketchDPI)
            Mono("Raster", Fmt.pixels(d.width, d.height))
            Mono("Pixel", Fmt.meters(sheet.pixelSizeM(dpi: model.project.sketchDPI), decimals: 4))
            ForEach(model.cornerInfo) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.id).font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    Text(Fmt.utm(c.utm)).font(CP.mono(12)).foregroundStyle(CP.ink)
                    Text(Fmt.latLon(c.latLon)).font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                    Text(Fmt.dms(c.latLon)).font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                        .accessibilityLabel("Degrees minutes seconds \(Fmt.dms(c.latLon))")
                }
                .textSelection(.enabled)
            }
        }
    }

    private var basemapSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            SectionTitle("Basemap")
            // 1. Source: Apple imagery (Satellite/Hybrid/Standard) — disabled while the image basemap (GeoTIFF) is in use.
            Segmented("Basemap", selection: $model.basemap, Basemap.allCases.map { .init($0, $0.label) })
            .disabled(model.usesBasemapImage)
            .accessibilityIdentifier("basemapSource")
            // Mode: saved HD image or live Apple Maps (real-time check while online).
            Segmented("Basemap mode", selection: Binding(get: { model.project.usesLiveBasemap }, set: { model.setLiveBasemap($0) }),
                      [.init(false, "HD image", icon: "photo"),
                       .init(true, "Live", icon: LicenseManager.shared.isPro ? "dot.radiowaves.left.and.right" : "lock.fill")])
            .disabled(model.usesBasemapImage || !model.project.areaLocked)
            .accessibilityIdentifier("basemapMode")
            .help("HD image: saved picture of the locked area, fixed at every zoom. Live: real-time Apple Maps while online.")
            mapDataInfo
            hdImagerySection
            basemapImageSection

            Divider().overlay(CP.line)

            // 2. Opacity of the basemap in use (Satellite/Hybrid/Standard or GeoTIFF).
            HStack(spacing: CP.Space.s) {
                Text("Opacity").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                Slider(value: Binding(get: { model.activeBasemapOpacity }, set: { model.setActiveBasemapOpacity($0) }), in: 0...1)
                    .accessibilityLabel("Opacity basemap")
                Text(verbatim: "\(Int((model.activeBasemapOpacity * 100).rounded()))%")
                    .font(CP.mono(13))
                    .foregroundStyle(CP.ink)
                    .frame(width: 40, alignment: .trailing)
            }
            HStack(spacing: CP.Space.s) {
                ForEach([0.0, 0.3, 0.6, 1.0], id: \.self) { v in
                    Button { model.setActiveBasemapOpacity(v) } label: {
                        Group {
                            if v == 0 { Image(systemName: "eye.slash") } else { Text(verbatim: "\(Int(v * 100))%") }
                        }
                        .font(.system(size: CP.fs(13)))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PastelButtonStyle(tone: abs(model.activeBasemapOpacity - v) < 0.005 ? CP.sage : CP.sand))
                    .accessibilityLabel(v == 0 ? "Hide basemap" : "Opacity \(Int(v * 100)) percent")
                    .help(v == 0 ? "Hide basemap (0%)" : "Opacity basemap \(Int(v * 100))%")
                }
            }
            Text(model.usesBasemapImage ? "Applies to the image basemap \(model.project.basemapImage?.originalName ?? "")." : "Applies to \(model.basemap.label) imagery.")
                .font(.system(size: CP.fs(12)))
                .foregroundStyle(CP.inkMuted)

            Divider().overlay(CP.line)

            // 3. Opacity of symbol area fills (tracing aid).
            HStack(spacing: CP.Space.s) {
                Text("Area").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                InfoHint("Opacity of symbol area fills (vegetation, open land) so the basemap stays visible while tracing. Export keeps full colors like OCAD/OOM. The basemap is only a drawing reference and is not exported.")
                Slider(value: Binding(get: { model.project.areaOpacityValue }, set: { model.setAreaOpacity($0) }), in: 0.1...1)
                    .accessibilityLabel("Symbol area opacity")
                    .help("Symbol area opacity")
                Text(verbatim: "\(Int((model.project.areaOpacityValue * 100).rounded()))%")
                    .font(CP.mono(13)).foregroundStyle(CP.ink).frame(width: 40, alignment: .trailing)
            }
        }
    }

    /// Map data info: the basemap source in use and its imagery date/year when available.
    private var mapDataInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Map data info", systemImage: "info.circle")
                .font(.system(size: CP.fs(13), weight: .semibold))
                .foregroundStyle(CP.ink)
            if let image = model.project.basemapImage, model.usesBasemapImage {
                Mono("Source", "Image basemap · \(image.originalName)")
                Mono("Date", image.dateLabel ?? "not in metadata")
                Text("Apple imagery is hidden while the image basemap is in use.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            } else {
                Mono("Source", "Apple Maps · \(model.basemap.label)\(model.showsImagerySnapshot ? " (HD image)" : " (live)")")
                if model.project.areaLocked, model.project.usesLiveBasemap {
                    Text("Live mode: real-time Apple Maps, needs an internet connection. Road widths on the Standard map change with the zoom level.")
                        .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 2) {
                    Mono("Imagery year", "not available")
                    InfoHint("Apple doesn't provide the imagery capture date or year through MapKit. Data providers and copyright: the Legal link in the bottom-left corner of the map.")
                }
            }
        }
        .padding(CP.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mapDataInfo")
    }

    /// HD Apple Maps images of the locked area (Satellite, Hybrid, Standard), shown instead of the live map.
    @ViewBuilder
    private var hdImagerySection: some View {
        if !model.usesBasemapImage {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Label("HD image", systemImage: "photo")
                        .font(.system(size: CP.fs(13), weight: .semibold))
                        .foregroundStyle(CP.ink)
                    if !license.isPro { ProLockBadge().padding(.leading, 4) }
                    if model.project.areaLocked {
                        InfoHint(model.project.usesLiveBasemap
                                 ? "Not shown in Live mode; still kept up to date for HD image mode and exports. Saved in this project only (each device downloads its own; not in .occa files)."
                                 : "The map shows a fixed image of the area, so roads and buildings keep their size at every zoom. Saved in this project only (each device downloads its own; not in .occa files). Export → Include basemap puts it under the map.")
                    }
                    Spacer(minLength: 0)
                    if model.project.areaLocked {
                        // Download again, as an icon at the end of the header row.
                        Button {
                            model.refreshImagery(force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: CP.fs(14), weight: .medium))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(model.isCapturingImagery ? CP.inkMuted : CP.sage.strong)
                        .disabled(model.isCapturingImagery)
                        .accessibilityLabel("Download again")
                        .help("Download the HD images of Satellite, Hybrid, and Standard again")
                        .accessibilityIdentifier("imageryRefresh")
                    }
                }
                if !model.project.areaLocked {
                    Text("Satellite, Hybrid, and Standard are saved as HD images when the area is locked. Until then the live map is shown.")
                        .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    if let s = model.imagerySnapshot {
                        Mono("Size", "\(s.width) × \(s.height) px · \(Fmt.number(s.metersPerPixel, decimals: 2)) m/px")
                        Mono("Saved", s.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if model.isCapturingImagery {
                        HStack(spacing: CP.Space.s) {
                            ProgressView().controlSize(.small)
                            Text("Downloading HD images\(model.imageryProgress.map { " · \($0)" } ?? "")…")
                                .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                        }
                        .accessibilityIdentifier("imageryProgress")
                    } else if model.imagerySnapshot == nil, model.imageryError == nil {
                        Text("No HD image yet; the live map is shown.")
                            .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    }
                    if let error = model.imageryError {
                        Text(error)
                            .font(.system(size: CP.fs(12))).foregroundStyle(CP.rose.strong)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(CP.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
        }
    }

    /// Georeferenced image basemap (GeoTIFF): import, show/hide, zoom, replace, delete.
    @ViewBuilder
    private var basemapImageSection: some View {
        if let image = model.project.basemapImage {
            VStack(alignment: .leading, spacing: CP.Space.s) {
                HStack(alignment: .center) {
                    Text("Image basemap").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                    Spacer(minLength: CP.Space.s)
                    Text(image.isVisible ? "In use" : "Not in use")
                        .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    Toggle("Use", isOn: Binding(get: { image.isVisible }, set: { model.setBasemapImageVisible($0) }))
                        .labelsHidden()
                        .font(.system(size: CP.fs(13)))
                        .tint(CP.sage.strong)
                        .fixedSize()
                        .accessibilityIdentifier("basemapImageVisible")
                        .help("Use the image basemap (GeoTIFF) as the basemap")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.originalName)
                        .font(.system(size: CP.fs(13), weight: .medium)).foregroundStyle(CP.ink)
                        .lineLimit(1).truncationMode(.middle)
                        .accessibilityIdentifier("basemapImageName")
                    Text(verbatim: basemapImageSummary(image))
                        .font(CP.mono(12)).foregroundStyle(CP.inkMuted).lineLimit(2)
                }
                HStack(spacing: CP.Space.s) {
                    Button { model.zoomToBasemapImage() } label: { Label("Zoom", systemImage: "scope") }
                        .help("Zoom to image basemap")
                    Button { if LicenseManager.shared.require(.basemapImport) { importingBasemap = true } } label: { Label("Replace…", systemImage: "arrow.triangle.2.circlepath") }
                        .help("Replace with another GeoTIFF")
                    Spacer(minLength: 0)
                    Button(role: .destructive) { model.removeBasemapImage() } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete image basemap")
                        .help("Delete image basemap")
                }
                .font(.system(size: CP.fs(13)))
                .lineLimit(1)
                .buttonStyle(PastelButtonStyle(tone: CP.sand))
            }
            .padding(CP.Space.s)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
        } else {
            HStack(spacing: CP.Space.xs) {
                Button { if LicenseManager.shared.require(.basemapImport) { importingBasemap = true } } label: { Label("Import basemap GeoTIFF…", systemImage: "photo.on.rectangle.angled") }
                    .font(.system(size: CP.fs(15), weight: .medium))
                    .buttonStyle(PastelButtonStyle(tone: CP.sand))
                    .accessibilityIdentifier("importBasemapImage")
                    .help("Import georeferenced imagery/map (GeoTIFF, UTM WGS84 or WGS84 lat/lon)")
                InfoHint("Or use georeferenced drone imagery, an old map, or an orthophoto (.tif) as the basemap; it's saved in the project file.")
            }
        }
    }

    private func basemapImageSummary(_ image: BasemapImage) -> String {
        var parts = ["\(image.width) × \(image.height) px"]
        if let zone = model.zone {
            let s = image.groundSizeM(in: zone)
            parts.append("\(Fmt.meters(s.width)) × \(Fmt.meters(s.height))")
        }
        switch image.crs {
        case let .utm(epsg): parts.append("EPSG:\(epsg)")
        case .geographic: parts.append("WGS84")
        }
        let res = image.crs == .geographic ? "" : " · \(Fmt.number(image.pixelSizeX, decimals: 2)) m/px"
        return parts.joined(separator: " · ") + res
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: CP.fs(12), weight: .semibold))
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
            Text(label).font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
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
            Text(label).font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
            Spacer()
            Text(value).font(CP.mono(13)).foregroundStyle(CP.ink).textSelection(.enabled)
        }
    }
}

/// Segmented tab strip whose segments are as wide as their labels (a system segmented control gives every segment
/// the same width, which truncates "Symbols" / "Contours" once there are five tabs on an iPad in portrait).
private struct InspectorTabStrip: View {
    @Binding var selection: InspectorPanel.Tab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InspectorPanel.Tab.allCases, id: \.self) { t in
                let on = selection == t
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = t }
                } label: {
                    Text(t.rawValue)
                        .font(.system(size: CP.fs(14), weight: on ? .semibold : .regular))
                        .foregroundStyle(CP.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.rawValue)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
