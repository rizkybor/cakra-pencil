import CakraCore
import SwiftUI
import UniformTypeIdentifiers

/// Field panel: the project's fieldwork data — GPS tracks and field notes (with averaged positions) — with show/hide,
/// zoom, rename, mark done, delete, and GPX import/export. Same on iPad and Mac; recording happens on iPad.
struct FieldPanel: View {
    @ObservedObject var model: WorkspaceModel
    @EnvironmentObject private var library: SymbolLibrary
    @State private var importing = false
    /// What the file picker accepts: field data (.occafield) or GPX.
    @State private var importTypes: [UTType] = []
    @State private var exportChoice = false
    @State private var filter: NoteFilter = .all
    @State private var renaming: FieldTrack?
    @State private var newName = ""
    @State private var symbolFor: FieldNote?
    /// Select mode: several tracks and notes, then Show / Hide (Mac: also ⌘-click and ⇧-click a row).
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    /// Last row clicked in select mode (⇧-click selects the rows between).
    @State private var anchor: UUID?

    enum NoteFilter: String, CaseIterable {
        case all = "All", todo = "To do", done = "Done"     // To do = not processed yet
    }

    private static let gpxType = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml

    private var field: FieldData { model.field }

    private var notes: [FieldNote] {
        field.notes.filter { filter == .all || (filter == .done) == $0.isDone }.sorted { $0.createdAt > $1.createdAt }
    }

    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        if license.isPro { panel } else { locked }
    }

    /// Starter: fieldwork needs a license key. Field data already in the project stays on the map.
    private var locked: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack(spacing: CP.Space.s) {
                Image(systemName: ProFeature.fieldwork.icon)
                    .font(.system(size: CP.fs(16), weight: .semibold))
                    .foregroundStyle(CP.peach.strong)
                Text("Field").font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                Spacer()
                ProLockBadge()
            }
            Text("Field mode, field notes with photos and GPS, track recording, and GPX need a license key: Trial, Professional, Lifetime, or Organization.")
                .font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button { LicenseManager.shared.require(.fieldwork) } label: {
                Label("Unlock fieldwork", systemImage: "key.horizontal").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .accessibilityIdentifier("fieldUnlock")
            Spacer(minLength: 0)
        }
        .padding(CP.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            if let id = model.trackLineID {
                TrackLineEditor(model: model, trackID: id)
            } else if let id = model.openFieldNoteID {
                // One note in detail (tap a note in the list or its pin on the map).
                FieldNoteDetail(model: model, noteID: id) { model.openFieldNote(nil) }
            } else {
                list
            }
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.bottom, CP.Space.m)
        .sheet(item: $symbolFor) { n in
            FieldSymbolPicker.forNote(model: model, note: n) { s in
                symbolFor = nil
                model.makeObject(fromNote: n.id, symbol: s)
            }
            .environmentObject(library)
        }
    }

    @ViewBuilder private var list: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            header
            if FieldCaptureSection.isAvailable {
                FieldCaptureSection(model: model, recorder: model.recorder)
            } else {
                // Mac: no GPS capture, but sketch notes can be drawn on the map with the mouse or trackpad.
                Button { model.startFieldSketch() } label: {
                    Label("Draw sketch note", systemImage: "scribble.variable").lineLimit(1).frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(model.zone == nil || model.fieldSketch != nil)
                .help("Draw or mark on the map, then save the drawing with a note")
                .accessibilityIdentifier("fieldDraw")
            }
            if field.isEmpty {
                emptyState
                Spacer(minLength: 0)
            } else {
                List {
                    tracksSection
                    notesSection
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                if selecting { selectionBar }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes, allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task {
                if url.pathExtension.lowercased() == FieldPackage.fileExtension {
                    await model.importFieldData(from: url)
                } else {
                    await model.importGPX(from: url)
                }
            }
        }
        .confirmationDialog("Export field data", isPresented: $exportChoice, titleVisibility: .visible) {
            Button("All field data") { Task { await model.exportFieldData(newOnly: false) } }
            if let last = field.lastExportAt {
                Button("New since \(FieldNoteDetail.dateText(last))") { Task { await model.exportFieldData(newOnly: true) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tracks, notes and photos — without the drawing. Import the file into the same project on the other iPad or Mac.")
        }
        #if DEBUG
        // `-cp-field-select`: Select mode with every note selected and the first note hidden (screenshots).
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-cp-field-select"), !selecting else { return }
            try? await Task.sleep(for: .seconds(2))
            if let first = field.notes.first { model.setNoteVisible(first.id, false) }
            selecting = true
            selection = Set(field.notes.map(\.id))
        }
        #endif
        .renameDialog("Rename track", subtitle: renaming.map { "Current name: \($0.name)" }, placeholder: "Track name",
                      confirm: "Rename", isPresented: renaming != nil, text: $newName,
                      onSave: {
                          if let t = renaming { model.renameTrack(t.id, to: newName.trimmingCharacters(in: .whitespacesAndNewlines)) }
                          renaming = nil
                      },
                      onCancel: { renaming = nil })
    }

    private func importFieldData() {
        guard LicenseManager.shared.require(.fieldTransfer) else { return }
        importTypes = [.occaFieldData]
        importing = true
    }

    private func importGPX() {
        guard LicenseManager.shared.require(.gpx) else { return }
        importTypes = [Self.gpxType]
        importing = true
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: CP.Space.s) {
            Text(verbatim: "\(field.tracks.count) \(field.tracks.count == 1 ? "track" : "tracks") · \(field.notes.count) \(field.notes.count == 1 ? "note" : "notes")")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .accessibilityIdentifier("fieldSummary")
            Spacer()
            if !field.isEmpty {
                Button(selecting ? "Done" : "Select") {
                    selecting.toggle()
                    selection = []
                    anchor = nil
                }
                .buttonStyle(.borderless)
                .font(.system(size: CP.fs(13), weight: selecting ? .semibold : .regular))
                .foregroundStyle(CP.sky.strong)
                .help(selecting ? "Done selecting" : "Select tracks and notes to show or hide them")
                .accessibilityIdentifier("fieldSelect")
            }
            SolidMenu(items: [
                .action("Import field data…", icon: "square.and.arrow.down.on.square", section: "Field data (.occafield) — iPad ⇄ Mac") { importFieldData() },
                .action("Export field data…", icon: "square.and.arrow.up.on.square", disabled: field.isEmpty,
                        section: "Field data (.occafield) — iPad ⇄ Mac") { if LicenseManager.shared.require(.fieldTransfer) { exportChoice = true } },
                .action("Import GPX…", icon: "square.and.arrow.down", section: "GPX — GPS watches and other apps") { importGPX() },
                .action("Export GPX…", icon: "square.and.arrow.up", disabled: field.isEmpty, section: "GPX — GPS watches and other apps") { model.exportGPX() },
                .divider,
                .action("Zoom to field data", icon: "scope", disabled: field.isEmpty) { model.zoomToFieldData() },
                .action("Field report (PDF)…", icon: "doc.richtext", disabled: field.isEmpty) { Task { await model.exportFieldReport() } },
            ], width: 300) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down.circle")
                    Text("Data")
                    Image(systemName: "chevron.down").font(.system(size: CP.fs(9), weight: .bold)).foregroundStyle(CP.inkMuted)
                }
                .font(.system(size: CP.fs(13), weight: .medium))
                .foregroundStyle(CP.ink)
                .padding(.horizontal, 10)
                .frame(height: CP.isMac ? 28 : 32)
                .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous).strokeBorder(CP.line))
                .contentShape(Rectangle())
            }
            .fixedSize()
            .accessibilityLabel("Data")
            .accessibilityIdentifier("fieldMenu")
        }
        .padding(.top, CP.Space.xs)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            HStack(spacing: 2) {
                Label("No field data yet", systemImage: "figure.walk")
                    .font(.system(size: CP.fs(15), weight: .semibold))
                    .foregroundStyle(CP.ink)
                InfoHint(FieldCaptureSection.isAvailable
                         ? "Record the tracks you walk, add field notes with photos, and average positions above — they appear here and on the map. Move them to the Mac (or another iPad) with Data › Export field data. You can also import field data or a GPX file from a GPS watch or another app."
                         : "Tracks, field notes with photos, and averaged positions are recorded on iPad. After each survey day, export the field data on the iPad and import it here — it is added to this project, your drawing stays as it is. You can also import a GPX file from a GPS watch or another app.")
            }
            // Side by side, same size.
            HStack(spacing: CP.Space.s) {
                Button { importFieldData() } label: {
                    Label("Field data…", systemImage: "square.and.arrow.down.on.square").lineLimit(1).frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Import field data")
                .help("Import field data (.occafield) exported on iPad")
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .accessibilityIdentifier("fieldImportData")
                Button { importGPX() } label: {
                    Label("GPX file…", systemImage: "square.and.arrow.down").lineLimit(1).frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Import GPX")
                .help("Import a GPX file from a GPS watch or another app")
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .accessibilityIdentifier("fieldImportGPX")
            }
        }
        .padding(.top, CP.Space.s)
    }

    private var tracksSection: some View {
        Section {
            ForEach(field.tracks) { t in trackRow(t) }
            CoverageRow(model: model).listRowBackground(Color.clear)
        } header: {
            HStack {
                sectionEye(field.tracks.map(\.isVisible), label: "tracks") { model.setTracksVisible($0) }
                Text("Tracks")
            }
        }
    }

    private func trackRow(_ t: FieldTrack) -> some View {
        HStack(spacing: CP.Space.s) {
            if selecting { checkmark(t.id) }
            eye(t.isVisible, label: t.name) { model.setTrackVisible(t.id, !t.isVisible) }
            HStack(spacing: CP.Space.s) {
                Capsule().fill(Color(hexString: t.colorHex)).frame(width: 18, height: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.name).font(.system(size: CP.fs(15))).foregroundStyle(t.isVisible ? CP.ink : CP.inkMuted).lineLimit(1)
                    Text(Self.trackSummary(t)).font(CP.mono(11)).foregroundStyle(CP.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .opacity(t.isVisible ? 1 : 0.6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(t.name), \(Self.trackSummary(t))\(t.isVisible ? "" : ", hidden")")
            .accessibilityAddTraits(selection.contains(t.id) ? .isSelected : [])
            .accessibilityIdentifier("fieldTrack")
        }
        .contentShape(Rectangle())
        .onTapGesture { rowTapped(t.id) { model.zoomToTrack(t) } }
        .listRowBackground(selection.contains(t.id) ? CP.sky.fill.opacity(0.6) : Color.clear)
        .contextMenu {
            Button { model.zoomToTrack(t) } label: { Label("Zoom to track", systemImage: "scope") }
            Button { model.openFieldNote(nil, zoom: false); model.trackLineID = t.id; model.zoomToTrack(t) } label: {
                Label("Make line object…", systemImage: "wand.and.stars")
            }
            .disabled(!model.project.areaLocked)
            Button { newName = t.name; renaming = t } label: { Label("Rename…", systemImage: "pencil") }
            Button(role: .destructive) { model.deleteTrack(t.id) } label: { Label("Delete track", systemImage: "trash") }
        }
        .swipeActions {
            Button(role: .destructive) { model.deleteTrack(t.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var notesSection: some View {
        Section {
            if field.notes.count > 1 || filter != .all {
                Segmented("Show", selection: $filter, NoteFilter.allCases.map { .init($0, $0.rawValue) })
                .listRowBackground(Color.clear)
            }
            ForEach(notes) { n in noteRow(n) }
            if notes.isEmpty, filter != .all {
                Text(filter == .todo ? "Every note is processed." : "No notes are marked done yet.")
                    .font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                    .listRowBackground(Color.clear)
            }
        } header: {
            HStack {
                sectionEye(notes.map(\.isShown), label: "notes") { on in model.setNotesVisible(on, ids: notes.map(\.id)) }
                Text("Notes")
                Spacer()
                let todo = field.notes.filter { !$0.isDone }.count
                if todo > 0 { Text(verbatim: "\(todo) to do").foregroundStyle(CP.peach.strong) }
            }
        }
    }

    private func noteRow(_ n: FieldNote) -> some View {
        HStack(spacing: CP.Space.s) {
            if selecting { checkmark(n.id) }
            eye(n.isShown, label: n.title) { model.setNoteVisible(n.id, !n.isShown) }
            HStack(spacing: CP.Space.s) {
                ZStack {
                    Circle().fill(Color(hexString: n.category.colorHex).opacity(n.isDone ? 0.45 : 1))
                    Image(systemName: n.isDone ? "checkmark" : n.category.icon)
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(n.title).font(.system(size: CP.fs(15))).foregroundStyle(n.isDone || !n.isShown ? CP.inkMuted : CP.ink).lineLimit(1)
                    Text(Self.noteSummary(n)).font(CP.mono(11)).foregroundStyle(CP.inkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
                if n.hasSketch {
                    Image(systemName: "scribble.variable").font(.system(size: CP.fs(12), weight: .semibold))
                        .foregroundStyle(Color(hexString: n.category.colorHex).opacity(0.8))
                        .help("Sketch on the map")
                        .accessibilityLabel("with sketch")
                }
                if !n.photos.isEmpty {
                    Label("\(n.photos.count)", systemImage: "photo").font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                }
            }
            .opacity(n.isShown ? 1 : 0.6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(n.title), \(Self.noteSummary(n))\(n.hasSketch ? ", with sketch" : "")\(n.isDone ? ", done" : "")\(n.isShown ? "" : ", hidden")")
            .accessibilityAddTraits(selection.contains(n.id) ? .isSelected : [])
            .accessibilityIdentifier("fieldNote")
        }
        .contentShape(Rectangle())
        .onTapGesture { rowTapped(n.id) { model.openFieldNote(n.id) } }
        .listRowBackground(selection.contains(n.id) ? CP.sky.fill.opacity(0.6) : Color.clear)
        .contextMenu {
            Button { model.openFieldNote(n.id) } label: { Label("Open note", systemImage: "doc.text.magnifyingglass") }
            Button { model.zoomToNote(n) } label: { Label("Zoom to note", systemImage: "scope") }
            if let _ = model.noteFeature(n) {
                Button { model.showNoteObject(n) } label: { Label("Show map object", systemImage: "cursorarrow.rays") }
            } else {
                Button { symbolFor = n } label: { Label("Make map object…", systemImage: "wand.and.stars") }
                    .disabled(!model.project.areaLocked)
            }
            Button { model.setNoteDone(n.id, !n.isDone) } label: {
                Label(n.isDone ? "Mark as to do" : "Mark as done", systemImage: n.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            Button(role: .destructive) { model.deleteNote(n.id) } label: { Label("Delete note", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button { model.setNoteDone(n.id, !n.isDone) } label: { Label(n.isDone ? "To do" : "Done", systemImage: "checkmark") }
                .tint(CP.sage.strong)
        }
        .swipeActions {
            Button(role: .destructive) { model.deleteNote(n.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: Select

    /// Rows in list order (tracks, then the notes shown), for ⇧-click ranges.
    private var rowOrder: [UUID] { field.tracks.map(\.id) + notes.map(\.id) }

    /// Tap / click on a row: in select mode it toggles the row; on Mac ⌘-click and ⇧-click select without the
    /// Select button (like Finder); otherwise the row's own action.
    private func rowTapped(_ id: UUID, open: () -> Void) {
        let keys = ModifierKeys.pressed
        if CP.isMac, keys.contains(.shift) || keys.contains(.command) {
            if !selecting { selecting = true; selection = [] }
            if keys.contains(.shift), let a = anchor, let i = rowOrder.firstIndex(of: a), let j = rowOrder.firstIndex(of: id) {
                selection.formUnion(rowOrder[min(i, j)...max(i, j)])
            } else {
                toggle(id)
            }
            anchor = id
            return
        }
        if selecting {
            toggle(id)
            anchor = id
        } else {
            open()
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func checkmark(_ id: UUID) -> some View {
        let on = selection.contains(id)
        return Button { toggle(id); anchor = id } label: {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.system(size: CP.fs(17)))
                .foregroundStyle(on ? CP.sky.strong : CP.inkMuted)
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Deselect" : "Select")
        .accessibilityIdentifier("fieldSelectRow")
    }

    /// Select mode: how many rows, All / None, Show and Hide for the selection.
    private var selectionBar: some View {
        let all = Set(rowOrder)
        return HStack(spacing: CP.Space.s) {
            Button(selection.isSuperset(of: all) && !all.isEmpty ? "None" : "All") {
                selection = selection.isSuperset(of: all) ? [] : all
            }
            .buttonStyle(.borderless)
            .foregroundStyle(CP.sky.strong)
            .accessibilityIdentifier("fieldSelectAll")
            Text(verbatim: "\(selection.count) selected")
                .font(.system(size: CP.fs(12)))
                .foregroundStyle(CP.inkMuted)
                .lineLimit(1)
                .accessibilityIdentifier("fieldSelectionCount")
            Spacer(minLength: 0)
            Button { model.setFieldItemsVisible(selection, true) } label: { Label("Show", systemImage: "eye").lineLimit(1).fixedSize() }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("fieldShowSelected")
            Button { model.setFieldItemsVisible(selection, false) } label: { Label("Hide", systemImage: "eye.slash").lineLimit(1).fixedSize() }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("fieldHideSelected")
        }
        .font(.system(size: CP.fs(13), weight: .medium))
        .padding(.horizontal, CP.Space.s)
        .padding(.vertical, 6)
        .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
    }

    /// Section eye: all shown (eye), all hidden (eye with a slash), some hidden (dimmed eye with a dash). Tap: show
    /// all when any is hidden, else hide all.
    private func sectionEye(_ states: [Bool], label: String, _ set: @escaping (Bool) -> Void) -> some View {
        let shown = states.filter { $0 }.count
        let allShown = shown == states.count, mixed = shown > 0 && !allShown
        return Button { set(!allShown) } label: {
            Image(systemName: allShown || mixed ? "eye" : "eye.slash")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(allShown ? CP.ink : CP.inkMuted)
                .overlay(alignment: .bottomTrailing) {
                    if mixed {
                        Image(systemName: "minus.circle.fill").font(.system(size: CP.fs(8), weight: .bold))
                            .foregroundStyle(CP.peach.strong).offset(x: 4, y: 3)
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(states.isEmpty)
        .help(allShown ? "Hide all \(label)" : "Show all \(label)")
        .accessibilityLabel(allShown ? "Hide \(label)" : "Show \(label)")
        .accessibilityValue(mixed ? "Some hidden" : allShown ? "All shown" : "All hidden")
        .accessibilityIdentifier("fieldEye-\(label)")
    }

    private func eye(_ on: Bool, label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? "eye" : "eye.slash")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(on ? CP.ink : CP.inkMuted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())          // the whole 28 pt square is tappable, not just the icon
        }
        .buttonStyle(.plain)
        .help(on ? "Hide on the map" : "Show on the map")
        .accessibilityLabel(on ? "Hide \(label)" : "Show \(label)")
        .accessibilityIdentifier("fieldItemEye")
    }

    // MARK: Text

    static func trackSummary(_ t: FieldTrack) -> String {
        var parts = [t.lengthM >= 1000 ? "\(Fmt.number(t.lengthM / 1000, decimals: 2)) km" : "\(Int(t.lengthM.rounded())) m"]
        if let d = t.duration, d > 0 {
            let m = Int(d / 60)
            parts.append(m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(max(m, 1)) min")
        }
        if let a = t.typicalAccuracyM { parts.append("±\(Int(a.rounded())) m") }
        if t.source == "gpx" { parts.append("GPX") }
        return parts.joined(separator: " · ")
    }

    static func noteSummary(_ n: FieldNote) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM HH:mm"
        var parts = [f.string(from: n.createdAt)]
        if let a = n.averaging {
            parts.append("averaged ±\(Fmt.number(a.accuracyM, decimals: 1)) m (\(a.samples))")
        } else if let acc = n.accuracyM {
            parts.append("GPS ±\(Int(acc.rounded())) m")
        }
        if n.text.contains("\n") || (n.title != n.category.label && n.averaging == nil) { parts.append(n.category.label) }
        return parts.joined(separator: " · ")
    }
}
