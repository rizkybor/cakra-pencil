import CakraCore
import Foundation

/// Fieldwork stage 2: quick vegetation classification, track → line objects, survey coverage.
extension WorkspaceModel {
    // MARK: Vegetation

    /// Record a runnability class (401–410) at the GPS position (or the map center) as a draft note.
    @discardableResult
    func addVegetationSample(_ v: VegetationClass, atGPS: Bool = true) -> FieldNote? {
        let n = addFieldNote(category: .vegetation, text: "", photos: [], heading: nil, atGPS: atGPS, vegetation: v)
        if n != nil { notice = "\(v.code) \(v.label) noted." }
        return n
    }

    // MARK: Track → line

    /// Line (or area) objects from a track: the part between `start` and `end` (fractions of the recorded length),
    /// split at pause gaps, simplified by `toleranceM`. One undo step for all parts.
    @discardableResult
    func makeObjects(fromTrack id: UUID, symbol s: MapSymbol, start: Double, end: Double, toleranceM: Double) -> Int {
        guard LicenseManager.shared.require(.fieldToMap) else { return 0 }
        guard let t = field.tracks.first(where: { $0.id == id }) else { return 0 }
        guard project.areaLocked else { notice = "Lock the map area first (Map tab)."; return 0 }
        let made = addFieldObjects(parts: t.lineParts(from: start, to: end, toleranceM: toleranceM), symbol: s)
        guard !made.isEmpty else { notice = "Nothing to convert in that part of the track."; return 0 }
        fieldLinePreview = []
        notice = "\(made.count) \(s.code) \(s.name) object\(made.count == 1 ? "" : "s") from \(t.name). Edit, cut or merge them like any object."
        return made.count
    }

    // MARK: Sketch → line / area

    /// Line or area objects from a note's sketch (one undo step): a line symbol makes one line per stroke, an area
    /// symbol one area from the strokes in drawing order. Simplified like a freehand line (0.1 mm on paper). The note
    /// is marked done and linked to the object.
    @discardableResult
    func makeObjects(fromSketchNote id: UUID, symbol s: MapSymbol) -> Int {
        guard LicenseManager.shared.require(.fieldToMap) else { return 0 }
        guard let n = field.notes.first(where: { $0.id == id }), let sketch = n.sketch else { return 0 }
        guard project.areaLocked else { notice = "Lock the map area first (Map tab)."; return 0 }
        let tolerance = project.sheet.groundMeters(forPaperMM: 0.1)
        let strokes = sketch.filter { $0.count >= 2 }
        let parts = s.kind == .area ? [strokes.flatMap { $0 }] : strokes
        let simple = parts.map { $0.count > 2 ? ContourGenerator.simplify($0, tolerance: tolerance) : $0 }
        let made = addFieldObjects(parts: simple, symbol: s, closeTolerance: tolerance * 20)
        guard let last = made.last else {
            notice = s.kind == .area ? "The sketch is too small for an area." : "The sketch has no lines to convert."
            return 0
        }
        updateNote(id) { $0.isDone = true; $0.featureID = last.id }
        notice = "\(made.count) \(s.code) \(s.name) object\(made.count == 1 ? "" : "s") from the sketch. Undo removes \(made.count == 1 ? "it" : "them")."
        return made.count
    }

    /// Lines (or areas, for an area symbol) from point lists, added in one undo step and selected.
    private func addFieldObjects(parts: [[Point2D]], symbol s: MapSymbol, closeTolerance: Double = 1) -> [Feature] {
        var made: [Feature] = []
        let area = s.kind == .area
        for part in parts {
            var pts = part
            if area {
                guard pts.count >= 3 else { continue }
                if let a = pts.first, let b = pts.last, a.distance(to: b) < closeTolerance { pts.removeLast() }
                guard pts.count >= 3 else { continue }
            } else {
                guard pts.count >= 2 else { continue }
            }
            var f = Feature(kind: area ? .area : .line, colorHex: s.colorHex, widthMM: PenPreset.clampWidth(s.drawingWidthMM),
                            nodes: pts.map { BezierNode(point: $0) })
            stamp(&f, with: s, widthMM: PenPreset.clampWidth(s.drawingWidthMM))
            made.append(f)
        }
        guard !made.isEmpty else { return [] }
        for i in made.indices where made[i].name.isEmpty {
            let n = features.filter { $0.symbolCode == s.code }.count + i + 1
            made[i].name = "\(s.code) \(s.name) \(n)"
        }
        editFeatures { $0.append(contentsOf: made) }
        selectedFeatureID = made.last?.id
        selectedNodeIndex = nil
        extraSelectedIDs = Set(made.dropLast().map(\.id))
        return made
    }

    // MARK: Coverage

    func setCoverageVisible(_ on: Bool) {
        guard !on || LicenseManager.shared.require(.trackRecording) else { return }
        updateField { $0.showCoverage = on }
    }
    func setCoverageRadius(_ m: Double) { updateField { $0.coverageRadiusM = m } }

    /// The map frame as a rectangle (UTM), for the coverage percentage.
    var frameRect: Rect2D? {
        frame.map { Rect2D(minX: $0.origin.x, minY: $0.origin.y, maxX: $0.origin.x + $0.widthM, maxY: $0.origin.y + $0.heightM) }
    }
}
