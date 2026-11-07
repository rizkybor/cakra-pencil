import CakraCore
import CoreLocation
import Foundation
import MapKit

/// Tools after the area is locked. Area selection is a separate mode (`isSelectingArea`).
/// `pen` = freehand sketch pencil; `bezier` = vector pen tool (Illustrator style).
enum Tool: String, CaseIterable, Identifiable {
    case navigate, select, node, measure, pen, eraser, point, bezier, freehand, rectangle, ellipse, control

    var id: String { rawValue }

    var label: String {
        switch self {
        case .navigate: return "Navigate"
        case .select: return "Move Tool"
        case .node: return "Node Tool"
        case .measure: return "Measure Tool"
        case .pen: return "Sketch pencil"
        case .eraser: return "Stroke eraser"
        case .point: return "Point symbol"
        case .bezier: return "Pen tool (bezier)"
        case .freehand: return "Freehand"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .control: return "Course control"
        }
    }

    var symbol: String {
        switch self {
        case .navigate: return "hand.raised"
        case .select: return "cursorarrow"
        case .node: return "point.3.filled.connected.trianglepath.dotted"
        case .measure: return "ruler"
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .point: return "smallcircle.filled.circle"
        case .bezier: return "point.topleft.down.to.point.bottomright.curvepath"
        case .freehand: return "scribble"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .control: return "flag"
        }
    }

    var shortcut: Character {
        switch self {
        case .navigate: return "h"
        case .select: return "v"
        case .node: return "a"
        case .measure: return "r"
        case .pen: return "n"
        case .eraser: return "e"
        case .point: return "t"
        case .bezier: return "p"
        case .freehand: return "f"
        case .rectangle: return "m"
        case .ellipse: return "l"
        case .control: return "k"
        }
    }

    /// Tools that use the color + width from the pen dock.
    var draws: Bool { self == .pen || self == .eraser || isVector && !selects }
    var isVector: Bool { selects || self == .point || self == .bezier || self == .freehand || self == .rectangle || self == .ellipse }

    /// Move Tool (select/move whole objects) and Node Tool (edit points & handles) both select objects.
    var selects: Bool { self == .select || self == .node }

    /// Short explanation for the tooltip.
    var hint: String? {
        switch self {
        case .select: return "select, move & duplicate objects; drag on empty space = selection box"
        case .node: return "edit object points & handles"
        case .measure: return "drag to measure distance & azimuth"
        default: return nil
        }
    }

    /// Drawing tools that match the symbol kind.
    func accepts(_ kind: MapSymbol.Kind) -> Bool {
        switch self {
        case .point: return kind == .point
        case .bezier, .freehand: return kind == .line || kind == .area
        case .rectangle, .ellipse: return kind == .area
        case .control: return false
        default: return true
        }
    }
}

enum Basemap: String, CaseIterable, Identifiable {
    case satellite, hybrid, standard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .satellite: return "Satellite"
        case .hybrid: return "Hybrid"
        case .standard: return "Standard"
        }
    }
}

enum SaveState: Equatable {
    case saved, saving, failed(String)
}

/// One-shot camera command from the UI to the map.
struct MapCommand: Equatable {
    enum Kind: Equatable {
        case zoomToFrame
        /// The whole map: frame + all objects, sketches, and courses (including those outside the frame).
        case fitMap
        case center(LatLon, spanM: Double)
        case followUser
        /// Factor > 1 = zoom in.
        case zoom(Double)
        case northUp
        /// The map rotates to follow the iPad's heading (FR-5.2).
        case followHeading
        /// Pan the map by a fraction of the screen (−1…1) right/down; used by the keyboard arrow keys.
        case pan(dx: Double, dy: Double)
        /// Fit a UTM box to the screen (zoom to an object from the layers panel).
        case zoomToExtent(Rect2D)
    }

    let id = UUID()
    let kind: Kind
}

/// Map state that changes every frame (rotation, compass, GPS accuracy). A separate object so only the compass and the
/// location button re-render, not the whole workspace (performance test: rotation 34 → 60 fps).
@MainActor
final class LiveMapState: ObservableObject {
    /// Map heading on screen (degrees from north, clockwise). 0 = north-up.
    @Published var mapHeading: Double = 0
    /// iPad heading from the magnetometer (degrees true north); nil when unavailable (e.g. simulator).
    @Published var deviceHeading: Double?
    /// Last GPS horizontal accuracy (m).
    @Published var myAccuracyM: Double?
}

@MainActor
final class WorkspaceModel: ObservableObject {
    let live = LiveMapState()
    @Published private(set) var project: Project {
        didSet {
            if oldValue.areaLocked != project.areaLocked || oldValue.frame != project.frame || oldValue.crsEPSG != project.crsEPSG {
                refreshImagery()
            }
        }
    }
    @Published private(set) var strokes: [Stroke]
    /// Incremented whenever `strokes` changes, so the map overlay knows when to redraw.
    @Published private(set) var strokesVersion = 0
    /// Vector objects; order = drawing order (last = topmost).
    /// Not @Published: changes are announced via `featuresVersion`, so a drag (updateFeatureLive) can
    /// update the map without re-rendering SwiftUI every frame (performance test: drag 18 → 60 fps).
    private(set) var features: [Feature]
    @Published private(set) var featuresVersion = 0
    /// Called on every object change during a drag; the map overlay updates only that object.
    var onLiveFeatureChange: ((Feature) -> Void)?
    @Published var selectedFeatureID: UUID?
    @Published var selectedNodeIndex: Int?
    /// Other objects also selected (multiple selection); `selectedFeatureID` stays the primary object. See +Selection.
    @Published var extraSelectedIDs: Set<UUID> = []
    /// Pen tool points being drawn (not yet an object).
    @Published private(set) var draftNodes: [BezierNode] = []
    /// Pencil sketch layer as one group in the layers panel.
    @Published var sketchVisible = true
    /// Active symbol from the symbol panel: pen tool/rectangle/ellipse draw with its color, width, and code.
    @Published private(set) var activeSymbol: MapSymbol?
    /// Look up a library symbol by code (set by WorkspaceView), so selecting an object also selects its symbol.
    /// Also determines the objects' Color Hierarchy; when set, the map is redrawn in its color order.
    var symbolLookup: ((String) -> MapSymbol?)? {
        didSet {
            featuresVersion += 1
            upgradeLineStylesFromSymbols()
        }
    }

