import CakraCore
import Foundation

/// List of .cakra packages in Documents/Projects. The Documents folder is visible in the Files app (UIFileSharingEnabled).
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
            lastError = "Couldn't create project: \(error.localizedDescription)"
            return nil
        }
    }

    func load(_ entry: Entry) -> ProjectDocument? {
        do {
            return try CakraPackage.read(at: entry.url)
        } catch {
            lastError = "Couldn't open project: \(error.localizedDescription)"
            return nil
        }
    }

    /// Bumped whenever a preview is rewritten, so cards reload their image.
    @Published private(set) var thumbnailVersion = 0

    func rename(_ entry: Entry, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var doc = load(entry) else { return }
        doc.project.name = trimmed
        doc.project.updatedAt = Date()
        do {
            try CakraPackage.write(doc, to: entry.url)
        } catch {
            lastError = "Couldn't rename: \(error.localizedDescription)"
        }
        reload()
    }

    /// Copy the whole package (sketch, objects, preview) as a new project.
    func duplicate(_ entry: Entry) {
        guard var doc = load(entry) else { return }
        doc.project.id = UUID()
        doc.project.name = entry.project.name + " (copy)"
        doc.project.createdAt = Date()
        doc.project.updatedAt = Date()
        let target = url(for: doc.project)
        do {
            try CakraPackage.write(doc, to: target)
            // The image basemap (GeoTIFF) is copied too.
            if let file = doc.project.basemapImage?.fileName {
                try? FileManager.default.copyItem(at: entry.url.appendingPathComponent(file), to: target.appendingPathComponent(file))
            }
            let thumb = ProjectThumbnail.url(in: entry.url)
            if FileManager.default.fileExists(atPath: thumb.path) {
                try? FileManager.default.copyItem(at: thumb, to: ProjectThumbnail.url(in: target))
            }
        } catch {
            lastError = "Couldn't duplicate: \(error.localizedDescription)"
        }
        reload()
    }

    /// Regenerate the card preview (imagery + vectors) for one project.
    func refreshThumbnail(_ entry: Entry) async {
        guard let doc = try? CakraPackage.read(at: entry.url), let data = await ProjectThumbnail.render(doc) else { return }
        try? data.write(to: ProjectThumbnail.url(in: entry.url), options: .atomic)
        thumbnailVersion += 1
    }

    // MARK: .cpencil file (iPad ↔ Mac)

    /// Wrap the project package into a single `.cpencil` file (in the background).
    func archive(_ entry: Entry) async -> ProjectFileDocument? {
        let url = entry.url
        do {
            let data = try await Task.detached(priority: .userInitiated) { try ProjectArchive.pack(packageAt: url) }.value
            return ProjectFileDocument(data: data)
        } catch {
            lastError = "Couldn't prepare project file: \(error.localizedDescription)"
            return nil
        }
    }

    /// Import a `.cpencil` file (from Files, Finder, AirDrop, or the Open file dialog). A project with the same id is not
    /// overwritten: the import becomes an "(imported)" copy. Returns the imported project.
    @discardableResult
    func importFile(at url: URL) async -> Entry? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let root = self.root
        let existing = Set(entries.map(\.id))
        do {
            let target = try await Task.detached(priority: .userInitiated) {
                try ProjectArchive.importArchive(Data(contentsOf: url), intoRoot: root, existingIDs: existing)
            }.value
            reload()
            let entry = entries.first { $0.url.standardizedFileURL == target.standardizedFileURL }
            if let entry { await refreshThumbnail(entry) }
            return entry
        } catch {
            lastError = "Couldn't import \(url.lastPathComponent): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            return nil
        }
    }

    func delete(_ entry: Entry) {
        do {
            try FileManager.default.removeItem(at: entry.url)
        } catch {
            lastError = "Couldn't delete: \(error.localizedDescription)"
        }
        reload()
    }
}

/// Autosave: value-type snapshot taken on the main thread, encode + write in the background (budget < 5 ms main thread).
actor ProjectWriter {
    private let url: URL
    private var pending: ProjectDocument?
    private var task: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    /// Debounce 300 ms; consecutive changes within one gesture become a single write.
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
