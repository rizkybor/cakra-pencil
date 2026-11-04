import CakraCore
import PDFKit
import SwiftUI

/// Halaman Course Planner (seperti Purple Pen): peta dengan overprint lintasan, rail alat khusus
/// (navigasi, start, kontrol, finish), dan panel Course lengkap: Lintasan · Kontrol · Deskripsi · Laporan.
/// Memakai model workspace yang sama, jadi undo, simpan otomatis, dan data peta tetap satu.
struct CoursePlannerView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var showingExport = false
    @State private var importingMap = false
    @State private var showingPreview = false
    @State private var tab = CourseTab.courses

    var body: some View {
        ZStack {
            MapCanvas(model: model, role: .course)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                CourseTopBar(model: model, showingExport: $showingExport, importingMap: $importingMap, showingPreview: $showingPreview)
                HStack(alignment: .top, spacing: 0) {
                    CourseToolRail(model: model)
                        .padding(CP.Space.m)
                    Spacer(minLength: 0)
                    VStack {
                        Spacer(minLength: 0)
                        MapControls(model: model)
                    }
                    .padding(.vertical, CP.Space.m)
                    CoursePlannerPanel(model: model, tab: $tab, showingExport: $showingExport, showingPreview: $showingPreview)
                        .frame(width: 400)
                        .padding(CP.Space.m)
                }
                CourseStatusBar(model: model)
                    .padding(.horizontal, CP.Space.m)
                    .padding(.bottom, CP.Space.m)
            }

            if let notice = model.notice {
                VStack {
                    Toast(text: notice) { model.notice = nil }
                        .padding(.top, 64)
                    Spacer()
                }
            }
        }
        .background(CP.paper)
        .sheet(isPresented: $showingExport) {
            ExportSheet(model: model, mode: .courses)
        }
        .sheet(isPresented: $showingPreview) {
            CoursePreviewSheet(model: model)
        }
        .fileImporter(isPresented: $importingMap, allowedContentTypes: LayerPanel.mapFileTypes) { result in
            if case let .success(url) = result { Task { await model.importOcad(from: url) } }
        }
    }
}

enum CourseTab: String, CaseIterable {
    case courses = "Lintasan"
    case controls = "Kontrol"
    case descriptions = "Deskripsi"
    case report = "Laporan"
}

// MARK: - Top bar

private struct CourseTopBar: View {
    @ObservedObject var model: WorkspaceModel
    @Binding var showingExport: Bool
    @Binding var importingMap: Bool
    @Binding var showingPreview: Bool

