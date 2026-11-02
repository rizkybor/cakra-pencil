import CakraCore
import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject private var repository: ProjectRepository
    @State private var showingNew = false
    @State private var open: OpenProject?
    @State private var pendingDelete: ProjectRepository.Entry?

    struct OpenProject: Identifiable {
        var url: URL
        var document: ProjectDocument
        var id: UUID { document.project.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if repository.entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(CP.paper2.ignoresSafeArea())
            .navigationTitle("Proyek")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNew = true
                    } label: {
                        Label("Proyek baru", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
        .sheet(isPresented: $showingNew) {
            NewProjectSheet { project in
                if let entry = repository.create(project), let doc = repository.load(entry) {
                    open = OpenProject(url: entry.url, document: doc)
                }
            }
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
        .fullScreenCover(item: $open, onDismiss: repository.reload) { item in
            WorkspaceView(model: WorkspaceModel(document: item.document, url: item.url))
        }
        .confirmationDialog("Hapus proyek ini?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { entry in
            Button("Hapus \(entry.project.name)", role: .destructive) { repository.delete(entry) }
        } message: { _ in
            Text("Sketsa dan pengaturan frame ikut terhapus. Tidak bisa dibatalkan.")
        }
        .alert("Terjadi masalah", isPresented: Binding(get: { repository.lastError != nil }, set: { if !$0 { repository.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(repository.lastError ?? "")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: CP.Space.l)], spacing: CP.Space.l) {
                ForEach(repository.entries) { entry in
                    Button {
                        if let doc = repository.load(entry) { open = OpenProject(url: entry.url, document: doc) }
                    } label: {
                        ProjectRow(project: entry.project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        ShareLink(item: entry.url) { Label("Bagikan .cakra", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { pendingDelete = entry } label: { Label("Hapus", systemImage: "trash") }
                    }
                }
            }
            .padding(CP.Space.xl)
        }
    }

    private var emptyState: some View {
        VStack(spacing: CP.Space.l) {
            ContourMotif()
                .frame(width: 260, height: 180)
            Text("Belum ada proyek")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CP.ink)
            Text("Pilih area A4 di atas citra, atur skala, lalu sketsa dengan Apple Pencil.")
                .font(.system(size: 15))
                .foregroundStyle(CP.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Proyek baru") { showingNew = true }
                .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack {
                Text(project.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CP.ink)
                    .lineLimit(1)
                Spacer()
                if project.areaLocked {
                    Image(systemName: "lock")
                        .foregroundStyle(CP.sage.strong)
                        .accessibilityLabel("Area terkunci")
                }
            }
            Text(project.technicalSummary)
                .font(CP.mono(13))
                .foregroundStyle(CP.inkMuted)
            Text("\(project.sheet.paper.name) \(project.sheet.orientation == .portrait ? "Portrait" : "Landscape") · diubah \(project.updatedAt.formatted(.relative(presentation: .named)))")
                .font(.system(size: 13))
                .foregroundStyle(CP.inkMuted)
        }
        .padding(CP.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cpPanel(floating: false)
    }
}
