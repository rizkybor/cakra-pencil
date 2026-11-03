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

    /// Set simbol bawaan yang ikut di bundle app (Resources/SymbolSets): selalu tersedia, tidak bisa dihapus,
    /// hanya bisa dinonaktifkan.
    static let builtInFile = "BOF O_Map 4000 O12 v1_ISSprOM2019-2.ocd"
    static let builtInName = "ISSprOM 2019-2 (bawaan)"

    func isBuiltIn(_ set: SymbolSet) -> Bool { set.sourceFile == Self.builtInFile }

    var builtInSet: SymbolSet? { sets.first(where: isBuiltIn) }

    func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        sets = urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SymbolSet.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let i = sets.firstIndex(where: isBuiltIn) { sets.insert(sets.remove(at: i), at: 0) }
        installBuiltInIfNeeded()
    }

    /// Impor set bawaan dari bundle pada peluncuran pertama (atau bila file JSON-nya hilang).
    /// Parsing ±360 KB berlangsung beberapa milidetik, jadi aman di main thread saat start.
    private func installBuiltInIfNeeded() {
        // Set yang sama pernah diimpor manual: akui sebagai bawaan, seragamkan namanya, pilihan aktif tetap.
        if let existing = builtInSet, existing.name != Self.builtInName {
            update(existing.id) { $0.name = Self.builtInName }
        }
        // Set bawaan tersimpan sebelum bentuk titik / garis ganda dibaca: perbarui dari bundle, pilihan aktif tetap.
        if let existing = builtInSet, existing.needsRefresh,
           let url = Bundle.main.url(forResource: (Self.builtInFile as NSString).deletingPathExtension, withExtension: "ocd"),
           let fresh = try? OcadReader.read(Data(contentsOf: url)).symbolSet(name: Self.builtInName, sourceFile: Self.builtInFile) {
            let disabled = Set(existing.symbols.filter { !$0.isEnabled }.map(\.number))
            update(existing.id) { set in
                set.symbols = fresh.symbols.map { s in
                    var s = s
                    s.isEnabled = !disabled.contains(s.number)
                    return s
                }
            }
        }
        guard builtInSet == nil,
              let url = Bundle.main.url(forResource: (Self.builtInFile as NSString).deletingPathExtension, withExtension: "ocd") else { return }
        do {
            var set = try OcadReader.read(Data(contentsOf: url)).symbolSet(name: Self.builtInName, sourceFile: Self.builtInFile)
            set.isEnabled = true
            // Simbol administratif BOF (nomor < 100: logo, warna bantu, garis skala) bukan simbol pemetaan:
            // nonaktif secara default, tetap bisa diaktifkan di mode Atur.
            for i in set.symbols.indices where set.symbols[i].number < 100_000 { set.symbols[i].isEnabled = false }
            save(set)
            sets.insert(set, at: 0)
        } catch {
            lastError = "Set simbol bawaan gagal dimuat: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
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
            let name = file == Self.builtInFile ? Self.builtInName : url.deletingPathExtension().lastPathComponent
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
        if let i = sets.firstIndex(where: isBuiltIn) { sets.insert(sets.remove(at: i), at: 0) }
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
        guard let set = sets.first(where: { $0.id == id }), !isBuiltIn(set) else { return }
        try? FileManager.default.removeItem(at: url(for: set))
        sets.removeAll { $0.id == id }
    }
}

extension SymbolSet {
    /// Set lama, diimpor sebelum bentuk simbol titik atau gaya garis IOF (garis ganda) dibaca.
    var needsRefresh: Bool {
        let missingPoints = symbols.contains { $0.kind == .point } && !symbols.contains { $0.pointElements != nil }
        let missingLines = symbols.contains { $0.kind == .line } && !symbols.contains { $0.lineStyle != nil }
        return missingPoints || missingLines
    }
}