    /// Line objects created before their symbol style was fully read (e.g. 509.1 Railway without the black layer):
    /// update their style from the symbol set. Only objects with an incomplete style; no undo step.
    func upgradeLineStylesFromSymbols() {
        guard let lookup = symbolLookup else { return }
        var changed = false
        let next = features.map { f -> Feature in
            guard f.kind == .line, let code = f.symbolCode, let style = lookup(code)?.lineStyle, style.casing != nil,
                  f.casingColorHex == nil || (style.innerDashMM != nil && f.innerDashMM == nil) else { return f }
            var g = f
            g.apply(style)
            changed = true
            return g
        }
        if changed { setFeatures(next) }
    }
    /// Line being continued with the pen tool (nil = drawing a new object).
    @Published private(set) var continuingFeatureID: UUID?
    /// Cut tool (OCAD Cut) active for the selected object; areas need two taps (the first point is stored).
    @Published var cutMode = false
    /// Result of the Measure Tool; cleared when switching tools.
    @Published var measurement: MapMeasurement?
    @Published var cutStart: PathPosition?
    /// Existing objects act as guides while drawing (OCAD Follow): the cursor snaps to their outline and the new
    /// shape follows that object. Stored per device.
    /// Always on (no button): a first tap then a second tap on the same object = that object's shape is
    /// followed; the cursor snaps to the outline of existing objects.
    var followGuides: Bool { true }
    /// Automatically merge snapped objects with the same symbol (see WorkspaceModel+Merge). Stored per device.
    /// Always on (no button).
    var autoMerge: Bool { true }
    // Contours (FR-8): elevation data in the project package + computed lines (see WorkspaceModel+Contours).
    @Published var dem: DEMGrid?
    @Published var importedContours: [ContourLine]?
    @Published var contourLines: [ContourLine] = []
    @Published var contourRelief: (min: Double, max: Double)?
    @Published var contourStatus: ContourStatus = .idle
    @Published private(set) var contourVersion = 0
    var contourTask: Task<Void, Never>?
    /// Contours panel → open the export sheet directly in "Contours only" mode.
    @Published var exportContoursOnly = false
    /// Course panel → open the export sheet directly in "Course" mode.
    @Published var exportCourses = false

    // Course planner (see WorkspaceModel+Course).
    /// Controls + courses. Not @Published: changes are announced via `coursesVersion` (control drags stay smooth).
    var courseSet: CourseSet
    @Published var coursesVersion = 0
    /// Called while a control is dragged; the map overlay redraws without going through SwiftUI.
    var onLiveCourseChange: (() -> Void)?
    /// Course shown + edited; nil = "All controls".
    @Published var selectedCourseID: UUID?
    @Published var selectedControlID: UUID?
    /// Kind of point placed by the Control tool.
    @Published var controlPlacement: ControlKind = .control
    /// Course Planner page is open (full screen over the mapping workspace).
    @Published var showsCoursePlanner = false
    /// Map content intensity on the Course page (like Purple Pen's "map intensity"): 0.2–1.
    @Published var courseMapIntensity: Double = 0.6
    /// Workspace tool before opening the Course Planner (restored when it closes).
    var toolBeforeCourses: Tool?
    /// Active course object tool on the Course page (text/shape); nil = placing controls.
    @Published var courseItemTool: CourseItem.Kind?
    @Published var selectedCourseItemID: UUID?
    /// Course object images already read (file name → image), for the map overlay.
    var courseImageCache: [String: CGImage] = [:]

    enum ContourStatus: Equatable {
        case idle, downloading(done: Int, total: Int), importing, generating, failed(String)
    }

    func contoursChanged() { contourVersion += 1 }

