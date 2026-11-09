import CakraCore
import SwiftUI

// MARK: - Quick vegetation classification

/// Tap the runnability class where you stand (ISOM / ISSprOM 401–410); each tap is a draft note, drawn as an area
/// at the desk. The sheet stays open so several classes can be noted in a row.
struct VegetationSheet: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var recorder: FieldRecorder
    @Environment(\.dismiss) private var dismiss
    @State private var useGPS = true
    @State private var last: VegetationClass?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CP.Space.m) {
                    Segmented("Position", selection: $useGPS, [.init(true, "My GPS position"), .init(false, "Map center")])
                    Text(FieldCaptureSection.gpsLine(recorder)).font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: CP.Space.s), GridItem(.flexible(), spacing: CP.Space.s)],
                              spacing: CP.Space.s) {
                        ForEach(VegetationClass.allCases, id: \.self) { v in classButton(v) }
                    }
                    if let last {
                        Label("\(last.code) \(last.label) noted — tap another class or Done.", systemImage: "checkmark.circle.fill")
                            .font(.system(size: CP.fs(13), weight: .medium))
                            .foregroundStyle(CP.sage.strong)
                            .accessibilityIdentifier("vegetationSaved")
                    }
                    Text("Each tap adds a draft note (Field panel). At the desk, open it and choose Make map object to draw the area.")
                        .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                }
                .padding(CP.Space.l)
            }
            .navigationTitle("Vegetation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .sheetConfirm) { Group { Button("Done") { dismiss() } }.buttonStyle(PrimaryButtonStyle(compact: true)) }.plainBar() }
        }
        .onAppear {
            recorder.setWantsNoteFix(true)
            useGPS = recorder.hasFix
        }
        .onDisappear { recorder.setWantsNoteFix(false) }
    }

    private func classButton(_ v: VegetationClass) -> some View {
        Button {
            if model.addVegetationSample(v, atGPS: useGPS) != nil {
                last = v
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            HStack(spacing: CP.Space.s) {
                RoundedRectangle(cornerRadius: 4).fill(Color(hexString: v.colorHex))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.25)))
                    .overlay {
                        // Good visibility classes: vertical green lines, as on the map.
                        if v == .slowGoodVisibility || v == .walkGoodVisibility {
                            HStack(spacing: 3) { ForEach(0..<4, id: \.self) { _ in Rectangle().fill(Color(hexString: "#3DB54A")).frame(width: 1.5) } }
                        }
                    }
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(v.code) \(v.label)").font(.system(size: CP.fs(13), weight: .semibold)).foregroundStyle(CP.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(v.speed).font(CP.mono(11)).foregroundStyle(CP.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(CP.Space.s)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(last == v ? CP.sage.fill : CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(last == v ? CP.sage.strong : CP.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(v.code) \(v.label)")
        .accessibilityIdentifier("veg-\(v.code)")
    }
}

// MARK: - Track → line

/// Turn a track (or part of it) into line objects, in the Field panel so the map stays visible: choose the symbol,
/// trim the start and end (the part is highlighted on the map), smooth, then make the objects. Pause gaps split the
/// line. The objects are ordinary map objects afterwards: node edit, cut and merge with the usual tools.
struct TrackLineEditor: View {
    @ObservedObject var model: WorkspaceModel
    let trackID: UUID
    @EnvironmentObject private var library: SymbolLibrary
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var smoothing = Smoothing.medium
    @State private var symbol: MapSymbol?
    @State private var choosing = false

    enum Smoothing: Double, CaseIterable {
        case off = 0, light = 1, medium = 2.5, strong = 6
        var label: String {
            switch self {
            case .off: return "Off"
            case .light: return "Light"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }
    }

    /// Path symbols first, then streams, vegetation boundary, fence.
    static let suggestedCodes = ["506", "505", "507", "508", "504", "305", "416", "516"]

    private var track: FieldTrack? { model.field.tracks.first { $0.id == trackID } }

    private var parts: [[Point2D]] { track?.lineParts(from: start, to: end, toleranceM: smoothing.rawValue) ?? [] }

