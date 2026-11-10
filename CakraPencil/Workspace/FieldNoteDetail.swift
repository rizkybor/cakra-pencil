import CakraCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Note detail

/// One field note in detail: photos, text and category (editable), position and accuracy, and the actions to process
/// it — make a map object from it, show that object, mark done, delete. In the Field panel on iPad and Mac, and as a
/// sheet in field mode.
struct FieldNoteDetail: View {
    @ObservedObject var model: WorkspaceModel
    let noteID: UUID
    /// Shown in the panel: a back button to the list. In a sheet the sheet has its own Done button.
    var onBack: (() -> Void)?

    @State private var text = ""
    @State private var choosingSymbol = false
    @State private var viewerIndex: Int?
    @State private var confirmDelete = false
    // Adding photos: Upload (Mac, from files), library (both), camera (iPad).
    @State private var uploading = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var cameraOpen = false
    /// Photo being marked up (Apple Pencil / mouse).
    @State private var markupPhoto: String?
    @EnvironmentObject private var library: SymbolLibrary

    private var note: FieldNote? { model.field.notes.first { $0.id == noteID } }

    var body: some View {
        if let n = note {
            ScrollView {
                VStack(alignment: .leading, spacing: CP.Space.m) {
                    if let onBack { backBar(onBack) }
                    titleRow(n)
                    if !n.photos.isEmpty { photoGrid(n) }
                    if n.photos.count < NewFieldNoteSheet.maxPhotos { addPhotoRow(n) }
                    textEditor(n)
                    actions(n)
                    infoCard(n)
                }
                .padding(.bottom, CP.Space.l)
            }
            .onAppear { text = n.text }
            .onChange(of: noteID) { _, _ in text = note?.text ?? "" }
            .sheet(isPresented: $choosingSymbol) {
                FieldSymbolPicker.forNote(model: model, note: n) { symbol in
                    choosingSymbol = false
                    model.makeObject(fromNote: n.id, symbol: symbol)
                }
                .environmentObject(library)
            }
            .fullScreenCover(isPresented: Binding(get: { viewerIndex != nil }, set: { if !$0 { viewerIndex = nil } })) {
                FieldPhotoViewer(model: model, note: n, index: viewerIndex ?? 0)
            }
            .fileImporter(isPresented: $uploading, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result else { return }
                Task { await addFiles(urls, to: n.id) }
            }
            .onChange(of: libraryItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var data: [Data] = []
                    for item in items {
                        if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d), let j = FieldPhoto.jpeg(img) { data.append(j) }
                    }
                    model.addPhotos(toNote: n.id, data)
                    libraryItems = []
                }
            }
            .fullScreenCover(isPresented: $cameraOpen) {
                CameraPicker { image in
                    if let image, let j = FieldPhoto.jpeg(image) { model.addPhotos(toNote: n.id, [j]) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: Binding(get: { markupPhoto != nil }, set: { if !$0 { markupPhoto = nil } })) {
                if let photo = markupPhoto { PhotoMarkupView(model: model, noteID: n.id, photo: photo) }
            }
            .confirmationDialog("Delete this note and its photos?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete note", role: .destructive) { model.deleteNote(n.id); onBack?() }
            }
        } else {
            VStack(alignment: .leading, spacing: CP.Space.m) {
                if let onBack { backBar(onBack) }
                Text("This note was deleted.").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
            }
        }
    }

    // MARK: Parts

    private func backBar(_ back: @escaping () -> Void) -> some View {
        Button(action: back) {
            Label("Notes", systemImage: "chevron.left").font(.system(size: CP.fs(14), weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(CP.sky.strong)
        .padding(.top, CP.Space.xs)
        .accessibilityIdentifier("noteBack")
    }

    private func titleRow(_ n: FieldNote) -> some View {
        HStack(spacing: CP.Space.s) {
            SolidMenu(items: FieldNote.Category.allCases.map { c in
                .action(c.label, icon: c.icon, checked: c == n.category) { model.updateNote(n.id) { $0.category = c } }
            }, width: 240) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(Color(hexString: n.category.colorHex))
                        Image(systemName: n.category.icon).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: 28, height: 28)
                    Text(n.category.label).font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(CP.inkMuted)
                }
            }
            .fixedSize()
            .accessibilityLabel("Category: \(n.category.label)")
            .accessibilityIdentifier("noteCategory")
            Spacer(minLength: 0)
            if n.isDone {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.system(size: CP.fs(12), weight: .semibold))
                    .foregroundStyle(CP.sage.strong)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(CP.sage.fill, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
                    .accessibilityIdentifier("noteDoneBadge")
            }
        }
    }

    /// One photo full width; more photos in two columns.
    @ViewBuilder private func photoGrid(_ n: FieldNote) -> some View {
        if n.photos.count == 1 {
            photoButton(n, 0, height: 180)
        } else {
            let cols = [GridItem(.flexible(), spacing: CP.Space.s), GridItem(.flexible(), spacing: CP.Space.s)]
            LazyVGrid(columns: cols, spacing: CP.Space.s) {
                ForEach(n.photos.indices, id: \.self) { i in photoButton(n, i, height: 110) }
            }
        }
    }

    /// Mac: Upload photo (files) and Photos library. iPad: camera and library.
    private func addPhotoRow(_ n: FieldNote) -> some View {
        let room = NewFieldNoteSheet.maxPhotos - n.photos.count
        return HStack(spacing: CP.Space.s) {
            if CP.isMac {
                Button { uploading = true } label: { Label("Upload photo…", systemImage: "square.and.arrow.up.on.square") }
                    .accessibilityIdentifier("noteUploadPhoto")
            } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { cameraOpen = true } label: { Label("Take photo", systemImage: "camera") }
            }
            PhotosPicker(selection: $libraryItems, maxSelectionCount: room, matching: .images) {
                Label(CP.isMac ? "From Photos…" : "Add photo", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("noteAddPhoto")
            Spacer(minLength: 0)
        }
        .font(.system(size: CP.fs(13), weight: .medium))
        .buttonStyle(.borderless)
        .foregroundStyle(CP.sky.strong)
    }

    /// Uploaded image files → resized JPEG (same 2048 px limit as photos taken in the field).
    private func addFiles(_ urls: [URL], to id: UUID) async {
        let data: [Data] = await Task.detached(priority: .userInitiated) {
            urls.compactMap { url in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let img = UIImage(contentsOfFile: url.path) else { return nil }
                return FieldPhoto.jpeg(img)
            }
        }.value
        if data.count < urls.count { model.notice = "Some files are not images and were skipped." }
        model.addPhotos(toNote: id, data)
    }

    private func photoButton(_ n: FieldNote, _ i: Int, height: CGFloat) -> some View {
        Button { viewerIndex = i } label: {
            FieldPhotoThumb(url: model.fieldPhotoURL(n.photos[i]), markup: model.markupURL(n.photos[i], in: n))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: CP.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
                .overlay(alignment: .topTrailing) {
                    if n.hasMarkup(n.photos[i]) {
                        Image(systemName: "pencil.tip.crop.circle.fill").font(.system(size: 18))
                            .foregroundStyle(.white, Color(hexString: "#E8202A")).padding(5)
                            .accessibilityLabel("Has markup")
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { markupPhoto = n.photos[i] } label: { Label("Markup…", systemImage: "pencil.tip.crop.circle") }
            Button(role: .destructive) { model.removePhoto(n.photos[i], fromNote: n.id) } label: { Label("Remove photo", systemImage: "trash") }
        }
        .accessibilityLabel("Photo \(i + 1) of \(n.photos.count)")
        .accessibilityIdentifier("notePhoto")
    }

    private func textEditor(_ n: FieldNote) -> some View {
        TextField("Add a note…", text: $text, axis: .vertical)
            .font(.system(size: CP.fs(14)))
            .lineLimit(2...8)
            .padding(CP.Space.s)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
            .onChange(of: text) { _, t in
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed != n.text { model.updateNote(n.id) { $0.text = trimmed } }
            }
            .accessibilityIdentifier("noteDetailText")
    }

    private func infoCard(_ n: FieldNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            info("clock", Self.dateText(n.createdAt))
            info("location", Self.positionText(n.position, zone: model.zone))
            if let a = n.averaging {
                info("scope", "Averaged: ±\(Fmt.number(a.accuracyM, decimals: 1)) m from \(a.samples) fixes in \(Int(a.durationS.rounded())) s")
            } else if let acc = n.accuracyM {
                info("dot.radiowaves.left.and.right", "GPS ±\(Int(acc.rounded())) m")
            } else {
                info("hand.tap", "Placed on the map")
            }
            if let h = n.photoHeadingDeg { info("location.north.line", "Camera facing \(Self.headingText(h))") }
            if let v = n.vegetation { info("leaf", "\(v.code) \(v.label) — draft for an area") }
            if let o = n.offset {
                let paces = o.paces.map { " (\(Fmt.number($0, decimals: 0)) paces)" } ?? ""
                info("arrow.up.right", "Offset \(Self.distanceText(o.distanceM))\(paces) at \(Self.headingText(o.bearingDeg)) from where you stood")
            }
        }
        .padding(CP.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CP.paper2.opacity(0.6), in: RoundedRectangle(cornerRadius: CP.Radius.control))
    }

    private func info(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.system(size: CP.fs(12))).foregroundStyle(CP.ink).textSelection(.enabled)
        } icon: {
            Image(systemName: icon).font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted).frame(width: 16)
        }
    }

    /// Icon-only actions in one row (names in tooltips on Mac and for VoiceOver).
    private func actions(_ n: FieldNote) -> some View {
        VStack(alignment: .leading, spacing: CP.Space.xs) {
            HStack(spacing: CP.Space.s) {
                if model.noteFeature(n) != nil {
                    action("cursorarrow.rays", "Show map object", tone: CP.sky, id: "noteShowObject") { model.showNoteObject(n) }
                } else {
                    action("wand.and.stars", "Make map object", tone: CP.sky, id: "noteMakeObject") { choosingSymbol = true }
                        .disabled(!model.project.areaLocked)
                }
                action("scope", "Zoom to note", tone: CP.butter, id: "noteZoom") { model.zoomToNote(n) }
                action(n.isDone ? "arrow.uturn.backward" : "checkmark", n.isDone ? "Mark as to do" : "Mark as done",
                       tone: CP.sage, id: "noteToggleDone") { model.setNoteDone(n.id, !n.isDone) }
                action("trash", "Delete note", tone: CP.rose, id: "noteDelete") { confirmDelete = true }
            }
            if !model.project.areaLocked {
                Text("Lock the map area (Map tab) to make map objects.")
                    .font(.system(size: CP.fs(11))).foregroundStyle(CP.inkMuted)
            }
        }
    }

    private func action(_ icon: String, _ name: String, tone: CP.Tone, id: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Label(name, systemImage: icon) }
            .buttonStyle(FieldButtonStyle(tone: tone))
            .labelStyle(.iconOnly)
            .help(name)
            .accessibilityLabel(name)
            .accessibilityIdentifier(id)
    }

    // MARK: Text

    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f.string(from: d)
    }

    /// "E 712 345  N 9 345 678 · 6.12345° S 106.12345° E"
    static func positionText(_ p: Point2D, zone: UTMZone?) -> String {
        let utm = "E \(Int(p.x.rounded()))  N \(Int(p.y.rounded()))"
        guard let zone else { return utm }
        let ll = zone.unproject(p)
        return utm + String(format: " · %.5f° %@ %.5f° %@", abs(ll.lat), ll.lat < 0 ? "S" : "N", abs(ll.lon), ll.lon < 0 ? "W" : "E")
    }

    /// "50 m", "12.5 m"
    static func distanceText(_ m: Double) -> String {
        let r = (m * 10).rounded() / 10
        return "\(Fmt.number(r, decimals: r == r.rounded() ? 0 : 1)) m"
    }

    /// "45° NE"
    static func headingText(_ deg: Double) -> String {
        let d = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return "\(Int(d.rounded()))° \(names[Int((d + 22.5) / 45) % 8])"
    }
}