    /// Size multiplier of the active symbol; 1 = IOF standard size from the symbol set. Resets to 1 on every symbol change.
    @Published private(set) var symbolSizeFactor: Double = 1
    static let sizeFactorRange: ClosedRange<Double> = 0.25...4
    @Published var tool: Tool {
        didSet {
            guard oldValue != tool else { return }
            cutMode = false
            cutStart = nil
            // Switching tools mid pen tool: save the draft as a line if it has enough points.
            if oldValue == .bezier {
                if draftNodes.count >= 2 { finishDraft(as: .line) } else { cancelDraft() }
            }
            if !tool.isVector { deselect() }
            if tool != .measure { measurement = nil }
            // Node Tool edits one object: a multiple selection is reduced to the primary object.
            if tool == .node { extraSelectedIDs = [] }
            // A symbol that doesn't match the new drawing tool is released (e.g. point symbol + pen tool).
            if let s = activeSymbol, tool != .control, !tool.accepts(s.kind) {
                activeSymbol = nil
                notice = "\(s.code) \(s.name) is a \(s.kind.label.lowercased()) symbol; released for the \(tool.label) tool."
            }
        }
    }
    @Published var pen = PenPreset.isom[0]
    @Published var basemap = Basemap.satellite {
        didSet { if oldValue != basemap { refreshImagery() } }
    }
    /// HD Apple Maps image of the locked area for the current basemap type; shown instead of the live map.
    @Published var imagerySnapshot: ImagerySnapshot?
    /// HD images are being downloaded (all three basemap types after the area is locked).
    @Published var isCapturingImagery = false
    /// Download progress, e.g. "Hybrid 2/3".
    @Published var imageryProgress: String?
    /// Last capture error (e.g. offline); the live map is shown meanwhile.
    @Published var imageryError: String?
    var imageryTask: Task<Void, Never>?
    /// Area (frame corners) the running download is for; switching basemap type doesn't restart it.
    var imageryTaskKey: String?
    @Published var fingerDraws = false
    @Published var showsInspector = true
    @Published private(set) var saveState = SaveState.saved
    @Published var mapCommand: MapCommand?
    @Published var notice: String?
    @Published var confirmUnlock = false
    /// Course page: file picker for Import course (.occa / .ocd / .omap / .xmap).
    @Published var showsCourseImporter = false
    /// Set when imported controls lie outside the locked map area (e.g. a course file made for another map):
    /// the user decides to undo the import or keep it.
    @Published var courseImportOutside: String?
    /// Tool before "Reselect area" (used again on Cancel).
    var toolBeforeReselect: Tool?
    /// The newly imported image basemap doesn't touch the frame: offer to move the frame to the image.
    @Published var confirmMoveFrameToBasemap = false
    @Published var followsHeading = false
    /// GPS position marker (radar + view direction) shown on the map.
    @Published var showsMyLocation = false

    let url: URL
    private let writer: ProjectWriter
    private var undoStack: [Edit] = []
    private var redoStack: [Edit] = []
    private var eraseBuffer: [Stroke] = []
    static let undoLimit = 200

    enum Edit {
        case add([Stroke])
        case remove([Stroke])
        case project(before: Project, after: Project)
        /// Snapshot of the whole vector object list: small enough, and handles add/delete/change/order all at once.
        case features(before: [Feature], after: [Feature])
        case courses(before: CourseSet, after: CourseSet)
    }

    init(document: ProjectDocument, url: URL) {
        self.project = document.project
        self.strokes = document.strokes
        self.features = document.features
        self.courseSet = document.courses
        self.selectedCourseID = document.courses.courses.first?.id
        self.url = url
        self.writer = ProjectWriter(url: url)
        self.tool = .pen
        loadContourData()
        // Course object images no longer referenced by the saved courses.json (deleted in a previous session).
        CourseImages.removeUnused(keeping: Set(document.courses.allItems.compactMap(\.imageName)), in: url)
        refreshImagery()
        #if DEBUG
        // For screenshots/UI tests: `-cp-select-first` selects the topmost object with the Select tool.
        // `-cp-show-location` turns on the position radar; `-cp-fake-heading <degrees>` fakes the compass (the simulator has none).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-cp-show-location") { self.showsMyLocation = true }
        // `-cp-open-course`: open the Course Planner right away (layout screenshot).
        if args.contains("-cp-open-course"), project.areaLocked { DispatchQueue.main.async { self.openCoursePlanner() } }
        if let i = args.firstIndex(of: "-cp-fake-heading"), i + 1 < args.count { self.live.deviceHeading = Double(args[i + 1]) }
        if ProcessInfo.processInfo.arguments.contains("-cp-select-first"), let f = document.features.last {
            self.tool = .node
            self.selectedFeatureID = f.id
            self.selectedNodeIndex = 1
        }
        #endif
    }

    /// While the area is not locked, the workspace is in Select Area mode: the frame stays at the screen center,
    /// and the map is moved underneath it.
    var isSelectingArea: Bool { !project.areaLocked }

    var frame: MapFrame? { project.frame }
    var zone: UTMZone? { project.zone }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Frame (FR-1.3 – FR-1.10)

    /// The frame follows the map center during Select Area mode (called when the map stops moving).
    /// The UTM CRS is chosen automatically from the location (FR-1.2); corners snap to multiples (FR-1.7).
    /// Not recorded in undo history: moving the map is not a data edit.
    func setFrameCenter(_ c: LatLon) {
        guard !project.areaLocked else { return }
        let zone = UTMZone(containing: c)
        var next = project
        next.crsEPSG = zone.epsg
        next.frameOrigin = MapFrame(center: zone.project(c), sheet: project.sheet).snapped(toStep: project.snapStepM).origin
        apply(next, recordUndo: false)
    }

    /// Change the sheet (scale, orientation, margin) keeping the center fixed (FR-1.4, FR-1.5).
    func updateSheet(_ change: (inout SheetSpec) -> Void) {
        var next = project
        change(&next.sheet)
        if let frame, !project.areaLocked {
            next.frameOrigin = frame.resized(to: next.sheet).snapped(toStep: next.snapStepM).origin
        } else if project.areaLocked {
            // Once locked, the extent must not change silently; scale/orientation only before locking.
            notice = "Unlock the area to change the frame size."
            return
        }
        apply(next)
    }

