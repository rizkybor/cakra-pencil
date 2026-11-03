import CakraCore
import SwiftUI

/// Dua tahap kerja:
/// 1. Pilih Area: frame A4 diam di tengah layar, user cari lokasi lalu geser/zoom peta, kemudian Kunci area.
/// 2. Sketsa (Mode Meja): hanya area terkunci yang tampil; rail alat kiri, dock pena bawah, inspector kanan.
struct WorkspaceView: View {
    @StateObject var model: WorkspaceModel
    @EnvironmentObject private var symbols: SymbolLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var showingExport = false

    var body: some View {
        ZStack {
            MapCanvas(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(model: model, showingExport: $showingExport) {
                    Task {
                        await model.flush()
                        dismiss()
                    }
                }
                .zIndex(10)

                if model.isSelectingArea {
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        Spacer()
                        MapControls(model: model)
                    }
                    .padding(.horizontal, CP.Space.m)
                    AreaPanel(model: model)
                        .padding(CP.Space.l)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        ToolRail(model: model)
                            .padding(CP.Space.m)
                        Spacer(minLength: 0)
                        if model.showsInspector {
                            InspectorPanel(model: model)
                                .frame(width: 300)
                                .padding(CP.Space.m)
                                .transition(.move(edge: .trailing))
                        }
                    }
                    Spacer(minLength: 0)
                    VectorToolBar(model: model)
                        .padding(.bottom, CP.Space.s)
                    ZStack(alignment: .bottomTrailing) {
                        PenDock(model: model)
                            .frame(maxWidth: .infinity)
                        MapControls(model: model)
                            .padding(.trailing, CP.Space.m)
                            .padding(.bottom, 64)
                    }
                    .padding(.bottom, CP.Space.l)
                }
            }