// MARK: - Symbol picker

/// Choose the symbol for objects made from field data: suggestions first, then the map's symbol set (searchable).
/// For a note: point symbols (placed at the note), then lines and areas (drawn from it). For a track: lines and areas.
struct FieldSymbolPicker: View {
    enum Purpose { case note, track }

    @ObservedObject var model: WorkspaceModel
    let purpose: Purpose
    let suggestedCodes: [String]
    var suggestedTitle = "Suggested"
    let onPick: (MapSymbol) -> Void
    @EnvironmentObject private var library: SymbolLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showLines = false

    /// The map's symbol set (same choice as the Symbol panel's default), sized for the map scale.
    private var set: SymbolSet? {
        let sets = library.preferredSets(for: model.project.sheet)
        return sets.first { !$0.isCourseDesign } ?? sets.first
    }

    private var usable: [MapSymbol] {
        (set?.symbols ?? []).filter { $0.isEnabled && $0.isDrawable && $0.kind != .text && (purpose == .note || $0.kind != .point) }
    }

    private var suggested: [MapSymbol] {
        // Sets write "204" or "204.0".
        suggestedCodes.compactMap { code in usable.first { $0.code == code || $0.code == code + ".0" } }
    }

    private func matches(_ s: MapSymbol) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || s.name.lowercased().contains(q) || s.code.hasPrefix(q)
    }

    var body: some View {
        NavigationStack {
            List {
                if set == nil {
                    Text("No symbol set is enabled. Turn one on in the Symbol panel (Manage).").foregroundStyle(CP.inkMuted)
                }
                if query.isEmpty, !suggested.isEmpty {
                    Section(suggestedTitle) { ForEach(suggested, id: \.code) { row($0) } }
                }
                if purpose == .note {
                    Section("Point symbols — placed at the note") {
                        ForEach(usable.filter { $0.kind == .point && matches($0) }, id: \.code) { row($0) }
                    }
                    Section {
                        if showLines || !query.isEmpty {
                            ForEach(usable.filter { $0.kind != .point && matches($0) }, id: \.code) { row($0) }
                        } else {
                            Button("Show lines and areas") { showLines = true }
                        }
                    } header: {
                        Text("Lines and areas — draw from the note")
                    }
                } else {
                    Section("Lines") { ForEach(usable.filter { $0.kind == .line && matches($0) }, id: \.code) { row($0) } }
                    Section("Areas — for a walk around an area") {
                        ForEach(usable.filter { $0.kind == .area && matches($0) }, id: \.code) { row($0) }
                    }
                }
            }
            .searchable(text: $query, prompt: "Code or name")
            .navigationTitle(purpose == .note ? "Make map object" : "Line symbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Group { Button("Cancel") { dismiss() } }.buttonStyle(SecondaryButtonStyle(compact: true)) }.plainBar() }
        }
        .frame(minWidth: CP.isMac ? 420 : nil, minHeight: CP.isMac ? 520 : nil)
    }

    private func row(_ s: MapSymbol) -> some View {
        Button { onPick(s) } label: {
            HStack(spacing: CP.Space.s) {
                SymbolSwatch(symbol: s, size: CGSize(width: 34, height: 28))
                Text(s.code).font(CP.mono(13)).foregroundStyle(CP.inkMuted).frame(minWidth: 44, alignment: .leading)
                Text(s.name).font(.system(size: CP.fs(15))).foregroundStyle(CP.ink).lineLimit(2)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.code) \(s.name)")
        .accessibilityIdentifier("noteSymbol-\(s.code)")
    }
}

extension FieldSymbolPicker {
    /// Picker for a note: the vegetation class's area first, then the category's point symbols.
    static func forNote(model: WorkspaceModel, note: FieldNote, onPick: @escaping (MapSymbol) -> Void) -> FieldSymbolPicker {
        let codes = (note.vegetation.map { [$0.code] } ?? []) + note.category.suggestedSymbolCodes
        return FieldSymbolPicker(model: model, purpose: .note, suggestedCodes: codes,
                                 suggestedTitle: "Suggested for \(note.vegetation.map { $0.label.lowercased() } ?? note.category.label.lowercased())",
                                 onPick: onPick)
    }
}

// MARK: - Photos

/// A photo thumbnail (with its markup), decoded off the main thread at a small size.
struct FieldPhotoThumb: View {
    let url: URL
    var markup: URL? = nil
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            CP.paper2
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(CP.inkMuted)
            }
        }
        .clipped()
        .task(id: url.path + FieldPhotoImage.stamp(markup)) {
            let u = url, m = markup
            image = await Task.detached(priority: .userInitiated) {
                FieldPhotoImage.load(photo: u, markup: m, maxSide: 480)
            }.value
        }
    }
}

