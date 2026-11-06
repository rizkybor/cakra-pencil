import CakraCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// File proyek `.cpencil` (dideklarasikan di Config/CakraPencil-Info.plist).
    static let cakraProject = UTType(exportedAs: ProjectArchive.typeIdentifier, conformingTo: .data)
}

/// Isi file `.cpencil` untuk `fileExporter` (Simpan file) di iPad dan Mac.
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

/// Nama file yang aman dari nama proyek (tanpa / : dsb.).
func projectFileName(_ name: String) -> String {
    let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Proyek" : cleaned
}
