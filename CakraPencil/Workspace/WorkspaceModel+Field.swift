import CakraCore
import Foundation

/// Fieldwork data (tracks, notes, averaged positions): shown on the map and in the Field panel on iPad and Mac.
/// Recording (GPS, camera) happens on iPad; the Mac reviews and processes the same data from the .occa file.
/// Field edits are saved with the project but are not part of the drawing undo history.
extension WorkspaceModel {
    func updateField(_ change: (inout FieldData) -> Void) {
        var next = field
        change(&next)
        guard next != field else { return }
        field = next
        scheduleSave()
    }

    // MARK: Display

    func setTracksVisible(_ on: Bool) { updateField { $0.showTracks = on } }
    func setNotesVisible(_ on: Bool) { updateField { $0.showNotes = on } }

    func setTrackVisible(_ id: UUID, _ on: Bool) {
        updateField { f in if let i = f.tracks.firstIndex(where: { $0.id == id }) { f.tracks[i].isVisible = on } }
    }

    func renameTrack(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        updateField { f in if let i = f.tracks.firstIndex(where: { $0.id == id }) { f.tracks[i].name = n } }
    }

    func deleteTrack(_ id: UUID) { updateField { $0.tracks.removeAll { $0.id == id } } }

    func setNoteDone(_ id: UUID, _ done: Bool) {
        updateField { f in if let i = f.notes.firstIndex(where: { $0.id == id }) { f.notes[i].isDone = done } }
    }

    /// Delete a note and its photo files.
    func deleteNote(_ id: UUID) {
        guard let note = field.notes.first(where: { $0.id == id }) else { return }
        for name in note.photos { try? FileManager.default.removeItem(at: fieldPhotoURL(name)) }
        updateField { $0.notes.removeAll { $0.id == id } }
    }

    func fieldPhotoURL(_ name: String) -> URL {
        url.appendingPathComponent(CakraPackage.fieldPhotosFolder).appendingPathComponent((name as NSString).lastPathComponent)
    }

    // MARK: Zoom

    func zoomToTrack(_ t: FieldTrack) {
        guard let extent = Rect2D(points: t.points.map(\.position)) else { return }
        mapCommand = MapCommand(kind: .zoomToExtent(extent))
    }

    func zoomToNote(_ n: FieldNote) {
        guard let zone else { return }
        mapCommand = MapCommand(kind: .center(zone.unproject(n.position), spanM: 120))
    }

    func zoomToFieldData() {
        guard let b = field.bounds else { return }
        mapCommand = MapCommand(kind: .zoomToExtent(b))
    }

    // MARK: GPX

    /// Import tracks and waypoints from a GPX file (GPS watch, phone app, OOM, QGIS) into this project's field data.
    func importGPX(from fileURL: URL) async {
        guard let zone else { notice = "Lock the map area before importing GPX."; return }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let existing = field.tracks.count
        let name = fileURL.deletingPathExtension().lastPathComponent
        let result = await Task.detached(priority: .userInitiated) {
            Result { () throws -> (tracks: [FieldTrack], notes: [FieldNote]) in
                let size = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                guard size <= 50_000_000 else { throw CocoaError(.fileReadTooLarge) }
                return try GPX.read(Data(contentsOf: fileURL), zone: zone, existingTracks: existing, fileName: name)
            }
        }.value
        switch result {
        case let .success(r):
            updateField { f in
                f.tracks += r.tracks
                f.notes += r.notes
                f.showTracks = true
                f.showNotes = true
            }
            let points = r.tracks.reduce(0) { $0 + $1.points.count }
            notice = "Imported \(r.tracks.count) track\(r.tracks.count == 1 ? "" : "s") (\(points) points) and \(r.notes.count) waypoint\(r.notes.count == 1 ? "" : "s")."
            zoomToFieldData()
        case let .failure(error):
            notice = "Couldn't import GPX: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// Write the field data as GPX and open the save dialog (Files on iPad, a save panel on Mac).
    func exportGPX() {
        guard let zone, !field.isEmpty else { return }
        do {
            let dir = TempExports.newDirectory()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(projectFileName(project.name))_field").appendingPathExtension("gpx")
            try GPX.export(field, zone: zone, name: project.name).write(to: file, atomically: true, encoding: .utf8)
            DocumentExport.present(file)
        } catch {
            notice = "Couldn't export GPX: \(error.localizedDescription)"
        }
    }
}
