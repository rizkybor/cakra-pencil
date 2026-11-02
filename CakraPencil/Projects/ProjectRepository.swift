import CakraCore
import Foundation

/// Daftar paket .cakra di Documents/Projects. Folder Documents terlihat di app Files (UIFileSharingEnabled).
@MainActor
final class ProjectRepository: ObservableObject {
    struct Entry: Identifiable, Hashable {
        var url: URL
        var project: Project
        var id: UUID { project.id }
    }

    @Published private(set) var entries: [Entry] = []
    @Published var lastError: String?

    let root: URL

    init(root: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? docs.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        entries = urls
            .filter { $0.pathExtension == CakraPackage.fileExtension }
            .compactMap { url in (try? CakraPackage.readProject(at: url)).map { Entry(url: url, project: $0) } }
            .sorted { $0.project.updatedAt > $1.project.updatedAt }
    }

    func url(for project: Project) -> URL {
        root.appendingPathComponent(project.id.uuidString).appendingPathExtension(CakraPackage.fileExtension)
    }

    func create(_ project: Project) -> Entry? {
        let url = url(for: project)
        do {
            try CakraPackage.write(ProjectDocument(project: project), to: url)
            reload()
            return Entry(url: url, project: project)
        } catch {
            lastError = "Gagal membuat proyek: \(error.localizedDescription)"
            return nil
        }
    }

    func load(_ entry: Entry) -> ProjectDocument? {
        do {
            return try CakraPackage.read(at: entry.url)
        } catch {
            lastError = "Proyek tidak bisa dibuka: \(error.localizedDescription)"
            return nil
        }
    }

    func delete(_ entry: Entry) {
        do {
            try FileManager.default.removeItem(at: entry.url)
        } catch {
            lastError = "Gagal menghapus: \(error.localizedDescription)"
        }
        reload()
    }
}

/// Autosave: snapshot value-type diambil di main thread, encode + tulis di background (budget < 5 ms main thread).
actor ProjectWriter {
    private let url: URL
    private var pending: ProjectDocument?
    private var task: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    /// Debounce 300 ms; perubahan beruntun dalam satu gestur jadi satu tulis.
    func schedule(_ doc: ProjectDocument, onSaved: @escaping @Sendable (Result<Void, Error>) -> Void) {
        pending = doc
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            flush(onSaved: onSaved)
        }
    }

    func flushNow() {
        task?.cancel()
        flush(onSaved: { _ in })
    }

    private func flush(onSaved: @Sendable (Result<Void, Error>) -> Void) {
        guard let doc = pending else { return }
        pending = nil
        onSaved(Result { try CakraPackage.write(doc, to: url) })
    }
}
