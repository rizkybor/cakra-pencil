import CakraCore
import SwiftUI

/// Home page: app identity, search + sorting, and project cards with a map preview.
/// Each card has a menu (Open, Rename, Duplicate, Share, Delete).
struct ProjectListView: View {
    @EnvironmentObject private var repository: ProjectRepository
    @EnvironmentObject private var symbols: SymbolLibrary
    @State private var showingNew = false
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.system.rawValue
    @State private var open: OpenProject?
    @State private var pendingDelete: ProjectRepository.Entry?
    @State private var renaming: ProjectRepository.Entry?
    @State private var newName = ""
    @State private var query = ""
    @State private var sort = Sort.recent
    /// .cpencil file: import (Open file) and save (Save file) — iPad (Files) and Mac (Finder dialog).
    @State private var importingFile = false
    @State private var savingFile: ProjectFileDocument?
    @State private var savingName = "Project"
    @State private var importedName: String?
    /// OCAD / OOM map picked in Open file: becomes a new project after the zone is confirmed.
    @State private var pendingMap: PendingMapImport?
    @State private var createdFromMap: ProjectRepository.Entry?
    /// Success effect on a card (renamed / duplicated / saved), cleared after a moment.
    @State private var cardEffects: [UUID: CardEffect] = [:]
    /// Cards shrinking away before their project is deleted.
    @State private var removingIDs: Set<UUID> = []
    /// Project whose .occa file is being saved (for its success effect).
    @State private var savingEntryID: UUID?
    /// Short message at the bottom (e.g. after deleting a project).
    @State private var toast: String?

    struct OpenProject: Identifiable {
        var url: URL
        var document: ProjectDocument
        var id: UUID { document.project.id }
    }

    enum Sort: String, CaseIterable {
        case recent = "Last modified"
        case name = "Name"
        case created = "Date created"
    }

    private var visible: [ProjectRepository.Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = repository.entries.filter { q.isEmpty || $0.project.name.lowercased().contains(q) }
        switch sort {
        case .recent: return filtered.sorted { $0.project.updatedAt > $1.project.updatedAt }
        case .name: return filtered.sorted { $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending }
        case .created: return filtered.sorted { $0.project.createdAt > $1.project.createdAt }
        }
    }

