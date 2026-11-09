import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Contours panel (FR-8): data source, interval, index, form lines, smoothing, appearance, relief info,
/// and "Convert to vector objects" for editing contour lines.
struct ContourPanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var importing = false

    private var s: ContourSettings { model.contourSettings }

    private static let types: [UTType] = [
        UTType(filenameExtension: "tif") ?? .tiff, .tiff,
        UTType(filenameExtension: "asc", conformingTo: .data) ?? .data,
        UTType(filenameExtension: "geojson", conformingTo: .json) ?? .json, .json,
    ]

    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        if license.isPro { panel } else { locked }
    }

    /// Starter: contours need a license key. Contours already in the project stay on the map.
    private var locked: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack(spacing: CP.Space.s) {
                Image(systemName: ProFeature.contours.icon)
                    .font(.system(size: CP.fs(16), weight: .semibold))
                    .foregroundStyle(CP.peach.strong)
                Text("Contours").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                ProLockBadge()
            }
            Text("Contours from elevation data (built-in or your own GeoTIFF / ASC / GeoJSON) need a license key: Trial, Professional, Lifetime, or Organization.")
                .font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { LicenseManager.shared.require(.contours) } label: {
                Label("Unlock contours", systemImage: "key.horizontal").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .accessibilityIdentifier("contourUnlock")
            Spacer(minLength: 0)
        }
        .padding(CP.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.l) {
                HStack {
                    Text("Show contours").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                    Spacer()
                    Toggle("Contours", isOn: Binding(get: { s.isEnabled }, set: { on in model.updateContours { $0.isEnabled = on } }))
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
            }
            .padding(CP.Space.l)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.types) { result in
            if case let .success(url) = result { Task { await model.importContourFile(url) } }
        }
    }

    // MARK: Opacity

    /// Raise/lower opacity 10% per tap, or drag the slider (5–100%). Only changes the drawing style.
    private var opacityControl: some View {
        VStack(alignment: .leading, spacing: CP.Space.xs) {
            HStack(spacing: CP.Space.s) {
                Text("Opacity").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                Spacer()
                Button { model.stepContourOpacity(by: -0.1) } label: { Image(systemName: "minus") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(s.opacity <= ContourSettings.opacityRange.lowerBound)
                    .accessibilityLabel("Decrease contour opacity")
                    .help("Decrease contour opacity")
                Text(verbatim: "\(Int((s.opacity * 100).rounded()))%")
                    .font(CP.mono(15, weight: .medium))
                    .foregroundStyle(CP.ink)
                    .frame(width: 52)
                Button { model.stepContourOpacity(by: 0.1) } label: { Image(systemName: "plus") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(s.opacity >= ContourSettings.opacityRange.upperBound)
                    .accessibilityLabel("Increase contour opacity")
                    .help("Increase contour opacity")
            }
            Slider(value: Binding(get: { s.opacity }, set: { v in model.updateContours { $0.opacity = v } }),
                   in: ContourSettings.opacityRange)
                .tint(Color(hexString: s.colorHex))
                .accessibilityLabel("Contour opacity")
                .help("Contour opacity")
                .accessibilityValue("\(Int((s.opacity * 100).rounded())) percent")
        }
        .disabled(!s.isEnabled)
        .opacity(s.isEnabled ? 1 : 0.5)
    }

    // MARK: Status and source

    @ViewBuilder
    private var status: some View {
        switch model.contourStatus {
        case let .downloading(done, total):
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("Downloading elevation data \(done)/\(total) tiles…").font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            }
        case .importing:
            HStack { ProgressView().controlSize(.small); Text("Reading file…").font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted) }
        case .generating:
            HStack { ProgressView().controlSize(.small); Text("Generating contours…").font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted) }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: CP.fs(12)))
                .foregroundStyle(CP.rose.strong)
        case .idle:
            EmptyView()
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack(spacing: 2) {
                Text("SOURCE").font(.system(size: CP.fs(12), weight: .semibold)).tracking(0.6).foregroundStyle(CP.inkMuted)
                InfoHint("Built-in contours: Terrain Tiles elevation data (AWS Open Data; Mapzen, SRTM/NASA, and other sources). For detailed maps use your own DEM, e.g. DEMNAS (BIG) or LiDAR.\n\nUpload: DEM GeoTIFF (.tif) or ASCII Grid (.asc) → contours are generated on this device; or GeoJSON contour lines with an elev property.")
            }
            if let dem = model.dem {
                info("Data", dem.header.source)
                info("Resolution", "±\(Fmt.number(dem.header.nativeResolutionM, decimals: 1)) m · grid \(Fmt.number(dem.cellSize, decimals: 1)) m")
            } else if let lines = model.importedContours {
                info("Data", "Imported contour lines · \(lines.count) lines")
            } else {
                Text("No contour data for this area yet.")
                    .font(.system(size: CP.fs(13)))
                    .foregroundStyle(CP.inkMuted)
            }
            if let r = model.contourRelief {
                info("Elevation", "\(Fmt.number(r.min, decimals: 0))–\(Fmt.number(r.max, decimals: 0)) m · range \(Fmt.number(r.max - r.min, decimals: 0)) m")
                info("Lines", "\(model.contourLines.count) (\(model.contourLines.filter { $0.kind == .index }.count) index)")
            }
            HStack(spacing: CP.Space.s) {
                Button {
                    Task { await model.downloadBuiltInContours() }
                } label: {
                    Label(model.dem?.header.source.hasPrefix("Terrain") == true ? "Download again" : "Built-in contours", systemImage: "icloud.and.arrow.down")
                        .lineLimit(1)
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .fixedSize()
                .accessibilityIdentifier("contourDownload")
                Button { if LicenseManager.shared.require(.contours) { importing = true } } label: {
                    Label("Upload", systemImage: "square.and.arrow.down").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
            .disabled(model.frame == nil || isBusy)
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
            Text("INTERVAL").font(.system(size: CP.fs(12), weight: .semibold)).tracking(0.6).foregroundStyle(CP.inkMuted)
            HStack(spacing: CP.Space.xs) {
                ForEach(ContourSettings.intervalPresetsM, id: \.self) { v in
                    Button { model.updateContours { $0.intervalM = v } } label: {
                        Text(verbatim: "\(Fmt.number(v, decimals: v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)) m")
                            .font(CP.mono(12, weight: s.intervalM == v ? .semibold : .regular))
                            .foregroundStyle(s.intervalM == v ? CP.sage.strong : CP.ink)
                            .padding(.horizontal, CP.Space.s)
                            .frame(height: 28)
                            .background(s.intervalM == v ? CP.sage.fill : CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            stepper("Interval", value: s.intervalM, step: 0.5, range: ContourSettings.intervalRangeM, text: "\(Fmt.number(s.intervalM, decimals: 1)) m") { v in
                model.updateContours { $0.intervalM = v }
            }
            if let res = model.dem?.header.nativeResolutionM, let warning = s.intervalWarning(nativeResolutionM: res) {
                Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: CP.fs(12))).foregroundStyle(CP.butter.strong)
            }
            stepper("Index every", value: Double(s.indexEvery), step: 1, range: 2...10, text: "\(s.indexEvery) lines") { v in
                model.updateContours { $0.indexEvery = Int(v) }
            }
            stepper("Base elevation", value: s.baseOffsetM, step: 0.5, range: -50...50, text: "\(Fmt.number(s.baseOffsetM, decimals: 1)) m") { v in
                model.updateContours { $0.baseOffsetM = v }
            }
            Toggle("Form lines (½ interval, dashed)", isOn: Binding(get: { s.showFormLines }, set: { on in model.updateContours { $0.showFormLines = on } }))
                .font(.system(size: CP.fs(13)))
                .tint(CP.sage.strong)
            VStack(alignment: .leading, spacing: CP.Space.xs) {
                Text("Smoothing").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                Segmented("Smoothing", selection: Binding(get: { s.smoothing }, set: { v in model.updateContours { $0.smoothing = v } }),
                          (0...3).map { .init($0, $0 == 0 ? "Off" : "\($0)") })
            }
            stepper("Minimum length", value: s.minLengthMM, step: 0.5, range: 0...20, text: Fmt.mm(s.minLengthMM, decimals: 1)) { v in
                model.updateContours { $0.minLengthMM = v }
            }
        }
    }

    // MARK: Appearance

    private static let colors: [(String, String)] = [("ISOM brown", "#D15C00"), ("Dark brown", "#8E4A2F"), ("Black", "#000000"), ("Blue", "#00A0E6")]

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Text("APPEARANCE").font(.system(size: CP.fs(12), weight: .semibold)).tracking(0.6).foregroundStyle(CP.inkMuted)
            HStack(spacing: CP.Space.s) {
                Text("Color").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                Spacer()
                ForEach(Self.colors, id: \.1) { name, hex in
                    Button { model.updateContours { $0.colorHex = hex } } label: {
                        Circle().fill(Color(hexString: hex)).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(s.colorHex == hex ? CP.peach.strong : CP.line, lineWidth: s.colorHex == hex ? 2 : 1).padding(-3))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(name) contours")
                    .help("\(name) contours")
                }
            }
            stepper("Contour width", value: s.contourWidthMM, step: 0.01, range: 0.05...1, text: Fmt.mm(s.contourWidthMM)) { v in
                model.updateContours { $0.contourWidthMM = PenPreset.clampWidth(v) }
            }
            stepper("Index width", value: s.indexWidthMM, step: 0.01, range: 0.05...1.5, text: Fmt.mm(s.indexWidthMM)) { v in
                model.updateContours { $0.indexWidthMM = PenPreset.clampWidth(v) }
            }
            let std = ContourSettings.standardWidths(scale: model.project.sheet.scaleDenominator)
            Button("Reset to \(MapStandard.for(scale: model.project.sheet.scaleDenominator).label) standard (\(String(format: "%g", std.contour)) / \(String(format: "%g", std.index)) mm, brown)") {
                model.updateContours {
                    $0.contourWidthMM = std.contour
                    $0.indexWidthMM = std.index
                    $0.colorHex = "#D15C00"
                    $0.opacity = 1
                }
            }
            .font(.system(size: CP.fs(12)))
            Toggle("Include in export (101.0 / 102.0 / 103.0)", isOn: Binding(get: { s.includeInExport }, set: { on in model.updateContours { $0.includeInExport = on } }))
                .font(.system(size: CP.fs(13)))
                .tint(CP.sage.strong)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Button { model.freezeContours() } label: {
                Label("Convert to vector objects (editable)", systemImage: "scribble.variable").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.contourLines.isEmpty || !s.isEnabled)
            Text("Contour lines become objects in the Layers panel: move, delete, or edit their points with the Select tool. Automatic contours are hidden so they aren't doubled.")
                .font(.system(size: CP.fs(11)))
                .foregroundStyle(CP.inkMuted)
            Button { model.exportContoursOnly = true } label: {
                Label("Export contours only (SHP, KML, KMZ)…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(PastelButtonStyle(tone: CP.sand))
            .disabled(model.contourLines.isEmpty)
            Button(role: .destructive) { model.removeContourData() } label: {
                Label("Delete this project's contour data", systemImage: "trash")
            }
            .font(.system(size: CP.fs(13)))
        }
    }

    // MARK: Helpers

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
            Spacer()
            Text(value).font(CP.mono(12)).foregroundStyle(CP.ink).multilineTextAlignment(.trailing)
        }
    }

    private func stepper(_ label: String, value: Double, step: Double, range: ClosedRange<Double>, text: String,
                         set: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: set), in: range, step: step) {
            HStack {
                Text(label).font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                Spacer()
                Text(verbatim: text).font(CP.mono(13)).foregroundStyle(CP.ink)
            }
        }
    }
}