            if let notice = model.notice {
                VStack {
                    Toast(text: notice) { model.notice = nil }
                        .padding(.top, 64)
                    Spacer()
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.showsInspector)
        .animation(.easeOut(duration: 0.18), value: model.isSelectingArea)
        .background { KeyboardNavigation(model: model) }
        #if DEBUG
        // Untuk screenshot/UI test: `-cp-import-ocd <file>` mengimpor file dari folder Documents app.
        .task {
            let args = ProcessInfo.processInfo.arguments
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let i = args.firstIndex(of: "-cp-import-ocd"), i + 1 < args.count {
                await model.importOcad(from: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-use-symbol <nomor>` mengaktifkan simbol dari set bawaan (mis. 417000).
            if let i = args.firstIndex(of: "-cp-use-symbol"), i + 1 < args.count, let n = Int(args[i + 1]),
               let sym = symbols.builtInSet?.symbols.first(where: { $0.number == n }) {
                model.useSymbol(sym)
            }
            // `-cp-download-contours` mengunduh kontur bawaan untuk frame.
            if args.contains("-cp-download-contours") { await model.downloadBuiltInContours() }
            // `-cp-zoom-points` zoom ke semua objek titik; `-cp-zoom-last` zoom ke 3 objek terakhir.
            if args.contains("-cp-zoom-points") || args.contains("-cp-zoom-last") {
                let targets = args.contains("-cp-zoom-last") ? Array(model.features.suffix(3)) : model.features.filter { $0.kind == .point }
                let pts = targets.flatMap { $0.nodes.map(\.point) }
                if var r = Rect2D(points: pts) {
                    r = r.insetBy(-15)
                    try? await Task.sleep(for: .seconds(1.5))
                    model.mapCommand = MapCommand(kind: .zoomToExtent(r))
                }
            }
            // `-cp-import-symbols` mengimpor semua .ocd di Documents/SymbolInbox sebagai set simbol.
            if args.contains("-cp-import-symbols") {
                let inbox = docs.appendingPathComponent("SymbolInbox")
                let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
                await symbols.importOcad(files.filter { $0.pathExtension == "ocd" })
            }
        }
        #endif
        .onChange(of: model.exportContoursOnly) { _, on in if on { showingExport = true } }
        .sheet(isPresented: $showingExport, onDismiss: { model.exportContoursOnly = false }) {
            ExportSheet(model: model, mode: model.exportContoursOnly ? .contours : .sheet)
        }
        .confirmationDialog("Buka kunci area?", isPresented: $model.confirmUnlock, titleVisibility: .visible) {
            Button("Buka kunci dan pilih ulang area") { model.unlockArea() }
        } message: {
            Text("Sketsa sudah ada. Data di luar frame baru akan disembunyikan saat export, tidak dihapus.")
        }
    }
}

private struct Toast: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(CP.butter.strong)
            .padding(.horizontal, CP.Space.l)
            .padding(.vertical, CP.Space.s)
            .background(CP.butter.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.butter.strong.opacity(0.4)))
            .onTapGesture(perform: onDismiss)
            .task {
                try? await Task.sleep(for: .seconds(4))
                onDismiss()
            }
    }
}

/// Shortcut keyboard tanpa tombol di layar: panah = geser peta, ⌘= / ⌘− = zoom.
private struct KeyboardNavigation: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        ZStack {
            key(.leftArrow, .pan(dx: -1, dy: 0))
            key(.rightArrow, .pan(dx: 1, dy: 0))
            key(.upArrow, .pan(dx: 0, dy: -1))
            key(.downArrow, .pan(dx: 0, dy: 1))
            key("=", .zoom(2), modifiers: .command)
            key("-", .zoom(0.5), modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func key(_ k: KeyEquivalent, _ kind: MapCommand.Kind, modifiers: EventModifiers = []) -> some View {
        Button("") { model.mapCommand = MapCommand(kind: kind) }
            .keyboardShortcut(k, modifiers: modifiers)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @ObservedObject var model: WorkspaceModel
    @Binding var showingExport: Bool
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: CP.Space.m) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Kembali ke daftar proyek")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.project.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CP.ink)
                    .lineLimit(1)
                Text(model.project.technicalSummary)
                    .font(CP.mono(12))
                    .lineLimit(1)
                    .foregroundStyle(CP.inkMuted)
                    .onTapGesture(count: 2) { model.mapCommand = MapCommand(kind: .zoomToFrame) }
            }
            .frame(minWidth: 140, alignment: .leading)

            LocationSearchField(model: model, prominent: model.isSelectingArea)
                .frame(maxWidth: model.isSelectingArea ? 520 : 380)

            Spacer(minLength: 0)

            SaveBadge(state: model.saveState)

            if !model.isSelectingArea {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(!model.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityLabel("Undo")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(!model.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .accessibilityLabel("Redo")
                Button { model.showsInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(ToolButtonStyle(isActive: model.showsInspector))
                    .accessibilityLabel("Inspector")
                Button("Export") { showingExport = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.vertical, CP.Space.s)
        .background(CP.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(CP.line).frame(height: 1) }
    }
}

private struct SaveBadge: View {
    let state: SaveState

    var body: some View {
        switch state {
        case .saved:
            Label("Tersimpan", systemImage: "checkmark").foregroundStyle(CP.sage.strong).font(.system(size: 13))
        case .saving:
            Label("Menyimpan", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(CP.inkMuted).font(.system(size: 13))
        case let .failed(msg):
            Label("Gagal simpan", systemImage: "exclamationmark.triangle")
                .foregroundStyle(CP.rose.strong).font(.system(size: 13))
                .help(msg)
        }
    }
}

// MARK: - Pilih Area

private struct AreaPanel: View {
    @ObservedObject var model: WorkspaceModel

    private var sheet: SheetSpec { model.project.sheet }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pilih area peta")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CP.ink)
                Spacer()
                Text(summary)
                    .font(CP.mono(13))
                    .foregroundStyle(CP.inkMuted)
            }
            Text("Cari lokasi di kolom atas, lalu geser dan zoom peta sampai area yang ingin dipetakan ada di dalam frame. Frame selalu di tengah layar.")
                .font(.system(size: 13))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: CP.Space.m) {
                Picker("Orientasi", selection: Binding(get: { sheet.orientation }, set: { o in model.updateSheet { $0.orientation = o } })) {
                    Text("Portrait").tag(SheetOrientation.portrait)
                    Text("Landscape").tag(SheetOrientation.landscape)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Picker("Skala", selection: Binding(get: { sheet.scaleDenominator }, set: { s in model.updateSheet { $0.scaleDenominator = s } })) {
                    ForEach(MapPresets.scales, id: \.self) { Text(verbatim: "1:\($0)").tag($0) }
                }
                .pickerStyle(.menu)

                Picker("Margin", selection: Binding(get: { sheet.marginMM }, set: { m in model.updateSheet { $0.marginMM = m } })) {
                    ForEach(MapPresets.marginsMM, id: \.self) { Text("Margin \(Fmt.mm($0, decimals: 0))").tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Picker("Snap pojok", selection: Binding(get: { model.project.snapStepM }, set: { model.setSnapStep($0) })) {
                    ForEach(MapPresets.snapStepsM, id: \.self) { Text(verbatim: $0 == 0 ? "Snap mati" : "Snap \($0) m").tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()

                Spacer(minLength: 0)

                Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: {
                    Label("Pas-kan", systemImage: "arrow.down.right.and.arrow.up.left")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.bordered)
                .tint(CP.ink)

                Button { model.lockArea() } label: {
                    Label("Kunci area", systemImage: "lock")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.frame == nil)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(CP.Space.l)
        .frame(maxWidth: 900)
        .cpPanel()
    }

    private var summary: String {
        var parts = ["\(Fmt.meters(sheet.groundWidthM, decimals: 0)) × \(Fmt.meters(sheet.groundHeightM, decimals: 0))"]
        let d = sheet.pixelDimensions(dpi: model.project.sketchDPI)
        parts.append(Fmt.pixels(d.width, d.height))
        if let zone = model.zone { parts.append(zone.label) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Kontrol peta (kompas digital + zoom)

private struct MapControls: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(spacing: CP.Space.s) {
            DigitalCompass(model: model, live: model.live)
            VStack(spacing: 0) {
                Button { model.mapCommand = MapCommand(kind: .zoom(2)) } label: { Image(systemName: "plus") }
                    .buttonStyle(ToolButtonStyle())
                    .accessibilityLabel("Zoom in")
                Rectangle().fill(CP.line).frame(width: 28, height: 1)
                Button { model.mapCommand = MapCommand(kind: .zoom(0.5)) } label: { Image(systemName: "minus") }
                    .buttonStyle(ToolButtonStyle())
                    .accessibilityLabel("Zoom out")
            }
            .padding(CP.Space.xs)
            .cpPanel()
            LocationButton(model: model, live: model.live)
        }
    }
}

/// Tampilkan/sembunyikan posisi GPS (radar + arah pandang). Tahan = pusatkan peta ke posisi saya.
private struct LocationButton: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var live: LiveMapState

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: model.showsMyLocation ? "location.fill" : "location")
                .font(.system(size: 18))
                .foregroundStyle(model.showsMyLocation ? CP.sky.strong : CP.ink)
            if model.showsMyLocation {
                Text(live.myAccuracyM.map { $0 < 10 ? String(format: "±%.1f m", $0) : String(format: "±%.0f m", $0) } ?? "cari…")
                    .font(CP.mono(10, weight: .medium))
                    .foregroundStyle(accuracyColor)
            }
        }
        .frame(width: 56, height: model.showsMyLocation ? 52 : CP.hitTarget)
        .background(model.showsMyLocation ? CP.sky.fill : CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(model.showsMyLocation ? CP.sky.strong : CP.line))
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { model.showsMyLocation.toggle() }
        .onLongPressGesture { model.mapCommand = MapCommand(kind: .followUser) }
        .accessibilityElement()
        .accessibilityLabel(model.showsMyLocation ? "Sembunyikan posisi saya" : "Tampilkan posisi saya")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Pusatkan ke posisi saya") { model.mapCommand = MapCommand(kind: .followUser) }
    }

    /// Hijau ≤ 5 m, kuning ≤ 15 m, merah di atasnya (iPad di bawah kanopi biasanya 5–15 m).
    private var accuracyColor: Color {
        guard let a = live.myAccuracyM else { return CP.inkMuted }
        return a <= 5 ? CP.sage.strong : (a <= 15 ? CP.butter.strong : CP.rose.strong)
    }
}

/// Jarum menunjuk utara di layar (ikut rotasi peta). Angka = arah hadap iPad bila magnetometer tersedia,
/// selain itu arah peta. Ketuk: kembali north-up; bila sudah north-up, peta ikut arah hadap iPad.
private struct DigitalCompass: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var live: LiveMapState

    private var isRotated: Bool {
        let h = live.mapHeading.truncatingRemainder(dividingBy: 360)
        return min(abs(h), abs(360 - abs(h))) > 0.5
    }

    private var readout: Double { live.deviceHeading ?? live.mapHeading }

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 2) {
                ZStack {
                    Circle().strokeBorder(CP.line, lineWidth: 1)
                    ForEach(0..<12) { i in
                        Rectangle()
                            .fill(CP.inkMuted)
                            .frame(width: 1, height: i % 3 == 0 ? 5 : 3)
                            .offset(y: -19)
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                    Needle()
                        .rotationEffect(.degrees(-live.mapHeading))
                }
                .frame(width: 44, height: 44)
                Text(String(format: "%03.0f° %@", readout.rounded().truncatingRemainder(dividingBy: 360), Self.cardinal(readout)))
                    .font(CP.mono(11, weight: .medium))
                    .foregroundStyle(model.followsHeading ? CP.sky.strong : CP.ink)
            }
            .padding(CP.Space.xs)
            .frame(width: 64)
            .background(model.followsHeading ? CP.sky.fill : CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(model.followsHeading ? CP.sky.strong : CP.line))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kompas, arah \(Int(readout.rounded())) derajat")
        .accessibilityHint(isRotated ? "Ketuk untuk kembali ke utara di atas" : "Ketuk agar peta mengikuti arah hadap iPad")
    }

    private func tap() {
        if model.followsHeading || isRotated {
            model.followsHeading = false
            model.mapCommand = MapCommand(kind: .northUp)
        } else if live.deviceHeading != nil {
            model.followsHeading = true
            model.mapCommand = MapCommand(kind: .followHeading)
        } else {
            model.notice = "Kompas iPad tidak tersedia di perangkat ini. Putar peta dengan dua jari."
        }
    }

    /// Arah mata angin singkat Bahasa Indonesia.
    static func cardinal(_ deg: Double) -> String {
        let names = ["U", "TL", "T", "Tg", "S", "BD", "B", "BL"]
        let i = Int(((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8
        return names[i]
    }
}

private struct Needle: View {
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 0, y: -14)); p.addLine(to: CGPoint(x: 4, y: 0)); p.addLine(to: CGPoint(x: -4, y: 0)); p.closeSubpath()
            }
            .fill(CP.rose.strong)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 14)); p.addLine(to: CGPoint(x: 4, y: 0)); p.addLine(to: CGPoint(x: -4, y: 0)); p.closeSubpath()
            }
            .fill(CP.inkMuted)
        }
        .offset(x: 22, y: 22)
        .frame(width: 44, height: 44)
    }
}

// MARK: - Rail alat

private struct ToolRail: View {
    @ObservedObject var model: WorkspaceModel

    /// Kelompok: navigasi/pilih · sketsa pensil · vektor.
    private let groups: [[Tool]] = [[.navigate, .select], [.pen, .eraser], [.point, .bezier, .rectangle, .ellipse]]

    var body: some View {
        VStack(spacing: CP.Space.xs) {
            ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
                if i > 0 { divider }
                ForEach(group) { tool in
                    Button { model.tool = tool } label: { Image(systemName: tool.symbol) }
                        .buttonStyle(ToolButtonStyle(isActive: model.tool == tool))
                        .keyboardShortcut(KeyEquivalent(tool.shortcut), modifiers: [])
                        .accessibilityLabel(tool.label)
                        .help("\(tool.label) (\(String(tool.shortcut).uppercased()))")
                }
            }
            divider
            Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(ToolButtonStyle())
                .accessibilityLabel("Zoom ke frame")
        }
        .padding(CP.Space.xs)
        .cpPanel()
    }

    private var divider: some View {
        Rectangle().fill(CP.line).frame(width: 28, height: 1).padding(.vertical, CP.Space.xs)
    }
}

// MARK: - Bar alat vektor

/// Bar kontekstual di atas dock: petunjuk + aksi pen tool, rectangle/ellipse, atau objek yang dipilih.
private struct VectorToolBar: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        Group {
            switch model.tool {
            case .bezier:
                if model.draftNodes.isEmpty {
                    hint("Pen tool: ketuk = titik sudut · tarik = kurva · ketuk titik pertama = tutup jadi area")
                } else {
                    bar {
                        Text(verbatim: "\(model.draftNodes.count) titik").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                        Button { model.finishDraftForActiveSymbol() } label: {
                            Label(model.activeSymbol?.kind == .area ? "Selesai area" : "Selesai garis", systemImage: "checkmark")
                        }
                            .keyboardShortcut(.return, modifiers: [])
                        Button { model.finishDraft(as: .area) } label: { Label("Tutup jadi area", systemImage: "square.dashed") }
                            .disabled(model.draftNodes.count < 3)
                        Button { model.removeLastDraftNode() } label: { Label("Hapus titik terakhir", systemImage: "delete.left") }
                            .keyboardShortcut(.delete, modifiers: [])
                        Button(role: .destructive) { model.cancelDraft() } label: { Label("Batal", systemImage: "xmark") }
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                }
            case .point:
                if let s = model.activeSymbol, s.kind == .point {
                    hint("\(s.code) \(s.name): ketuk peta untuk menempatkan. Ukuran di dock pena.")
                } else {
                    hint("Simbol titik: pilih simbol titik di panel Simbol (mis. 204.0 Boulder, 417.0 pohon), lalu ketuk peta.")
                }
            case .rectangle:
                hint("Rectangle: tarik dari pojok ke pojok. Hasilnya area 4 titik yang bisa diedit.")
            case .ellipse:
                hint("Ellipse: tarik dari pojok ke pojok. Hasilnya area 4 titik bezier yang bisa diedit.")
            case .select:
                if let f = model.selectedFeature {
                    bar {
                        Text(f.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink).lineLimit(1)
                        if f.kind != .point {
                            Picker("Jenis", selection: Binding(get: { f.kind }, set: { k in model.updateFeature(f.id) { $0.kind = k } })) {
                                ForEach([FeatureKind.line, .area], id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                            .disabled(f.isLocked || (f.nodes.count < 3))
                        }
                        // Ubah ukuran: titik dalam % dari ukuran standar, garis/area dalam mm.
                        HStack(spacing: 4) {
                            Button { f.kind == .point ? model.resizeSelected(by: 1 / 1.1) : model.adjustSelectedWidth(by: -0.01) } label: {
                                Label(f.kind == .point ? "Perkecil" : "Tipiskan", systemImage: "minus.magnifyingglass")
                            }
                            Text(verbatim: f.kind == .point ? "\(Int((f.effectiveSizeFactor * 100).rounded()))%" : Fmt.mm(f.widthMM))
                                .font(CP.mono(12, weight: .medium))
                                .frame(minWidth: 52)
                            Button { f.kind == .point ? model.resizeSelected(by: 1.1) : model.adjustSelectedWidth(by: 0.01) } label: {
                                Label(f.kind == .point ? "Perbesar" : "Tebalkan", systemImage: "plus.magnifyingglass")
                            }
                            if (f.kind == .point && f.sizeFactor != nil)
                                || (f.kind != .point && f.standardWidthMM.map { abs($0 - f.widthMM) > 0.005 } == true) {
                                Button { model.resetSelectedSize() } label: { Label("Standar", systemImage: "arrow.counterclockwise") }
                            }
                        }
                        .disabled(f.isLocked)
                        Button { model.applyPenStyleToSelection() } label: { Label("Pakai warna pena", systemImage: "paintbrush") }
                            .disabled(f.isLocked)
                        if let i = model.selectedNodeIndex {
                            Button { if let id = model.selectedFeatureID { model.updateFeature(id) { $0.toggleSmooth(at: i) } } } label: {
                                Label("Sudut ↔ halus", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                            Button { model.deleteSelectedNode() } label: { Label("Hapus titik", systemImage: "minus.circle") }
                        }
                        Button(role: .destructive) { model.deleteFeature(f.id) } label: { Label("Hapus objek", systemImage: "trash") }
                            .keyboardShortcut(.delete, modifiers: [])
                        Button { model.deselect() } label: { Label("Selesai", systemImage: "checkmark") }
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else {
                    hint("Pilih: ketuk objek untuk memilih · geser titik/handle · ketuk dua kali titik = sudut ↔ halus")
                }
            default:
                EmptyView()
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(CP.inkMuted)
            .padding(.horizontal, CP.Space.m)
            .padding(.vertical, CP.Space.s)
            .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
    }

    /// Label lengkap bila muat; di layar sempit (iPad Air/mini portrait) jadi ikon saja.
    private func bar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let items = content()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: CP.Space.m) { items }.labelStyle(.titleAndIcon).lineLimit(1).fixedSize()
            HStack(spacing: CP.Space.s) { items }.labelStyle(.iconOnly).lineLimit(1).fixedSize()
        }
            .font(.system(size: 13, weight: .medium))
            .buttonStyle(.bordered)
            .tint(CP.ink)
            .padding(.horizontal, CP.Space.m)
            .padding(.vertical, CP.Space.s)
            .cpPanel()
    }
}

// MARK: - Dock pena

private struct PenDock: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        HStack(spacing: CP.Space.m) {
            ForEach(PenPreset.isom) { preset in
                let active = model.pen.colorHex == preset.colorHex
                Button {
                    model.pen = preset
                    model.clearSymbol()
                    if !model.tool.draws { model.tool = .pen }
                } label: {
                    Circle()
                        .fill(Color(hexString: preset.colorHex))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(CP.paper, lineWidth: 2))
                        .overlay(Circle().strokeBorder(active ? CP.peach.strong : CP.line, lineWidth: active ? 2 : 1).padding(-3))
                        .frame(width: CP.hitTarget, height: CP.hitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pena \(preset.name) \(Fmt.mm(preset.widthMM))")
            }

            Rectangle().fill(CP.line).frame(width: 1, height: 28)

            if let s = model.activeSymbol {
                SymbolSizeControl(model: model, symbol: s)
            } else {
                penWidthControls
            }

            Rectangle().fill(CP.line).frame(width: 1, height: 28)

            Toggle(isOn: $model.fingerDraws) {
                Image(systemName: "hand.point.up.left")
            }
            .toggleStyle(.button)
            .tint(CP.peach.strong)
            .accessibilityLabel("Jari ikut menggambar")
            .help("Untuk iPad tanpa Pencil atau simulator: satu jari menggambar, dua jari navigasi")
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.vertical, CP.Space.xs)
        .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(CP.peach.fill, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }

    @ViewBuilder
    private var penWidthControls: some View {
            Button { model.setPenWidth(model.pen.widthMM - 0.01) } label: { Image(systemName: "minus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("[", modifiers: [])
                .accessibilityLabel("Kurangi tebal")
            Slider(value: Binding(get: { model.pen.widthMM }, set: { model.setPenWidth($0) }),
                   in: PenPreset.widthRange)
                .frame(width: 140)
                .accessibilityLabel("Tebal garis")
            Button { model.setPenWidth(model.pen.widthMM + 0.01) } label: { Image(systemName: "plus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("]", modifiers: [])
                .accessibilityLabel("Tambah tebal")
            Text(Fmt.mm(model.pen.widthMM))
                .font(CP.mono(15, weight: .medium))
                .foregroundStyle(CP.ink)
                .frame(width: 76, alignment: .trailing)
    }
}

/// Simbol aktif di dock: contoh bentuk, kode, dan ukuran (% dari standar IOF set simbol) dengan tombol Standar.
private struct SymbolSizeControl: View {
    @ObservedObject var model: WorkspaceModel
    let symbol: MapSymbol

    private var isPoint: Bool { symbol.kind == .point }
    private var standard: Double { model.activeStandardWidthMM ?? symbol.drawingWidthMM }
    private var isStandard: Bool {
        isPoint ? model.symbolSizeFactor == 1 : abs(model.pen.widthMM - standard) < 0.005
    }

    var body: some View {
        HStack(spacing: CP.Space.s) {
            SymbolSwatch(symbol: symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: symbol.code).font(CP.mono(12, weight: .semibold)).foregroundStyle(CP.ink)
                Text(symbol.name).font(.system(size: 11)).foregroundStyle(CP.inkMuted).lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
            Button { step(-1) } label: { Image(systemName: "minus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("[", modifiers: [])
                .accessibilityLabel(isPoint ? "Perkecil simbol" : "Tipiskan garis 0,01 mm")
            readout
                .frame(width: 84)
            Button { step(1) } label: { Image(systemName: "plus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("]", modifiers: [])
                .accessibilityLabel(isPoint ? "Perbesar simbol" : "Tebalkan garis 0,01 mm")
            Button("Standar") { reset() }
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .disabled(isStandard)
                .help("Kembali ke ukuran standar IOF dari set simbol")
        }
    }

    /// Titik: persen (Ø mm di bawahnya). Garis/area: tebal mm (persen standar IOF di bawahnya), ketuk = preset.
    @ViewBuilder
    private var readout: some View {
        if isPoint {
            VStack(spacing: 0) {
                Text(verbatim: "\(Int((model.symbolSizeFactor * 100).rounded()))%")
                    .font(CP.mono(15, weight: .medium))
                    .foregroundStyle(isStandard ? CP.ink : CP.peach.strong)
                Text(verbatim: "Ø \(Fmt.mm((symbol.pointElements ?? []).diameterMM * model.symbolSizeFactor))")
                    .font(CP.mono(10)).foregroundStyle(CP.inkMuted)
            }
        } else {
            Menu {
                Section("Tebal dari standar IOF \(Fmt.mm(standard))") {
                    ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { k in
                        Button { model.setSymbolLineWidth(standard * k) } label: {
                            Text(verbatim: "\(Int(k * 100))% · \(Fmt.mm(PenPreset.clampWidth(standard * k)))")
                        }
                    }
                }
            } label: {
                VStack(spacing: 0) {
                    Text(Fmt.mm(model.pen.widthMM))
                        .font(CP.mono(14, weight: .medium))
                        .foregroundStyle(isStandard ? CP.ink : CP.peach.strong)
                    Text(verbatim: "\(Int((model.pen.widthMM / max(standard, 0.01) * 100).rounded()))% IOF")
                        .font(CP.mono(10)).foregroundStyle(CP.inkMuted)
                }
            }
            .accessibilityLabel("Tebal garis \(Fmt.mm(model.pen.widthMM))")
        }
    }

    private func step(_ dir: Double) {
        if isPoint {
            model.setSymbolSize(dir > 0 ? model.symbolSizeFactor * 1.1 : model.symbolSizeFactor / 1.1)
        } else {
            model.setSymbolLineWidth(model.pen.widthMM + 0.01 * dir)
        }
    }

    private func reset() {
        if isPoint { model.setSymbolSize(1) } else { model.setSymbolLineWidth(standard) }
    }
}
