import CakraCore
import SwiftUI

/// Panel Lintasan (course planner, seperti Purple Pen): daftar lintasan, tempatkan start/kontrol/finish,
/// urutan kontrol + panjang leg, deskripsi kontrol IOF, beban peserta per kontrol/leg, pemeriksaan, dan export.
struct CoursePanel: View {
    @ObservedObject var model: WorkspaceModel
    @State private var eventTitle = ""
    @State private var renaming: Course?
    @State private var newName = ""
    @State private var editingControl: ControlPoint?

    private var set: CourseSet { model.courseSet }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.l) {
                eventSection
                courseSelector
                placementSection
                if let course = model.selectedCourse {
                    courseStats(course)
                    controlList(course)
                } else {
                    allControlsList
                }
                Divider().overlay(CP.line)
                loadSection
                warningsSection
                Button { model.exportCourses = true } label: {
                    Label("Export lintasan…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(set.courses.isEmpty)
                Text("Simbol lintasan mengikuti \(model.project.sheet.scaleDenominator <= 5000 ? "ISSprOM 2019-2" : "ISOM 2017-2"). Deskripsi kontrol: IOF 2018 (teks). Export IOF XML 3.0 untuk MeOS, OE, SportSoftware, SI Config.")
                    .font(.system(size: 11)).foregroundStyle(CP.inkMuted)
            }
            .padding(CP.Space.l)
        }
        .onAppear { eventTitle = set.eventTitle }
        .sheet(item: $editingControl) { c in
            ControlEditor(model: model, controlID: c.id)
        }
        .alert("Ganti nama lintasan", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nama", text: $newName)
            Button("Simpan") {
                if let c = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.updateCourse(c.id) { $0.name = newName.trimmingCharacters(in: .whitespaces) }
                }
                renaming = nil
            }
            Button("Batal", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Acara + pilih lintasan

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.xs) {
            Text("Nama acara").font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            TextField("mis. Kejurda Sprint 2026", text: $eventTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.setEventTitle(eventTitle) }
                .onDisappear { if eventTitle != set.eventTitle { model.setEventTitle(eventTitle) } }
        }
    }

    private var courseSelector: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack {
                Text("Lintasan").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                Toggle("Tampilkan", isOn: $model.showsCourses).labelsHidden().tint(CP.sage.strong)
                    .accessibilityLabel("Tampilkan lintasan di peta")
            }
            HStack(spacing: CP.Space.s) {
                Picker("Lintasan", selection: $model.selectedCourseID) {
                    Text("Semua kontrol").tag(UUID?.none)
                    ForEach(set.courses) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Pilih lintasan")
                Spacer(minLength: 0)
                Button { model.addCourse() } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Lintasan baru")
                if let c = model.selectedCourse {
                    Menu {
                        Button { newName = c.name; renaming = c } label: { Label("Ganti nama", systemImage: "pencil") }
                        Button { model.duplicateCourse(c.id) } label: { Label("Duplikat", systemImage: "plus.square.on.square") }
                        Picker("Jenis", selection: Binding(get: { c.kind }, set: { k in model.updateCourse(c.id) { $0.kind = k } })) {
                            ForEach(CourseKind.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        Button { model.zoomToCourse() } label: { Label("Zoom ke lintasan", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                        Divider()
                        Button(role: .destructive) { model.deleteCourse(c.id) } label: { Label("Hapus lintasan", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Menu lintasan \(c.name)")
                }
            }
        }
    }

    // MARK: Tempatkan

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Picker("Tempatkan", selection: $model.controlPlacement) {
                ForEach(ControlKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if model.tool == .control {
                Text(model.selectedCourse == nil
                     ? "Ketuk peta: \(model.controlPlacement.label.lowercased()) baru. Tarik kontrol untuk memindahkan."
                     : "Ketuk peta: \(model.controlPlacement.label.lowercased()) baru di lintasan ini. Ketuk kontrol lain = pakai ulang. Tarik = pindah.")
                    .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            } else {
                Button { model.tool = .control } label: {
                    Label("Pakai alat Kontrol (K)", systemImage: "flag").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(CP.ink)
            }
        }
    }

    // MARK: Ringkasan lintasan

    private func courseStats(_ course: Course) -> some View {
        let controls = set.controls(of: course).filter { $0.kind == .control }.count
        return VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack {
                stat(course.kind == .score ? "Score" : Fmt.km(set.length(of: course)), "panjang")
                Spacer()
                stat("\(controls)", "kontrol")
                Spacer()
                stat(course.climbM.map { "\($0) m" } ?? "–", "tanjakan")
            }
            Stepper(value: Binding(get: { course.competitors }, set: { v in model.updateCourse(course.id) { $0.competitors = max(0, v) } }),
                    in: 0...5000, step: 5) {
                HStack {
                    Text("Peserta").font(.system(size: 14)).foregroundStyle(CP.ink)
                    Spacer()
                    Text(verbatim: "\(course.competitors)").font(CP.mono(13)).foregroundStyle(CP.ink)
                }
            }
            .accessibilityLabel("Jumlah peserta")
            Stepper(value: Binding(get: { course.climbM ?? 0 }, set: { v in model.updateCourse(course.id) { $0.climbM = v > 0 ? v : nil } }),
                    in: 0...3000, step: 5) {
                HStack {
                    Text("Tanjakan").font(.system(size: 14)).foregroundStyle(CP.ink)
                    Spacer()
                    Text(verbatim: "\(course.climbM ?? 0) m").font(CP.mono(13)).foregroundStyle(CP.ink)
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(CP.mono(16, weight: .semibold)).foregroundStyle(CP.ink)
            Text(label).font(.system(size: 11)).foregroundStyle(CP.inkMuted)
        }
    }

    // MARK: Daftar kontrol

    private func controlList(_ course: Course) -> some View {
        let list = set.controls(of: course)
        let legs = set.legLengths(of: course)
        var number = 0
        let numbers: [String] = list.map { c in
            guard c.kind == .control else { return "" }
            number += 1
            return course.kind == .score ? "" : "\(number)"
        }
        return VStack(alignment: .leading, spacing: 2) {
            if list.isEmpty {
                Text("Belum ada kontrol. Pilih Start lalu ketuk peta, lanjut Kontrol, dan akhiri dengan Finish.")
                    .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            }
            ForEach(Array(list.enumerated()), id: \.offset) { i, c in
                controlRow(c, number: numbers[i], leg: i > 0 && course.kind == .normal ? legs[i - 1] : nil)
                    .contextMenu {
                        Button { model.selectedControlID = c.id; editingControl = c } label: { Label("Deskripsi & kode", systemImage: "list.bullet.rectangle") }
                        if i > 0 { Button { model.moveSelectedCourseControls(from: [i], to: i - 1) } label: { Label("Naik", systemImage: "arrow.up") } }
                        if i < list.count - 1 { Button { model.moveSelectedCourseControls(from: [i], to: i + 2) } label: { Label("Turun", systemImage: "arrow.down") } }
                        Button { model.removeFromSelectedCourse(at: i) } label: { Label("Keluarkan dari lintasan", systemImage: "minus.circle") }
                        Button(role: .destructive) { model.deleteControl(c.id) } label: { Label("Hapus dari peta", systemImage: "trash") }
                    }
            }
        }
    }

    private var allControlsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if set.controls.isEmpty {
                Text("Belum ada kontrol. Buat lintasan dengan +, atau ketuk peta dengan alat Kontrol untuk menyiapkan kontrol dulu.")
                    .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            }
            ForEach(set.controls) { c in
                controlRow(c, number: "", leg: nil)
                    .contextMenu {
                        Button { model.selectedControlID = c.id; editingControl = c } label: { Label("Deskripsi & kode", systemImage: "list.bullet.rectangle") }
                        Button(role: .destructive) { model.deleteControl(c.id) } label: { Label("Hapus dari peta", systemImage: "trash") }
                    }
            }
        }
    }

    private func controlRow(_ c: ControlPoint, number: String, leg: Double?) -> some View {
        let selected = model.selectedControlID == c.id
        return Button {
            model.selectedControlID = c.id
            editingControl = c
        } label: {
            HStack(spacing: CP.Space.s) {
                ControlGlyph(kind: c.kind).frame(width: 18, height: 18)
                Text(verbatim: number).font(CP.mono(12)).foregroundStyle(CP.inkMuted).frame(width: 18, alignment: .trailing)
                Text(verbatim: c.label(in: set)).font(CP.mono(13, weight: .semibold)).foregroundStyle(CP.ink).frame(width: 34, alignment: .leading)
                Text(c.description.isEmpty ? (c.kind == .control ? "ketuk untuk deskripsi" : "") : c.description.text)
                    .font(.system(size: 12)).foregroundStyle(c.description.isEmpty ? CP.inkMuted : CP.ink).lineLimit(1)
                Spacer(minLength: 2)
                if let leg { Text(verbatim: "\(Int(leg.rounded())) m").font(CP.mono(11)).foregroundStyle(CP.inkMuted) }
            }
            .padding(.vertical, 5).padding(.horizontal, CP.Space.xs)
            .background(selected ? CP.sky.fill : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(c.kind.label) \(c.label(in: set))\(number.isEmpty ? "" : ", nomor \(number)")")
    }

    // MARK: Beban peserta

    private var loadSection: some View {
        let loads = set.controlLoads().filter { $0.courseCount > 0 }.sorted { $0.visits > $1.visits }
        let legs = set.sharedLegLoads()
        return VStack(alignment: .leading, spacing: CP.Space.s) {
            Text("Beban peserta").font(.system(size: 15, weight: .semibold)).foregroundStyle(CP.ink)
            if loads.isEmpty {
                Text("Isi jumlah peserta per lintasan untuk menghitung beban tiap kontrol.")
                    .font(.system(size: 12)).foregroundStyle(CP.inkMuted)
            } else {
                ForEach(loads.prefix(12), id: \.controlID) { l in
                    HStack {
                        Text(verbatim: set.control(l.controlID)?.label(in: set) ?? "?").font(CP.mono(12, weight: .medium)).frame(width: 34, alignment: .leading)
                        Text("\(l.courseCount) lintasan").font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                        Spacer()
                        Text(verbatim: "\(l.visits) peserta").font(CP.mono(12)).foregroundStyle(CP.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !legs.isEmpty {
                    Text("Leg bersama").font(.system(size: 12, weight: .semibold)).foregroundStyle(CP.inkMuted).padding(.top, CP.Space.xs)
                    ForEach(legs.prefix(6), id: \.self) { l in
                        HStack {
                            Text(verbatim: "\(set.control(l.from)?.label(in: set) ?? "?")–\(set.control(l.to)?.label(in: set) ?? "?")")
                                .font(CP.mono(12, weight: .medium))
                            Text("\(l.courseCount) lintasan").font(.system(size: 12)).foregroundStyle(CP.inkMuted)
                            Spacer()
                            Text(verbatim: "\(l.visits) peserta").font(CP.mono(12)).foregroundStyle(CP.ink)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        let w = set.warnings()
        if !w.isEmpty, !set.courses.isEmpty {
            VStack(alignment: .leading, spacing: CP.Space.xs) {
                Label("Periksa lintasan", systemImage: "exclamationmark.triangle").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CP.butter.strong)
                ForEach(w.prefix(8), id: \.self) { Text("• \($0)").font(.system(size: 12)).foregroundStyle(CP.ink) }
            }
            .padding(CP.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CP.butter.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
        }
    }
}

/// Ikon start (segitiga), kontrol (lingkaran), finish (lingkaran ganda) dalam ungu lintasan.
struct ControlGlyph: View {
    let kind: ControlKind
    var body: some View {
        let purple = Color(hexString: "#A626FF")
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
