import CakraCore
import Foundation

/// Field data between devices (`.occafield`), on iPad and Mac alike: export the tracks, notes and photos (all, or
/// only what is new since the last export), import them into the open project — new data is added, nothing already
/// there is duplicated, the drawing and the work done at the desk (done notes, map objects) are untouched.
extension WorkspaceModel {
    /// `saveTo`: write the file there instead of the save dialog (UI tests).
    func exportFieldData(newOnly: Bool, saveTo target: URL? = nil) async {
        guard LicenseManager.shared.require(.fieldTransfer) else { return }
        guard let zone else { notice = "Lock the map area before exporting field data."; return }
        let since = newOnly ? field.lastExportAt : nil
        let field = self.field, photosDir = url.appendingPathComponent(CakraPackage.fieldPhotosFolder)
        let id = project.id, name = project.name
        let started = Date()
        let result = await Task.detached(priority: .userInitiated) {
            Result { () throws -> Data in
                try FieldPackage.make(field: field, since: since, projectID: id, projectName: name, zone: zone, exportedAt: started) {
                    try? Data(contentsOf: photosDir.appendingPathComponent(($0 as NSString).lastPathComponent))
                }.encoded()
            }
        }.value
        do {
            let data = try result.get()
            let dir = TempExports.newDirectory()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd_HHmm"; return f.string(from: started) }()
            let file = dir.appendingPathComponent("\(projectFileName(name))_field_\(stamp)").appendingPathExtension(FieldPackage.fileExtension)
            try data.write(to: target ?? file, options: .atomic)
            updateField { $0.lastExportAt = started }
            if let target {
                notice = "Field data saved (\(target.lastPathComponent))."
            } else {
                DocumentExport.present(file)
            }
        } catch {
            notice = "Couldn't export field data: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// Add the field data in a `.occafield` file to this project.
    func importFieldData(from fileURL: URL) async {
        guard LicenseManager.shared.require(.fieldTransfer) else { return }
        guard let zone else { notice = "Lock the map area before importing field data."; return }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let decoded = await Task.detached(priority: .userInitiated) {
            Result { () throws -> FieldPackage in
                let size = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                guard size <= 2_000_000_000 else { throw CocoaError(.fileReadTooLarge) }
                return try FieldPackage.decode(Data(contentsOf: fileURL))
            }
        }.value
        let package: FieldPackage
        do { package = try decoded.get() } catch {
            notice = "Couldn't import field data: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            return
        }
        // Data from another zone (another area) is moved into this project's zone.
        let incoming = package.field.reprojected(from: package.manifest.zone, to: zone)
        let dir = url.appendingPathComponent(CakraPackage.fieldPhotosFolder)
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        var next = field
        let r = next.merge(incoming, existingPhotos: existing)
        if !r.newPhotos.isEmpty {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in r.newPhotos {
                guard let data = package.photos[name] else { continue }
                try? data.write(to: dir.appendingPathComponent((name as NSString).lastPathComponent),
                                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        updateField { $0 = next }
        var message = "Field data from \(package.manifest.projectName): \(r.summary)."
        if package.manifest.projectID != project.id { message += " (It came from another project.)" }
        notice = message
        if r.newTracks + r.newNotes > 0 { zoomToFieldData() }
    }
}
