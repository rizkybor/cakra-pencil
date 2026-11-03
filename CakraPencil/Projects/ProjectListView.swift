import CakraCore
import SwiftUI

/// Halaman utama: identitas app, pencarian + urutan, dan kartu proyek dengan pratinjau peta.
/// Setiap kartu punya menu (Buka, Ganti nama, Duplikat, Bagikan, Hapus).
struct ProjectListView: View {
    @EnvironmentObject private var repository: ProjectRepository
    @EnvironmentObject private var symbols: SymbolLibrary
    @State private var showingNew = false
    @State private var open: OpenProject?
    @State private var pendingDelete: ProjectRepository.Entry?
    @State private var renaming: ProjectRepository.Entry?
    @State private var newName = ""
    @State private var query = ""
    @State private var sort = Sort.recent

    struct OpenProject: Identifiable {
        var url: URL
        var document: ProjectDocument
        var id: UUID { document.project.id }
    }

    enum Sort: String, CaseIterable {
        case recent = "Terakhir diubah"
        case name = "Nama"
        case created = "Tanggal dibuat"
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CP.Space.xl) {
                header
                if repository.entries.isEmpty {
                    emptyState
                } else {
                    toolbar
                    if visible.isEmpty {
                        Text("Tidak ada proyek bernama \"\(query)\".")
                            .font(.system(size: 15))
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
        // Kredit selalu di dasar layar, di atas latar halaman.
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
        // Untuk screenshot/UI test: `-cp-open-first` membuka proyek terbaru saat launch.
        .task {
            if ProcessInfo.processInfo.arguments.contains("-cp-open-first"), let entry = repository.entries.first,
               let doc = repository.load(entry) {
                open = OpenProject(url: entry.url, document: doc)
            }
        }
        #endif
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
        .confirmationDialog("Hapus proyek ini?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { entry in
            Button("Hapus \(entry.project.name)", role: .destructive) { repository.delete(entry) }
        } message: { entry in
            Text("Lembar \(entry.project.name) beserta sketsa, objek vektor, dan pengaturan frame-nya dihapus permanen. Tidak bisa dibatalkan.")
        }
        .alert("Ganti nama proyek", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nama proyek", text: $newName)
            Button("Simpan") {
                if let e = renaming { repository.rename(e, to: newName) }
                renaming = nil
            }
            Button("Batal", role: .cancel) { renaming = nil }
        }
        .alert("Terjadi masalah", isPresented: Binding(get: { repository.lastError != nil }, set: { if !$0 { repository.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(repository.lastError ?? "")
        }
    }

    // MARK: Bagian

    private var header: some View {
        HStack(alignment: .center, spacing: CP.Space.l) {
            AppMark()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cakra Pencil")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(CP.ink)
                Text("Petakan medan, presisi di ujung pena.")
                    .font(.system(size: 15))
                    .foregroundStyle(CP.inkMuted)
            }
            Spacer()
            Button {
                showingNew = true
            } label: {
                Label("Proyek baru", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var toolbar: some View {
        HStack(spacing: CP.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Proyek")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CP.ink)
                Text(summary)
                    .font(CP.mono(12))
                    .foregroundStyle(CP.inkMuted)
            }
            Spacer()
            HStack(spacing: CP.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(CP.inkMuted)
                TextField("Cari proyek", text: $query)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, CP.Space.m)
            .frame(width: 260, height: 38)
            .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
            Menu {
                Picker("Urutkan", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CP.ink)
                    .padding(.horizontal, CP.Space.m)
                    .frame(height: 38)
                    .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
            }
        }
    }

    private var credit: some View {
        Text("cakra-pencil 2026 | developer by Rizky Ajie Kurniawan")
            .font(CP.mono(11))
            .foregroundStyle(CP.inkMuted.opacity(0.8))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Kredit: cakra-pencil 2026, developer by Rizky Ajie Kurniawan")
    }

    private var summary: String {
        let all = repository.entries
        let locked = all.filter(\.project.areaLocked).count
        return "\(all.count) lembar · \(locked) terkunci"
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: CP.Space.xl)], spacing: CP.Space.xl) {
            ForEach(visible) { entry in
                ProjectCard(entry: entry, thumbnailVersion: repository.thumbnailVersion,
                            onOpen: { openEntry(entry) },
                            onRename: { newName = entry.project.name; renaming = entry },
                            onDuplicate: { repository.duplicate(entry) },
                            onDelete: { pendingDelete = entry })
                    .task(id: entry.id) {
                        // Proyek lama tanpa pratinjau: buat sekali.
                        if entry.project.frame != nil,
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
            Text("Belum ada lembar peta")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CP.ink)
            Text("Buat proyek, pilih area A4 di atas citra satelit, lalu sketsa dengan Apple Pencil. Hasilnya langsung ter-georeferensi untuk OCAD dan OpenOrienteering Mapper.")
                .font(.system(size: 15))
                .foregroundStyle(CP.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button { showingNew = true } label: { Label("Buat proyek pertama", systemImage: "plus") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func openEntry(_ entry: ProjectRepository.Entry) {
        if let doc = repository.load(entry) { open = OpenProject(url: entry.url, document: doc) }
    }

    /// Setelah workspace ditutup: muat ulang daftar dan perbarui pratinjau proyek yang baru dibuka.
    private func refreshAfterClose() {
        let closedID = open?.id
        repository.reload()
        guard let entry = repository.entries.first(where: { $0.id == closedID }) ?? repository.entries.first else { return }
        Task { await repository.refreshThumbnail(entry) }
    }
}

// MARK: - Kartu proyek

private struct ProjectCard: View {
    let entry: ProjectRepository.Entry
    let thumbnailVersion: Int
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

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
                    badge(project.areaLocked ? "Terkunci" : "Pilih area", symbol: project.areaLocked ? "lock.fill" : "rectangle.dashed",
                          tone: project.areaLocked ? CP.sage : CP.butter)
                    badge("1:\(project.sheet.scaleDenominator)", symbol: nil, tone: CP.Tone(fill: CP.paper, strong: CP.ink))
                }
                .padding(CP.Space.s)
            }
            Rectangle().fill(CP.line).frame(height: 1)
            HStack(alignment: .top, spacing: CP.Space.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CP.ink)
                        .lineLimit(1)
                    Text(project.technicalSummary + " · \(project.sheet.paper.name) \(project.sheet.orientation == .portrait ? "Portrait" : "Landscape")")
                        .font(CP.mono(12))
                        .foregroundStyle(CP.inkMuted)
                        .lineLimit(1)
                    Text("Diubah \(project.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 12))
                        .foregroundStyle(CP.inkMuted)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(action: onOpen) { Label("Buka", systemImage: "arrow.up.right.square") }
                    Button(action: onRename) { Label("Ganti nama", systemImage: "pencil") }
                    Button(action: onDuplicate) { Label("Duplikat", systemImage: "plus.square.on.square") }
                    ShareLink(item: entry.url) { Label("Bagikan .cakra", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive, action: onDelete) { Label("Hapus proyek", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CP.ink)
                        .frame(width: CP.hitTarget, height: CP.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Menu proyek \(project.name)")
            }
            .padding(CP.Space.m)
        }
        .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
        .clipShape(RoundedRectangle(cornerRadius: CP.Radius.panel))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(CP.line))
        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: CP.Radius.panel))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(action: onOpen) { Label("Buka", systemImage: "arrow.up.right.square") }
            Button(action: onRename) { Label("Ganti nama", systemImage: "pencil") }
            Button(action: onDuplicate) { Label("Duplikat", systemImage: "plus.square.on.square") }
            Button(role: .destructive, action: onDelete) { Label("Hapus proyek", systemImage: "trash") }
        }
        .task(id: thumbnailVersion) {
            let url = ProjectThumbnail.url(in: entry.url)
            thumbnail = await Task.detached { UIImage(contentsOfFile: url.path) }.value
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                CP.paper2
                ContourMotif().padding(CP.Space.l)
                if project.frame == nil {
                    Text("Area belum dipilih")
                        .font(.system(size: 13))
                        .foregroundStyle(CP.inkMuted)
                }
            }
        }
    }

    private func badge(_ text: String, symbol: String?, tone: CP.Tone) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(verbatim: text).font(CP.mono(11, weight: .medium))
        }
        .foregroundStyle(tone.strong)
        .padding(.horizontal, CP.Space.s)
        .frame(height: 22)
        .background(tone.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(tone.strong.opacity(0.25)))
    }
}

/// Logo: pensil heksagonal bersisi putih/oranye (warna bendera kontrol orienteering) yang menggores garis oranye.
/// Gambar dirender oleh `Tools/render-logo.swift`, sumber yang sama dengan ikon app.
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
