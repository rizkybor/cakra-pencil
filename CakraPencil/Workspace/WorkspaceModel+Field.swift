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

    func updateNote(_ id: UUID, _ change: (inout FieldNote) -> Void) {
        updateField { f in if let i = f.notes.firstIndex(where: { $0.id == id }) { change(&f.notes[i]) } }
    }

    /// Delete a note and its photo files.
    func deleteNote(_ id: UUID) {
        guard let note = field.notes.first(where: { $0.id == id }) else { return }
        if openFieldNoteID == id { openFieldNoteID = nil }
        for name in note.photos { try? FileManager.default.removeItem(at: fieldPhotoURL(name)) }
        updateField { $0.notes.removeAll { $0.id == id } }
    }

    func fieldPhotoURL(_ name: String) -> URL {
        url.appendingPathComponent(CakraPackage.fieldPhotosFolder).appendingPathComponent((name as NSString).lastPathComponent)
    }

    // MARK: Notes → map objects

    /// Show a note in detail (Field panel or field-mode sheet) and center the map on it.
    func openFieldNote(_ id: UUID?, zoom: Bool = true) {
        openFieldNoteID = id
        if zoom, let id, let n = field.notes.first(where: { $0.id == id }) { zoomToNote(n) }
    }

    /// The map object made from the note, if it still exists (it may have been deleted or undone).
    func noteFeature(_ n: FieldNote) -> Feature? {
        n.featureID.flatMap { id in features.first { $0.id == id } }
    }

    /// Point symbol: the object is placed at the note's position (one undo step), the note is marked done and linked
    /// to it. Line / area symbol: the symbol is picked and the map centered on the note, to draw it from there.
    func makeObject(fromNote id: UUID, symbol s: MapSymbol) {
        guard let n = field.notes.first(where: { $0.id == id }) else { return }
        guard project.areaLocked else { notice = "Lock the map area first (Map tab)."; return }
        if s.kind == .point {
            guard let elements = s.pointElements, !elements.isEmpty else { return }
            let f = Feature.point(at: n.position, elements: elements, symbolCode: s.code, symbolName: s.name)
            addFeature(f)
            updateNote(id) { $0.isDone = true; $0.featureID = f.id }
            zoomToNote(n)
            notice = "\(s.code) \(s.name) placed at the note. Undo removes it."
        } else {
            useSymbol(s)
            zoomToNote(n)
            notice = "Draw the \(s.name.lowercased()) from the note, then mark the note as done."
        }
    }

    /// Select the object made from the note and center the map on it.
    func showNoteObject(_ n: FieldNote) {
        guard let f = noteFeature(n) else { return }
        tool = .select
        selectedFeatureID = f.id
        selectedNodeIndex = nil
        extraSelectedIDs = []
        zoomToNote(n)
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

// MARK: - Recording (iPad)

extension WorkspaceModel {
    /// Start recording a new track (named "Track n", next palette color).
    func startTrackRecording() {
        guard zone != nil, !recorder.isRecording else { return }
        let track = FieldTrack(name: field.nextTrackName(), colorHex: field.nextTrackColor)
        updateField { f in
            f.tracks.append(track)
            f.showTracks = true
        }
        recorder.onTrackPoint = { [weak self] p in self?.appendTrackPoint(p, to: track.id) }
        recorder.startTrack(id: track.id)
    }

    func pauseTrackRecording() {
        recorder.pause()
        scheduleSave()
    }

    func resumeTrackRecording() { recorder.resume() }

    /// Stop recording; a track with fewer than 2 points is removed.
    func stopTrackRecording() {
        guard let id = recorder.recordingTrackID else { return }
        recorder.stopTrack()
        recorder.onTrackPoint = nil
        if let t = field.tracks.first(where: { $0.id == id }), t.points.count < 2 {
            updateField { $0.tracks.removeAll { $0.id == id } }
            notice = "Track not saved: no GPS points were recorded."
        } else {
            scheduleSave()
            if let t = field.tracks.first(where: { $0.id == id }) {
                notice = "\(t.name) saved: \(FieldPanel.trackSummary(t))."
            }
        }
    }

    /// GPS point while recording: kept in memory right away (map + panel), written to disk every 10 points (and on
    /// pause/stop) so long walks don't rewrite the project file every second.
    private func appendTrackPoint(_ p: FieldTrack.Point, to id: UUID) {
        guard let i = field.tracks.firstIndex(where: { $0.id == id }) else { return }
        field.tracks[i].points.append(p)
        if field.tracks[i].points.count % 10 == 0 { scheduleSave() }
    }

    // MARK: Notes

    /// Position for a new note: the current GPS fix (with its accuracy), else the map center.
    var noteGPSPosition: (Point2D, Double)? { recorder.currentPosition }

    var mapCenterPosition: Point2D? {
        guard let zone, let c = live.mapCenter else { return nil }
        return zone.project(c)
    }

    /// Add a field note; `photos` are JPEG data (already downscaled), saved in the package's field-photos folder.
    @discardableResult
    func addFieldNote(category: FieldNote.Category, text: String, photos: [Data], heading: Double?,
                      atGPS: Bool, averaging: FieldNote.Averaging? = nil, position override: Point2D? = nil,
                      offset: (bearingDeg: Double, distanceM: Double, paces: Double?)? = nil,
                      vegetation: VegetationClass? = nil) -> FieldNote? {
        let gps = atGPS ? noteGPSPosition : nil
        guard let standing = override ?? gps?.0 ?? mapCenterPosition else {
            notice = "No position for the note: wait for GPS or move the map."
            return nil
        }
        // Bearing + distance: the note goes to the target, the standing position is kept with it.
        var fieldOffset: FieldOffset?
        var position = standing
        if let o = offset, o.distanceM > 0, let zone {
            let f = FieldOffset(from: standing, bearingDeg: o.bearingDeg, distanceM: o.distanceM, paces: o.paces)
            fieldOffset = f
            position = f.target(zone: zone)
        }
        var names: [String] = []
        let dir = url.appendingPathComponent(CakraPackage.fieldPhotosFolder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for data in photos {
            let name = "\(UUID().uuidString).jpg"
            do {
                try data.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                names.append(name)
            } catch {
                notice = "Couldn't save the photo: \(error.localizedDescription)"
            }
        }
        let note = FieldNote(position: position, category: category, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                             photos: names, photoHeadingDeg: names.isEmpty ? nil : heading,
                             accuracyM: override == nil ? gps?.1 : averaging?.accuracyM, averaging: averaging,
                             offset: fieldOffset, vegetation: vegetation)
        updateField { f in
            f.notes.append(note)
            f.showNotes = true
        }
        return note
    }

    /// Save the finished averaging as a note (exact averaged position).
    func saveAveragedPosition(category: FieldNote.Category, text: String) {
        guard let r = recorder.averagingResult else { return }
        addFieldNote(category: category, text: text, photos: [], heading: nil, atGPS: false,
                     averaging: .init(samples: r.samples, accuracyM: r.accuracyM, durationS: r.durationS), position: r.position)
        recorder.clearAveragingResult()
        notice = "Averaged position saved (±\(Fmt.number(r.accuracyM, decimals: 1)) m, \(r.samples) fixes)."
    }
}