/// Full-screen photo viewer: swipe (or ← →) between the note's photos, pinch or double-tap to zoom, share a photo.
/// The caption shows the note, the time and the direction the camera faced.
struct FieldPhotoViewer: View {
    @ObservedObject var model: WorkspaceModel
    let note: FieldNote
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var markingUp = false

    /// The note as it is now (markups change while the viewer is open).
    private var current: FieldNote { model.field.notes.first { $0.id == note.id } ?? note }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(note.photos.enumerated()), id: \.offset) { i, name in
                    ZoomablePhoto(url: model.fieldPhotoURL(name), markup: model.markupURL(name, in: current)).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: note.photos.count > 1 ? .always : .never))
            .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                caption
            }
            .padding(CP.Space.m)

            // Keyboard (Mac, iPad keyboard): ← → between photos, Esc closes.
            Group {
                Button("") { index = max(0, index - 1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { index = min(note.photos.count - 1, index + 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("photoViewer")
        .fullScreenCover(isPresented: $markingUp) {
            if note.photos.indices.contains(index) { PhotoMarkupView(model: model, noteID: note.id, photo: note.photos[index]) }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close")
            .help("Close (Esc)")
            .accessibilityIdentifier("photoViewerClose")
            Spacer()
            if note.photos.count > 1 {
                Text(verbatim: "\(index + 1) / \(note.photos.count)").font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Color.black.opacity(0.55), in: Capsule())
            }
            Spacer()
            if note.photos.indices.contains(index) {
                Button { markingUp = true } label: {
                    Image(systemName: "pencil.tip.crop.circle").font(.system(size: 19, weight: .bold)).frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Markup")
                .help("Draw on the photo (Apple Pencil, finger or mouse)")
                .accessibilityIdentifier("photoMarkup")
                ShareLink(item: model.fieldPhotoURL(note.photos[index])) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .bold)).frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel("Share photo")
            }
        }
        .foregroundStyle(.white)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title).font(.system(size: 16, weight: .semibold))
            HStack(spacing: CP.Space.m) {
                Text(FieldNoteDetail.dateText(note.createdAt))
                if let h = note.photoHeadingDeg {
                    Label("Facing \(FieldNoteDetail.headingText(h))", systemImage: "location.north.line.fill")
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding(.bottom, note.photos.count > 1 ? 28 : 0)
    }
}

/// A photo that fits the screen; pinch (or trackpad pinch) to zoom up to 5×, drag when zoomed, double-tap to toggle.
private struct ZoomablePhoto: View {
    let url: URL
    var markup: URL? = nil
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(max(baseScale * v.magnification, 1), 5) }
                    .onEnded { _ in
                        baseScale = scale
                        if scale <= 1.01 { reset() }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: scale > 1 ? 0 : 10_000)
                    .onChanged { v in
                        offset = CGSize(width: baseOffset.width + v.translation.width, height: baseOffset.height + v.translation.height)
                    }
                    .onEnded { _ in baseOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if scale > 1 { reset() } else { scale = 2.5; baseScale = 2.5 }
                }
            }
        }
        .task(id: url.path + FieldPhotoImage.stamp(markup)) {
            let u = url, m = markup
            image = await Task.detached(priority: .userInitiated) { FieldPhotoImage.load(photo: u, markup: m) }.value
        }
    }

    private func reset() {
        scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero
    }
}
