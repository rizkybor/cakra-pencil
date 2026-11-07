import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Dua tahap kerja:
/// 1. Pilih Area: frame A4 diam di tengah layar, user cari lokasi lalu geser/zoom peta, kemudian Kunci area.
/// 2. Sketsa (Mode Meja): hanya area terkunci yang tampil; rail alat kiri, dock pena bawah, inspector kanan.
struct WorkspaceView: View {
    @StateObject var model: WorkspaceModel
    @EnvironmentObject private var symbols: SymbolLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var showingExport = false
    @State private var savingFile: ProjectFileDocument?
    /// Mac: tepi bawah pita toolbar; kanvas peta dimulai di bawahnya (frame tidak tertutup).
    @State private var bandBottom: CGFloat = 0

    private var mapTopInset: CGFloat { CP.isMac ? bandBottom : 0 }

    /// Tulis perubahan terakhir, lalu bungkus paket proyek jadi file .cpencil.
    private func saveFile() {
        Task {
            await model.flush()
            let url = model.url
            do {
                let data = try await Task.detached(priority: .userInitiated) { try ProjectArchive.pack(packageAt: url) }.value
                savingFile = ProjectFileDocument(data: data)
            } catch {
                model.notice = "Gagal menyiapkan file proyek: \(error.localizedDescription)"
            }
        }
    }

    /// Mac: kompas di pojok kanan pita toolbar.
    private var bandCompass: some View {
        DigitalCompass(model: model, live: model.live, embedded: true).modifier(BandCornerPadding())
    }