    /// About screen (credits); `-cp-show-about` opens it at launch (DEBUG, screenshots).
    @State private var showingAbout = false
    @State private var showingGuide = false
    @State private var confirmQuit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.xl) {
                header
                if repository.entries.isEmpty {
                    emptyState
                } else {
                    toolbar
                    if visible.isEmpty {
                        Text("No project named \"\(query)\".")
                            .font(.system(size: CP.fs(15)))
                            .foregroundStyle(CP.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, CP.Space.xxl)
                    } else {
                        grid
                    }
                }
            }
            .padding(.horizontal, CP.Space.xxl)
            .padding(.vertical, CP.Space.xl)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "trash")
                    .font(.system(size: CP.fs(13), weight: .medium))
                    .foregroundStyle(CP.rose.strong)
                    .padding(.horizontal, CP.Space.m)
                    .frame(height: 36)
                    .background(CP.rose.fill, in: Capsule())
                    .overlay(Capsule().strokeBorder(CP.rose.strong.opacity(0.25)))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("projectToast")
            }
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .sheet(isPresented: $showingGuide) { GuideView() }
        // First launch on this device: the guide opens after the splash screen.
        .task {
            guard GuideView.shouldOpenAutomatically else { return }
            let splash = !ProcessInfo.processInfo.arguments.contains("-cp-no-splash")
            try? await Task.sleep(for: .seconds(splash ? 4.8 : 0.6))
            if open == nil { showingGuide = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGuide)) { _ in if open == nil { showingGuide = true } }
        .alert("Quit \(AppInfo.name)?", isPresented: $confirmQuit) {
            Button("Quit", role: .destructive) { MacWindow.quit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your projects are saved automatically.")
        }
        #if DEBUG
        .onAppear {
            // Presented after the list appears (a sheet set up before the first layout doesn't show on Mac).
            if ProcessInfo.processInfo.arguments.contains("-cp-show-about") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showingAbout = true }
            }
            // `-cp-test-quit`: run the Quit button's action after 3 s (checks that the Mac app really quits).
            if ProcessInfo.processInfo.arguments.contains("-cp-test-quit") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MacWindow.quit() }
            }
            // `-cp-open-map-file <file>`: same as Open file with Documents/<file> (.ocd/.omap; UI tests).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-cp-open-map-file"), i + 1 < args.count {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                importFiles([docs.appendingPathComponent(args[i + 1])])
            }
        }
        #endif
        // Credit always at the bottom of the screen, above the page background.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            credit
                .padding(.vertical, CP.Space.s)
                .background(CP.paper2.opacity(0.92))
        }
        .background {
            ZStack(alignment: .topTrailing) {
                CP.paper2
                ContourMotif()
                    .frame(width: 520, height: 360)
                    .opacity(0.45)
                    .offset(x: 160, y: -120)
            }
            .ignoresSafeArea()
        }
        #if DEBUG
        // For screenshots/UI tests: `-cp-open-first` opens the most recent project at launch.
        .task {
            let args = ProcessInfo.processInfo.arguments
            // `-cp-open-project <name>` opens a specific project (e.g. "Uji Performa" for the performance test).
            let named = args.firstIndex(of: "-cp-open-project").flatMap { i in
                i + 1 < args.count ? repository.entries.first { $0.project.name == args[i + 1] } : nil
            }
            // `-cp-import-file <name>`: import Documents/<name> (.cpencil) as if from Files/Finder.
            if let i = args.firstIndex(of: "-cp-import-file"), i + 1 < args.count {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                importFiles([docs.appendingPathComponent(args[i + 1])])
            }
            if let entry = named ?? (args.contains("-cp-open-first") ? repository.entries.first : nil),
               let doc = repository.load(entry) {
                open = OpenProject(url: entry.url, document: doc)
            }
        }
        #endif
        // Save / open a .cpencil project file (iPad: Files; Mac: Finder dialog). Also from Files/Finder/AirDrop.
        .fileExporter(isPresented: Binding(get: { savingFile != nil }, set: { if !$0 { savingFile = nil } }),
                      document: savingFile, contentType: .cakraProject, defaultFilename: savingName) { result in
            switch result {
            case .success: if let id = savingEntryID { flash(id, .saved, after: 0.35) }
            case let .failure(error): repository.lastError = "Couldn't save file: \(error.localizedDescription)"
            }
            savingFile = nil
            savingEntryID = nil
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.cakraProject] + LayerPanel.mapFileTypes, allowsMultipleSelection: true) { result in
            if case let .success(urls) = result { importFiles(urls) }
        }
        .onOpenURL { url in
            let ext = url.pathExtension.lowercased()
            if ext == OccaSymbolFile.fileExtension {
                // A shared symbol set opened from Files / Finder / AirDrop: add it to the symbol library.
                Task {
                    await symbols.importOcad([url])
                    if symbols.lastError == nil { importedName = "Symbol set \(url.deletingPathExtension().lastPathComponent) added to the symbol library." }
                }
                return
            }
            guard ProjectArchive.acceptedExtensions.contains(ext) || MapFileImport.fileExtensions.contains(ext) else { return }
            importFiles([url])
        }
        .sheet(item: $pendingMap, onDismiss: {
            // Open the new project once the sheet has fully closed: presenting the workspace while the sheet is still
            // animating away is ignored by iOS (a fixed delay was not always enough).
            if let entry = createdFromMap { createdFromMap = nil; openEntry(entry) }
        }) { pending in
            MapImportSheet(pending: pending,
                           suggestedZone: repository.entries.first?.project.zone ?? UTMZone(number: 48, isNorth: false)!) { doc in
                guard let entry = repository.create(document: doc) else { return }
                Task { await repository.refreshThumbnail(entry) }
                createdFromMap = entry          // opened right away when the sheet is gone (its area is locked)
            }
        }
        .alert(importedName?.hasPrefix("Symbol set") == true ? "Symbol set imported" : "Project imported", isPresented: Binding(get: { importedName != nil }, set: { if !$0 { importedName = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importedName ?? "")
        }
        .sheet(isPresented: $showingNew) {
            NewProjectSheet { project in
                if let entry = repository.create(project), let doc = repository.load(entry) {
                    open = OpenProject(url: entry.url, document: doc)
                }
            }
        }
        .fullScreenCover(item: $open, onDismiss: refreshAfterClose) { item in
            WorkspaceView(model: WorkspaceModel(document: item.document, url: item.url))
                .environmentObject(symbols)
        }
        // Alert (not confirmationDialog): a dialog triggered from inside a Menu may fail to show when the menu closes.
        .alert("Delete project?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { entry in
            Button("Delete", role: .destructive) { remove(entry) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("The sheet \(entry.project.name) and its sketch, vector objects, contours, and frame settings will be permanently deleted. This can't be undone.")
        }
        .renameDialog("Rename project", subtitle: renaming.map { "Current name: \($0.project.name)" }, placeholder: "Project name",
                      isPresented: renaming != nil, text: $newName,
                      onSave: {
                          if let e = renaming {
                              repository.rename(e, to: newName.trimmingCharacters(in: .whitespacesAndNewlines))
                              flash(e.id, .renamed, after: 0.35)
                          }
                          renaming = nil
                      },
                      onCancel: { renaming = nil })
        .alert("Something went wrong", isPresented: Binding(get: { repository.lastError != nil }, set: { if !$0 { repository.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(repository.lastError ?? "")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: CP.Space.l) {
            AppMark()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: CP.Space.s) {
                    HStack(alignment: .firstTextBaseline, spacing: CP.Space.s) {
                        Text(AppInfo.name)
                            .font(.system(size: CP.fs(28), weight: .semibold))
                            .tracking(-0.6)
                            .foregroundStyle(CP.ink)
                        Text(AppInfo.fullName)
                            .font(.system(size: CP.fs(15), weight: .medium))
                            .foregroundStyle(CP.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .combine)
                    // About (credits, release, supported files) and Guide: two icons close together, next to the
                    // app's identity, apart from the actions on the right.
                    HStack(spacing: 2) {
                        Button {
                            showingAbout = true
                        } label: {
                            headerIcon("info.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("About \(AppInfo.name)")
                        .accessibilityIdentifier("aboutButton")
                        .help("About \(AppInfo.name) · credits")
                        Button {
                            showingGuide = true
                        } label: {
                            headerIcon("book")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(AppInfo.name) guide")
                        .accessibilityIdentifier("guideButton")
                        .help("Guide: start a project, draw, fieldwork, iPad ⇄ Mac (⌘?)")
                        // Appearance: System (default) / Light / Dark.
                        SolidMenu(items: AppearanceMode.allCases.map { m in
                            .action(m.label, icon: m.icon, checked: m.rawValue == appearance, section: "Appearance",
                                    identifier: "appearance-\(m.rawValue)") { appearance = m.rawValue }
                        }, width: 200) {
                            headerIcon((AppearanceMode(rawValue: appearance) ?? .system).icon)
                        }
                        .accessibilityLabel("Appearance: \((AppearanceMode(rawValue: appearance) ?? .system).label)")
                        .accessibilityIdentifier("appearanceButton")
                        .help("Appearance: System, Light, or Dark")
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
                }
                Text(AppInfo.tagline)
                    .font(.system(size: CP.fs(14)))
                    .foregroundStyle(CP.inkMuted)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                importingFile = true
            } label: {
                Label("Open file", systemImage: "folder")
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut("o", modifiers: .command)
            .help("Open a .occa project file, or an OCAD (.ocd) / OOM (.omap, .xmap) map as a new project (⌘O)")
            Button {
                showingNew = true
            } label: {
                Label("New project", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
            // Mac only: iPadOS apps don't quit themselves (swipe up to leave); OCCA has no accounts to log out of.
            if CP.isMac {
                Button { confirmQuit = true } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Quit \(AppInfo.name)")
                .accessibilityIdentifier("quitApp")
                .help("Quit \(AppInfo.name) (⌘Q)")
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: CP.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Projects")
                    .font(.system(size: CP.fs(20), weight: .semibold))
                    .foregroundStyle(CP.ink)
                Text(summary)
                    .font(CP.mono(12))
                    .foregroundStyle(CP.inkMuted)
            }
            Spacer()
            HStack(spacing: CP.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(CP.inkMuted)
                TextField("Search projects", text: $query)
                    .font(.system(size: CP.fs(15)))
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, CP.Space.m)
            .frame(width: 260, height: Self.controlHeight)
            .searchFieldSurface()
            SolidMenu(items: Sort.allCases.map { o in .action(o.rawValue, checked: o == sort, section: "Sort by") { sort = o } }, width: 220) {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: CP.fs(13), weight: .medium))
                    .foregroundStyle(CP.sand.strong)
                    .padding(.horizontal, CP.Space.m)
                    .frame(height: Self.controlHeight)
                    .background(CP.sand.fill, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.sand.strong.opacity(0.18)))
            }
            .fixedSize()
        }
    }

    /// Credit footer: supporting company logo; tap = About screen.
    private var credit: some View {
        Button { showingAbout = true } label: {
            HStack(spacing: CP.Space.s) {
                Text("\(AppInfo.name) 2026 · \(AppInfo.country) · Supported by")
                    .font(CP.mono(11))
                    .foregroundStyle(CP.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image("JCDLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 18)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Credit: \(AppInfo.name) 2026, \(AppInfo.country), supported by \(AppInfo.supporter). Opens About.")
        .accessibilityIdentifier("creditFooter")
        .help("About \(AppInfo.name)")
    }

    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: CP.fs(16), weight: .medium))
            .foregroundStyle(CP.inkMuted)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }

    /// Search field and sort button: one height, so they line up exactly.
    private static let controlHeight: CGFloat = 36

    private var summary: String {
        let n = repository.entries.count
        return "\(n) \(n == 1 ? "project" : "projects")"
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: CP.Space.xl)], spacing: CP.Space.xl) {
            ForEach(visible) { entry in
                ProjectCard(entry: entry, thumbnailVersion: repository.thumbnailVersion,
                            onOpen: { openEntry(entry) },
                            onRename: { newName = entry.project.name; renaming = entry },
                            onDuplicate: { duplicate(entry) },
                            onSave: { save(entry) },
                            onDelete: { DispatchQueue.main.async { pendingDelete = entry } },
                            effect: cardEffects[entry.id],
                            removing: removingIDs.contains(entry.id))
                    .task(id: entry.id) {
                        // Older project without a preview: create one once.
                        if entry.project.areaLocked,
                           !FileManager.default.fileExists(atPath: ProjectThumbnail.url(in: entry.url).path) {
                            await repository.refreshThumbnail(entry)
                        }
                    }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: CP.Space.l) {
            ContourMotif()
                .frame(width: 300, height: 200)
            Text("No map sheets yet")
                .font(.system(size: CP.fs(22), weight: .semibold))
                .foregroundStyle(CP.ink)
            Text("Create a project, select an A4 area on satellite imagery, then sketch with Apple Pencil. The result is georeferenced right away for OCAD and OpenOrienteering Mapper.")
                .font(.system(size: CP.fs(15)))
                .foregroundStyle(CP.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button { showingNew = true } label: { Label("Create first project", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func save(_ entry: ProjectRepository.Entry) {
        Task {
            guard let doc = await repository.archive(entry) else { return }
            savingName = projectFileName(entry.project.name)
            savingEntryID = entry.id
            savingFile = doc
        }
    }

    // MARK: Card effects

    /// Highlight a card for a moment after an action succeeded.
    /// `after`: wait for a closing dialog first, so the effect is seen.
    private func flash(_ id: UUID, _ effect: CardEffect, after delay: Double = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { cardEffects[id] = effect }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 2.4) {
            withAnimation(.easeOut(duration: 0.4)) { if cardEffects[id] == effect { cardEffects[id] = nil } }
        }
    }

    /// Duplicate, then highlight the new copy.
    private func duplicate(_ entry: ProjectRepository.Entry) {
        let before = Set(repository.entries.map(\.id))
        repository.duplicate(entry)
        if let copy = repository.entries.first(where: { !before.contains($0.id) }) { flash(copy.id, .duplicated) }
    }

    /// The card shrinks and fades, then the project is deleted and a short message confirms it.
    private func remove(_ entry: ProjectRepository.Entry) {
        withAnimation(.easeIn(duration: 0.25)) { _ = removingIDs.insert(entry.id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeInOut(duration: 0.3)) { repository.delete(entry) }
            removingIDs.remove(entry.id)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = "“\(entry.project.name)” deleted" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.3)) { toast = nil }
            }
        }
    }

    /// .occa project files are imported directly; an OCAD / OOM map file opens "New project from map" (first one only,
    /// since each needs its UTM zone confirmed).
    private func importFiles(_ urls: [URL]) {
        Task {
            var names: [String] = []
            var maps: [URL] = []
            for url in urls {
                if MapFileImport.fileExtensions.contains(url.pathExtension.lowercased()) { maps.append(url); continue }
                if let entry = await repository.importFile(at: url) { names.append(entry.project.name) }
            }
            if !names.isEmpty { importedName = names.joined(separator: ", ") }
            if let url = maps.first, let content = await repository.readMapFile(at: url) {
                pendingMap = PendingMapImport(fileName: url.lastPathComponent, content: content)
                if maps.count > 1 { repository.lastError = "Only one map file at a time: \(url.lastPathComponent) is imported first." }
            }
        }
    }

    private func openEntry(_ entry: ProjectRepository.Entry) {
        if let doc = repository.load(entry) { open = OpenProject(url: entry.url, document: doc) }
    }

    /// After the workspace closes: reload the list and refresh the preview of the project that was just open.
    private func refreshAfterClose() {
        let closedID = open?.id
        repository.reload()
        guard let entry = repository.entries.first(where: { $0.id == closedID }) ?? repository.entries.first else { return }
        Task { await repository.refreshThumbnail(entry) }
    }
}

// MARK: - Project card

/// Success effect on a project card.
enum CardEffect: Equatable {
    case renamed, duplicated, saved

    var label: String {
        switch self {
        case .renamed: "Renamed"
        case .duplicated: "Duplicated"
        case .saved: "File saved"
        }
    }
}

private struct ProjectCard: View {
    let entry: ProjectRepository.Entry
    let thumbnailVersion: Int
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDuplicate: () -> Void
    var onSave: () -> Void
    var onDelete: () -> Void
    var effect: CardEffect? = nil
    var removing = false

    @State private var thumbnail: UIImage?

    private var project: Project { entry.project }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                preview
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipped()
                HStack(spacing: CP.Space.xs) {
                    badge("1:\(project.sheet.scaleDenominator)", symbol: nil, tone: CP.Tone(fill: CP.paper, strong: CP.ink))
                    // Symbol standard of the map (from its scale): ISSprOM for sprint maps, ISOM for forest maps.
                    badge(MapStandard.for(scale: project.sheet.scaleDenominator).label, symbol: nil,
                          tone: CP.Tone(fill: CP.paper, strong: CP.ink))
                        .help("Symbols: IOF \(MapStandard.for(scale: project.sheet.scaleDenominator).label)")
                }
                .padding(CP.Space.s)
            }
            Rectangle().fill(CP.line).frame(height: 1)
            HStack(alignment: .top, spacing: CP.Space.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: CP.fs(17), weight: .semibold))
                        .foregroundStyle(CP.ink)
                        .lineLimit(1)
                    // Scale is in the chip on the preview, so the line starts with the resolution.
                    Text((["\(project.sketchDPI) dpi"] + [project.zone?.label].compactMap { $0 }
                          + ["\(project.sheet.paper.name) \(project.sheet.orientation == .portrait ? "Portrait" : "Landscape")"]).joined(separator: " · "))
                        .font(CP.mono(12))
                        .foregroundStyle(CP.inkMuted)
                        .lineLimit(1)
                    Text("Created \(Self.createdText(project.createdAt)) · Modified \(project.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                SolidMenu(items: [
                    .action("Open", icon: "arrow.up.right.square", onOpen),
                    .action("Rename", icon: "pencil", onRename),
                    .action("Duplicate", icon: "plus.square.on.square", onDuplicate),
                    .action("Save file…", icon: "square.and.arrow.down", onSave),
                    .divider,
                    .action("Delete project", icon: "trash", role: .destructive, onDelete),
                ], width: 220) {
                    // Plain round "more" button (no system menu chrome or chevron on Mac).
                    Image(systemName: "ellipsis")
                        .font(.system(size: CP.fs(15), weight: .bold))
                        .foregroundStyle(CP.inkMuted)
                        .frame(width: 32, height: 32)
                        .background(CP.paper2, in: Circle())
                        .overlay(Circle().strokeBorder(CP.line))
                        .frame(width: CP.hitTarget, height: CP.hitTarget)
                        .contentShape(Rectangle())
                }
                .help("Project actions")
                .accessibilityLabel("Project menu \(project.name)")
            }
            .padding(CP.Space.m)
        }
        .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
        .clipShape(RoundedRectangle(cornerRadius: CP.Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(effect == nil ? CP.line : CP.sage.strong,
                                                                               lineWidth: effect == nil ? 1 : 2.5))
        // Success: sage ring + glow and a "✓ Renamed / Duplicated / File saved" badge on the preview.
        .overlay(alignment: .topTrailing) {
            if let effect {
                Label(effect.label, systemImage: "checkmark.circle.fill")
                    .font(.system(size: CP.fs(12), weight: .semibold))
                    .foregroundStyle(CP.sage.strong)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(CP.sage.fill, in: Capsule())
                    .overlay(Capsule().strokeBorder(CP.sage.strong.opacity(0.35)))
                    .padding(CP.Space.s)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityIdentifier("cardEffect")
            }
        }
        .shadow(color: effect == nil ? .black.opacity(0.06) : CP.sage.strong.opacity(0.45), radius: effect == nil ? 1 : 14, y: 1)
        .scaleEffect(removing ? 0.88 : (effect == nil ? 1 : 1.015))
        .opacity(removing ? 0 : 1)
        .contentShape(RoundedRectangle(cornerRadius: CP.Radius.panel))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(action: onOpen) { Label("Open", systemImage: "arrow.up.right.square") }
            Button(action: onRename) { Label("Rename", systemImage: "pencil") }
            Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button(action: onSave) { Label("Save file…", systemImage: "square.and.arrow.down") }
            Button(role: .destructive, action: onDelete) { Label("Delete project", systemImage: "trash") }
        }
        .task(id: thumbnailVersion) {
            let url = ProjectThumbnail.url(in: entry.url)
            thumbnail = await Task.detached { UIImage(contentsOfFile: url.path) }.value
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-card-\(project.name)")
    }

    @ViewBuilder
    private var preview: some View {
        // Imagery preview only for projects whose area is locked (selected or from a basemap). Projects that
        // aren't: a clearly different empty view, not a satellite photo of the start location resembling other projects.
        if project.areaLocked, let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                CP.paper2
                ContourMotif().padding(CP.Space.l).opacity(0.7)
                VStack(spacing: CP.Space.s) {
                    Image(systemName: project.areaLocked ? "map" : "viewfinder")
                        .font(.system(size: CP.fs(28), weight: .light))
                        .foregroundStyle(CP.inkMuted)
                    Text(project.areaLocked ? "No preview yet" : "No area selected")
                        .font(.system(size: CP.fs(15), weight: .semibold))
                        .foregroundStyle(CP.ink)
                    if !project.areaLocked {
                        Text("Select a map area or upload a GeoTIFF basemap")
                            .font(.system(size: CP.fs(12)))
                            .foregroundStyle(CP.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(CP.Space.m)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Creation date and time in the device's time zone, with the Indonesian zone name (WIB / WITA / WIT) when it
    /// applies, e.g. "9 Nov 2026, 17:27 WIB".
    static func createdText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = "d MMM yyyy, HH:mm"
        return "\(f.string(from: date)) \(zoneName(timeZone, at: date))"
    }

    static func zoneName(_ tz: TimeZone, at date: Date) -> String {
        switch tz.identifier {
        case "Asia/Jakarta", "Asia/Pontianak": return "WIB"
        case "Asia/Makassar": return "WITA"
        case "Asia/Jayapura": return "WIT"
        default: return tz.abbreviation(for: date) ?? "GMT"
        }
    }

    private func badge(_ text: String, symbol: String?, tone: CP.Tone) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: CP.fs(10), weight: .semibold)) }
            Text(verbatim: text).font(CP.mono(11, weight: .medium))
        }
        .foregroundStyle(tone.strong)
        .padding(.horizontal, CP.Space.s)
        .frame(height: 22)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous).strokeBorder(tone.strong.opacity(0.25)))
    }
}

/// Logo: a hexagonal pencil with white/orange faces (orienteering control flag colors) drawing an orange line.
/// The image is rendered by `Tools/render-logo.swift`, the same source as the app icon.
struct AppMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: s, height: s)
                .clipShape(RoundedRectangle(cornerRadius: s * 0.225, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: s * 0.225, style: .continuous).strokeBorder(CP.line, lineWidth: 1))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