    var body: some View {
        HStack(spacing: CP.Space.m) {
            Button { model.closeCoursePlanner() } label: {
                Label("Peta kerja", systemImage: "chevron.left").font(.system(size: 15, weight: .medium)).lineLimit(1).fixedSize()
            }
            .buttonStyle(.bordered)
            .tint(CP.ink)
            .accessibilityLabel("Kembali ke peta kerja")

            Image(systemName: "flag.2.crossed").foregroundStyle(Color(hexString: "#A626FF")).font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Course Planner").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink).lineLimit(1).fixedSize()
                Text(subtitle).font(CP.mono(12)).foregroundStyle(CP.inkMuted).lineLimit(1)
            }
            .layoutPriority(-1)
            Spacer(minLength: 0)
            // Lebar cukup: ikon + teks; layar sempit (iPad portrait): ikon saja.
            ViewThatFits(in: .horizontal) {
                actions.labelStyle(.titleAndIcon)
                actions.labelStyle(.iconOnly)
            }
            .layoutPriority(1)
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(ToolButtonStyle())
                .disabled(!model.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel("Undo")
                .accessibilityIdentifier("courseUndo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(ToolButtonStyle())
                .disabled(!model.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .accessibilityLabel("Redo")
            Button("Export") { showingExport = true }
                .buttonStyle(PrimaryButtonStyle())
                .lineLimit(1)
                .fixedSize()
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.courseSet.courses.isEmpty)
                .accessibilityIdentifier("courseExport")
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.vertical, CP.Space.s)
        .background(CP.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(CP.line).frame(height: 1) }
    }

    private var actions: some View {
        HStack(spacing: CP.Space.s) {
            Button { importingMap = true } label: {
                Label("Import peta", systemImage: "square.and.arrow.down").font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(CP.ink)
            .help("Pakai peta OCAD / OOM (.ocd, .omap, .xmap) ter-georeferensi sebagai latar lintasan")
            .accessibilityLabel("Import peta OCAD atau OOM")
            Button { showingPreview = true } label: {
                Label("Pratinjau", systemImage: "eye").font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(Color(hexString: "#A626FF"))
            .disabled(model.courseSet.courses.isEmpty)
            .keyboardShortcut("p", modifiers: .command)
            .accessibilityLabel("Pratinjau deskripsi kontrol")
            SaveBadge(state: model.saveState)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var subtitle: String {
        let set = model.courseSet
        let standard = model.project.sheet.scaleDenominator <= 5000 ? "ISSprOM" : "ISOM"
        let event = set.eventTitle.isEmpty ? model.project.name : set.eventTitle
        return "\(event) · 1:\(model.project.sheet.scaleDenominator) · \(standard) · \(set.courses.count) lintasan · \(set.controls.filter { $0.kind == .control }.count) kontrol"
    }
}

// MARK: - Rail alat

private struct CourseToolRail: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(spacing: CP.Space.xs) {
            Button { model.useCourseTool(nil) } label: { Image(systemName: "hand.raised") }
                .buttonStyle(ToolButtonStyle(isActive: model.tool == .navigate))
                .keyboardShortcut("h", modifiers: [])
                .accessibilityLabel("Navigasi")
            divider
            place(.start, key: "s")
            place(.control, key: "k")
            place(.finish, key: "f")
            divider
            Button { model.zoomToCourse() } label: { Image(systemName: "scope") }
                .buttonStyle(ToolButtonStyle())
                .accessibilityLabel("Zoom ke lintasan")
            Button { model.mapCommand = MapCommand(kind: .zoomToFrame) } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(ToolButtonStyle())
                .accessibilityLabel("Zoom ke frame")
        }
        .padding(CP.Space.xs)
        .cpPanel()
    }

    private func place(_ kind: ControlKind, key: Character) -> some View {
        let active = model.tool == .control && model.controlPlacement == kind
        return Button { model.useCourseTool(kind) } label: {
            ControlGlyph(kind: kind, color: active ? .white : Color(hexString: "#A626FF")).frame(width: 22, height: 22)
        }
        .buttonStyle(ToolButtonStyle(isActive: active))
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
        .accessibilityLabel("Tempatkan \(kind.label)")
        .help("Tempatkan \(kind.label) (\(String(key).uppercased()))")
    }

    private var divider: some View {
        Rectangle().fill(CP.line).frame(width: 28, height: 1).padding(.vertical, CP.Space.xs)
    }
}

// MARK: - Status bawah: petunjuk alat + intensitas peta

private struct CourseStatusBar: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        HStack(spacing: CP.Space.l) {
            Text(hint).font(.system(size: 13)).foregroundStyle(CP.inkMuted).lineLimit(2)
            Spacer(minLength: CP.Space.m)
            if let id = model.selectedControlID, let c = model.courseSet.control(id) {
                ControlSizeStepper(model: model, control: c)
            }
            Image(systemName: "map").foregroundStyle(CP.inkMuted)
                .help("Latar: peta hasil gambar. Citra satelit tidak dipakai di halaman Course.")
                .accessibilityLabel("Latar: peta hasil gambar, tanpa citra satelit")
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(CP.inkMuted)
                .accessibilityHidden(true)
            Slider(value: $model.courseMapIntensity, in: 0.2...1)
                .frame(width: 130)
                .tint(CP.ink)
                .accessibilityLabel("Intensitas peta")
            Text(verbatim: "\(Int((model.courseMapIntensity * 100).rounded()))%").font(CP.mono(12)).foregroundStyle(CP.ink).frame(width: 40)
        }
        .padding(.horizontal, CP.Space.l)
        .padding(.vertical, CP.Space.s)
        .cpPanel()
    }

    private var hint: String {
        guard model.tool == .control else { return "Navigasi: geser, cubit, putar peta" }
        let target = model.selectedCourse.map { "lintasan \($0.name)" } ?? "semua kontrol"
        return "Ketuk peta: \(model.controlPlacement.label.lowercased()) baru (\(target)) · tarik = pindah"
    }
}

// MARK: - Panel Course

struct CoursePlannerPanel: View {
    @ObservedObject var model: WorkspaceModel
    @Binding var tab: CourseTab
    @Binding var showingExport: Bool
    @Binding var showingPreview: Bool
    @State private var editingControl: ControlPoint?
    @State private var renaming: Course?
    @State private var newName = ""
    @State private var eventTitle = ""
    @State private var reordering = false

    private var set: CourseSet { model.courseSet }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel Course", selection: $tab) {
                ForEach(CourseTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], CP.Space.l)
            .padding(.bottom, CP.Space.s)

