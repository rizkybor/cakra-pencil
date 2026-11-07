import CakraCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.cpencil` project file (declared in Config/CakraPencil-Info.plist).
    static let cakraProject = UTType(exportedAs: ProjectArchive.typeIdentifier, conformingTo: .data)
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
