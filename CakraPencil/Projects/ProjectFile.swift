import CakraCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.cpencil` project file (declared in Config/CakraPencil-Info.plist).
    static let cakraProject = UTType(exportedAs: ProjectArchive.typeIdentifier, conformingTo: .data)
    /// `.occasym` OCCA symbol set (JSON).
    static let occaSymbolSet = UTType(exportedAs: "id.cakrapencil.symbolset", conformingTo: .json)
    /// `.occafield`: field data (tracks, notes, photos) moved between iPad and Mac without the drawing.
    static let occaFieldData = UTType(exportedAs: "id.cakrapencil.fielddata", conformingTo: .data)
}

/// Save a copy of a file with the system document picker (Files on iPad, a save panel on Mac), presented from the
/// topmost view controller.
@MainActor
enum DocumentExport {
    /// Shows the system "save to" picker. Called from a menu, the menu may still be closing: presenting on it fails
    /// silently, so wait for it (a few short retries).
    static func present(_ url: URL, attempt: Int = 0) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene?.windows.first?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        if top.presentedViewController?.isBeingDismissed == true || top.isBeingDismissed {
            guard attempt < 8 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { present(url, attempt: attempt + 1) }
            return
        }
        top.present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), animated: true)
    }
}

/// Contents of a `.cpencil` file for `fileExporter` (Save file) on iPad and Mac.
struct ProjectFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.cakraProject] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A safe file name derived from the project name (no / : etc.).
func projectFileName(_ name: String) -> String {
    let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Project" : cleaned
}
