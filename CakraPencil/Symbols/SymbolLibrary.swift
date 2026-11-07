import CakraCore
import Foundation

/// Library of symbol sets (ISOM, ISSprOM, school, ...) imported from OCAD files. App level: import once,
/// used in all projects. Each set and each symbol can be enabled/disabled; disabled ones don't
/// appear in the symbol panel's "Use" mode.
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

    /// Built-in symbol set shipped in the app bundle (Resources/SymbolSets): always available, can't be deleted,
    /// only disabled.
    static let builtInFile = "BOF O_Map 4000 O12 v1_ISSprOM2019-2.ocd"
    static let builtInName = "ISSprOM 2019-2 (built-in)"

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

    /// Import the built-in set from the bundle on first launch (or when its JSON file is missing).
    /// Parsing ±360 KB takes a few milliseconds, so it's safe on the main thread at startup.
    private func installBuiltInIfNeeded() {
        // The same set was imported manually before: treat it as built-in, normalize its name, keep enabled choices.
        if let existing = builtInSet, existing.name != Self.builtInName {
            update(existing.id) { $0.name = Self.builtInName }
        }
        // Built-in set saved before point shapes / double lines were read: refresh from the bundle, keep enabled choices.
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
                set.readerVersion = SymbolSet.currentReaderVersion
            }
        }
        guard builtInSet == nil,
              let url = Bundle.main.url(forResource: (Self.builtInFile as NSString).deletingPathExtension, withExtension: "ocd") else { return }
        do {
            var set = try OcadReader.read(Data(contentsOf: url)).symbolSet(name: Self.builtInName, sourceFile: Self.builtInFile)
            set.isEnabled = true
            // BOF administrative symbols (number < 100: logo, helper colors, scale bar) aren't mapping symbols:
            // disabled by default, can still be enabled in Manage mode.
            for i in set.symbols.indices where set.symbols[i].number < 100_000 { set.symbols[i].isEnabled = false }
            save(set)
            sets.insert(set, at: 0)
        } catch {
            lastError = "Couldn't load built-in symbol set: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func url(for set: SymbolSet) -> URL {
        root.appendingPathComponent(set.id.uuidString).appendingPathExtension("json")
    }

    private func save(_ set: SymbolSet) {
        do {
            try JSONEncoder().encode(set).write(to: url(for: set), options: .atomic)
        } catch {
            lastError = "Couldn't save symbol set: \(error.localizedDescription)"
        }
    }

    /// Import one or more .ocd files. A file with the same name replaces the old set, but the per-symbol
    /// enabled/disabled choices are kept.
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
    /// Created by an older reader: the built-in set is refreshed from the bundle, manually imported sets need re-importing.
    var needsRefresh: Bool { isOutdated }
}