            switch tab {
            case .courses: coursesTab
            case .controls: controlsTab
            case .descriptions: descriptionsTab
            case .report: reportTab
            }
        }
        .frame(maxHeight: .infinity)
        .cpPanel()
        .onAppear { eventTitle = set.eventTitle }
        .sheet(item: $editingControl) { c in ControlEditor(model: model, controlID: c.id) }
        .alert("Ganti nama lintasan", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nama", text: $newName)
            Button("Simpan") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let c = renaming, !name.isEmpty { model.updateCourse(c.id) { $0.name = name } }
                renaming = nil
            }
            Button("Batal", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Tab Lintasan

    private var coursesTab: some View {
        List {
            Section {
                TextField("Nama acara (mis. Kejurda Sprint 2026)", text: $eventTitle)
                    .onSubmit { model.setEventTitle(eventTitle) }
                    .onDisappear { if eventTitle != set.eventTitle { model.setEventTitle(eventTitle) } }
            } header: { Text("Acara") }

            Section {
                courseCard(nil)
                ForEach(set.courses) { courseCard($0) }
                Button { model.addCourse() } label: {
                    Label("Lintasan baru", systemImage: "plus.circle.fill").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color(hexString: "#A626FF"))
            } header: {
                Text("Lintasan (\(set.courses.count))")
            }

            if let course = model.selectedCourse {
                courseDetail(course)
                courseControls(course)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .textCase(nil)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
    }

    private func courseCard(_ course: Course?) -> some View {
        let selected = model.selectedCourseID == course?.id
        let controls = course.map { set.controls(of: $0).filter { $0.kind == .control }.count } ?? set.controls.filter { $0.kind == .control }.count
        return Button { model.selectedCourseID = course?.id } label: {
            HStack(spacing: CP.Space.s) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color(hexString: "#A626FF") : CP.inkMuted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(course?.name ?? "Semua kontrol").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
                    Text(course.map { c in
                        "\(c.kind == .score ? "Score" : Fmt.km(set.length(of: c))) · \(controls) kontrol · \(c.competitors) peserta"
                    } ?? "\(controls) kontrol di peta").font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(course.map { "Lintasan \($0.name)" } ?? "Semua kontrol")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            if let c = course {
                Button { newName = c.name; renaming = c } label: { Label("Ganti nama", systemImage: "pencil") }
                Button { model.duplicateCourse(c.id) } label: { Label("Duplikat", systemImage: "plus.square.on.square") }
                Button { model.selectedCourseID = c.id; model.zoomToCourse() } label: { Label("Zoom ke lintasan", systemImage: "scope") }
                Divider()
                Button(role: .destructive) { model.deleteCourse(c.id) } label: { Label("Hapus lintasan", systemImage: "trash") }
            }
        }
    }

    private func courseDetail(_ course: Course) -> some View {
        Section {
            Picker("Jenis", selection: Binding(get: { course.kind }, set: { k in model.updateCourse(course.id) { $0.kind = k } })) {
                ForEach(CourseKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                stat(course.kind == .score ? "Score" : Fmt.km(set.length(of: course)), "panjang")
                Spacer()
                stat("\(set.controls(of: course).filter { $0.kind == .control }.count)", "kontrol")
                Spacer()
                stat(course.climbM.map { "\($0) m" } ?? "–", "tanjakan")
            }
            Stepper(value: Binding(get: { course.competitors }, set: { v in model.updateCourse(course.id) { $0.competitors = max(0, v) } }),
                    in: 0...5000, step: 5) {
                HStack {
                    Text("Peserta")
                    Spacer()
                    Text(verbatim: "\(course.competitors)").font(CP.mono(14))
                }
            }
            Stepper(value: Binding(get: { course.climbM ?? 0 }, set: { v in model.updateCourse(course.id) { $0.climbM = v > 0 ? v : nil } }),
                    in: 0...3000, step: 5) {
                HStack {
                    Text("Tanjakan")
                    Spacer()
                    Text(verbatim: "\(course.climbM ?? 0) m").font(CP.mono(14))
                }
            }
        } header: {
            HStack {
                Text("Lintasan \(course.name)").textCase(nil)
                Spacer()
                Menu {
                    Button { newName = course.name; renaming = course } label: { Label("Ganti nama", systemImage: "pencil") }
                    Button { model.duplicateCourse(course.id) } label: { Label("Duplikat", systemImage: "plus.square.on.square") }
                    Button { model.zoomToCourse() } label: { Label("Zoom ke lintasan", systemImage: "scope") }
                    Divider()
                    Button(role: .destructive) { model.deleteCourse(course.id) } label: { Label("Hapus lintasan", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Menu lintasan \(course.name)")
            }
        }
    }

    private func courseControls(_ course: Course) -> some View {
        let list = set.controls(of: course)
        let legs = set.legLengths(of: course)
        var n = 0
        let numbers: [String] = list.map { c in
            guard c.kind == .control else { return "" }
            n += 1
            return course.kind == .score ? "" : "\(n)"
        }
        return Section {
            if list.isEmpty {
                Text("Pilih Start di rail kiri lalu ketuk peta, lanjut Kontrol, akhiri dengan Finish.")
                    .font(.system(size: 13)).foregroundStyle(CP.inkMuted)
            }
            ForEach(Array(list.enumerated()), id: \.offset) { i, c in
                controlRow(c, number: numbers[i], detail: i > 0 && course.kind == .normal ? "\(Int(legs[i - 1].rounded())) m" : nil)
            }
            .onMove { model.moveSelectedCourseControls(from: $0, to: $1) }
            .onDelete { idx in idx.sorted(by: >).forEach { model.removeFromSelectedCourse(at: $0) } }
        } header: {
            HStack {
                Text("Urutan kontrol")
                Spacer()
                Button(reordering ? "Selesai" : "Atur urutan") { reordering.toggle() }
                    .font(.system(size: 13, weight: .semibold))
                    .textCase(nil)
                    .disabled(list.count < 2)
            }
        } footer: {
            Text("Ketuk baris untuk kode dan deskripsi IOF. Geser ke kiri untuk mengeluarkan dari lintasan (kontrol tetap di peta).")
        }
    }

    private func controlRow(_ c: ControlPoint, number: String, detail: String?) -> some View {
        Button {
            model.selectedControlID = c.id
            editingControl = c
        } label: {
            HStack(spacing: CP.Space.s) {
                ControlGlyph(kind: c.kind).frame(width: 18, height: 18)
                Text(verbatim: number).font(CP.mono(12)).foregroundStyle(CP.inkMuted).frame(width: 18, alignment: .trailing)
                Text(verbatim: c.label(in: set)).font(CP.mono(14, weight: .semibold)).foregroundStyle(CP.ink).frame(width: 36, alignment: .leading)
                Text(c.description.isEmpty ? (c.kind == .control ? "ketuk untuk deskripsi" : c.kind.label) : c.description.text)
                    .font(.system(size: 13)).foregroundStyle(c.description.isEmpty ? CP.inkMuted : CP.ink).lineLimit(1)
                Spacer(minLength: 2)
                if let detail { Text(verbatim: detail).font(CP.mono(11)).foregroundStyle(CP.inkMuted) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(model.selectedControlID == c.id ? CP.sky.fill : nil)
        .accessibilityLabel("\(c.kind.label) \(c.label(in: set))\(number.isEmpty ? "" : ", nomor \(number)")")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(CP.mono(17, weight: .semibold)).foregroundStyle(CP.ink)
            Text(label).font(.system(size: 11)).foregroundStyle(CP.inkMuted)
        }
    }

    // MARK: Tab Kontrol

    private var controlsTab: some View {
        let loads = Dictionary(uniqueKeysWithValues: set.controlLoads().map { ($0.controlID, $0) })
        return List {
            Section {
                Stepper(value: Binding(get: { set.firstCode }, set: { v in model.editCourses { $0.firstCode = v } }), in: 31...200) {
                    HStack {
                        Text("Kode awal")
                        Spacer()
                        Text(verbatim: "\(set.firstCode)").font(CP.mono(14))
                    }
                }
                Toggle("Lewati kode yang terbaca lain bila terbalik (66/99, 68/89)",
                       isOn: Binding(get: { set.avoidAmbiguousCodes }, set: { on in model.editCourses { $0.avoidAmbiguousCodes = on } }))
                    .tint(CP.sage.strong)
                Button { model.renumberControls() } label: { Label("Nomori ulang semua kode", systemImage: "number") }
                    .disabled(set.controls.isEmpty)
            } header: { Text("Penomoran kode") } footer: {
                Text("Nomori ulang mengikuti urutan lintasan (lintasan pertama dulu). Kode 31–255 sesuai unit SPORTident/Emit.")
            }

            sizeSection

            Section {
                if set.controls.isEmpty {
                    Text("Belum ada kontrol. Pilih Kontrol di rail kiri lalu ketuk peta.").font(.system(size: 13)).foregroundStyle(CP.inkMuted)
                }
                ForEach(set.controls) { c in
                    let using = set.courses.filter { $0.controlIDs.contains(c.id) }.map(\.name)
                    let visits = loads[c.id]?.visits ?? 0
                    controlRow(c, number: "", detail: using.isEmpty ? "tidak dipakai" : "\(using.joined(separator: ",")) · \(visits)")
                }
                .onDelete { idx in idx.map { set.controls[$0].id }.forEach(model.deleteControl) }
            } header: { Text("Semua kontrol (\(set.controls.count))") } footer: {
                Text("Kanan: lintasan yang memakai · jumlah peserta. Geser ke kiri untuk menghapus dari peta dan semua lintasan.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .textCase(nil)
    }

    private var sizeSection: some View {
        let a = set.effectiveAppearance
        let custom = set.controls.filter { $0.sizeFactor != nil }.count
        return Section {
            percentStepper("Lingkaran kontrol, start, finish", a.controlScale) { v in model.updateAppearance { $0.controlScale = v } }
            percentStepper("Nomor kontrol", a.numberScale) { v in model.updateAppearance { $0.numberScale = v } }
            percentStepper("Tebal garis", a.lineScale) { v in model.updateAppearance { $0.lineScale = v } }
            if !a.isStandard || custom > 0 {
                Button { model.resetAllControlSizes() } label: { Label("Kembali ke standar IOF", systemImage: "arrow.counterclockwise") }
            }
        } header: { Text("Ukuran simbol lintasan").textCase(nil) } footer: {
            let base = model.courseStyle
            Text("100% = standar \(model.project.sheet.scaleDenominator <= 5000 ? "ISSprOM" : "ISOM"): lingkaran \(Fmt.mm(base.controlDiameterMM, decimals: 1)), start \(Fmt.mm(base.startSideMM, decimals: 1)), nomor \(Fmt.mm(base.numberHeightMM, decimals: 1)), garis \(Fmt.mm(base.lineWidthMM)).\(custom > 0 ? " \(custom) kontrol punya ukuran sendiri (atur di editor kontrol)." : "")")
        }
    }

    private func percentStepper(_ title: String, _ value: Double, set: @escaping (Double) -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: set), in: CourseAppearance.range, step: 0.05) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(Int((value * 100).rounded()))%").font(CP.mono(14))
                    .foregroundStyle(abs(value - 1) < 0.001 ? CP.inkMuted : CP.ink)
            }
        }
        .accessibilityLabel("\(title), \(Int((value * 100).rounded())) persen")
    }

    // MARK: Tab Deskripsi

    private var descriptionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.m) {
                if set.courses.isEmpty {
                    Text("Buat lintasan dulu di tab Lintasan.").font(.system(size: 13)).foregroundStyle(CP.inkMuted)
                } else {
                    Picker("Lintasan", selection: Binding(get: { model.selectedCourseID ?? set.courses.first?.id },
                                                         set: { model.selectedCourseID = $0 })) {
                        ForEach(set.courses) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .pickerStyle(.segmented)
                    if let course = model.selectedCourse ?? set.courses.first {
                        DescriptionSheetView(sheet: DescriptionSheet(set, course: course)) { index in
                            let list = set.controls(of: course)
                            if list.indices.contains(index) { editingControl = list[index] }
                        }
                        Text("Ketuk baris untuk mengubah deskripsi. Deskripsi teks IOF 2018; dicetak di sudut peta lomba (atur di Tata letak cetak).")
                            .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                        Button { showingPreview = true } label: {
                            Label("Pratinjau peta lomba (seperti hasil cetak)", systemImage: "eye").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(hexString: "#A626FF"))
                        .accessibilityLabel("Pratinjau PDF deskripsi")
                        Button { showingExport = true } label: {
                            Label("Export PDF + deskripsi…", systemImage: "doc.richtext").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Divider().overlay(CP.line).padding(.vertical, CP.Space.xs)
                        PrintLayoutSection(model: model)
                    }
                }
            }
            .padding(CP.Space.l)
        }
    }

    // MARK: Tab Laporan

    private var reportTab: some View {
        let loads = set.controlLoads().filter { $0.courseCount > 0 }.sorted { $0.visits > $1.visits }
        let legs = set.sharedLegLoads()
        let warnings = set.warnings()
        return ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.l) {
                reportTitle("Ringkasan lintasan")
                Grid(alignment: .leading, horizontalSpacing: CP.Space.m, verticalSpacing: CP.Space.xs) {
                    GridRow {
                        ForEach(["Lintasan", "Panjang", "Naik", "Kontrol", "Peserta"], id: \.self) {
                            Text($0).font(.system(size: 11, weight: .semibold)).foregroundStyle(CP.inkMuted)
                        }
                    }
                    ForEach(set.courses) { c in
                        GridRow {
                            Text(c.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(verbatim: c.kind == .score ? "Score" : Fmt.km(set.length(of: c))).font(CP.mono(12))
                            Text(verbatim: c.climbM.map { "\($0) m" } ?? "–").font(CP.mono(12))
                            Text(verbatim: "\(set.controls(of: c).filter { $0.kind == .control }.count)").font(CP.mono(12))
                            Text(verbatim: "\(c.competitors)").font(CP.mono(12))
                        }
                    }
                }
                if set.courses.isEmpty { Text("Belum ada lintasan.").font(.system(size: 13)).foregroundStyle(CP.inkMuted) }

                reportTitle("Beban peserta per kontrol")
                if loads.isEmpty {
                    Text("Isi jumlah peserta per lintasan untuk menghitung beban tiap kontrol.").font(.system(size: 13)).foregroundStyle(CP.inkMuted)
                } else {
                    let maxVisits = max(loads.first?.visits ?? 1, 1)
                    ForEach(loads, id: \.controlID) { l in
                        HStack(spacing: CP.Space.s) {
                            Text(verbatim: set.control(l.controlID)?.label(in: set) ?? "?").font(CP.mono(12, weight: .semibold)).frame(width: 34, alignment: .leading)
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 3).fill(Color(hexString: "#A626FF").opacity(0.55))
                                    .frame(width: max(2, g.size.width * Double(l.visits) / Double(maxVisits)))
                            }
                            .frame(height: 10)
                            Text(verbatim: "\(l.visits)").font(CP.mono(12)).frame(width: 44, alignment: .trailing)
                            Text(verbatim: "\(l.courseCount)×").font(CP.mono(11)).foregroundStyle(CP.inkMuted).frame(width: 26, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Kontrol \(set.control(l.controlID)?.label(in: set) ?? ""), \(l.visits) peserta, \(l.courseCount) lintasan")
                    }
                }

                if !legs.isEmpty {
                    reportTitle("Leg bersama")
                    ForEach(legs, id: \.self) { l in
                        HStack {
                            Text(verbatim: "\(set.control(l.from)?.label(in: set) ?? "?")–\(set.control(l.to)?.label(in: set) ?? "?")").font(CP.mono(12, weight: .semibold))
                            Text("\(l.courseCount) lintasan").font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                            Spacer()
                            Text(verbatim: "\(l.visits) peserta").font(CP.mono(12))
                        }
                    }
                }

                reportTitle("Pemeriksaan")
                if warnings.isEmpty {
                    Label("Tidak ada masalah", systemImage: "checkmark.circle").foregroundStyle(CP.sage.strong).font(.system(size: 13))
                } else {
                    VStack(alignment: .leading, spacing: CP.Space.xs) {
                        ForEach(warnings, id: \.self) { Text("• \($0)").font(.system(size: 12)).foregroundStyle(CP.ink) }
                    }
                    .padding(CP.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CP.butter.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                }

                Button { showingExport = true } label: {
                    Label("Export lintasan…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(set.courses.isEmpty)
                Text("IOF XML 3.0 (MeOS, OE/SportSoftware, SI Config, Purple Pen, OCAD), PDF peta lintasan + deskripsi, PNG + world file.")
                    .font(.system(size: 11)).foregroundStyle(CP.inkMuted)
            }
            .padding(CP.Space.l)
        }
    }

    private func reportTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
    }
}

// MARK: - Lembar deskripsi (pratinjau)

/// Tabel deskripsi seperti hasil cetak: kolom A (nomor), B (kode), lalu deskripsi teks; garis tebal tiap 3 kontrol.
struct DescriptionSheetView: View {
    let sheet: DescriptionSheet
    var onTapRow: (Int) -> Void = { _ in }

    var body: some View {
        let cell: CGFloat = 42
        VStack(spacing: 0) {
            if !sheet.title.isEmpty {
                Text(sheet.title).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: cell)
                    .overlay(alignment: .bottom) { line(1) }
            }
            HStack(spacing: 0) {
                Text(sheet.courseName).font(.system(size: 14, weight: .semibold)).padding(.leading, 6).frame(maxWidth: .infinity, alignment: .leading)
                Text(sheet.lengthText).font(CP.mono(13)).frame(width: cell * 1.8).overlay(alignment: .leading) { vline() }
                Text(sheet.climbText).font(CP.mono(13)).frame(width: cell * 1.6).overlay(alignment: .leading) { vline() }
            }
            .frame(height: cell)
            .overlay(alignment: .bottom) { line(1) }
            let thickRows = Self.thickRows(sheet)
            ForEach(Array(sheet.rows.enumerated()), id: \.offset) { i, row in
                let thick = thickRows.contains(i)
                Button { onTapRow(i) } label: {
                    HStack(spacing: 0) {
                        Group {
                            switch row.kind {
                            case .control: Text(row.number).font(.system(size: 17, weight: .medium))
                            default: ControlGlyph(kind: row.kind, color: CP.ink).frame(width: 24, height: 24)
                            }
                        }
                        .frame(width: cell, height: cell)
                        Text(row.code).font(.system(size: 17, weight: .medium)).frame(width: cell, height: cell)
                            .overlay(alignment: .leading) { vline() }
                        Text(row.text).font(.system(size: 13)).lineLimit(2).minimumScaleFactor(0.8)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .overlay(alignment: .leading) { vline() }
                    }
                    .frame(height: cell)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { if i < sheet.rows.count - 1 { line(thick ? 2.5 : 1) } }
                .accessibilityLabel("Baris \(row.number) \(row.code) \(row.text)")
            }
        }
        .foregroundStyle(CP.ink)
        .background(Color.white.opacity(0.0001))
        .overlay(Rectangle().strokeBorder(CP.ink, lineWidth: 2.5))
    }

    /// Baris setelah setiap kontrol ke-3, 6, 9, … diberi garis tebal.
    static func thickRows(_ sheet: DescriptionSheet) -> Set<Int> {
        var n = 0, out = Set<Int>()
        for (i, r) in sheet.rows.enumerated() where r.kind == .control {
            n += 1
            if n % 3 == 0, i < sheet.rows.count - 1 { out.insert(i) }
        }
        return out
    }

    private func line(_ w: CGFloat) -> some View { Rectangle().fill(CP.ink).frame(height: w) }
    private func vline() -> some View { Rectangle().fill(CP.ink).frame(width: 1) }
}

/// Ikon start (segitiga), kontrol (lingkaran), finish (lingkaran ganda) dalam ungu lintasan.
struct ControlGlyph: View {
    let kind: ControlKind
    var color = Color(hexString: "#A626FF")
    var body: some View {
        let purple = color
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2 - 1.5
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            switch kind {
            case .control:
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(purple), lineWidth: 1.6)
            case .finish:
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(purple), lineWidth: 1.4)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.6, width: 1.2 * r, height: 1.2 * r)), with: .color(purple), lineWidth: 1.4)
            case .start:
                var p = Path()
                for i in 0..<3 {
                    let a = -Double.pi / 2 + Double(i) * 2 * .pi / 3
                    let q = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a) + r * 0.15)
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                p.closeSubpath()
                ctx.stroke(p, with: .color(purple), lineWidth: 1.6)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Editor kontrol (kode + deskripsi IOF)

private struct ControlEditor: View {
    @ObservedObject var model: WorkspaceModel
    let controlID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var codeText = ""
    @State private var dimension = ""

    private var control: ControlPoint? { model.courseSet.control(controlID) }

    var body: some View {
        NavigationStack {
            Form {
                if let c = control {
                    Section {
                        HStack {
                            ControlGlyph(kind: c.kind).frame(width: 22, height: 22)
                            Text(c.kind.label).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text(verbatim: c.label(in: model.courseSet)).font(CP.mono(17, weight: .semibold))
                        }
                        if c.kind == .control {
                            HStack {
                                Text("Kode")
                                Spacer()
                                TextField("31–255", text: $codeText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                    .onSubmit { applyCode() }
                                Button("Pakai") { applyCode() }.buttonStyle(.bordered)
                            }
                        }
                        let using = model.courseSet.courses.filter { $0.controlIDs.contains(c.id) }.map(\.name)
                        Text(using.isEmpty ? "Belum dipakai lintasan mana pun." : "Dipakai: \(using.joined(separator: ", "))")
                            .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                    }
                    Section {
                        Stepper(value: Binding(get: { c.effectiveSize }, set: { model.setControlSize($0, for: controlID) }),
                                in: ControlPoint.sizeRange, step: 0.1) {
                            HStack {
                                Text("Ukuran objek")
                                Spacer()
                                Text(verbatim: "\(Int((c.effectiveSize * 100).rounded()))%").font(CP.mono(15))
                            }
                        }
                        .accessibilityLabel("Ukuran objek kontrol, \(Int((c.effectiveSize * 100).rounded())) persen")
                        if c.sizeFactor != nil {
                            Button { model.setControlSize(1, for: controlID) } label: { Label("Standar IOF (100%)", systemImage: "arrow.counterclockwise") }
                        }
                    } header: { Text("Ukuran") } footer: {
                        Text("100% = ukuran standar IOF untuk skala ini. Ukuran semua kontrol sekaligus: tab Kontrol → Ukuran simbol lintasan.")
                    }
                    Section {
                        Text(c.description.isEmpty ? "Belum ada deskripsi." : c.description.text)
                            .font(.system(size: 15, weight: .medium))
                    } header: { Text("Deskripsi (teks IOF)") }
                    Section {
                        picker(.d, value: c.description.feature) { v in model.updateControl(controlID) { $0.description.feature = v } }
                        picker(.c, value: c.description.which) { v in model.updateControl(controlID) { $0.description.which = v } }
                        picker(.e, value: c.description.appearance) { v in model.updateControl(controlID) { $0.description.appearance = v } }
                        HStack {
                            Text("F · Dimensi")
                            Spacer()
                            TextField("mis. 1.5 atau 8x4", text: $dimension)
                                .multilineTextAlignment(.trailing)
                                .onSubmit { model.updateControl(controlID) { $0.description.dimension = dimension.isEmpty ? nil : dimension } }
                        }
                        picker(.f, value: IOFSymbols.symbol(c.description.dimension)?.column == .f ? c.description.dimension : nil, title: "F · Kombinasi") { v in
                            dimension = ""
                            model.updateControl(controlID) { $0.description.dimension = v }
                        }
                        picker(.g, value: c.description.location) { v in model.updateControl(controlID) { $0.description.location = v } }
                        picker(.h, value: c.description.other) { v in model.updateControl(controlID) { $0.description.other = v } }
                    } header: { Text("Kolom C–H") }
                    Section {
                        Button(role: .destructive) {
                            model.deleteControl(controlID)
                            dismiss()
                        } label: { Label("Hapus dari peta dan semua lintasan", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Kontrol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") {
                        if let c = control, IOFSymbols.symbol(c.description.dimension)?.column != .f, dimension != (c.description.dimension ?? "") {
                            model.updateControl(controlID) { $0.description.dimension = dimension.isEmpty ? nil : dimension }
                        }
                        applyCode()
                        dismiss()
                    }
                }
            }
            .onAppear {
                codeText = control?.code.map(String.init) ?? ""
                let d = control?.description.dimension
                dimension = IOFSymbols.symbol(d)?.column == .f ? "" : (d ?? "")
            }
        }
    }

    private func applyCode() {
        guard let c = control, c.kind == .control, let code = Int(codeText), code != c.code else { return }
        model.setCode(code, for: controlID)
        codeText = model.courseSet.control(controlID)?.code.map(String.init) ?? codeText
    }

    /// Pilih simbol satu kolom; kolom D dikelompokkan seperti spesifikasi IOF.
    private func picker(_ column: IOFSymbol.Column, value: String?, title: String? = nil, set: @escaping (String?) -> Void) -> some View {
        let symbols = IOFSymbols.symbols(in: column)
        let groups = Array(NSOrderedSet(array: symbols.map { $0.group ?? "" })) as? [String] ?? [""]
        return Picker("\(column.rawValue) · \(title.map { String($0.dropFirst(4)) } ?? column.title)",
                      selection: Binding(get: { value ?? "" }, set: { set($0.isEmpty ? nil : $0) })) {
            Text("—").tag("")
            ForEach(groups, id: \.self) { g in
                Section(g) {
                    ForEach(symbols.filter { ($0.group ?? "") == g }) { s in
                        Text("\(s.id)  \(s.name)").tag(s.id)
                    }
                }
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Ukuran kontrol terpilih (status bar)

/// − 100% + untuk kontrol terpilih; ketuk persen = kembali ke standar IOF.
private struct ControlSizeStepper: View {
    @ObservedObject var model: WorkspaceModel
    let control: ControlPoint

    var body: some View {
        HStack(spacing: CP.Space.xs) {
            ControlGlyph(kind: control.kind).frame(width: 16, height: 16)
            Text(verbatim: control.label(in: model.courseSet)).font(CP.mono(12, weight: .semibold))
            Button { model.stepControlSize(-0.1, for: control.id) } label: { Image(systemName: "minus") }
                .buttonStyle(.bordered)
                .disabled(control.effectiveSize <= ControlPoint.sizeRange.lowerBound + 0.001)
                .accessibilityLabel("Perkecil kontrol")
            Button { model.setControlSize(1, for: control.id) } label: {
                Text(verbatim: "\(Int((control.effectiveSize * 100).rounded()))%").font(CP.mono(12)).frame(minWidth: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ukuran kontrol \(Int((control.effectiveSize * 100).rounded())) persen, ketuk untuk standar IOF")
            Button { model.stepControlSize(0.1, for: control.id) } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered)
                .disabled(control.effectiveSize >= ControlPoint.sizeRange.upperBound - 0.001)
                .accessibilityLabel("Perbesar kontrol")
        }
        .tint(CP.ink)
    }
}

// MARK: - Pratinjau PDF (sama dengan hasil export)

struct CoursePreviewSheet: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var courseID: UUID?
    @State private var page = 0
    @State private var data: Data?
    @State private var share: ExportSheet.ShareItems?

    private var hasSeparatePage: Bool {
        let l = model.courseSet.effectivePrintLayout
        return l.separateDescriptionPage || !l.descriptionOnMap
    }

    private var course: Course? {
        (courseID ?? model.selectedCourseID).flatMap { model.courseSet.course($0) } ?? model.courseSet.courses.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: CP.Space.m) {
                HStack(spacing: CP.Space.m) {
                    Picker("Lintasan", selection: Binding(get: { course?.id }, set: { courseID = $0 })) {
                        ForEach(model.courseSet.courses) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .pickerStyle(.menu)
                    if hasSeparatePage {
                        Picker("Halaman", selection: $page) {
                            Text("Peta lomba").tag(0)
                            Text("Deskripsi terpisah").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                    }
                }
                .padding(.horizontal, CP.Space.l)
                if let data {
                    PDFPreview(data: data, page: page)
                        .accessibilityLabel(page == 1 ? "Pratinjau halaman deskripsi kontrol" : "Pratinjau peta lomba")
                } else {
                    ProgressView("Menyiapkan PDF…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text("Persis isi PDF yang akan di-export: peta \(model.project.sheet.paper.name) 1:\(model.project.sheet.scaleDenominator) dengan overprint, deskripsi kontrol, panah utara, dan kotak judul\(hasSeparatePage ? ", plus halaman deskripsi terpisah" : ""). Cubit untuk zoom.")
                    .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                    .padding(.horizontal, CP.Space.l)
                    .padding(.bottom, CP.Space.s)
            }
            .padding(.top, CP.Space.s)
            .background(CP.paper2)
            .navigationTitle("Pratinjau \(course?.name ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export PDF") { exportPDF() }.disabled(data == nil)
                }
            }
            .task(id: course?.id) { await render() }
            .sheet(item: $share) { ActivityView(items: $0.urls) }
        }
    }

    private func render() async {
        data = nil
        guard let course, let req = model.coursePDFRequest(for: course) else { return }
        data = await Task.detached(priority: .userInitiated) { GeoPDFExporter.document(req) }.value
    }

    private func exportPDF() {
        guard let data, let course else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("\(safeFileName(model.project.name))_\(safeFileName(course.name)).pdf")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            share = ExportSheet.ShareItems(urls: [url])
        } catch {
            model.notice = "PDF gagal ditulis: \(error.localizedDescription)"
        }
    }
}

/// PDFKit: tampilkan satu halaman (zoom dengan cubit).
private struct PDFPreview: UIViewRepresentable {
    let data: Data
    let page: Int

    final class Coordinator {
        var data: Data?
        var page = -1
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePage  // satu halaman utuh terlihat, seperti lembar cetak
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(white: 0.9, alpha: 1)
        v.pageShadowsEnabled = true
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if context.coordinator.data != data {
            context.coordinator.data = data
            v.document = PDFDocument(data: data)
        }
        guard let doc = v.document, let p = doc.page(at: min(page, doc.pageCount - 1)), context.coordinator.page != page || v.currentPage != p else { return }
        context.coordinator.page = page
        DispatchQueue.main.async {
            if page == 1 {
                // Halaman deskripsi: perbesar ke tabel (pojok kiri atas A4) agar terbaca; cubit untuk zoom lagi.
                v.autoScales = false
                let box = p.bounds(for: .mediaBox)
                v.scaleFactor = max(v.bounds.width, 300) / 260
                v.go(to: CGRect(x: 0, y: box.height - 300, width: 260, height: 300), on: p)
            } else {
                v.autoScales = true
                v.go(to: p)
            }
        }
    }
}

// MARK: - Tata letak cetak

/// Pengaturan peta lomba satu halaman: posisi + ukuran deskripsi, judul, panah utara, skala batang.
private struct PrintLayoutSection: View {
    @ObservedObject var model: WorkspaceModel
    @State private var subtitle = ""

    var body: some View {
        let l = model.courseSet.effectivePrintLayout
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Text("Tata letak cetak").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
            Toggle("Deskripsi di peta", isOn: Binding(get: { l.descriptionOnMap }, set: { v in model.updatePrintLayout { $0.descriptionOnMap = v } }))
            if l.descriptionOnMap {
                Picker("Posisi deskripsi", selection: Binding(get: { l.descriptionCorner }, set: { v in model.updatePrintLayout { $0.descriptionCorner = v } })) {
                    ForEach(CoursePrintLayout.Corner.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Stepper(value: Binding(get: { l.descriptionCellMM }, set: { v in model.updatePrintLayout { $0.descriptionCellMM = v } }),
                        in: CoursePrintLayout.cellRangeMM, step: 0.5) {
                    HStack {
                        Text("Ukuran kotak deskripsi")
                        Spacer()
                        Text(verbatim: Fmt.mm(l.descriptionCellMM, decimals: 1)).font(CP.mono(13))
                    }
                }
            }
            Toggle("Halaman deskripsi terpisah", isOn: Binding(get: { l.separateDescriptionPage || !l.descriptionOnMap },
                                                             set: { v in model.updatePrintLayout { $0.separateDescriptionPage = v } }))
                .disabled(!l.descriptionOnMap)
            Toggle("Kotak judul (acara, lintasan, skala)", isOn: Binding(get: { l.showTitleBlock }, set: { v in model.updatePrintLayout { $0.showTitleBlock = v } }))
            if l.showTitleBlock {
                TextField("Jenis lomba (mis. Middle Distance)", text: $subtitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.updatePrintLayout { $0.subtitle = subtitle.trimmingCharacters(in: .whitespaces) } }
                    .onDisappear { if subtitle != l.subtitle { model.updatePrintLayout { $0.subtitle = subtitle.trimmingCharacters(in: .whitespaces) } } }
                Toggle("Skala batang", isOn: Binding(get: { l.showScaleBar }, set: { v in model.updatePrintLayout { $0.showScaleBar = v } }))
            }
            Toggle("Panah utara", isOn: Binding(get: { l.showNorthArrow }, set: { v in model.updatePrintLayout { $0.showNorthArrow = v } }))
            Text("IOF: kotak deskripsi 5–7 mm. Deskripsi berlatar putih di sudut peta; kotak judul menghindari sudut deskripsi.")
                .font(.system(size: 11)).foregroundStyle(CP.inkMuted)
        }
        .font(.system(size: 14))
        .tint(CP.sage.strong)
        .onAppear { subtitle = l.subtitle }
    }
}