    func setSnapStep(_ step: Int) {
        var next = project
        next.snapStepM = step
        if let frame, !project.areaLocked { next.frameOrigin = frame.snapped(toStep: step).origin }
        apply(next)
    }

    /// North line grid settings; display only, so not recorded in undo history.
    func updateGrid(_ change: (inout NorthGrid) -> Void) {
        var next = project
        var g = project.grid
        change(&g)
        g.spacingM = min(max(g.spacingM, NorthGrid.spacingRangeM.lowerBound), NorthGrid.spacingRangeM.upperBound)
        g.opacity = min(max(g.opacity, 0.05), 1)
        g.declinationDeg = min(max(g.declinationDeg, -30), 30)
        next.northGrid = g
        apply(next, recordUndo: false)
    }

    /// Quick show/hide of the north lines (vertical grid) on the map; settings stay as they are.
    func toggleNorthLines() {
        updateGrid { $0.isEnabled.toggle() }
        let g = project.grid
        notice = g.isEnabled
            ? "North lines shown: every \(Int(g.spacingM)) m, \(g.reference.label.lowercased()). Settings: Map tab → North line grid."
            : "North lines hidden."
    }

    /// Fill opacity of symbol areas on the map (display; export keeps full color). Not recorded in undo.
    func setAreaOpacity(_ value: Double) {
        var next = project
        next.areaOpacity = (min(max(value, 0.1), 1) * 100).rounded() / 100
        apply(next, recordUndo: false)
    }

    /// Display only, so not recorded in undo history.
    func setBasemapOpacity(_ value: Double) {
        var next = project
        next.basemapOpacity = (min(max(value, 0), 1) * 100).rounded() / 100
        apply(next, recordUndo: false)
    }

    func setDPI(_ dpi: Int) {
        var next = project
        next.sketchDPI = dpi
        apply(next)
    }

