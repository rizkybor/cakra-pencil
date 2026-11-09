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
        let parts = t.lineParts(from: start, to: end, toleranceM: toleranceM)
        var made: [Feature] = []
        for part in parts {
            let area = s.kind == .area
            var pts = part
            if area {
                guard pts.count >= 3 else { continue }
                if let a = pts.first, let b = pts.last, a.distance(to: b) < 1 { pts.removeLast() }
            }
            var f = Feature(kind: area ? .area : .line, colorHex: s.colorHex, widthMM: PenPreset.clampWidth(s.drawingWidthMM),
                            nodes: pts.map { BezierNode(point: $0) })
            stamp(&f, with: s, widthMM: PenPreset.clampWidth(s.drawingWidthMM))
            made.append(f)
        }
        guard !made.isEmpty else { notice = "Nothing to convert in that part of the track."; return 0 }
        for i in made.indices where made[i].name.isEmpty {
            let n = features.filter { $0.symbolCode == s.code }.count + i + 1
            made[i].name = "\(s.code) \(s.name) \(n)"
        }
        editFeatures { $0.append(contentsOf: made) }
        selectedFeatureID = made.last?.id
        selectedNodeIndex = nil
        extraSelectedIDs = Set(made.dropLast().map(\.id))
        fieldLinePreview = []
        notice = "\(made.count) \(s.code) \(s.name) object\(made.count == 1 ? "" : "s") from \(t.name). Edit, cut or merge them like any object."
        return made.count
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
