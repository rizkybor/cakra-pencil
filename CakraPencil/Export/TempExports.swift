import Foundation

/// Exports are written to `tmp/export-<uuid>/` and handed to the Share Sheet / document picker. Those folders were
/// never removed (a 900 dpi map export is ±64 MB), so they piled up on the device. This creates them and clears old
/// ones: all at launch, and on each new export the ones older than 10 minutes (a share may still be reading the
/// newest).
enum TempExports {
    static let prefix = "export-"

    /// A new, empty export folder (older export folders are removed first).
    static func newDirectory() -> URL {
        cleanUp(olderThan: 10 * 60)
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(UUID().uuidString)", isDirectory: true)
    }

    /// Remove export folders (and the symbol set export folder) older than `age` seconds; 0 = all.
    static func cleanUp(olderThan age: TimeInterval = 0) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let items = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in items where url.lastPathComponent.hasPrefix(prefix) || url.lastPathComponent == "SymbolSetExport" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if age == 0 || modified < cutoff { try? fm.removeItem(at: url) }
        }
    }
}
