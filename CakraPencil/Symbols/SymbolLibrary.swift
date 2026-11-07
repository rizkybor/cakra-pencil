import CakraCore
import Foundation

/// Library of symbol sets (ISOM, ISSprOM, school, ...) from OCAD (.ocd) and OpenOrienteering Mapper (.omap/.xmap)
/// files, plus the built-in sets shipped in the app. App level: import once,
/// used in all projects. Each set and each symbol can be enabled/disabled; disabled ones don't
/// appear in the symbol panel's "Use" mode.
@MainActor
final class SymbolLibrary: ObservableObject {
    @Published private(set) var sets: [SymbolSet] = [] { didSet { preferredCache = [:] } }
    private var preferredCache: [Int: [SymbolSet]] = [:]
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

    /// The other built-in sets: OpenOrienteering Mapper symbol sets (GPL-3.0, © OpenOrienteering Mapper contributors,
    /// github.com/OpenOrienteering/mapper). Course design sets keep only the course symbols 701–799 (OCCA has its own
    /// control description pictograms).
    struct BuiltIn {
        let file: String
        let name: String
        let courseOnly: Bool
    }

    static let openOrienteeringSets: [BuiltIn] = [
        BuiltIn(file: "ISSprOM 2019_4000.omap", name: "ISSprOM 2019-2 · OpenOrienteering", courseOnly: false),
        BuiltIn(file: "ISOM 2017-2_10000.omap", name: "ISOM 2017-2 · OpenOrienteering", courseOnly: false),
        BuiltIn(file: "Course_Design_4000.omap", name: "Course design 1:4000 · OpenOrienteering", courseOnly: true),
        BuiltIn(file: "Course_Design_10000.omap", name: "Course design 1:10000 · OpenOrienteering", courseOnly: true),
    ]

    func isBuiltIn(_ set: SymbolSet) -> Bool {
        set.sourceFile == Self.builtInFile || Self.openOrienteeringSets.contains { $0.file == set.sourceFile }
    }

    /// Built-in order first (BOF, OpenOrienteering sets), then the user's own sets by name.
    private func sortSets() {
        let order = [Self.builtInFile] + Self.openOrienteeringSets.map(\.file)
        sets.sort { a, b in
            let ia = order.firstIndex(of: a.sourceFile) ?? Int.max, ib = order.firstIndex(of: b.sourceFile) ?? Int.max
            return ia != ib ? ia < ib : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Enabled sets for a map of `scale`, best first — same scale, then the same IOF standard, map sets before course
    /// design sets, built-in order otherwise — each sized for the map (e.g. the ISOM 1:10000 set × 0.667 on a 1:15000
    /// map). Cached per scale; used for the default set and for looking up an object's symbol.
    func preferredSets(forMapScale scale: Int) -> [SymbolSet] {
        if let cached = preferredCache[scale] { return cached }
        let standard = MapStandard.for(scale: scale)
        func tier(_ s: SymbolSet) -> Int {
            let base = s.scale == scale ? 0 : (s.standard == standard ? 1 : 2)
            return base + (s.isCourseDesign ? 3 : 0)
        }
        let list = enabledSets.enumerated()
            .sorted { tier($0.element) != tier($1.element) ? tier($0.element) < tier($1.element) : $0.offset < $1.offset }
            .map { $0.element.scaled(by: $0.element.sizeFactor(forMapScale: scale)) }
        preferredCache[scale] = list
        return list
    }

    /// Bundle file (flat or in its Resources subfolder).
    static func bundleURL(_ file: String) -> URL? {
        let name = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "OpenOrienteering")
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "SymbolSets/OpenOrienteering")
    }

    /// Reads a symbol set file by extension: OCAD .ocd, or OpenOrienteering Mapper .omap / .xmap.
    nonisolated static func readSet(_ data: Data, file: String, name: String, courseOnly: Bool = false) throws -> SymbolSet {
        switch (file as NSString).pathExtension.lowercased() {
        case "omap", "xmap":
            return try OmapSymbolSet.read(data, name: name, sourceFile: file, codeFilter: courseOnly ? { (700...799).contains($0) } : nil)
        default:
            return try OcadReader.read(data).symbolSet(name: name, sourceFile: file)
        }
    }

    /// The BOF ISSprOM set (the original built-in set).
    var builtInSet: SymbolSet? { sets.first { $0.sourceFile == Self.builtInFile } }

    func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        sets = urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SymbolSet.self, from: Data(contentsOf: $0)) }
        installBuiltInIfNeeded()
        installOpenOrienteeringSets()
        sortSets()
    }

    /// Install the OpenOrienteering sets on first launch (or when missing / read by an older reader, keeping the
    /// user's enabled choices). Each file is ±300 KB of XML, parsed in a few tens of milliseconds.
    private func installOpenOrienteeringSets() {
        for b in Self.openOrienteeringSets {
            let existing = sets.first { $0.sourceFile == b.file }
            if let existing, !existing.needsRefresh { continue }
            guard let url = Self.bundleURL(b.file) else { continue }
            do {
                var set = try Self.readSet(Data(contentsOf: url), file: b.file, name: b.name, courseOnly: b.courseOnly)
                if let existing {
                    set.id = existing.id
                    set.isEnabled = existing.isEnabled
                    let disabled = Set(existing.symbols.filter { !$0.isEnabled }.map(\.number))
                    for i in set.symbols.indices where disabled.contains(set.symbols[i].number) { set.symbols[i].isEnabled = false }
                    sets.removeAll { $0.id == existing.id }
                }
                save(set)
                sets.append(set)
            } catch {
                lastError = "Couldn't load built-in symbol set \(b.name): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            }
        }
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

    /// Import one or more symbol set files (.ocd, .omap, .xmap). A file with the same name replaces the old set, but
    /// the per-symbol enabled/disabled choices are kept. Built-in sets can't be replaced.
    func importOcad(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        var failures: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let file = url.lastPathComponent
            if Self.openOrienteeringSets.contains(where: { $0.file == file }) { continue }   // already built in
            let name = file == Self.builtInFile ? Self.builtInName : url.deletingPathExtension().lastPathComponent
            let parsed = await Task.detached(priority: .userInitiated) {
                Result { try Self.readSet(Data(contentsOf: url), file: file, name: name) }
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
        sortSets()
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
