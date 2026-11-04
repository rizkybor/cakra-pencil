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
            MapCanvas(model: model, role: .workspace)
                .ignoresSafeArea()

            // Selama halaman Course terbuka, UI workspace di bawahnya tidak dirender (panel layer dengan ratusan
            // objek ikut dihitung ulang tiap perubahan; uji performa: ubah panel Course 190 ms → beberapa ms).
            if !model.showsCoursePlanner {
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
                        // Rail kaku (± 600 pt); di landscape layar kecil tidak muat → gulir, jangan dorong layar.
                        ViewThatFits(in: .vertical) {
                            ToolRail(model: model)
                                .padding(CP.Space.m)
                            ScrollView(.vertical, showsIndicators: false) {
                                ToolRail(model: model)
                                    .padding(CP.Space.m)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        Spacer(minLength: 0)
                        // Kontrol peta di samping inspector (rata bawah), bukan ditumpuk vertikal: rail/inspector +
                        // kontrol peta melebihi tinggi layar landscape → bar atas dan dock terdorong keluar layar.
                        HStack(alignment: .bottom, spacing: 0) {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                MapControls(model: model)
                            }
                            .padding(.vertical, CP.Space.m)
                            .padding(.trailing, model.showsInspector ? 0 : CP.Space.m)
                            if model.showsInspector {
                                InspectorPanel(model: model)
                                    .frame(width: 300)
                                    .padding(CP.Space.m)
                                    .transition(.move(edge: .trailing))
                            }
                        }
                    }
                    VectorToolBar(model: model)
                        .padding(.bottom, CP.Space.s)
                    // Dock bisa lebih lebar dari layar (potret + simbol aktif): geser horizontal, jangan meluber.
                    ViewThatFits(in: .horizontal) {
                        PenDock(model: model)
                        ScrollView(.horizontal, showsIndicators: false) {
                            PenDock(model: model).padding(.horizontal, CP.Space.m)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, CP.Space.l)
                }
            }
            // Keyboard (mis. cari simbol) menutupi dock, bukan memampatkan tata letak: tanpa ini tinggi
            // rail + panel melebihi sisa layar dan bar atas terdorong keluar layar.
            .ignoresSafeArea(.keyboard)

            }

            if let notice = model.notice, !model.showsCoursePlanner {
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
        .onAppear { model.symbolLookup = { [weak symbols, weak model] code in
            guard let symbols else { return nil }
            // Set aktif dengan skala proyek dulu, lalu set lain.
            let scale = model?.project.sheet.scaleDenominator
            let sets = symbols.enabledSets.sorted { ($0.scale == scale ? 0 : 1) < ($1.scale == scale ? 0 : 1) } + symbols.sets
            return sets.lazy.compactMap { $0.symbols.first { $0.code == code } }.first
        } }
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
        .fullScreenCover(isPresented: Binding(get: { model.showsCoursePlanner }, set: { if !$0 { model.closeCoursePlanner() } })) {
            CoursePlannerView(model: model)
                .environmentObject(symbols)
        }
        .confirmationDialog("Buka kunci area?", isPresented: $model.confirmUnlock, titleVisibility: .visible) {
            Button("Buka kunci dan pilih ulang area") { model.unlockArea() }
        } message: {
            Text("Sketsa sudah ada. Data di luar frame baru akan disembunyikan saat export, tidak dihapus.")
        }
    }
}