    /// Dock pena; bisa lebih lebar dari ruang yang ada (potret + simbol aktif): geser horizontal, jangan meluber.
    private var penDock: some View {
        ViewThatFits(in: .horizontal) {
            PenDock(model: model)
            ScrollView(.horizontal, showsIndicators: false) {
                PenDock(model: model).padding(.horizontal, CP.Space.m)
            }
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        ZStack {
            MapCanvas(model: model, role: .workspace)
                .padding(.top, mapTopInset)
                .ignoresSafeArea(edges: mapTopInset > 0 ? [.bottom, .horizontal] : .all)

            // Selama halaman Course terbuka, UI workspace di bawahnya tidak dirender (panel layer dengan ratusan
            // objek ikut dihitung ulang tiap perubahan; uji performa: ubah panel Course 190 ms → beberapa ms).
            if !model.showsCoursePlanner {
            VStack(spacing: 0) {
                TopBar(model: model, showingExport: $showingExport, onSaveFile: saveFile) {
                    Task {
                        await model.flush()
                        dismiss()
                    }
                }
                .zIndex(10)

                if model.isSelectingArea && CP.isMac {
                    // Mac: panel pilih area + kontrol peta menempel di pita atas.
                    AreaPanel(model: model)
                    .padding(.horizontal, CP.Space.m)
                    .padding(.vertical, CP.Space.s)
                    .modifier(MacBand())
                    .modifier(BandBottomReader(space: "workspace"))
                    Spacer(minLength: 0)
                } else if model.isSelectingArea {
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        Spacer()
                        MapControls(model: model)
                    }
                    .padding(.horizontal, CP.Space.m)
                    AreaPanel(model: model)
                        .padding(CP.Space.l)
                } else if CP.isMac {
                    // Mac: pita toolbar menempel di bawah bar atas (seperti OCAD): alat + kontrol peta + pena dalam
                    // satu baris (jendela sempit: dua baris), lalu baris bar kontekstual bila ada. Panel kanan di bawahnya.
                    VStack(alignment: .leading, spacing: 0) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: CP.Space.s) {
                                ToolRail(model: model, horizontal: true, showsCompass: false)
                                BandSeparator()
                                PenDock(model: model)
                                Spacer(minLength: 0)
                                bandCompass
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    ToolRail(model: model, horizontal: true, showsCompass: false)
                                    Spacer(minLength: 0)
                                    bandCompass
                                }
                                Rectangle().fill(CP.line).frame(height: 1)
                                HStack { PenDock(model: model); Spacer(minLength: 0) }
                            }
                        }
                        .padding(.horizontal, CP.Space.s)
                        .padding(.vertical, 2)
                        VectorToolBar(model: model)
                    }
                    .modifier(MacBand())
                    .modifier(BandBottomReader(space: "workspace"))
                    // Panel kanan menempel penuh di sisi kanan, dari bawah pita sampai bawah jendela.
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if model.showsInspector {
                            InspectorPanel(model: model)
                                .frame(width: 300)
                                .transition(.move(edge: .trailing))
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        // Rail alat + kontrol peta dalam satu panel. Bila tidak muat (landscape layar kecil): gulir,
                        // agar bar atas dan dock tidak terdorong keluar layar.
                        ViewThatFits(in: .vertical) {
                            ToolRail(model: model)
                                .padding(CP.Space.m)
                            // Landscape layar kecil: panel yang sama, kontrol peta jadi kolom kedua.
                            ToolRail(model: model, twoColumns: true)
                                .padding(CP.Space.m)
                            ScrollView(.vertical, showsIndicators: false) {
                                ToolRail(model: model)
                                    .padding(CP.Space.m)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
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
                    penDock
                        .padding(.bottom, CP.Space.l)
                }
            }
            // Keyboard (mis. cari simbol) menutupi dock, bukan memampatkan tata letak: tanpa ini tinggi
            // rail + panel melebihi sisa layar dan bar atas terdorong keluar layar.
            .ignoresSafeArea(.keyboard)

            }

            if let notice = model.notice, !model.showsCoursePlanner {
                VStack {
                    // Mac: bar alat ada di atas, jadi pesan muncul di bawah.
                    if CP.isMac { Spacer() }
                    Toast(text: notice) { model.notice = nil }
                        .padding(CP.isMac ? .bottom : .top, CP.isMac ? CP.Space.xl : 64)
                    if !CP.isMac { Spacer() }
                }
            }
        }
        .coordinateSpace(name: "workspace")
        .onPreferenceChange(BandBottomKey.self) { bandBottom = $0 }
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
            // `-cp-reselect-area`: tekan "Pilih ulang area" (uji Batal / basemap saat pilih ulang).
            if args.contains("-cp-reselect-area"), model.project.areaLocked { model.unlockArea() }
            // `-cp-skip-area-basemap <file>`: lewati pilih area dengan Documents/<file> (GeoTIFF).
            if let i = args.firstIndex(of: "-cp-skip-area-basemap"), i + 1 < args.count {
                await model.skipAreaSelection(withBasemap: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-import-basemap <file>`: impor Documents/<file> (GeoTIFF) sebagai basemap gambar.
            if let i = args.firstIndex(of: "-cp-import-basemap"), i + 1 < args.count {
                await model.importBasemapImage(from: docs.appendingPathComponent(args[i + 1]))
            }
            // `-cp-move-frame-to-basemap`: setujui "Pindahkan frame ke gambar" (uji tampil basemap).
            if args.contains("-cp-move-frame-to-basemap"), model.project.basemapImage != nil, !model.basemapImageTouchesFrame {
                model.confirmMoveFrameToBasemap = false
                model.moveFrameToBasemapImage()
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
        #if DEBUG
        // `-cp-save-file <nama>`: simpan proyek ke Documents/<nama>.cpencil tanpa dialog (uji iPad ↔ Mac).
        .task {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-cp-save-file"), i + 1 < args.count else { return }
            await model.flush()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let data = try? ProjectArchive.pack(packageAt: model.url) {
                try? data.write(to: docs.appendingPathComponent(args[i + 1]).appendingPathExtension(ProjectArchive.fileExtension))
            }
        }
        #endif
        .onChange(of: model.exportContoursOnly) { _, on in if on { showingExport = true } }
        // Simpan file proyek .cpencil (iPad: Files; Mac: dialog Finder); bisa diimpor di iPad maupun Mac.
        .fileExporter(isPresented: Binding(get: { savingFile != nil }, set: { if !$0 { savingFile = nil } }),
                      document: savingFile, contentType: .cakraProject, defaultFilename: projectFileName(model.project.name)) { result in
            switch result {
            case .success: model.notice = "File proyek tersimpan."
            case let .failure(error): model.notice = "Gagal menyimpan file: \(error.localizedDescription)"
            }
            savingFile = nil
        }
        .sheet(isPresented: $showingExport, onDismiss: { model.exportContoursOnly = false }) {
            ExportSheet(model: model, mode: model.exportContoursOnly ? .contours : .sheet)
        }
        .fullScreenCover(isPresented: Binding(get: { model.showsCoursePlanner }, set: { if !$0 { model.closeCoursePlanner() } })) {
            CoursePlannerView(model: model)
                .environmentObject(symbols)
        }
        .alert("Basemap di luar frame", isPresented: $model.confirmMoveFrameToBasemap) {
            Button("Pindahkan frame ke gambar") { model.moveFrameToBasemapImage() }
            Button("Biarkan", role: .cancel) {}
        } message: {
            Text("Gambar tidak menyentuh frame peta, jadi tidak terlihat (area di luar frame ditutup). Pindahkan frame ke tengah gambar? Skala dan objek yang sudah ada tidak berubah; bisa di-undo.")
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
            .font(.system(size: CP.fs(15)))
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
            // Pilih semua (⌘A) tanpa tombol.
            Button("") { model.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
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
    var onSaveFile: () -> Void = {}
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: CP.Space.m) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Kembali ke daftar proyek")
            .help("Kembali ke daftar proyek")

            VStack(alignment: .leading, spacing: 2) {
                Text(model.project.name)
                    .font(.system(size: CP.fs(15), weight: .semibold))
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
                    .help("Undo (⌘Z)")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(!model.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .accessibilityLabel("Redo")
                    .help("Redo (⇧⌘Z)")
                Button { model.openCoursePlanner() } label: {
                    Label("Course", systemImage: "flag.2.crossed")
                        .font(.system(size: CP.fs(15), weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.bordered)
                .tint(Color(hexString: "#A626FF"))
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityLabel("Buka Course Planner")
                .help("Buka Course Planner")
                Button { model.showsInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(ToolButtonStyle(isActive: model.showsInspector))
                    .accessibilityLabel("Inspector")
                    .help("Tampilkan/sembunyikan panel kanan")
                Button(action: onSaveFile) { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(ToolButtonStyle())
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityLabel("Simpan file proyek")
                    .help("Simpan file proyek .occa — bisa dibuka di iPad dan Mac (⌘S)")
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
        badge
            .lineLimit(1)
            .fixedSize()   // tidak terlipat dua baris saat bar atas sempit (iPad potret)
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .saved:
            Label("Tersimpan", systemImage: "checkmark").foregroundStyle(CP.sage.strong).font(.system(size: CP.fs(13)))
        case .saving:
            Label("Menyimpan", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(CP.inkMuted).font(.system(size: CP.fs(13)))
        case let .failed(msg):
            Label("Gagal simpan", systemImage: "exclamationmark.triangle")
                .foregroundStyle(CP.rose.strong).font(.system(size: CP.fs(13)))
                .help(msg)
        }
    }
}

// MARK: - Pilih Area

/// Panel pilih area: melayang di bawah (iPad) atau menempel di pita atas (Mac).
private struct AreaChrome: ViewModifier {
    @Environment(\.docked) private var docked

    func body(content: Content) -> some View {
        if docked {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content
                .padding(CP.Space.l)
                .frame(maxWidth: 900)
                .cpPanel()
        }
    }
}

private struct AreaPanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var importingBasemap = false
    @Environment(\.docked) private var docked

    private var sheet: SheetSpec { model.project.sheet }

    var body: some View {
        Group {
            if docked { macBody } else { padBody }
        }
        // Lewati pilih area: area diambil dari basemap GeoTIFF yang sudah di-georeferensi.
        .fileImporter(isPresented: $importingBasemap, allowedContentTypes: [.tiff]) { result in
            if case let .success(url) = result { Task { await model.skipAreaSelection(withBasemap: url) } }
        }
        .modifier(AreaChrome())
    }

    /// Mac (pita toolbar atas): judul + ukuran dan kontrol peta di baris pertama, petunjuk satu baris,
    /// lalu pengaturan rata kiri dan aksi rata kanan.
    private var macBody: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack(alignment: .center, spacing: CP.Space.m) {
                Text("Pilih area peta")
                    .font(.system(size: CP.fs(17), weight: .semibold))
                    .foregroundStyle(CP.ink)
                Text(summary)
                    .font(CP.mono(13))
                    .foregroundStyle(CP.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: CP.Space.m)
                MapControls(model: model, horizontal: true)
            }
            Text("Geser dan zoom peta sampai area yang ingin dipetakan ada di dalam frame (frame selalu di tengah), atau lewati dengan upload basemap GeoTIFF.")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CP.Space.m) {
                    settings
                    Spacer(minLength: CP.Space.l)
                    actions
                }
                VStack(alignment: .leading, spacing: CP.Space.s) {
                    HStack(spacing: CP.Space.m) { settings }
                    HStack(spacing: CP.Space.m) {
                        Spacer(minLength: 0)
                        actions
                    }
                }
            }
        }
        .padding(.vertical, CP.Space.xs)
    }

    private var padBody: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pilih area peta")
                    .font(.system(size: CP.fs(17), weight: .semibold))
                    .foregroundStyle(CP.ink)
                Spacer()
                Text(summary)
                    .font(CP.mono(13))
                    .foregroundStyle(CP.inkMuted)
            }
            Text("Cari lokasi di kolom atas, lalu geser dan zoom peta sampai area yang ingin dipetakan ada di dalam frame. Frame selalu di tengah layar. Sudah punya citra ter-georeferensi? Lewati dan upload basemap GeoTIFF — frame otomatis di tengah gambar.")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            // Satu baris bila muat; layar sempit (iPad potret): aksi turun ke baris kedua, rata kanan.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CP.Space.m) {
                    settings
                    Spacer(minLength: 0)
                    actions
                }
                VStack(alignment: .leading, spacing: CP.Space.s) {
                    HStack(spacing: CP.Space.m) { settings }
                    HStack(spacing: CP.Space.m) {
                        Spacer(minLength: 0)
                        actions
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var settings: some View {
        Picker("Orientasi", selection: Binding(get: { sheet.orientation }, set: { o in model.updateSheet { $0.orientation = o } })) {
            Text("Portrait").tag(SheetOrientation.portrait)
            Text("Landscape").tag(SheetOrientation.landscape)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 220)

        Picker("Skala", selection: Binding(get: { sheet.scaleDenominator }, set: { s in model.updateSheet { $0.scaleDenominator = s } })) {
            ForEach(MapPresets.scales, id: \.self) { Text(verbatim: "1:\($0)").tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Skala peta")

        Picker("Margin", selection: Binding(get: { sheet.marginMM }, set: { m in model.updateSheet { $0.marginMM = m } })) {
            ForEach(MapPresets.marginsMM, id: \.self) { Text("Margin \(Fmt.mm($0, decimals: 0))").tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Margin cetak")

        Picker("Snap pojok", selection: Binding(get: { model.project.snapStepM }, set: { model.setSnapStep($0) })) {
            ForEach(MapPresets.snapStepsM, id: \.self) { Text(verbatim: $0 == 0 ? "Snap mati" : "Snap \($0) m").tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Snap pojok frame ke kelipatan meter")
    }

    @ViewBuilder
    private var actions: some View {
        if model.project.areaBackup != nil {
            // Pilih ulang area belum dikunci: kembali ke area (dan tampilan) sebelumnya.
            Button { model.cancelReselectArea() } label: {
                Label("Batal", systemImage: "arrow.uturn.backward")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.bordered)
            .tint(CP.ink)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityIdentifier("cancelReselectArea")
            .help("Batal pilih ulang area: kembali ke area sebelumnya (Esc)")
        }
        Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: {
            Label("Pas-kan", systemImage: "arrow.down.right.and.arrow.up.left")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.bordered)
        .tint(CP.ink)

        Button { importingBasemap = true } label: {
            Label("Lewati — upload basemap", systemImage: "photo.on.rectangle.angled")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.bordered)
        .tint(CP.ink)
        .accessibilityIdentifier("skipAreaWithBasemap")
        .help("Lewati pilih area: upload GeoTIFF ter-georeferensi, frame otomatis di tengah gambar lalu area dikunci")

        Button { model.lockArea() } label: {
            Label("Kunci area", systemImage: "lock")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(model.frame == nil)
        .keyboardShortcut(.return, modifiers: .command)
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
    /// Mac: satu baris di pita toolbar atas.
    var horizontal = false
    /// Mac: kompas di pojok kanan pita (ditaruh terpisah).
    var showsCompass = true

    /// Lebar kolom = lebar rail alat (tombol 44 pt + padding), agar kontrol peta segaris di bawah rail.
    static let width = CP.hitTarget + 2 * CP.Space.xs

    var body: some View {
        if horizontal {
            HStack(spacing: CP.Space.xs) {
                zoomButton("plus", factor: 2, label: "Zoom in")
                zoomButton("minus", factor: 0.5, label: "Zoom out")
                FitMapButton(model: model)
                BandSeparator().padding(.horizontal, CP.Space.xs)
                LocationButton(model: model, live: model.live, embedded: true)
                if showsCompass { DigitalCompass(model: model, live: model.live, embedded: true).modifier(BandCornerPadding()) }
            }
            .fixedSize()
        } else {
            vertical
        }
    }

    private var vertical: some View {
        VStack(spacing: CP.Space.s) {
            DigitalCompass(model: model, live: model.live)
            VStack(spacing: 0) {
                zoomButton("plus", factor: 2, label: "Zoom in")
                Rectangle().fill(CP.line).frame(width: 28, height: 1)
                zoomButton("minus", factor: 0.5, label: "Zoom out")
                Rectangle().fill(CP.line).frame(width: 28, height: 1)
                FitMapButton(model: model)
            }
            .padding(CP.Space.xs)
            .cpPanel()
            LocationButton(model: model, live: model.live)
        }
        .frame(width: Self.width)
    }

    private func zoomButton(_ icon: String, factor: Double, label: String) -> some View {
        Button { model.mapCommand = MapCommand(kind: .zoom(factor)) } label: { Image(systemName: icon) }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel(label)
            .help(label)
    }
}

/// Lihat seluruh peta (frame + semua objek), seperti "Zoom to fit" di OCAD.
private struct FitMapButton: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        Button { model.mapCommand = MapCommand(kind: .fitMap) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
            .buttonStyle(ToolButtonStyle())
            .keyboardShortcut("0", modifiers: .command)
            .accessibilityLabel("Lihat seluruh peta")
            .help("Lihat seluruh peta (⌘0)")
    }
}

/// Tampilkan/sembunyikan posisi GPS (radar + arah pandang). Tahan = pusatkan peta ke posisi saya.
private struct LocationButton: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var live: LiveMapState
    /// Di dalam rail alat: tanpa panel sendiri (disorot biru hanya saat aktif), ukuran tombol rail.
    var embedded = false

    var body: some View {
        let on = model.showsMyLocation
        let radius = embedded ? CP.Radius.control : CP.Radius.panel
        VStack(spacing: 2) {
            Image(systemName: model.showsMyLocation ? "location.fill" : "location")
                .font(.system(size: CP.fs(18)))
                .foregroundStyle(model.showsMyLocation ? CP.sky.strong : CP.ink)
            if model.showsMyLocation {
                Text(live.myAccuracyM.map { $0 < 10 ? String(format: "±%.1f m", $0) : String(format: "±%.0f m", $0) } ?? "cari…")
                    .font(CP.mono(10, weight: .medium))
                    .foregroundStyle(accuracyColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: embedded ? CP.hitTarget : MapControls.width, height: on ? 52 : CP.hitTarget)
        .background(on ? CP.sky.fill : (embedded ? .clear : CP.paper), in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(on ? CP.sky.strong : (embedded ? .clear : CP.line)))
        .shadow(color: .black.opacity(embedded ? 0 : 0.08), radius: 1, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { model.showsMyLocation.toggle() }
        .onLongPressGesture { model.mapCommand = MapCommand(kind: .followUser) }
        .accessibilityElement()
        .accessibilityLabel(model.showsMyLocation ? "Sembunyikan posisi saya" : "Tampilkan posisi saya")
        .help(model.showsMyLocation ? "Sembunyikan posisi saya · tahan = pusatkan peta" : "Tampilkan posisi saya · tahan = pusatkan peta")
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
struct DigitalCompass: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var live: LiveMapState
    /// Di dalam rail alat: tanpa panel sendiri (disorot biru hanya saat mengikuti arah iPad).
    var embedded = false

    private var isRotated: Bool {
        let h = live.mapHeading.truncatingRemainder(dividingBy: 360)
        return min(abs(h), abs(360 - abs(h))) > 0.5
    }

    private var readout: Double { live.deviceHeading ?? live.mapHeading }

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 2) {
                dial
                readoutText
            }
            .padding(.vertical, CP.Space.xs)
            .frame(width: embedded ? CP.hitTarget : MapControls.width)
            .background(model.followsHeading ? CP.sky.fill : (embedded ? .clear : CP.paper),
                        in: RoundedRectangle(cornerRadius: embedded ? CP.Radius.control : CP.Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: embedded ? CP.Radius.control : CP.Radius.panel)
                .strokeBorder(model.followsHeading ? CP.sky.strong : (embedded ? .clear : CP.line)))
            .shadow(color: .black.opacity(embedded ? 0 : 0.08), radius: 1, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kompas, arah \(Int(readout.rounded())) derajat")
        .help(isRotated ? "Kompas: ketuk = kembali utara di atas" : "Kompas: ketuk = peta ikut arah hadap iPad")
        .accessibilityHint(isRotated ? "Ketuk untuk kembali ke utara di atas" : "Ketuk agar peta mengikuti arah hadap iPad")
    }

    private var dial: some View {
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
    }

    private var readoutText: some View {
        Text(String(format: "%03.0f° %@", readout.rounded().truncatingRemainder(dividingBy: 360), Self.cardinal(readout)))
            .font(CP.mono(11, weight: .medium))
            .foregroundStyle(model.followsHeading ? CP.sky.strong : CP.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
    /// Kontrol peta di kolom kedua (masih satu panel) bila satu kolom tidak muat tinggi layar.
    var twoColumns = false
    /// Mac: satu baris mendatar di atas (kelompok dipisah garis tegak).
    var horizontal = false
    /// Mac: kompas dipindah ke pojok kanan pita toolbar.
    var showsCompass = true

    /// Kelompok: navigasi/move/node/ukur · sketsa pensil · vektor.
    private let groups: [[Tool]] = [[.navigate, .select, .node, .measure], [.pen, .eraser], [.point, .bezier, .freehand, .rectangle, .ellipse]]

    var body: some View {
        Group {
            if horizontal {
                HStack(spacing: CP.Space.xs) {
                    tools
                    divider
                    mapControls
                }
                .fixedSize()
            } else if twoColumns {
                HStack(alignment: .top, spacing: CP.Space.xs) {
                    VStack(spacing: CP.Space.xs) { tools }
                    Rectangle().fill(CP.line).frame(width: 1).padding(.vertical, CP.Space.xs)
                    VStack(spacing: CP.Space.xs) { mapControls }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: CP.Space.xs) {
                    tools
                    divider
                    mapControls
                }
            }
        }
        .modifier(DockChrome())
    }

    @ViewBuilder
    private var tools: some View {
        ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
            if i > 0 { divider }
            ForEach(group) { tool in
                Button { model.tool = tool } label: { Image(systemName: tool.symbol) }
                    .buttonStyle(ToolButtonStyle(isActive: model.tool == tool))
                    .keyboardShortcut(KeyEquivalent(tool.shortcut), modifiers: [])
                    .accessibilityLabel(tool.label)
                    .help("\(tool.label)\(tool.hint.map { ": \($0)" } ?? "") (\(String(tool.shortcut).uppercased()))")
            }
        }
    }

    /// Kontrol peta (dulu panel terpisah di bawah rail): zoom, seluruh peta, frame, kompas, lokasi.
    @ViewBuilder
    private var mapControls: some View {
        Button { model.mapCommand = MapCommand(kind: .zoom(2)) } label: { Image(systemName: "plus") }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Zoom in")
            .help("Zoom in (⌘=)")
        Button { model.mapCommand = MapCommand(kind: .zoom(0.5)) } label: { Image(systemName: "minus") }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Zoom out")
            .help("Zoom out (⌘−)")
        FitMapButton(model: model)
        Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: { Image(systemName: "rectangle.dashed") }
            .buttonStyle(ToolButtonStyle())
            .accessibilityLabel("Zoom ke frame")
            .help("Zoom ke frame peta")
        divider
        if showsCompass { DigitalCompass(model: model, live: model.live, embedded: true) }
        LocationButton(model: model, live: model.live, embedded: true)
    }

    private var divider: some View {
        Rectangle().fill(CP.line)
            .frame(width: horizontal ? 1 : 28, height: horizontal ? 28 : 1)
            .padding(horizontal ? .horizontal : .vertical, CP.Space.xs)
    }
}

// MARK: - Bar alat vektor

/// Bar kontekstual di atas dock: petunjuk + aksi pen tool, rectangle/ellipse, atau objek yang dipilih.
private struct VectorToolBar: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.docked) private var docked

    var body: some View {
        Group {
            switch model.tool {
            case .bezier:
                if model.draftNodes.isEmpty {
                    // Ketuk = titik sudut · tarik = kurva · ketuk dua kali = selesai · ketuk dua titik di objek yang
                    // sama = bentuknya diikuti · ujung yang ditempel ke objek bersimbol sama = digabung.
                    EmptyView()
                } else {
                    bar {
                        Text(verbatim: "\(model.draftNodes.count) titik").font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                        Button { model.finishDraftForActiveSymbol() } label: {
                            Label(model.activeSymbol?.kind == .area ? "Selesai area" : "Selesai garis", systemImage: "checkmark")
                        }
                            .help(model.activeSymbol?.kind == .area ? "Selesai area (Return)" : "Selesai garis (Return)")
                            .keyboardShortcut(.return, modifiers: [])
                        Button { model.finishDraft(as: .area) } label: { Label("Tutup jadi area", systemImage: "square.dashed") }
                            .help("Tutup jadi area")
                            .disabled(model.draftNodes.count < 3)
                        Button { model.removeLastDraftNode() } label: { Label("Hapus titik terakhir", systemImage: "delete.left") }
                            .help("Hapus titik terakhir (Delete)")
                            .keyboardShortcut(.delete, modifiers: [])
                        Button(role: .destructive) { model.cancelDraft() } label: { Label("Batal", systemImage: "xmark") }
                            .help("Batal (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                }
            case .point:
                if let s = model.activeSymbol, s.kind == .point {
                    EmptyView()   // ketuk peta untuk menempatkan (menempel ke garis/sudut objek lain)
                } else {
                    hint("Simbol titik: pilih simbol titik di panel Simbol (mis. 204.0 Boulder, 417.0 pohon), lalu ketuk peta.")
                }
            case .freehand, .rectangle, .ellipse:
                // Gambar bebas: goresan dirapikan, bagian yang menyusuri objek lain mengikuti bentuknya.
                // Rectangle/ellipse: tarik dari pojok ke pojok (pojok menempel ke objek lain).
                EmptyView()
            case .measure:
                if let m = model.measurement {
                    bar {
                        Image(systemName: "ruler").foregroundStyle(CP.ink)
                        Text(verbatim: Fmt.meters(m.meters, decimals: m.meters < 100 ? 1 : 0))
                            .font(CP.mono(15, weight: .semibold)).foregroundStyle(CP.ink)
                            .accessibilityIdentifier("measureDistance")
                        Text(verbatim: "\(Fmt.mm(m.paperMM(scaleDenominator: model.project.sheet.scaleDenominator), decimals: 1)) di peta 1:\(model.project.sheet.scaleDenominator)")
                            .font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                        Text(verbatim: "Azimut \(Int(m.gridBearing.rounded()) % 360)°")
                            .font(CP.mono(13)).foregroundStyle(CP.inkMuted)
                            .help("Azimut grid (dari utara grid UTM)")
                        Button { model.measurement = nil } label: { Label("Hapus ukuran", systemImage: "xmark") }
                            .help("Hapus ukuran (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else {
                    hint("Ukur: tarik dari titik awal ke titik akhir. Ujungnya menempel ke objek.")
                }
            case .select, .node:
                if model.cutMode, let f = model.selectedFeature {
                    bar {
                        Image(systemName: "scissors").foregroundStyle(CP.ink)
                        Text(f.kind == .line ? "Potong: ketuk titik di garis untuk memotongnya jadi dua"
                             : model.cutStart == nil ? "Belah area: ketuk titik pertama di tepi area"
                             : "Belah area: ketuk titik kedua di tepi seberangnya")
                            .font(.system(size: CP.fs(13))).foregroundStyle(CP.ink)
                        Button(role: .cancel) { model.cancelCut() } label: { Label("Batal", systemImage: "xmark") }
                            .help("Batal (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else if model.isMultiSelection {
                    bar {
                        Text(verbatim: "\(model.selectedIDs.count) objek dipilih")
                            .font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                            .accessibilityIdentifier("selectionCount")
                        let mergeKinds = model.selectionMergeKinds
                        if !mergeKinds.isEmpty {
                            // Garis = Join (sambung di ujung), area = Gabungkan (satukan bentuk).
                            MergeButton(title: mergeKinds == [.line] ? "Join" : (mergeKinds == [.area] ? "Gabungkan" : "Join & Gabungkan"),
                                        help: mergeKinds == [.line] ? "Join garis terpilih bersimbol sama yang ujungnya bertemu"
                                            : mergeKinds == [.area] ? "Gabungkan area terpilih bersimbol sama yang bersentuhan"
                                            : "Join garis dan gabungkan area terpilih bersimbol sama yang bertemu") { model.mergeSelection() }
                                .accessibilityIdentifier("mergeSelection")
                        }
                        Button { model.duplicateSelection() } label: { Label("Duplikat", systemImage: "plus.square.on.square") }
                            .help("Duplikat (⌘D)")
                            .keyboardShortcut("d", modifiers: .command)
                        Button(role: .destructive) { model.deleteSelection() } label: { Label("Hapus \(model.selectedIDs.count) objek", systemImage: "trash") }
                            .help("Hapus \(model.selectedIDs.count) objek (Delete)")
                            .keyboardShortcut(.delete, modifiers: [])
                        Button { model.deselect() } label: { Label("Selesai", systemImage: "checkmark") }
                            .help("Selesai (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else if let f = model.selectedFeature {
                    bar {
                        BarTitle(text: f.displayName)
                        if model.mergeCandidateCount > 0 {
                            // OCAD Merge / OOM Connect paths + Unify areas: objek bersimbol sama yang bertemu.
                            // Di depan dan menonjol agar langsung terlihat saat dua objek bertemu.
                            MergeButton(title: f.kind == .line ? "Join" : "Gabungkan",
                                        help: f.kind == .line ? "Sambung dengan garis bersimbol sama yang ujungnya bertemu"
                                                              : "Gabung dengan area bersimbol sama yang bersentuhan") { model.mergeSelected() }
                                .accessibilityIdentifier("mergeSelected")
                        }
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
                            .help(f.kind == .point ? "Perkecil simbol" : "Tipiskan garis (−0,01 mm)")
                            Text(verbatim: f.kind == .point ? "\(Int((f.effectiveSizeFactor * 100).rounded()))%" : Fmt.mm(f.widthMM))
                                .font(CP.mono(12, weight: .medium))
                                .frame(minWidth: 52)
                            Button { f.kind == .point ? model.resizeSelected(by: 1.1) : model.adjustSelectedWidth(by: 0.01) } label: {
                                Label(f.kind == .point ? "Perbesar" : "Tebalkan", systemImage: "plus.magnifyingglass")
                            }
                            .help(f.kind == .point ? "Perbesar simbol" : "Tebalkan garis (+0,01 mm)")
                            if (f.kind == .point && f.sizeFactor != nil)
                                || (f.kind != .point && f.standardWidthMM.map { abs($0 - f.widthMM) > 0.005 } == true) {
                                Button { model.resetSelectedSize() } label: { Label("Standar", systemImage: "arrow.counterclockwise") }
                                    .help("Kembali ke ukuran standar IOF")
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
                        if let s = model.activeSymbol, s.code != f.symbolCode, model.canSwitch(f, to: s) {
                            // OOM "Switch symbol": pilih objek, pilih simbol di panel, lalu ganti.
                            Button { model.switchSelectedSymbol() } label: {
                                Label("Ganti simbol → \(s.code)", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .help("Ganti simbol objek ke \(s.code) \(s.name)")
                            .disabled(f.isLocked)
                        }
                        if f.symbolCode == nil {
                            Button { model.applyPenStyleToSelection() } label: { Label("Pakai warna pena", systemImage: "paintbrush") }
                                .help("Pakai warna pena")
                                .disabled(f.isLocked)
                        }
                        if model.tool == .node, let i = model.selectedNodeIndex, f.nodes.indices.contains(i) {
                            NodeStylePicker(model: model, current: f.nodeStyle(at: i))
                                .disabled(f.isLocked)
                            Button { model.deleteSelectedNode() } label: { Label("Hapus titik", systemImage: "minus.circle") }
                                .help("Hapus titik")
                        }
                        RotationButton(model: model, feature: f)
                            .disabled(f.isLocked)
                        if f.kind != .point {
                            ShapeEditMenu(model: model, feature: f)
                                .disabled(f.isLocked)
                        }
                        Button { model.duplicateSelection() } label: { Label("Duplikat", systemImage: "plus.square.on.square") }
                            .help("Duplikat (⌘D)")
                            .keyboardShortcut("d", modifiers: .command)
                        Button(role: .destructive) { model.deleteSelection() } label: { Label("Hapus objek", systemImage: "trash") }
                            .help("Hapus objek (Delete)")
                            .keyboardShortcut(.delete, modifiers: [])
                        Button { model.deselect() } label: { Label("Selesai", systemImage: "checkmark") }
                            .help("Selesai (Esc)")
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                } else {
                    // Ketuk objek = pilih · tarik di tempat kosong = kotak pilih · Shift + ketuk = tambah · ⌘A = semua.
                    EmptyView()
                }
            default:
                EmptyView()
            }
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private func hint(_ text: String) -> some View {
        if docked {
            Text(text)
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .padding(.horizontal, CP.Space.s)
                .padding(.vertical, CP.Space.xs + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(CP.line).frame(height: 1) }
        } else {
            Text(text)
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.s)
                .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
        }
    }

    /// Label lengkap bila muat; di layar sempit (iPad Air/mini portrait) jadi ikon saja.
    private func bar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let items = content()
        let panel = { (content: AnyView) in
            content
                .font(.system(size: CP.fs(13), weight: .medium))
                .buttonStyle(.bordered)
                .tint(CP.ink)
                .modifier(BarChrome())
        }
        // Label lengkap → ikon saja → ikon tanpa nama objek → terakhir bisa digeser ke samping, agar bar tidak
        // pernah mendorong layar keluar.
        return ViewThatFits(in: .horizontal) {
            panel(AnyView(HStack(spacing: CP.Space.m) { items }.labelStyle(.titleAndIcon).lineLimit(1).fixedSize()))
            panel(AnyView(HStack(spacing: CP.Space.s) { items }.labelStyle(.iconOnly).lineLimit(1).fixedSize()))
            panel(AnyView(HStack(spacing: CP.Space.xs) { items }.labelStyle(.iconOnly).lineLimit(1).fixedSize()
                .environment(\.barCompact, true)))
            ScrollView(.horizontal, showsIndicators: false) {
                panel(AnyView(HStack(spacing: CP.Space.s) { items }.labelStyle(.iconOnly).lineLimit(1).fixedSize()))
                    .padding(.horizontal, CP.Space.m)
            }
        }
    }
}

/// Bar alat: panel melayang (iPad) atau baris rata kiri di pita toolbar atas (Mac).
private struct BarChrome: ViewModifier {
    @Environment(\.docked) private var docked

    func body(content: Content) -> some View {
        if docked {
            content
                .padding(.horizontal, CP.Space.s)
                .padding(.vertical, CP.Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(CP.line).frame(height: 1) }
        } else {
            content
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.s)
                .cpPanel()
        }
    }
}

/// Nama objek di bar alat; disembunyikan di varian bar paling ringkas (nama juga tampil di panel layer).
private struct BarTitle: View {
    let text: String
    @Environment(\.barCompact) private var compact

    var body: some View {
        if !compact {
            Text(text).font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink).lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .leading)
        }
    }
}

private struct BarCompactKey: EnvironmentKey { static let defaultValue = false }
private struct DockedKey: EnvironmentKey { static let defaultValue = false }

/// Mac: rail, dock pena, dan bar alat menempel di pita toolbar atas (tanpa bingkai panel melayang).
struct DockChrome: ViewModifier {
    @Environment(\.docked) private var docked
    var padding: CGFloat = CP.Space.xs
    var horizontalPadding: CGFloat?

    func body(content: Content) -> some View {
        if docked {
            content
        } else {
            content
                .padding(.vertical, padding)
                .padding(.horizontal, horizontalPadding ?? padding)
                .cpPanel()
        }
    }
}

/// Pita toolbar Mac: latar kertas, garis bawah, isi menempel rata kiri.
struct MacBand: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.docked, true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CP.paper)
            .overlay(alignment: .bottom) { Rectangle().fill(CP.line).frame(height: 1) }
    }
}

/// Tepi bawah pita toolbar (dalam ruang koordinat `space`), untuk menggeser kanvas peta ke bawahnya.
struct BandBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct BandBottomReader: ViewModifier {
    let space: String

    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear.preference(key: BandBottomKey.self, value: g.frame(in: .named(space)).maxY)
        })
    }
}

/// Panel kanan: melayang (iPad) atau menempel penuh di sisi kanan jendela dengan garis tepi kiri (Mac).
struct SidePanelChrome: ViewModifier {
    var maxHeight: CGFloat = .infinity
    var minHeight: CGFloat = 0

    func body(content: Content) -> some View {
        if CP.isMac {
            content
                .frame(maxHeight: .infinity)
                .background(CP.paper)
                .overlay(alignment: .leading) { Rectangle().fill(CP.line).frame(width: 1) }
        } else {
            content
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .cpPanel()
        }
    }
}

/// Jarak untuk elemen di pojok kanan pita toolbar (kompas), agar tidak mepet tepi jendela.
struct BandCornerPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.leading, CP.Space.s)
            .padding(.trailing, CP.Space.m)
            .padding(.vertical, CP.Space.xs)
    }
}

/// Garis pemisah tegak antarkelompok di pita toolbar.
struct BandSeparator: View {
    var body: some View { Rectangle().fill(CP.line).frame(width: 1, height: 28) }
}

extension EnvironmentValues {
    /// Bar alat dalam varian paling ringkas (layar sempit).
    var barCompact: Bool {
        get { self[BarCompactKey.self] }
        set { self[BarCompactKey.self] = newValue }
    }

    /// Menempel di pita toolbar atas (Mac).
    var docked: Bool {
        get { self[DockedKey.self] }
        set { self[DockedKey.self] = newValue }
    }
}



// MARK: - Dock pena

private struct PenDockChrome: ViewModifier {
    @Environment(\.docked) private var docked

    func body(content: Content) -> some View {
        if docked {
            content
        } else {
            content
                .padding(.horizontal, CP.Space.m)
                .padding(.vertical, CP.Space.xs)
                .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
                .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(CP.peach.fill, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
    }
}

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
                .help("Pena \(preset.name) \(Fmt.mm(preset.widthMM))")
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
        .modifier(PenDockChrome())
    }

    @ViewBuilder
    private var penWidthControls: some View {
            Button { model.setPenWidth(model.pen.widthMM - 0.01) } label: { Image(systemName: "minus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("[", modifiers: [])
                .accessibilityLabel("Kurangi tebal")
                .help("Kurangi tebal ([)")
            Slider(value: Binding(get: { model.pen.widthMM }, set: { model.setPenWidth($0) }),
                   in: PenPreset.widthRange)
                .frame(width: 140)
                .accessibilityLabel("Tebal garis")
                .help("Tebal garis")
            Button { model.setPenWidth(model.pen.widthMM + 0.01) } label: { Image(systemName: "plus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("]", modifiers: [])
                .accessibilityLabel("Tambah tebal")
                .help("Tambah tebal (])")
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
                Text(symbol.name).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted).lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
            Button { step(-1) } label: { Image(systemName: "minus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("[", modifiers: [])
                .accessibilityLabel(isPoint ? "Perkecil simbol" : "Tipiskan garis 0,01 mm")
                .help(isPoint ? "Perkecil simbol ([)" : "Tipiskan garis 0,01 mm ([)")
            readout
                .frame(width: 84)
            Button { step(1) } label: { Image(systemName: "plus") }
                .buttonStyle(ToolButtonStyle())
                .keyboardShortcut("]", modifiers: [])
                .accessibilityLabel(isPoint ? "Perbesar simbol" : "Tebalkan garis 0,01 mm")
                .help(isPoint ? "Perbesar simbol (])" : "Tebalkan garis 0,01 mm (])")
            Button("Standar") { reset() }
                .font(.system(size: CP.fs(12), weight: .medium))
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
        .help("Rotasi objek (\(Int(feature.rotationDegrees.rounded()))°)")
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
                Text("Rotasi objek").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                Text(verbatim: degreesText(current)).font(CP.mono(17, weight: .semibold)).foregroundStyle(CP.ink)
            }
            Text("Searah jarum jam terhadap utara grid, berputar di titik tengah objek.")
                .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
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
            .help("Sudut rotasi")
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
            Text("Edit bentuk").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
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
            Text("Tambah titik: ketuk dua kali di garis objek terpilih. Gabung: tombol Join (garis) / Gabungkan (area).")
                .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
        }
    }

    private func action(_ title: String, _ icon: String, _ detail: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: CP.Space.m) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(CP.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: CP.fs(14), weight: .medium)).foregroundStyle(CP.ink)
                    Text(detail).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .help(title)
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
                Text("Skala objek").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                Text(verbatim: "\(Int(percent.rounded()))%").font(CP.mono(17, weight: .semibold)).foregroundStyle(CP.ink)
            }
            Text("Bentuk diperbesar/diperkecil sebanding dari titik tengahnya; tebal garis tetap.")
                .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
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
            .help("Skala")
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
                .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
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
            Text("Garis paralel").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
            Text(isArea ? "Area: kiri = ke dalam, kanan = ke luar." : "Kiri/kanan mengikuti arah garis digambar (balik arah bila terbalik).")
                .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            HStack {
                Text("Jarak").font(.system(size: CP.fs(13))).foregroundStyle(CP.ink)
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
            .font(.system(size: CP.fs(13), weight: .medium))
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
            Label(feature.symbolCode.map { "Simbol \($0)" } ?? "Beri simbol", systemImage: "arrow.triangle.2.circlepath")
        }
        .popover(isPresented: $showing) {
            SymbolSwitchPicker(model: model, library: symbols) { showing = false }
                .frame(width: 380, height: 520)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Ganti simbol objek")
        .help("Ganti simbol objek")
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
            .help("Isi area")
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
            Text(fill ? "Isi dengan simbol area" : "Ganti simbol").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
            if fill {
                Text("Bentuk garis diisi area baru di bawahnya; simbol garisnya tetap. Garis yang belum tertutup ditutup lurus.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            } else if let f {
                Text(f.symbolCode.map { "Sekarang: \($0) \(f.symbolName ?? "")" } ?? "Objek sketsa tanpa simbol")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted).lineLimit(1)
                Text(f.kind == .point ? "Simbol titik bisa diganti ke simbol titik lain."
                     : "Garis dan area bisa saling ditukar; bentuk objek tetap.")
                    .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            }
            TextField("Cari kode atau nama (mis. 506 atau path)", text: $query)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !fill, let code = f?.symbolCode, model.sameSymbolCount > 1 {
                Toggle("Semua objek \(code) (\(model.sameSymbolCount))", isOn: $allSame)
                    .font(.system(size: CP.fs(13)))
                    .tint(CP.peach.strong)
            }
            let list = candidates
            if list.isEmpty {
                Text(library.enabledSets.isEmpty ? "Belum ada set simbol aktif." : "Tidak ada simbol yang cocok.")
                    .font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
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
                                    Text(s.name).font(.system(size: CP.fs(13))).foregroundStyle(CP.ink).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if s.kind.rawValue != f?.kind.rawValue {
                                        Text(s.kind.label).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
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

// MARK: - Convert to Sharp / Smooth / Smart

/// Tiga tombol jenis titik untuk titik aktif di Node Tool (seperti Affinity Designer).
private struct NodeStylePicker: View {
    @ObservedObject var model: WorkspaceModel
    let current: NodeStyle

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NodeStyle.allCases, id: \.self) { style in
                Button { model.convertSelectedNode(to: style) } label: {
                    NodeStyleIcon(style: style)
                        .frame(width: 34, height: 30)
                        .background(style == current ? CP.sky.fill : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(style == current ? CP.sky.strong : CP.ink)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(style == current ? .isSelected : [])
                .help("\(style.title): \(style.hint)")
            }
        }
        .padding(2)
        .background(CP.line.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension NodeStyle {
    var title: String {
        switch self {
        case .sharp: return "Convert to Sharp"
        case .smooth: return "Convert to Smooth"
        case .smart: return "Convert to Smart"
        }
    }

    var hint: String {
        switch self {
        case .sharp: return "sudut tajam, tanpa handle"
        case .smooth: return "lengkung halus, handle segaris"
        case .smart: return "lengkung otomatis mengikuti titik tetangga"
        }
    }
}

/// Ikon jenis titik: sharp = Λ dengan titik penuh, smooth = lengkung + handle mendatar, smart = lengkung + titik kosong.
private struct NodeStyleIcon: View {
    let style: NodeStyle

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let top = CGPoint(x: w / 2, y: h * 0.3)
            let left = CGPoint(x: w * 0.22, y: h * 0.82), right = CGPoint(x: w * 0.78, y: h * 0.82)
            var path = Path()
            path.move(to: left)
            switch style {
            case .sharp:
                path.addLine(to: top)
                path.addLine(to: right)
            case .smooth, .smart:
                path.addCurve(to: top, control1: CGPoint(x: left.x, y: h * 0.5), control2: CGPoint(x: w * 0.3, y: top.y))
                path.addCurve(to: right, control1: CGPoint(x: w * 0.7, y: top.y), control2: CGPoint(x: right.x, y: h * 0.5))
            }
            ctx.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            let r: CGFloat = 3
            let dot = Path(ellipseIn: CGRect(x: top.x - r, y: top.y - r, width: 2 * r, height: 2 * r))
            switch style {
            case .sharp:
                ctx.fill(dot, with: .foreground)
            case .smooth:
                var handle = Path()
                handle.move(to: CGPoint(x: w * 0.3, y: top.y))
                handle.addLine(to: CGPoint(x: w * 0.7, y: top.y))
                ctx.stroke(handle, with: .foreground, lineWidth: 1)
                for x in [w * 0.3, w * 0.7] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: top.y - 1.8, width: 3.6, height: 3.6)), with: .foreground)
                }
                ctx.fill(dot, with: .foreground)
            case .smart:
                ctx.fill(dot, with: .color(CP.paper))
                ctx.stroke(dot, with: .foreground, lineWidth: 1.4)
            }
        }
    }
}

/// Tombol gabung (menonjol, nama selalu tampil) saat objek bersimbol sama bertemu.
private struct MergeButton: View {
    let title: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: "link") }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .tint(CP.sky.strong)
            .help("\(help) (⌘J)")
            .keyboardShortcut("j", modifiers: .command)
    }
}