    var body: some View {
        ScrollView {
            if let t = track {
                VStack(alignment: .leading, spacing: CP.Space.m) {
                    Button { close() } label: {
                        Label("Tracks", systemImage: "chevron.left").font(.system(size: CP.fs(14), weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CP.sky.strong)
                    .padding(.top, CP.Space.xs)
                    .accessibilityIdentifier("trackLineBack")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Make line from \(t.name)").font(.system(size: CP.fs(16), weight: .semibold)).foregroundStyle(CP.ink)
                        Text(FieldPanel.trackSummary(t)).font(CP.mono(11)).foregroundStyle(CP.inkMuted)
                    }

                    symbolRow
                    trimSection(t)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Smoothing").font(.system(size: CP.fs(13), weight: .medium)).foregroundStyle(CP.ink)
                        Segmented("Smoothing", selection: $smoothing, Smoothing.allCases.map { .init($0, $0.label) })
                        Text("Removes GPS zigzag: points closer than \(Fmt.number(smoothing.rawValue, decimals: 1)) m to the line are dropped.")
                            .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                    }

                    let ps = parts
                    Text(verbatim: "\(ps.count) \(ps.count == 1 ? "line" : "lines") · \(ps.reduce(0) { $0 + $1.count }) points"
                         + (ps.count > 1 ? " — split at pauses" : ""))
                        .font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                        .accessibilityIdentifier("trackLineResult")

                    Button {
                        if let s = symbol, model.makeObjects(fromTrack: t.id, symbol: s, start: start, end: end, toleranceM: smoothing.rawValue) > 0 {
                            close()
                        }
                    } label: {
                        Label("Make \(ps.count == 1 ? "object" : "objects")", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(FieldButtonStyle(tone: CP.sage))
                    .disabled(symbol == nil || ps.isEmpty || !model.project.areaLocked)
                    .accessibilityIdentifier("trackMakeObjects")
                    if !model.project.areaLocked {
                        Text("Lock the map area (Map tab) to make map objects.").font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                    }
                }
                .padding(.bottom, CP.Space.l)
            }
        }
        .onAppear {
            if symbol == nil { symbol = defaultSymbol }
            updatePreview()
        }
        .onChange(of: start) { _, _ in updatePreview() }
        .onChange(of: end) { _, _ in updatePreview() }
        .onChange(of: smoothing) { _, _ in updatePreview() }
        .onDisappear { model.fieldLinePreview = [] }
        .sheet(isPresented: $choosing) {
            FieldSymbolPicker(model: model, purpose: .track, suggestedCodes: Self.suggestedCodes, suggestedTitle: "Paths and other lines") { s in
                symbol = s
                choosing = false
            }
            .environmentObject(library)
        }
    }

    private var defaultSymbol: MapSymbol? {
        let sets = library.preferredSets(forMapScale: model.project.sheet.scaleDenominator)
        guard let set = sets.first(where: { !$0.isCourseDesign }) ?? sets.first else { return nil }
        let usable = set.symbols.filter { $0.isEnabled && $0.isDrawable && $0.kind == .line }
        return Self.suggestedCodes.lazy.compactMap { c in usable.first { $0.code == c || $0.code == c + ".0" } }.first ?? usable.first
    }

    private var symbolRow: some View {
        Button { choosing = true } label: {
            HStack(spacing: CP.Space.s) {
                if let s = symbol {
                    SymbolSwatch(symbol: s, size: CGSize(width: 34, height: 28))
                    Text("\(s.code) \(s.name)").font(.system(size: CP.fs(14))).foregroundStyle(CP.ink).lineLimit(2)
                } else {
                    Text("Choose a line symbol").font(.system(size: CP.fs(14))).foregroundStyle(CP.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CP.inkMuted)
            }
            .padding(CP.Space.s)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Symbol: \(symbol.map { "\($0.code) \($0.name)" } ?? "none")")
        .accessibilityIdentifier("trackLineSymbol")
    }

    private func trimSection(_ t: FieldTrack) -> some View {
        let total = t.lengthM
        return VStack(alignment: .leading, spacing: 4) {
            Text("Part of the track").font(.system(size: CP.fs(13), weight: .medium)).foregroundStyle(CP.ink)
            HStack {
                Text("From").frame(width: 44, alignment: .leading)
                Slider(value: Binding(get: { start }, set: { start = min($0, end - 0.01) }), in: 0...1)
                    .accessibilityIdentifier("trackLineStart")
                Text(Self.meters(start * total)).font(CP.mono(12)).frame(width: 70, alignment: .trailing)
            }
            HStack {
                Text("To").frame(width: 44, alignment: .leading)
                Slider(value: Binding(get: { end }, set: { end = max($0, start + 0.01) }), in: 0...1)
                    .accessibilityIdentifier("trackLineEnd")
                Text(Self.meters(end * total)).font(CP.mono(12)).frame(width: 70, alignment: .trailing)
            }
            Text("The highlighted part on the map becomes the line.").font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
        }
        .font(.system(size: CP.fs(13)))
    }

    static func meters(_ m: Double) -> String {
        m >= 1000 ? "\(Fmt.number(m / 1000, decimals: 2)) km" : "\(Int(m.rounded())) m"
    }

    private func updatePreview() { model.fieldLinePreview = parts }

    private func close() {
        model.fieldLinePreview = []
        model.trackLineID = nil
    }
}

// MARK: - Survey coverage

/// Coverage row in the Field panel: show/hide the walked band on the map, its radius, and the share of the map frame
/// covered (computed off the main thread).
struct CoverageRow: View {
    @ObservedObject var model: WorkspaceModel
    @State private var percent: Double?

    private var field: FieldData { model.field }

    var body: some View {
        HStack(spacing: CP.Space.s) {
            Button { model.setCoverageVisible(!(field.showCoverage ?? false)) } label: {
                Image(systemName: field.showCoverage == true ? "eye" : "eye.slash")
                    .font(.system(size: CP.fs(13)))
                    .foregroundStyle(field.showCoverage == true ? CP.ink : CP.inkMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(field.showCoverage == true ? "Hide coverage" : "Show coverage")
            .help(field.showCoverage == true ? "Hide coverage" : "Show coverage")
            .accessibilityIdentifier("coverageToggle")
            RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.1, green: 0.55, blue: 0.95).opacity(0.35)).frame(width: 18, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text("Survey coverage").font(.system(size: CP.fs(15))).foregroundStyle(CP.ink)
                Text(percent.map { "\(Int(($0 * 100).rounded())) % of the map area walked (±\(Int(field.coverageRadius)) m)" }
                     ?? (model.frame == nil ? "Lock the map area to measure" : "Measuring…"))
                    .font(CP.mono(11)).foregroundStyle(CP.inkMuted).lineLimit(1)
                    .accessibilityIdentifier("coveragePercent")
            }
            Spacer(minLength: 0)
            SolidMenu(items: [10.0, 25, 50, 100].map { r in
                .action("±\(Int(r)) m", checked: abs(r - field.coverageRadius) < 0.01, section: "Seen on each side") { model.setCoverageRadius(r) }
            }, width: 200) {
                Text("±\(Int(field.coverageRadius)) m").font(.system(size: CP.fs(12), weight: .medium)).foregroundStyle(CP.ink)
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous).strokeBorder(CP.line))
            }
            .fixedSize()
            .accessibilityLabel("Coverage radius")
        }
        .task(id: CoverageKey(tracks: field.tracks, radius: field.coverageRadius, frame: model.frameRect)) {
            guard let area = model.frameRect else { percent = nil; return }
            let tracks = field.tracks, r = field.coverageRadius
            percent = await Task.detached(priority: .utility) { FieldCoverage.fraction(of: area, tracks: tracks, radiusM: r) }.value
        }
    }

    private struct CoverageKey: Equatable {
        var tracks: [FieldTrack]
        var radius: Double
        var frame: Rect2D?
    }
}