struct Toast: View {
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
                Button { model.openCoursePlanner() } label: {
                    Label("Course", systemImage: "flag.2.crossed")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.bordered)
                .tint(Color(hexString: "#A626FF"))
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityLabel("Buka Course Planner")
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

struct SaveBadge: View {
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

struct MapControls: View {
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
                Rectangle().fill(CP.line).frame(width: 28, height: 1)
                // Lihat seluruh peta (frame + semua objek), seperti "Zoom to fit" di OCAD.
                Button { model.mapCommand = MapCommand(kind: .fitMap) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(ToolButtonStyle())
                    .keyboardShortcut("0", modifiers: .command)
                    .accessibilityLabel("Lihat seluruh peta")
                    .help("Lihat seluruh peta (⌘0)")
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
    private let groups: [[Tool]] = [[.navigate, .select], [.pen, .eraser], [.point, .bezier, .freehand, .rectangle, .ellipse]]

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
            Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: { Image(systemName: "rectangle.dashed") }
                .buttonStyle(ToolButtonStyle())
                .accessibilityLabel("Zoom ke frame")
                .help("Zoom ke frame peta")
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
                    hint("Pen tool: ketuk = titik sudut · tarik = kurva · ketuk dua kali = selesai · mulai di ujung garis bersimbol sama = lanjutkan · ketuk dua titik di objek yang sama = bentuknya diikuti", merge: true, guide: true)
                } else {
                    bar {
                        Text(verbatim: "\(model.draftNodes.count) titik").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                        GuideToggle(model: model)
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
                    hint("\(s.code) \(s.name): ketuk peta untuk menempatkan (menempel ke garis/sudut objek lain). Ukuran di dock pena.", guide: true)
                } else {
                    hint("Simbol titik: pilih simbol titik di panel Simbol (mis. 204.0 Boulder, 417.0 pohon), lalu ketuk peta.")
                }
            case .freehand:
                hint(model.activeSymbol?.kind == .area
                     ? "Gambar bebas: tarik keliling area, lepas untuk menutup. Goresan dirapikan otomatis."
                     : "Gambar bebas: tarik garis dengan Pencil, lepas untuk selesai. Goresan dirapikan otomatis; bagian yang menyusuri objek lain mengikuti bentuknya.",
                     merge: true, guide: true)
            case .rectangle:
                hint("Rectangle: tarik dari pojok ke pojok (pojok menempel ke objek lain). Hasilnya area 4 titik yang bisa diedit.", merge: true, guide: true)
            case .ellipse:
                hint("Ellipse: tarik dari pojok ke pojok (pojok menempel ke objek lain). Hasilnya area 4 titik bezier yang bisa diedit.", guide: true)
            case .select:
                if model.cutMode, let f = model.selectedFeature {
                    bar {
                        Image(systemName: "scissors").foregroundStyle(CP.ink)
                        Text(f.kind == .line ? "Potong: ketuk titik di garis untuk memotongnya jadi dua"
                             : model.cutStart == nil ? "Belah area: ketuk titik pertama di tepi area"
                             : "Belah area: ketuk titik kedua di tepi seberangnya")
                            .font(.system(size: 13)).foregroundStyle(CP.ink)
                        Button(role: .cancel) { model.cancelCut() } label: { Label("Batal", systemImage: "xmark") }
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else if let f = model.selectedFeature {
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
                        SymbolSwitchButton(model: model, feature: f)
                            .disabled(f.isLocked)
                        if f.canFillWithArea {
                            // OCAD Fill: isi bentuk garis dengan simbol area, garisnya tidak hilang.
                            FillAreaButton(model: model)
                                .disabled(f.isLocked)
                        }
                        if model.mergeCandidateCount > 0 {
                            // OCAD Merge / OOM Connect paths + Unify areas: objek bersimbol sama yang tersambung.
                            Button { model.mergeSelected() } label: {
                                Label(f.kind == .line ? "Sambung garis" : "Gabung area", systemImage: "link")
                            }
                            .accessibilityIdentifier("mergeSelected")
                        }
                        if let s = model.activeSymbol, s.code != f.symbolCode, model.canSwitch(f, to: s) {
                            // OOM "Switch symbol": pilih objek, pilih simbol di panel, lalu ganti.
                            Button { model.switchSelectedSymbol() } label: {
                                Label("Ganti simbol → \(s.code)", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(f.isLocked)
                        }
                        if f.symbolCode == nil {
                            Button { model.applyPenStyleToSelection() } label: { Label("Pakai warna pena", systemImage: "paintbrush") }
                                .disabled(f.isLocked)
                        }
                        if let i = model.selectedNodeIndex {
                            Button { if let id = model.selectedFeatureID { model.updateFeature(id) { $0.toggleSmooth(at: i) } } } label: {
                                Label("Sudut ↔ halus", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                            Button { model.deleteSelectedNode() } label: { Label("Hapus titik", systemImage: "minus.circle") }
                        }
                        RotationButton(model: model, feature: f)
                            .disabled(f.isLocked)
                        if f.kind != .point {
                            ShapeEditMenu(model: model, feature: f)
                                .disabled(f.isLocked)
                        }
                        Button(role: .destructive) { model.deleteFeature(f.id) } label: { Label("Hapus objek", systemImage: "trash") }
                            .keyboardShortcut(.delete, modifiers: [])
                        Button { model.deselect() } label: { Label("Selesai", systemImage: "checkmark") }
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else {
                    hint("Pilih: ketuk objek untuk memilih · geser titik/handle · ketuk dua kali titik = sudut ↔ halus · ketuk dua kali garis = tambah titik · tempel ujung garis/sisi area ke objek bersimbol sama = gabung", merge: true)
                }
            default:
                EmptyView()
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private func hint(_ text: String, merge: Bool = false, guide: Bool = false) -> some View {
        HStack(spacing: CP.Space.m) {
            // Alat dengan sakelar: cukup sakelarnya (tanpa teks petunjuk).
            if !merge && !guide {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(CP.inkMuted)
            }
            if guide { GuideToggle(model: model) }
            if merge {
                // Sakelar gabung otomatis (OCAD/OOM): ujung garis / sisi area yang ditempel ke objek bersimbol sama menyatu.
                Toggle(isOn: $model.autoMerge) {
                    Label("Gabung otomatis", systemImage: "link")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                .toggleStyle(.button)
                .tint(CP.ink)
                .fixedSize()
                .accessibilityIdentifier("autoMerge")
            }
        }
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

/// Sakelar panduan objek (OCAD Follow): kursor menempel ke garis objek yang ada dan bentuk baru mengikutinya.
private struct GuideToggle: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        Toggle(isOn: $model.followGuides) {
            Label("Ikuti objek", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .toggleStyle(.button)
        .tint(CP.ink)
        .fixedSize()
        .accessibilityIdentifier("followGuides")
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

// MARK: - Rotasi objek

/// Tombol "↻ sudut" di bar objek terpilih; membuka panel slider 0–360°, langkah ±1°/±15°, dan preset.
private struct RotationButton: View {
    @ObservedObject var model: WorkspaceModel
    let feature: Feature
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label("Rotasi \(degreesText(feature.rotationDegrees))", systemImage: "rotate.right")
        }
        .popover(isPresented: $showing) {
            RotationPanel(model: model)
                .frame(width: 320)
                .padding(CP.Space.l)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Rotasi objek, \(Int(feature.rotationDegrees.rounded())) derajat")
    }
}

private struct RotationPanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var before: [Feature]?
    @State private var liveDegrees: Double?

    private var current: Double { liveDegrees ?? model.selectedFeature?.rotationDegrees ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack {
                Text("Rotasi objek").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                Text(verbatim: degreesText(current)).font(CP.mono(17, weight: .semibold)).foregroundStyle(CP.ink)
            }
            Text("Searah jarum jam terhadap utara grid, berputar di titik tengah objek.")
                .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            Slider(value: Binding(get: { current }, set: { v in
                liveDegrees = v
                model.rotateSelectedLive(to: v)
            }), in: 0...360, step: 1) { editing in
                if editing {
                    before = model.features
                } else {
                    if let before { model.commitFeatureEdit(from: before) }
                    before = nil
                    liveDegrees = nil
                }
            }
            .accessibilityLabel("Sudut rotasi")
            .accessibilityValue("\(Int(current.rounded())) derajat")
            HStack(spacing: CP.Space.s) {
                ForEach([-15.0, -1, 1, 15], id: \.self) { d in
                    Button(d > 0 ? "+\(Int(d))°" : "\(Int(d))°") { model.setSelectedRotation(current + d) }
                        .font(CP.mono(13, weight: .medium))
                        .buttonStyle(.bordered)
                        .tint(CP.ink)
                }
            }
            HStack(spacing: CP.Space.xs) {
                ForEach([0.0, 45, 90, 135, 180, 270], id: \.self) { d in
                    Button(degreesText(d)) { model.setSelectedRotation(d) }
                        .font(CP.mono(12))
                        .buttonStyle(.bordered)
                        .tint(abs(current - d) < 0.05 ? CP.sage.strong : CP.inkMuted)
                }
            }
        }
    }
}

// MARK: - Edit bentuk (OCAD: Cut, Scale, Move parallel, Reverse)

/// Tombol + popover, bukan `Menu`: Menu di dalam ViewThatFits bar membuat SwiftUI crash saat objek berubah
/// (undo/potong; terbukti di uji UI).
private struct ShapeEditMenu: View {
    @ObservedObject var model: WorkspaceModel
    let feature: Feature
    private enum Page { case actions, scale, parallel }
    @State private var showing = false
    @State private var page = Page.actions

    var body: some View {
        Button { page = .actions; showing = true } label: {
            Label("Edit bentuk", systemImage: "scissors")
        }
        .accessibilityIdentifier("shapeEdit")
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: CP.Space.m) {
                switch page {
                case .actions: actions
                case .scale: ScalePanel(model: model)
                case .parallel: ParallelPanel(model: model) { showing = false }
                }
            }
            .frame(width: 340)
            .padding(CP.Space.l)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Text("Edit bentuk").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
            action(feature.kind == .line ? "Potong garis" : "Belah area", "scissors",
                   feature.kind == .line ? "Ketuk titik di garis untuk memotongnya jadi dua." : "Ketuk dua titik di tepi area.") {
                showing = false
                model.startCut()
            }
            action("Skala…", "arrow.up.left.and.arrow.down.right", "Perbesar/perkecil bentuk, tebal garis tetap.") { page = .scale }
            action("Paralel…", "line.3.horizontal", "Salin atau geser sejajar (jalan, jalur ganda).") { page = .parallel }
            if feature.kind == .line {
                action("Balik arah garis", "arrow.left.arrow.right", "Untuk tebing, pagar, dan simbol berarah.") {
                    showing = false
                    model.reverseSelected()
                }
            }
            Text("Tambah titik: ketuk dua kali di garis objek terpilih. Gabung: tombol Sambung garis/Gabung area.")
                .font(.system(size: 11)).foregroundStyle(CP.inkMuted)
        }
    }

    private func action(_ title: String, _ icon: String, _ detail: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: CP.Space.m) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(CP.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(CP.ink)
                    Text(detail).font(.system(size: 11)).foregroundStyle(CP.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// OCAD Scale: ubah ukuran geometri sebanding terhadap titik tengah objek (tebal garis tetap).
private struct ScalePanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var original: Feature?
    @State private var before: [Feature]?
    @State private var percent = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack {
                Text("Skala objek").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                Text(verbatim: "\(Int(percent.rounded()))%").font(CP.mono(17, weight: .semibold)).foregroundStyle(CP.ink)
            }
            Text("Bentuk diperbesar/diperkecil sebanding dari titik tengahnya; tebal garis tetap.")
                .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            Slider(value: $percent, in: 10...400, step: 1) { editing in
                if editing {
                    before = model.features
                    original = model.selectedFeature
                } else {
                    if let before { model.commitFeatureEdit(from: before) }
                    before = nil
                    original = nil
                    percent = 100
                }
            }
            .onChange(of: percent) { _, v in
                if let original { model.scaleLive(original, by: v / 100) }
            }
            .accessibilityLabel("Skala")
            .accessibilityValue("\(Int(percent.rounded())) persen")
            HStack(spacing: CP.Space.s) {
                ForEach([50.0, 90, 110, 150, 200], id: \.self) { k in
                    Button("\(Int(k))%") { model.scaleSelected(by: k / 100) }
                        .font(CP.mono(13, weight: .medium))
                        .buttonStyle(.bordered)
                        .tint(CP.ink)
                }
            }
            Text("Tombol diterapkan dari ukuran sekarang (bisa diulang). Slider kembali ke 100% setelah dilepas.")
                .font(.system(size: 11)).foregroundStyle(CP.inkMuted)
        }
    }
}

/// OCAD Move parallel: salin atau geser garis/area sejajar (jalan ganda, tepi jalur, batas berlapis).
private struct ParallelPanel: View {
    @ObservedObject var model: WorkspaceModel
    let dismiss: () -> Void
    @State private var mm = 1.0
    @State private var side = WorkspaceModel.ParallelSide.left

    private var meters: Double { model.project.sheet.groundMeters(forPaperMM: mm) }

    var body: some View {
        let isArea = model.selectedFeature?.kind == .area
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Text("Garis paralel").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
            Text(isArea ? "Area: kiri = ke dalam, kanan = ke luar." : "Kiri/kanan mengikuti arah garis digambar (balik arah bila terbalik).")
                .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            HStack {
                Text("Jarak").font(.system(size: 13)).foregroundStyle(CP.ink)
                Spacer()
                Stepper(value: $mm, in: 0.1...20, step: 0.1) {
                    Text(verbatim: "\(Fmt.mm(mm, decimals: 1)) · \(Fmt.meters(meters, decimals: 1))")
                        .font(CP.mono(13, weight: .medium))
                }
                .fixedSize()
            }
            Picker("Sisi", selection: $side) {
                ForEach(WorkspaceModel.ParallelSide.allCases) { s in
                    Text(isArea ? (s == .left ? "Dalam" : s == .right ? "Luar" : s.rawValue) : s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: CP.Space.s) {
                Button {
                    model.parallelSelected(meters: meters, side: side, copy: true)
                    dismiss()
                } label: { Label("Salin paralel", systemImage: "plus.square.on.square") }
                    .buttonStyle(.borderedProminent)
                    .tint(CP.ink)
                    .accessibilityIdentifier("parallelCopy")
                Button {
                    model.parallelSelected(meters: meters, side: side, copy: false)
                    dismiss()
                } label: { Label("Geser", systemImage: "arrow.right.to.line") }
                    .buttonStyle(.bordered)
                    .tint(CP.ink)
                    .disabled(side == .both)
            }
            .font(.system(size: 13, weight: .medium))
        }
    }
}

// MARK: - Ganti simbol objek terpilih

/// OCAD "Change symbol" / OOM "Switch symbol": pilih objek → Ganti simbol → ketuk simbol baru.
private struct SymbolSwitchButton: View {
    @ObservedObject var model: WorkspaceModel
    @EnvironmentObject private var symbols: SymbolLibrary
    let feature: Feature
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label(feature.symbolCode.map { "Simbol \($0)" } ?? "Beri simbol", systemImage: "square.on.square")
        }
        .popover(isPresented: $showing) {
            SymbolSwitchPicker(model: model, library: symbols) { showing = false }
                .frame(width: 380, height: 520)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Ganti simbol objek")
        .accessibilityValue(feature.symbolCode ?? "tanpa simbol")
    }
}

/// OCAD "Fill": garis terpilih → pilih simbol area → area baru di bawah garis, garis tetap.
private struct FillAreaButton: View {
    @ObservedObject var model: WorkspaceModel
    @EnvironmentObject private var symbols: SymbolLibrary
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Label("Isi area", systemImage: "drop.halffull") }
            .popover(isPresented: $showing) {
                SymbolSwitchPicker(model: model, library: symbols, fill: true) { showing = false }
                    .frame(width: 380, height: 520)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityIdentifier("fillArea")
    }
}

private struct SymbolSwitchPicker: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var library: SymbolLibrary
    /// Mode isi: hanya simbol area; memilih = buat area dari garis (garis tetap).
    var fill = false
    let dismiss: () -> Void
    @State private var query = ""
    @State private var allSame = false

    /// Simbol dari set aktif (set berskala proyek dulu), unik per kode, yang jenisnya cocok dengan objek.
    private var candidates: [MapSymbol] {
        guard let f = model.selectedFeature else { return [] }
        let scale = model.project.sheet.scaleDenominator
        let sets = library.enabledSets.sorted { ($0.scale == scale ? 0 : 1) < ($1.scale == scale ? 0 : 1) }
        var seen = Set<String>()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return sets.flatMap(\.symbols).filter { s in
            s.isEnabled && s.isDrawable && (fill ? s.kind == .area : f.canSwitch(to: s)) && seen.insert(s.code).inserted
                && (q.isEmpty || s.code.hasPrefix(q) || s.name.lowercased().contains(q))
        }
    }

    var body: some View {
        let f = model.selectedFeature
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Text(fill ? "Isi dengan simbol area" : "Ganti simbol").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
            if fill {
                Text("Bentuk garis diisi area baru di bawahnya; simbol garisnya tetap. Garis yang belum tertutup ditutup lurus.")
                    .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            } else if let f {
                Text(f.symbolCode.map { "Sekarang: \($0) \(f.symbolName ?? "")" } ?? "Objek sketsa tanpa simbol")
                    .font(.system(size: 12)).foregroundStyle(CP.inkMuted).lineLimit(1)
                Text(f.kind == .point ? "Simbol titik bisa diganti ke simbol titik lain."
                     : "Garis dan area bisa saling ditukar; bentuk objek tetap.")
                    .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            }
            TextField("Cari kode atau nama (mis. 506 atau path)", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !fill, let code = f?.symbolCode, model.sameSymbolCount > 1 {
                Toggle("Semua objek \(code) (\(model.sameSymbolCount))", isOn: $allSame)
                    .font(.system(size: 13))
                    .tint(CP.peach.strong)
            }
            let list = candidates
            if list.isEmpty {
                Text(library.enabledSets.isEmpty ? "Belum ada set simbol aktif." : "Tidak ada simbol yang cocok.")
                    .font(.system(size: 13)).foregroundStyle(CP.inkMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(list, id: \.code) { s in
                            let current = !fill && s.code == f?.symbolCode
                            Button {
                                if fill { model.fillSelected(with: s) } else { model.switchSelectedSymbol(to: s, allSame: allSame) }
                                dismiss()
                            } label: {
                                HStack(spacing: CP.Space.s) {
                                    SymbolSwatch(symbol: s)
                                    Text(s.code).font(CP.mono(12, weight: .medium)).foregroundStyle(CP.ink).frame(width: 48, alignment: .leading)
                                    Text(s.name).font(.system(size: 13)).foregroundStyle(CP.ink).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if s.kind.rawValue != f?.kind.rawValue {
                                        Text(s.kind.label).font(.system(size: 11)).foregroundStyle(CP.inkMuted)
                                    }
                                    if current { Image(systemName: "checkmark").foregroundStyle(CP.peach.strong) }
                                }
                                .padding(.vertical, 6).padding(.horizontal, CP.Space.s)
                                .contentShape(Rectangle())
                                .background(current ? CP.peach.fill : .clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .disabled(current && !allSame)
                            .accessibilityLabel("\(s.code) \(s.name), \(s.kind.label)")
                        }
                    }
                }
            }
        }
        .padding(CP.Space.l)
    }
}

private func degreesText(_ d: Double) -> String {
    d.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(d))°" : String(format: "%.1f°", locale: Locale(identifier: "id_ID"), d)
}
