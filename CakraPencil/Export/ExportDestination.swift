import Foundation
import UIKit

/// Where exports are saved. Default: the device's Documents, in an OCCA › Exports folder.
/// - iPad: the app's Documents folder, shown in Files as On My iPad › OCCA › Exports.
/// - Mac: ~/Documents/OCCA/Exports (the sandbox allows that folder; see CakraPencilMac.entitlements).
/// The user can pick another folder (Export › Location › Change…); it is kept as a bookmark until reset.
/// Exporters write into a temporary folder first (`TempExports`); `save` moves the finished files here.
enum ExportDestination {
    private static let bookmarkKey = "occa.export.folderBookmark"

    /// The folder exports go to: the chosen one, or the default.
    static var folder: URL { customFolder ?? defaultFolder }

    /// The folder the user picked, nil = default. A folder that no longer exists falls back to the default.
    static var customFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: bookmarkResolution, relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale, let fresh = try? bookmark(for: url) { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
        return url
    }

    /// Remember a folder from the folder picker (a security-scoped URL); nil = back to the default.
    static func setCustomFolder(_ url: URL?) throws {
        guard let url else { UserDefaults.standard.removeObject(forKey: bookmarkKey); return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        UserDefaults.standard.set(try bookmark(for: url), forKey: bookmarkKey)
    }

    private static func bookmark(for url: URL) throws -> Data {
        #if targetEnvironment(macCatalyst)
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private static var bookmarkResolution: URL.BookmarkResolutionOptions {
        #if targetEnvironment(macCatalyst)
        .withSecurityScope
        #else
        []
        #endif
    }

    static var defaultFolder: URL {
        #if targetEnvironment(macCatalyst)
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appendingPathComponent("Documents/OCCA/Exports", isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }

    /// The folder as the user sees it.
    static var displayPath: String {
        if let custom = customFolder {
            let parts = custom.standardizedFileURL.pathComponents.filter { $0 != "/" }
            return parts.suffix(2).joined(separator: " › ")
        }
        return defaultDisplayPath
    }

    static var defaultDisplayPath: String {
        #if targetEnvironment(macCatalyst)
        "Documents › OCCA › Exports"
        #else
        "On My iPad › OCCA › Exports"
        #endif
    }

    /// A file name the user typed, without characters that can't be in a file name. Spaces and letters stay.
    static func cleanFileName(_ s: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let kept = String(String.UnicodeScalarView(s.unicodeScalars.filter { !banned.contains($0) }))
        return kept.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// Moves the files into `folder` and returns their new URLs. When a name is already taken, the whole set gets the
    /// same " 2", " 3"… suffix, so a PDF and its world files keep matching names; nothing is overwritten.
    static func save(_ files: [URL]) throws -> [URL] {
        let fm = FileManager.default
        let dir = folder
        let access = dir.startAccessingSecurityScopedResource()
        defer { if access { dir.stopAccessingSecurityScopedResource() } }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        func target(_ url: URL, _ n: Int) -> URL {
            guard n > 1 else { return dir.appendingPathComponent(url.lastPathComponent) }
            let ext = url.pathExtension
            let stem = url.deletingPathExtension().lastPathComponent
            return dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
        }
        var n = 1
        while files.contains(where: { fm.fileExists(atPath: target($0, n).path) }) { n += 1 }
        // Copy (not move) so a folder on another volume or a cloud drive works too; the temp folder is cleared later.
        return try files.map { url in
            let to = target(url, n)
            try fm.copyItem(at: url, to: to)
            return to
        }
    }

    /// Opens the exports folder in Finder (Mac) or the Files app (iPad).
    @MainActor
    static func reveal() {
        let dir = folder
        let access = dir.startAccessingSecurityScopedResource()
        defer { if access { dir.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #if targetEnvironment(macCatalyst)
        UIApplication.shared.open(dir)
        #else
        if let url = URL(string: "shareddocuments://" + dir.path) { UIApplication.shared.open(url) }
        #endif
    }
}
