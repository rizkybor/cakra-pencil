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

    enum NoteFilter: String, CaseIterable {
        case all = "All", todo = "To do", done = "Done"     // To do = not processed yet
    }

    private static let gpxType = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml

    private var field: FieldData { model.field }

    private var notes: [FieldNote] {
        field.notes.filter { filter == .all || (filter == .done) == $0.isDone }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
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
        .renameDialog("Rename track", subtitle: renaming.map { "Current name: \($0.name)" }, placeholder: "Track name",
                      confirm: "Rename", isPresented: renaming != nil, text: $newName,
                      onSave: {
                          if let t = renaming { model.renameTrack(t.id, to: newName.trimmingCharacters(in: .whitespacesAndNewlines)) }
                          renaming = nil
                      },
                      onCancel: { renaming = nil })
    }

    private func importFieldData() {
        importTypes = [.occaFieldData]
        importing = true
    }

    private func importGPX() {
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
            SolidMenu(items: [
                .action("Import field data…", icon: "square.and.arrow.down.on.square", section: "Field data (.occafield) — iPad ⇄ Mac") { importFieldData() },
                .action("Export field data…", icon: "square.and.arrow.up.on.square", disabled: field.isEmpty,
                        section: "Field data (.occafield) — iPad ⇄ Mac") { exportChoice = true },
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
                eye(field.showTracks, label: "tracks") { model.setTracksVisible(!field.showTracks) }
                Text("Tracks")
            }
        }
    }

    private func trackRow(_ t: FieldTrack) -> some View {
        HStack(spacing: CP.Space.s) {
            eye(t.isVisible, label: t.name) { model.setTrackVisible(t.id, !t.isVisible) }
            Capsule().fill(Color(hexString: t.colorHex)).frame(width: 18, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.name).font(.system(size: CP.fs(15))).foregroundStyle(CP.ink).lineLimit(1)
                Text(Self.trackSummary(t)).font(CP.mono(11)).foregroundStyle(CP.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.zoomToTrack(t) }
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
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(t.name), \(Self.trackSummary(t))")
        .accessibilityIdentifier("fieldTrack")
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
                eye(field.showNotes, label: "notes") { model.setNotesVisible(!field.showNotes) }
                Text("Notes")
                Spacer()
                let todo = field.notes.filter { !$0.isDone }.count
                if todo > 0 { Text(verbatim: "\(todo) to do").foregroundStyle(CP.peach.strong) }
            }
        }
    }

    private func noteRow(_ n: FieldNote) -> some View {
        HStack(spacing: CP.Space.s) {
            ZStack {
                Circle().fill(Color(hexString: n.category.colorHex).opacity(n.isDone ? 0.45 : 1))
                Image(systemName: n.isDone ? "checkmark" : n.category.icon)
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(n.title).font(.system(size: CP.fs(15))).foregroundStyle(n.isDone ? CP.inkMuted : CP.ink).lineLimit(1)
                Text(Self.noteSummary(n)).font(CP.mono(11)).foregroundStyle(CP.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if !n.photos.isEmpty {
                Label("\(n.photos.count)", systemImage: "photo").font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.openFieldNote(n.id) }
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
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(n.title), \(Self.noteSummary(n))\(n.isDone ? ", done" : "")")
        .accessibilityIdentifier("fieldNote")
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
        .accessibilityLabel(on ? "Hide \(label)" : "Show \(label)")
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