    /// Box containing the map frame and all visible content (UTM).
    var mapContentExtent: Rect2D? {
        var pts: [Point2D] = frame?.corners ?? []
        for f in features where f.isVisible {
            if let b = f.bounds { pts += [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.maxY)] }
        }
        if sketchVisible { for s in strokes { pts += s.points } }
        pts += courseSet.controls.map(\.position)
        for item in courseSet.allItems {
            if let b = item.bounds(sheet: project.sheet) { pts += [Point2D(x: b.minX, y: b.minY), Point2D(x: b.maxX, y: b.maxY)] }
        }
        return Rect2D(points: pts)
    }

    func lockArea() {
        guard frame != nil else { return }
        var next = project
        next.areaLocked = true
        next.areaBackup = nil
        apply(next)
        tool = .pen
        mapCommand = MapCommand(kind: .zoomToFrame)
    }

    /// Cancel reselecting the area: return to the previously locked area (CRS, frame, sheet, snap); basemap and
    /// other settings are unchanged.
    func cancelReselectArea() {
        guard let saved = project.areaBackup else { return }
        var next = project
        saved.restore(into: &next)
        apply(next)
        tool = toolBeforeReselect ?? .pen
        mapCommand = MapCommand(kind: .zoomToFrame)
        notice = "Reselect area canceled; the previous area is used again."
    }

    /// FR-1.10: once there are sketches, unlocking needs confirmation. Data outside the frame is hidden, not deleted.
    func requestUnlock() {
        if strokes.isEmpty { unlockArea() } else { confirmUnlock = true }
    }

    func unlockArea() {
        // Save the current locked area: until the new area is locked, the user can go back (Cancel).
        var next = project
        if project.areaLocked {
            next.areaBackup = AreaBackup(of: project)
            toolBeforeReselect = tool
        }
        next.areaLocked = false
        apply(next)
        mapCommand = MapCommand(kind: .zoomToFrame)
    }

    // MARK: Sketch (FR-3)

    func addStroke(points: [Point2D]) {
        guard !points.isEmpty else { return }
        let s = Stroke(colorHex: pen.colorHex, widthMM: pen.widthMM, points: points)
        strokes.append(s)
        strokesChanged()
        record(.add([s]))
    }

    /// Delete strokes touched by the eraser; one gesture = one undo step.
    func erase(at p: Point2D, radiusM: Double) {
        let halfWidth = { (s: Stroke) in self.project.sheet.groundMeters(forPaperMM: s.widthMM) / 2 }
        let hit = strokes.filter { s in
            guard let b = s.bounds else { return false }
            let r = radiusM + halfWidth(s)
            guard p.x >= b.minX - r, p.x <= b.maxX + r, p.y >= b.minY - r, p.y <= b.maxY + r else { return false }
            return s.distance(to: p) <= r
        }
        guard !hit.isEmpty else { return }
        let ids = Set(hit.map(\.id))
        strokes.removeAll { ids.contains($0.id) }
        eraseBuffer.append(contentsOf: hit)
        strokesChanged()
    }

    func endErase() {
        guard !eraseBuffer.isEmpty else { return }
        record(.remove(eraseBuffer))
        eraseBuffer = []
    }

    func setPenWidth(_ mm: Double) {
        pen.widthMM = PenPreset.clampWidth(mm)
    }

    func togglePenEraser() {
        tool = tool == .eraser ? .pen : .eraser
    }

    // MARK: Vector objects (FR-4)

    var selectedFeature: Feature? {
        selectedFeatureID.flatMap { id in features.first { $0.id == id } }
    }

    private func setFeatures(_ next: [Feature]) {
        features = next
        if let id = selectedFeatureID, !next.contains(where: { $0.id == id }) {
            selectedFeatureID = nil
            selectedNodeIndex = nil
        }
        if !extraSelectedIDs.isEmpty {
            let ids = Set(next.map(\.id))
            extraSelectedIDs.formIntersection(ids)
            if selectedFeatureID == nil, let first = next.first(where: { extraSelectedIDs.contains($0.id) }) {
                selectedFeatureID = first.id
                extraSelectedIDs.remove(first.id)
            }
        }
        featuresVersion += 1
        scheduleSave()
    }

    /// Change the object list as one undo step.
    func editFeatures(_ change: (inout [Feature]) -> Void) {
        let before = features
        var next = features
        change(&next)
        guard next != before else { return }
        setFeatures(next)
        record(.features(before: before, after: next))
    }

    /// `merge`: a drawn object whose ends/sides are snapped to an object with the same symbol is merged right away
    /// (one undo step together with adding it).
    func addFeature(_ f: Feature, merge: Bool = false) {
        var f = f
        if f.name.isEmpty {
            if let code = f.symbolCode {
                let n = features.filter { $0.symbolCode == code }.count + 1
                f.name = "\(code) \(f.symbolName ?? "") \(n)"
            } else {
                let n = features.filter { $0.kind == f.kind }.count + 1
                f.name = "\(f.kind.label) \(n)"
            }
        }
        var result = f.id
        editFeatures { list in
            list.append(f)
            if merge, autoMerge { result = autoMerged(f.id, in: &list) }
        }
        selectedFeatureID = result
        selectedNodeIndex = nil
        extraSelectedIDs = []
    }

    /// Change one object during a drag without recording undo; `commitFeatureEdit` records one step at the end of the gesture.
    func updateFeatureLive(_ f: Feature) {
        guard let i = features.firstIndex(where: { $0.id == f.id }), features[i] != f else { return }
        features[i] = f
        onLiveFeatureChange?(f)
    }

    /// Replace the object list without recording undo (merging at the end of a gesture; `commitFeatureEdit` records it).
    func setFeaturesForMerge(_ list: [Feature]) {
        features = list
    }

    /// End of gesture: one undo step, then announce the change to SwiftUI (layers panel, toolbar) only once.
    func commitFeatureEdit(from before: [Feature]) {
        guard before != features else { return }
        record(.features(before: before, after: features))
        featuresVersion += 1
        scheduleSave()
    }

    func updateFeature(_ id: UUID, _ change: (inout Feature) -> Void) {
        editFeatures { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            change(&list[i])
        }
    }

    func deleteFeature(_ id: UUID) {
        editFeatures { $0.removeAll { $0.id == id } }
    }

    /// Reorder from the layers panel's point of view (index 0 = topmost).
    func moveFeatures(fromLayerOffsets source: IndexSet, toLayerOffset destination: Int) {
        editFeatures { list in
            var reversed = Array(list.reversed())
            reversed.move(fromOffsets: source, toOffset: destination)
            list = Array(reversed.reversed())
        }
    }

    func deleteSelectedNode() {
        guard let id = selectedFeatureID, let i = selectedNodeIndex, let f = selectedFeature else { return }
        guard f.nodes.count > (f.kind == .area ? 3 : 2) else {
            notice = "\(f.kind.label) needs at least \(f.kind == .area ? 3 : 2) points."
            return
        }
        updateFeature(id) {
            $0.nodes.remove(at: i)
            $0.refreshSmartNodes()
        }
        selectedNodeIndex = nil
    }

    /// Convert to Sharp / Smooth / Smart for the active point.
    func convertSelectedNode(to style: NodeStyle) {
        guard let id = selectedFeatureID, let i = selectedNodeIndex, selectedFeature?.isLocked == false else { return }
        updateFeature(id) { $0.convertNode(at: i, to: style) }
    }

    func applyPenStyleToSelection() {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { f in
            f.colorHex = pen.colorHex
            f.widthMM = pen.widthMM
        }
    }

    func deselect() {
        cutMode = false
        cutStart = nil
        selectedFeatureID = nil
        selectedNodeIndex = nil
        extraSelectedIDs = []
    }

    // MARK: Import OCAD

    /// Read an OCAD (.ocd) or OOM (.omap/.xmap) map in the background, add its objects as vector objects
    /// (one undo step). Used in the workspace and as the background map on the Course page.
    func importOcad(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let zone = self.zone
        enum Imported { case map([Feature], OcadImportReport), courses(OcadCourseImport) }
        let result = await Task.detached(priority: .userInitiated) { () -> Result<Imported, Error> in
            Result {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                // Size limit per the file import policy (PRD: Security).
                guard (attrs[.size] as? Int ?? 0) <= 200_000_000 else { throw OcadReadError.corrupt("file larger than 200 MB") }
                let data = try Data(contentsOf: url)
                switch url.pathExtension.lowercased() {
                case "omap", "xmap":
                    guard let zone else { throw OmapReadError.notGeoreferenced }
                    let (f, r) = try OmapReader.read(data, zone: zone)
                    return .map(f, r)
                default:
                    // OCAD course setting file (controls + courses) → Course Planner, not map objects.
                    let courses = try OcadReader.courses(data)
                    if !courses.controls.isEmpty { return .courses(courses) }
                    let (f, r) = try OcadReader.read(data).features()
                    return .map(f, r)
                }
            }
        }.value
        switch result {
        case let .failure(error):
            notice = (error as? LocalizedError)?.errorDescription ?? "Import failed: \(error.localizedDescription)"
        case let .success(.courses(c)):
            importCourses(c, from: url.lastPathComponent)
        case let .success(.map(imported, report)):
            guard !imported.isEmpty else {
                notice = "No lines or areas in this file."
                return
            }
            editFeatures { $0.append(contentsOf: imported) }
            var parts = ["\(report.imported) objects imported from \(url.lastPathComponent)"]
            if report.skippedPoints > 0 { parts.append("\(report.skippedPoints) point objects skipped") }
            if report.skippedText > 0 { parts.append("\(report.skippedText) texts skipped") }
            if report.droppedHoles > 0 { parts.append("\(report.droppedHoles) area holes ignored") }
            let bounds = Rect2D(points: imported.compactMap(\.bounds).flatMap { [Point2D(x: $0.minX, y: $0.minY), Point2D(x: $0.maxX, y: $0.maxY)] })
            if let b = bounds, let frame, !frame.extent.intersects(b) {
                let km = frame.center.distance(to: b.center) / 1000
                parts.append(String(format: "objects are %.1f km from the locked area — Reselect area to see them", km))
            } else if let b = bounds {
                mapCommand = MapCommand(kind: .zoomToExtent(b))
            }
            notice = parts.joined(separator: " · ")
        }
    }

    // MARK: Symbols

    /// Use a symbol for the next vector objects. The sketch pencil keeps using the regular pen presets.
    func useSymbol(_ s: MapSymbol) {
        activeSymbol = s
        symbolSizeFactor = 1
        pen = PenPreset(name: s.name, colorHex: s.colorHex, widthMM: PenPreset.clampWidth(s.drawingWidthMM))
        // The tool follows the symbol kind: point → tap, line → pen tool, area → pen tool (or rectangle/ellipse).
        switch s.kind {
        case .point: tool = .point
        case .line: tool = .bezier
        case .area: if !(tool == .bezier || tool == .rectangle || tool == .ellipse) { tool = .bezier }
        case .text: break
        }
    }

    /// Change the active symbol size (line/area: the pen width changes too).
    func setSymbolSize(_ factor: Double) {
        symbolSizeFactor = (min(max(factor, Self.sizeFactorRange.lowerBound), Self.sizeFactorRange.upperBound) * 100).rounded() / 100
        if let s = activeSymbol, s.kind != .point {
            pen.widthMM = PenPreset.clampWidth(s.drawingWidthMM * symbolSizeFactor)
        }
    }

    /// Place the active point symbol at position `p` (UTM).
    func placePoint(at p: Point2D) {
        guard let s = activeSymbol, s.kind == .point, let elements = s.pointElements, !elements.isEmpty else {
            notice = "Select a point symbol in the Symbol panel first (e.g. 204.0 Boulder)."
            return
        }
        addFeature(Feature.point(at: p, elements: elements, sizeFactor: symbolSizeFactor, symbolCode: s.code, symbolName: s.name))
    }

    /// Resize the selected object: points via sizeFactor, lines/areas via width.
    func resizeSelected(by step: Double) {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { f in
            if f.kind == .point {
                let k = min(max(f.effectiveSizeFactor * step, Self.sizeFactorRange.lowerBound), Self.sizeFactorRange.upperBound)
                f.sizeFactor = abs(k - 1) < 0.001 ? nil : (k * 100).rounded() / 100
                f.widthMM = (f.pointElements ?? []).diameterMM * f.effectiveSizeFactor
            } else {
                f.setWidth(f.widthMM * step)
            }
        }
    }

    // MARK: Object rotation (0–360°)

    /// One undo step (± buttons, presets).
    func setSelectedRotation(_ degrees: Double) {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { $0.setRotation(degrees) }
    }

    /// While the slider is dragged: update the map live; `commitFeatureEdit(from:)` records undo at the end.
    /// `exactly`: no 0.1° rounding (precise rotation so sides are exactly parallel to other objects).
    func rotateSelectedLive(to degrees: Double, exactly: Bool = false) {
        guard var f = selectedFeature else { return }
        if exactly { f.setRotationExactly(degrees) } else { f.setRotation(degrees) }
        updateFeatureLive(f)
    }

    /// Change the width of the selected line/area in mm (e.g. ±0.01).
    func adjustSelectedWidth(by deltaMM: Double) {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { $0.setWidth($0.widthMM + deltaMM) }
    }

    /// Back to IOF standard size: point = 100%, line/area = the symbol's standard width.
    func resetSelectedSize() {
        guard let id = selectedFeatureID else { return }
        updateFeature(id) { f in
            if f.kind == .point {
                f.sizeFactor = nil
                f.widthMM = (f.pointElements ?? []).diameterMM
            } else if let std = f.standardWidthMM {
                f.setWidth(std)
            }
        }
    }

    func clearSymbol() {
        activeSymbol = nil
    }

    /// Attach the active symbol's code + name to the newly created object.
    func stampActiveSymbol(_ f: inout Feature) {
        guard let s = activeSymbol else { return }
        f.symbolCode = s.code
        f.symbolName = s.name
        // Line: IOF style (including double-line edges), then the user-chosen width; the standard width is stored.
        if f.kind == .line, let style = s.lineStyle {
            f.apply(style)
            f.setWidth(pen.widthMM)
        } else if f.kind != .point {
            f.standardWidthMM = s.drawingWidthMM
        }
    }

    /// IOF standard width of the active line/area symbol.
    var activeStandardWidthMM: Double? {
        guard let s = activeSymbol, s.kind != .point else { return nil }
        return PenPreset.clampWidth(s.drawingWidthMM)
    }

    /// Change the active line symbol width (mm); the size factor follows for the percent display.
    func setSymbolLineWidth(_ mm: Double) {
        pen.widthMM = PenPreset.clampWidth(mm)
        if let std = activeStandardWidthMM, std > 0 { symbolSizeFactor = (pen.widthMM / std * 100).rounded() / 100 }
    }

    // MARK: Pen tool (bezier)

    func appendDraftNode(_ n: BezierNode) {
        draftNodes.append(n)
    }

    /// Pen tool following a guide object: `nodes` starts at the last draft point (its out handle is used).
    func appendFollowedDraft(_ nodes: [BezierNode]) {
        guard let first = nodes.first else { return }
        if let last = draftNodes.indices.last, draftNodes[last].point.distance(to: first.point) < 1e-6 {
            draftNodes[last].outHandle = first.outHandle
            draftNodes += nodes.dropFirst()
        } else {
            draftNodes += nodes
        }
    }

    func updateLastDraftNode(_ n: BezierNode) {
        guard !draftNodes.isEmpty else { return }
        draftNodes[draftNodes.count - 1] = n
    }

    func removeLastDraftNode() {
        _ = draftNodes.popLast()
    }

    func cancelDraft() {
        draftNodes = []
        continuingFeatureID = nil
    }

    /// Like OCAD/OOM: starting to draw at the end of a line with the same symbol → that line is continued, not a new object.
    /// `fromStart` = starting at the first point: point order is reversed so the touched end becomes the draft's last point.
    func beginContinuation(of f: Feature, fromStart: Bool) {
        draftNodes = fromStart
            ? f.nodes.reversed().map { BezierNode(point: $0.point, inHandle: $0.outHandle, outHandle: $0.inHandle) }
            : f.nodes
        continuingFeatureID = f.id
        notice = "Continuing \(f.displayName)"
    }

    /// Turn the draft into an object: a line (≥ 2 points) or closed area (≥ 3 points).
    func finishDraft(as kind: FeatureKind) {
        let minimum = kind == .area ? 3 : 2
        guard draftNodes.count >= minimum else {
            notice = "\(kind.label) needs at least \(minimum) points."
            return
        }
        if let id = continuingFeatureID {
            let nodes = draftNodes
            var result = id
            editFeatures { list in
                guard let i = list.firstIndex(where: { $0.id == id }) else { return }
                list[i].nodes = nodes
                if kind == .area { list[i].kind = .area }
                if autoMerge { result = autoMerged(id, in: &list) }
            }
            selectedFeatureID = result
            draftNodes = []
            continuingFeatureID = nil
            return
        }
        var f = Feature(kind: kind, colorHex: pen.colorHex, widthMM: pen.widthMM, nodes: draftNodes)
        stampActiveSymbol(&f)
        addFeature(f, merge: true)
        draftNodes = []
    }

    /// Freehand: the stroke is simplified (0.1 mm paper tolerance) and becomes a line, or an area if the symbol is an area.
    /// `guideRadiusM`: parts of the stroke running along another object within this distance snap to that object's shape
    /// (when object guides are on).
    func addFreehand(_ points: [Point2D], guideRadiusM: Double = 0) {
        let tolerance = project.sheet.groundMeters(forPaperMM: 0.1)
        var nodes: [BezierNode]
        if followGuides, guideRadiusM > 0 {
            let guides = features.filter { $0.isVisible && $0.kind != .point }
            nodes = GuideTrace.trace(points, guides: guides, radius: guideRadiusM, simplifyTolerance: tolerance)
        } else {
            nodes = ContourGenerator.simplify(points, tolerance: tolerance).map { BezierNode(point: $0) }
        }
        let asArea = activeSymbol?.kind == .area && nodes.count >= 3
        guard nodes.count >= 2 else { return }
        // Area: an end point close to the start point is not repeated (the area closes itself).
        if asArea, let first = nodes.first, let last = nodes.last, first.point.distance(to: last.point) < tolerance * 20 { nodes.removeLast() }
        var f = Feature(kind: asArea ? .area : .line, colorHex: pen.colorHex, widthMM: pen.widthMM, nodes: nodes)
        stampActiveSymbol(&f)
        addFeature(f, merge: true)
    }

    // MARK: Symbol ↔ object (like OCAD/OOM)

    /// Select an object; its symbol is selected in the panel too (without changing the tool).
    func select(_ f: Feature) {
        selectedFeatureID = f.id
        selectedNodeIndex = nil
        extraSelectedIDs = []
        if let code = f.symbolCode, let s = symbolLookup?(code) {
            activeSymbol = s
            symbolSizeFactor = 1
        }
    }

    /// Symbol picked in the panel while an object is selected: store it as the "Change symbol" candidate, tool unchanged.
    func chooseSymbolForSelection(_ s: MapSymbol) {
        activeSymbol = s
        symbolSizeFactor = 1
    }

    /// Replace the selected object's symbol with the active symbol (OOM: Switch symbol). Kinds must match.
    func switchSelectedSymbol() {
        guard let s = activeSymbol else { return }
        switchSelectedSymbol(to: s)
    }

    /// Change the selected object's symbol to `s` (one undo step). `allSame`: all unlocked objects with
    /// the same symbol are changed too (OCAD: Change symbol for all objects of that symbol).
    func switchSelectedSymbol(to s: MapSymbol, allSame: Bool = false) {
        guard let f = selectedFeature, !f.isLocked, f.canSwitch(to: s) else { return }
        let code = f.symbolCode
        var changed = 0, skipped = 0
        editFeatures { list in
            for i in list.indices {
                let target = list[i].id == f.id
                    || (allSame && code != nil && list[i].symbolCode == code && !list[i].isLocked)
                guard target else { continue }
                if list[i].switchSymbol(to: s) { changed += 1 } else { skipped += 1 }
            }
        }
        activeSymbol = s
        symbolSizeFactor = 1
        if allSame {
            notice = "\(changed) objects changed to \(s.code) \(s.name)"
                + (skipped > 0 ? " · \(skipped) skipped (kind doesn't match)." : ".")
        }
    }

    /// Number of (unlocked) objects using the selected object's symbol, including the object itself.
    var sameSymbolCount: Int {
        guard let code = selectedFeature?.symbolCode else { return 0 }
        return features.filter { $0.symbolCode == code && !$0.isLocked }.count
    }

    func canSwitch(_ f: Feature, to s: MapSymbol) -> Bool { f.canSwitch(to: s) }

    /// Finish according to the active symbol: an area symbol closes the path, otherwise it becomes a line.
    func finishDraftForActiveSymbol() {
        finishDraft(as: activeSymbol?.kind == .area ? .area : .line)
    }

    // MARK: Undo / redo

    func undo() {
        guard let edit = undoStack.popLast() else { return }
        invert(edit)
        redoStack.append(edit)
        objectWillChange.send()
    }

    func redo() {
        guard let edit = redoStack.popLast() else { return }
        replay(edit)
        undoStack.append(edit)
        objectWillChange.send()
    }

    private func invert(_ edit: Edit) {
        switch edit {
        case let .add(s):
            let ids = Set(s.map(\.id))
            strokes.removeAll { ids.contains($0.id) }
            strokesChanged()
        case let .remove(s):
            strokes.append(contentsOf: s)
            strokesChanged()
        case let .project(before, _):
            apply(before, recordUndo: false)
        case let .features(before, _):
            setFeatures(before)
        case let .courses(before, _):
            setCourses(before)
        }
    }

    private func replay(_ edit: Edit) {
        switch edit {
        case let .add(s):
            strokes.append(contentsOf: s)
            strokesChanged()
        case let .remove(s):
            let ids = Set(s.map(\.id))
            strokes.removeAll { ids.contains($0.id) }
            strokesChanged()
        case let .project(_, after):
            apply(after, recordUndo: false)
        case let .features(_, after):
            setFeatures(after)
        case let .courses(_, after):
            setCourses(after)
        }
    }

    func record(_ edit: Edit) {
        undoStack.append(edit)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
        redoStack.removeAll()
    }

    func apply(_ next: Project, recordUndo: Bool = true) {
        guard next != project else { return }
        let before = project
        project = next
        if recordUndo { record(.project(before: before, after: next)) }
        scheduleSave()
    }

    private func strokesChanged() {
        strokesVersion += 1
        scheduleSave()
    }

    // MARK: Autosave

    /// The modified date is only written to the file (it doesn't change the @Published `project`), and the save state is
    /// only announced when it changes: an edit no longer triggers two full-screen renders (performance test).
    func scheduleSave() {
        var saved = project
        saved.updatedAt = Date()
        if saveState != .saving { saveState = .saving }
        let doc = ProjectDocument(project: saved, strokes: strokes, features: features, courses: courseSet)
        let writer = writer
        Task { [weak self] in
            await writer.schedule(doc) { [weak self] result in
                Task { @MainActor [weak self] in
                    switch result {
                    case .success: if self?.saveState != .saved { self?.saveState = .saved }
                    case let .failure(error): self?.saveState = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    func flush() async {
        await writer.flushNow()
    }

    // MARK: Location search

    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if let c = CoordinateParser.parse(query) {
            goTo(c)
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                notice = "Location \"\(query)\" not found."
                return
            }
            let c = item.placemark.coordinate
            goTo(LatLon(lat: c.latitude, lon: c.longitude))
        } catch {
            notice = "Search needs internet. Enter lat, lon or UTM coordinates (e.g. 48S 787500 9234500)."
        }
    }

    /// Fly to a location. In Select Area mode the frame follows to the map center; once locked,
    /// the map is restricted to the area, so locations outside the frame are rejected.
    func goTo(_ c: LatLon) {
        if let frame, let zone, project.areaLocked {
            guard frame.extent.insetBy(-50).intersects(Rect2D(points: [zone.project(c)])!) else {
                notice = "Location is outside the locked area. Unlock the area to change location."
                return
            }
            mapCommand = MapCommand(kind: .center(c, spanM: 400))
        } else {
            let s = project.sheet
            mapCommand = MapCommand(kind: .center(c, spanM: max(s.groundWidthM, s.groundHeightM) * 1.8))
        }
    }

    // MARK: Frame info (FR-1.9)

    struct CornerInfo: Identifiable {
        let id: String
        let utm: Point2D
        let latLon: LatLon
    }

    var cornerInfo: [CornerInfo] {
        guard let frame, let zone else { return [] }
        let names = ["Top left", "Top right", "Bottom right", "Bottom left"]
        return zip(names, frame.corners).map { CornerInfo(id: $0, utm: $1, latLon: zone.unproject($1)) }
    }
}
