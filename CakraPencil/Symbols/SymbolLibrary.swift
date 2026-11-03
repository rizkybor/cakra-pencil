import CakraCore
import Foundation

/// Pustaka set simbol (ISOM, ISSprOM, sekolah, ...) yang diimpor dari file OCAD. Tingkat app: sekali impor,
/// dipakai di semua proyek. Tiap set dan tiap simbol bisa diaktifkan/nonaktifkan; yang nonaktif tidak
/// muncul di mode "Pakai" panel simbol.
@MainActor
final class SymbolLibrary: ObservableObject {
    @Published private(set) var sets: [SymbolSet] = []
    @Published var lastError: String?
    @Published private(set) var isImporting = false

    let root: URL

    init(root: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.root = root ?? docs.appendingPathComponent("SymbolSets", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        load()
    }

    var enabledSets: [SymbolSet] { sets.filter(\.isEnabled) }

    func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        sets = urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SymbolSet.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func url(for set: SymbolSet) -> URL {
        root.appendingPathComponent(set.id.uuidString).appendingPathExtension("json")
    }

    private func save(_ set: SymbolSet) {
        do {
            try JSONEncoder().encode(set).write(to: url(for: set), options: .atomic)
        } catch {
            lastError = "Set simbol gagal disimpan: \(error.localizedDescription)"
        }
    }

    /// Impor satu atau beberapa file .ocd. File dengan nama yang sama mengganti set lama, tapi pilihan
    /// aktif/nonaktif per simbol dipertahankan.
    func importOcad(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let file = url.lastPathComponent
            let name = url.deletingPathExtension().lastPathComponent
            let parsed = await Task.detached(priority: .userInitiated) {
                Result { try OcadReader.read(Data(contentsOf: url)).symbolSet(name: name, sourceFile: file) }
            }.value
            switch parsed {
            case var .success(set):
                if let old = sets.first(where: { $0.sourceFile == file }) {
                    set.id = old.id
                    set.isEnabled = old.isEnabled
                    let disabled = Set(old.symbols.filter { !$0.isEnabled }.map(\.number))
                    for i in set.symbols.indices where disabled.contains(set.symbols[i].number) { set.symbols[i].isEnabled = false }
                    sets.removeAll { $0.id == old.id }
                }
                save(set)
                sets.append(set)
            case let .failure(error):
                failures.append("\(file): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
        sets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !failures.isEmpty { lastError = failures.joined(separator: "\n") }
    }

    func update(_ id: UUID, _ change: (inout SymbolSet) -> Void) {
        guard let i = sets.firstIndex(where: { $0.id == id }) else { return }
        change(&sets[i])
        save(sets[i])
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        update(id) { $0.isEnabled = on }
    }

    func setSymbols(_ numbers: Set<Int>, enabled: Bool, in id: UUID) {
        update(id) { set in
            for i in set.symbols.indices where numbers.contains(set.symbols[i].number) { set.symbols[i].isEnabled = enabled }
        }
    }

    func delete(_ id: UUID) {
        guard let set = sets.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: url(for: set))
        sets.removeAll { $0.id == id }
    }
}
