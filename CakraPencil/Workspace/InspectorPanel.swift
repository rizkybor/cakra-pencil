import CakraCore
import SwiftUI

/// Inspector kanan: pengaturan frame, info frame (FR-1.9), dan basemap.
struct InspectorPanel: View {
    @ObservedObject var model: WorkspaceModel

    private var sheet: SheetSpec { model.project.sheet }
    private var locked: Bool { model.project.areaLocked }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.l) {
                frameSection
                Divider().overlay(CP.line)
                basemapSection
                Divider().overlay(CP.line)
                infoSection
            }
            .padding(CP.Space.l)
        }
        .frame(maxHeight: 640)
        .cpPanel()
    }

    private var frameSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            SectionTitle("Frame A4")
            Picker("Orientasi", selection: Binding(get: { sheet.orientation }, set: { o in model.updateSheet { $0.orientation = o } })) {
                Text("Portrait").tag(SheetOrientation.portrait)
                Text("Landscape").tag(SheetOrientation.landscape)
            }
            .pickerStyle(.segmented)
            .disabled(locked)

            Row("Skala") {
                Picker("Skala", selection: Binding(get: { sheet.scaleDenominator }, set: { s in model.updateSheet { $0.scaleDenominator = s } })) {
                    ForEach(MapPresets.scales, id: \.self) { Text(verbatim: "1:\($0)").tag($0) }
                }
                .disabled(locked)
            }
            Row("Margin") {
                Picker("Margin", selection: Binding(get: { sheet.marginMM }, set: { m in model.updateSheet { $0.marginMM = m } })) {
                    ForEach(MapPresets.marginsMM, id: \.self) { Text(Fmt.mm($0, decimals: 0)).tag($0) }
                }
                .disabled(locked)
            }
            Row("Snap pojok") {
                Picker("Snap", selection: Binding(get: { model.project.snapStepM }, set: { model.setSnapStep($0) })) {
                    ForEach(MapPresets.snapStepsM, id: \.self) { Text(verbatim: $0 == 0 ? "Mati" : "\($0) m").tag($0) }
                }
                .disabled(locked)
            }
            Row("Resolusi") {
                Picker("dpi", selection: Binding(get: { model.project.sketchDPI }, set: { model.setDPI($0) })) {
                    ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                }
            }

            if locked {
                Button { model.requestUnlock() } label: {
                    Label("Buka kunci area", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button { model.lockArea() } label: {
                    Label("Kunci area", systemImage: "lock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.frame == nil)
                Text("Geser frame dengan satu jari di dalam frame. Di luar frame, peta tetap bisa di-pan dan zoom.")
                    .font(.system(size: 13))
                    .foregroundStyle(CP.inkMuted)
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
