import CakraCore
import Foundation

/// Course planner (like Purple Pen / OCAD Course Setting): controls are shared by many courses.
/// Control tool: tap the map = new control (added to the selected course), tap an existing control = reuse it
/// in this course, drag = move (all courses follow).
extension WorkspaceModel {
    var selectedCourse: Course? { selectedCourseID.flatMap { courseSet.course($0) } }

    var courseStyle: CourseStyle { .standard(scale: project.sheet.scaleDenominator) }

    /// Overprint shown on the map: the selected course, or all controls.
    var currentOverprint: CourseOverprint {
        CourseOverprint.make(courseSet, course: selectedCourse, sheet: project.sheet)
    }

    /// Control hit-test radius (ground m) = control circle radius (including the user-chosen size).
    var controlHitRadiusM: Double {
        project.sheet.groundMeters(forPaperMM: courseStyle.controlDiameterMM / 2 * courseSet.effectiveAppearance.controlScale)
    }

    // MARK: Symbol size (IOF standard = 100%)

    /// Size of one control (multiplier; 1 = IOF standard). One undo step.
    func setControlSize(_ factor: Double, for id: UUID) {
        let k = (min(max(factor, ControlPoint.sizeRange.lowerBound), ControlPoint.sizeRange.upperBound) * 100).rounded() / 100
        updateControl(id) { $0.sizeFactor = abs(k - 1) < 0.001 ? nil : k }
    }

    func stepControlSize(_ delta: Double, for id: UUID) {
        guard let c = courseSet.control(id) else { return }
        setControlSize(c.effectiveSize + delta, for: id)
    }

    /// Size of all course symbols (circles, numbers, lines).
    func updateAppearance(_ change: (inout CourseAppearance) -> Void) {
        editCourses { set in
            var a = set.effectiveAppearance
            change(&a)
            let r = CourseAppearance.range
            func clamp(_ v: Double) -> Double { (min(max(v, r.lowerBound), r.upperBound) * 100).rounded() / 100 }
            a = CourseAppearance(controlScale: clamp(a.controlScale), numberScale: clamp(a.numberScale), lineScale: clamp(a.lineScale))
            set.appearance = a.isStandard ? nil : a
        }
    }

    func resetAllControlSizes() {
        editCourses { set in
            set.appearance = nil
            for i in set.controls.indices { set.controls[i].sizeFactor = nil }
        }
    }

    // MARK: Course PDF (preview = export)

    /// Course map + description sheet, exactly the same as the exported PDF file.
    /// `course == nil`: "All controls" (master): every control labeled with its code, no legs, descriptions sorted by code.
    func coursePDFRequest(for course: Course?) -> GeoPDFRequest? {
        guard let frame, let zone else { return nil }
        let title = courseSet.eventTitle.isEmpty ? project.name : courseSet.eventTitle
        // Title = event name (or project); the course name has its own field in the title box and descriptions.
        var req = GeoPDFRequest(title: title, frame: frame, sheet: project.sheet, zone: zone,
                             strokes: sketchVisible ? strokes : [], features: layered(contourExportFeatures + features), grid: project.grid,
                             overprint: CourseOverprint.make(courseSet, course: course, sheet: project.sheet),
                             descriptions: DescriptionSheet(courseSet, course: course),
                             printLayout: courseSet.effectivePrintLayout,
                             contourIntervalM: hasContourData && contourSettings.isEnabled ? contourSettings.intervalM : nil,
                             images: courseImageData(for: course))
        // Free plan: small "Made with OCCA" credit (preview and export alike).
        if !LicenseManager.shared.isPro { req.watermark = ExportSheet.freeCredit }
        return req
    }

    /// Print layout of the race map (position and columns of the control descriptions). One undo step.
    func updatePrintLayout(_ change: (inout CoursePrintLayout) -> Void) {
        editCourses { set in
            var l = set.effectivePrintLayout
            change(&l)
            l.descriptionCellMM = min(max((l.descriptionCellMM * 2).rounded() / 2, CoursePrintLayout.cellRangeMM.lowerBound), CoursePrintLayout.cellRangeMM.upperBound)
            set.printLayout = l == CoursePrintLayout() ? nil : l
        }
    }

    // MARK: Course Planner page

    func openCoursePlanner() {
        toolBeforeCourses = tool
        controlPlacement = selectedCourse.map { c in courseSet.controls(of: c).contains { $0.kind == .start } } == false ? .start : .control
        tool = .control
        showsCoursePlanner = true
    }

    func closeCoursePlanner() {
        showsCoursePlanner = false
        let previous = toolBeforeCourses ?? .select
        tool = previous == .control ? .select : previous
    }

    /// Select a tool in the Course rail: navigate, or place start/control/finish.
    func useCourseTool(_ kind: ControlKind?) {
        courseEditMode = .place
        courseItemTool = nil
        if let kind {
            controlPlacement = kind
            tool = .control
        } else {
            tool = .navigate
        }
    }

    /// Course Move Tool: select and move controls and course objects without placing new ones.
    func useCourseMoveTool() {
        courseItemTool = nil
        courseEditMode = .move
        tool = .control
    }

    /// Cut leg tool: gaps in the course line of the open course.
    func useLegGapTool() {
        courseItemTool = nil
        courseEditMode = .legGap
        tool = .control
        if selectedCourse?.kind != .normal { notice = "Open a course (not All controls or a score course) to cut its legs." }
    }

    /// A leg of the open (normal) course near `p`: its controls, the fraction `t` along it, and its geometry.
    struct LegHit {
        var from: UUID, to: UUID
        var t: Double
        var a: Point2D, b: Point2D
        var length: Double
        func point(_ t: Double) -> Point2D { Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        /// Fraction along this leg of the point closest to `p` (0…1).
        func fraction(of p: Point2D) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y
            return max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)))
        }
    }

    func legHit(at p: Point2D, toleranceM: Double) -> LegHit? {
        guard let course = selectedCourse, course.kind == .normal else { return nil }
        let list = courseSet.controls(of: course)
        var best: (hit: LegHit, dist: Double)?
        for (a, b) in zip(list, list.dropFirst()) where a.id != b.id {
            let dx = b.position.x - a.position.x, dy = b.position.y - a.position.y
            let len2 = dx * dx + dy * dy
            guard len2 > 0 else { continue }
            let t = max(0, min(1, ((p.x - a.position.x) * dx + (p.y - a.position.y) * dy) / len2))
            let q = Point2D(x: a.position.x + dx * t, y: a.position.y + dy * t)
            let dist = q.distance(to: p)
            if dist <= toleranceM, dist < (best?.dist ?? .infinity) {
                best = (LegHit(from: a.id, to: b.id, t: t, a: a.position, b: b.position, length: len2.squareRoot()), dist)
            }
        }
        return best?.hit
    }

    /// Cut leg by dragging: a gap from fraction `t1` to `t2` of the leg (any order); gaps it overlaps are replaced.
    /// One undo step.
    func setLegGap(_ leg: LegHit, from t1: Double, to t2: Double) {
        guard let course = selectedCourse else { return }
        let lo = min(t1, t2), hi = max(t1, t2)
        guard hi > lo else { return }
        let mmPerM = 1 / project.sheet.groundMeters(forPaperMM: 1)
        let lengthMM = (hi - lo) * leg.length * mmPerM
        updateCourse(course.id) { c in
            var gaps = (c.legGaps ?? []).filter { g in
                guard g.from == leg.from, g.to == leg.to else { return true }
                let half = project.sheet.groundMeters(forPaperMM: g.lengthMM) / 2 / leg.length
                return g.at + half < lo || g.at - half > hi   // keep gaps that don't overlap the new one
            }
            gaps.append(LegGap(from: leg.from, to: leg.to, at: (lo + hi) / 2, lengthMM: lengthMM))
            c.legGaps = gaps
        }
    }

    /// Cut leg: on a leg of the open course near `p` (within `toleranceM`), add a gap — or remove the gap that is
    /// already there. One undo step. Returns false when no leg is near.
    @discardableResult
    func toggleLegGap(at p: Point2D, toleranceM: Double) -> Bool {
        guard let course = selectedCourse, course.kind == .normal else {
            notice = "Open a course (not All controls or a score course) to cut its legs."
            return false
        }
        guard let hit = legHit(at: p, toleranceM: toleranceM) else { return false }
        let leg = (from: hit.from, to: hit.to, t: hit.t, length: hit.length)
        let gapHalfM = project.sheet.groundMeters(forPaperMM: LegGap.defaultLengthMM) / 2
        updateCourse(course.id) { c in
            var gaps = c.legGaps ?? []
            // Tap on an existing gap of this leg = remove it.
            if let i = gaps.firstIndex(where: { $0.from == leg.from && $0.to == leg.to
                && abs($0.at - leg.t) * leg.length <= max(project.sheet.groundMeters(forPaperMM: $0.lengthMM) / 2, gapHalfM) }) {
                gaps.remove(at: i)
            } else {
                gaps.append(LegGap(from: leg.from, to: leg.to, at: leg.t))
            }
            c.legGaps = gaps.isEmpty ? nil : gaps
        }
        return true
    }

    func renumberControls() {
        editCourses { $0 = $0.renumbered() }
        notice = "Control codes renumbered starting at \(courseSet.firstCode)."
    }

    // MARK: Changes + undo

    func setCourses(_ next: CourseSet) {
        courseSet = next
        if let id = selectedCourseID, next.course(id) == nil { selectedCourseID = next.courses.first?.id }
        if let id = selectedControlID, next.control(id) == nil { selectedControlID = nil }
        if let id = selectedCourseItemID, !next.allItems.contains(where: { $0.id == id }) { selectedCourseItemID = nil }
        coursesVersion += 1
        scheduleSave()
    }

    /// One undo step.
    func editCourses(_ change: (inout CourseSet) -> Void) {
        guard LicenseManager.shared.requireEditing() else { return }
        let before = courseSet
        var next = courseSet
        change(&next)
        guard next != before else { return }
        setCourses(next)
        record(.courses(before: before, after: next))
    }

    /// During a drag: update without undo; `commitCourseEdit(from:)` records one step at the end.
    func moveControlLive(_ id: UUID, to p: Point2D) {
        guard !isReadOnly, let i = courseSet.controls.firstIndex(where: { $0.id == id }) else { return }
        courseSet.controls[i].position = p
        onLiveCourseChange?()
    }

    func commitCourseEdit(from before: CourseSet) {
        guard before != courseSet else { return }
        record(.courses(before: before, after: courseSet))
        coursesVersion += 1
        scheduleSave()
    }

    // MARK: Courses

    /// A new course immediately uses the existing start and finish (shared start/finish, like Purple Pen),
    /// so you only need to tap controls; without a start, the tool begins with Start.
    func addCourse() {
        // Starter: up to FreeLimits.courses courses.
        guard LicenseManager.shared.require(.unlimitedCourses, when: courseSet.courses.count >= FreeLimits.courses) else { return }
        let start = courseSet.controls.first { $0.kind == .start }
        let finish = courseSet.controls.first { $0.kind == .finish }
        let course = Course(name: nextCourseName(), controlIDs: [start?.id, finish?.id].compactMap { $0 })
        editCourses { $0.courses.append(course) }
        selectedCourseID = course.id
        controlPlacement = start == nil ? .start : .control
        tool = .control
    }

    private func nextCourseName() -> String {
        let used = Set(courseSet.courses.map(\.name))
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" where !used.contains(String(letter)) { return String(letter) }
        return "Course \(courseSet.courses.count + 1)"
    }

    func updateCourse(_ id: UUID, _ change: (inout Course) -> Void) {
        editCourses { set in
            guard let i = set.courses.firstIndex(where: { $0.id == id }) else { return }
            change(&set.courses[i])
        }
    }

    func deleteCourse(_ id: UUID) {
        editCourses { $0.courses.removeAll { $0.id == id } }
    }

    func duplicateCourse(_ id: UUID) {
        guard LicenseManager.shared.require(.unlimitedCourses, when: courseSet.courses.count >= FreeLimits.courses) else { return }
        guard var copy = courseSet.course(id) else { return }
        copy.id = UUID()
        copy.name += " (copy)"
        editCourses { $0.courses.append(copy) }
        selectedCourseID = copy.id
    }

    func setEventTitle(_ title: String) {
        editCourses { $0.eventTitle = title }
    }

    func setOrganizer(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard n != (courseSet.organizer ?? "") else { return }
        editCourses { $0.organizer = n.isEmpty ? nil : n }
    }

    // MARK: Controls

    /// Tap an empty spot on the map with the Control tool.
    func placeControl(at p: Point2D) {
        let kind = controlPlacement
        var code: Int?
        if kind == .control {
            guard let next = courseSet.nextFreeCode() else {
                notice = "Control codes 31–255 are all used."
                return
            }
            code = next
        }
        let c = ControlPoint(kind: kind, code: code, position: p)
        editCourses { set in
            set.controls.append(c)
            if let cid = selectedCourseID, let i = set.courses.firstIndex(where: { $0.id == cid }) {
                let lookup = set
                Self.insert(c, into: &set.courses[i]) { lookup.control($0)?.kind }
            }
        }
        selectedControlID = c.id
        // After the start, continue placing controls (like Purple Pen).
        if kind == .start { controlPlacement = .control }
    }

    /// Tap an existing control: use it in the selected course if it isn't there yet, then select it.
    func tapControl(_ id: UUID) {
        selectedControlID = id
        // Only the place mode adds a tapped control to the open course; the Move Tool just selects it.
        guard courseEditMode == .place,
              let c = courseSet.control(id), let course = selectedCourse, !course.controlIDs.contains(id) else { return }
        editCourses { set in
            guard let i = set.courses.firstIndex(where: { $0.id == course.id }) else { return }
            let lookup = set
            Self.insert(c, into: &set.courses[i]) { lookup.control($0)?.kind }
        }
    }

    /// Start at the beginning (replaces the old start), finish at the end (replaces the old finish), controls before the finish.
    static func insert(_ c: ControlPoint, into course: inout Course, kinds: (UUID) -> ControlKind?) {
        var ids = course.controlIDs
        let firstIsStart = ids.first.flatMap(kinds) == .start
        let lastIsFinish = ids.last.flatMap(kinds) == .finish
        switch c.kind {
        case .start:
            if firstIsStart { ids[0] = c.id } else { ids.insert(c.id, at: 0) }
        case .finish:
            if lastIsFinish { ids[ids.count - 1] = c.id } else { ids.append(c.id) }
        case .control:
            if lastIsFinish { ids.insert(c.id, at: ids.count - 1) } else { ids.append(c.id) }
        }
        course.controlIDs = ids
    }

    /// Remove a control from the selected course only (position i).
    func removeFromSelectedCourse(at index: Int) {
        guard let cid = selectedCourseID else { return }
        updateCourse(cid) { if $0.controlIDs.indices.contains(index) { $0.controlIDs.remove(at: index) } }
    }

    /// Delete a control from the map and all courses.
    func deleteControl(_ id: UUID) {
        editCourses { set in
            set.controls.removeAll { $0.id == id }
            for i in set.courses.indices { set.courses[i].controlIDs.removeAll { $0 == id } }
        }
    }

    func moveSelectedCourseControls(from source: IndexSet, to destination: Int) {
        guard let cid = selectedCourseID else { return }
        updateCourse(cid) { $0.controlIDs.move(fromOffsets: source, toOffset: destination) }
    }

    func updateControl(_ id: UUID, _ change: (inout ControlPoint) -> Void) {
        editCourses { set in
            guard let i = set.controls.firstIndex(where: { $0.id == id }) else { return }
            change(&set.controls[i])
        }
    }

    /// Change the code; rejected if outside 31–255 or already used by another control.
    func setCode(_ code: Int, for id: UUID) {
        guard CourseSet.codeRange.contains(code) else {
            notice = "Control code must be 31–255 (punching unit limit)."
            return
        }
        if let other = courseSet.controls.first(where: { $0.code == code && $0.id != id }) {
            notice = "Code \(code) is already used by another control (\(other.label(in: courseSet)))."
            return
        }
        updateControl(id) { $0.code = code }
        if CourseSet.isAmbiguous(code) { notice = "Code \(code) reads differently upside down; consider changing it." }
    }

    /// Control near a UTM point (for the Control tool); minimum `radiusM` = circle radius.
    func control(near p: Point2D, radiusM: Double) -> ControlPoint? {
        courseSet.controls
            .map { ($0, $0.position.distance(to: p)) }
            .filter { $0.1 <= max(radiusM, controlHitRadiusM) }
            .min { $0.1 < $1.1 }?.0
    }

    /// Zoom to all controls of the selected course.
    func zoomToCourse() {
        guard let b = currentOverprint.bounds else { return }
        mapCommand = MapCommand(kind: .zoomToExtent(b))
    }
}

// MARK: Import OCAD course setting

extension WorkspaceModel {
    /// Course page → Import course: controls and courses from an .occa project, an OCAD course setting file, or the
    /// course symbols of an OOM map, placed in this project's zone.
    func importCourseFile(from url: URL) async {
        guard LicenseManager.shared.require(.importMaps) else { return }
        guard let zone, project.areaLocked else {
            notice = "Lock the map area first, then import courses."
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let result = await Task.detached(priority: .userInitiated) { () -> Result<OcadCourseImport, Error> in
            Result {
                let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                guard size <= 200_000_000 else { throw OcadReadError.corrupt("file larger than 200 MB") }
                return try CourseFileImport.read(Data(contentsOf: url), fileExtension: url.pathExtension, zone: zone)
            }
        }.value
        switch result {
        case let .failure(error):
            notice = (error as? LocalizedError)?.errorDescription ?? "Import failed: \(error.localizedDescription)"
        case let .success(c):
            importCourses(c, from: url.lastPathComponent)
        }
    }

    /// Add controls and courses from an OCAD course setting file (one undo step). A control whose code (or start/finish
    /// within 1 m) already exists is reused; a course whose name exists gets " (imported)".
    func importCourses(_ c: OcadCourseImport, from fileName: String) {
        guard !c.controls.isEmpty else {
            notice = "No controls in \(fileName)."
            return
        }
        var added = 0
        editCourses { set in
            var idMap: [UUID: UUID] = [:]
            for control in c.controls {
                let existing = set.controls.first { e in
                    e.kind == control.kind && (control.kind == .control
                        ? e.code != nil && e.code == control.code
                        : e.position.distance(to: control.position) < 1)
                }
                if let existing {
                    idMap[control.id] = existing.id
                } else {
                    var new = control
                    // Controls without a code (e.g. from OOM course symbols) get the next free code.
                    if new.kind == .control, new.code == nil { new.code = set.nextFreeCode() }
                    set.controls.append(new)
                    idMap[control.id] = new.id
                    added += 1
                }
            }
            let names = Set(set.courses.map(\.name))
            for var course in c.courses {
                course.controlIDs = course.controlIDs.compactMap { idMap[$0] }
                if names.contains(course.name) { course.name += " (imported)" }
                set.courses.append(course)
            }
        }
        selectedCourseID = courseSet.courses.last?.id ?? selectedCourseID
        var parts = ["\(c.courses.count) courses and \(added) controls imported from \(fileName)"]
        if added < c.controls.count { parts.append("\(c.controls.count - added) controls already existed") }
        if c.courses.isEmpty { parts.append("the file has no course order — add the controls to a course") }
        if c.skippedDescriptions > 0 { parts.append("control descriptions not converted (re-enter them in Descriptions)") }
        if c.missingReferences > 0 { parts.append("\(c.missingReferences) unknown control references skipped") }
        notice = parts.joined(separator: " · ")
        // Controls outside the locked area don't show on this map: say so clearly (not just in the notice).
        if let frame, let b = Rect2D(points: c.controls.map(\.position)), !frame.extent.intersects(b) {
            let km = frame.center.distance(to: b.center) / 1000
            let dx = b.center.x - frame.center.x, dy = b.center.y - frame.center.y
            courseImportOutside = String(format: "The controls in %@ are %.1f km %@ of this map's locked area, so they don't show on this map — the file was probably made for another map. Undo the import, or keep the courses?",
                                         fileName, km, Self.direction(dx: dx, dy: dy))
        }
    }

    /// The course has controls but none of them lies in the locked map area.
    func isOutsideMap(_ course: Course) -> Bool {
        guard let frame else { return false }
        let pts = courseSet.controls(of: course).map(\.position)
        let e = frame.extent
        return !pts.isEmpty && !pts.contains { (e.minX...e.maxX).contains($0.x) && (e.minY...e.maxY).contains($0.y) }
    }

    /// Compass direction of an offset in grid meters, e.g. "northwest".
    static func direction(dx: Double, dy: Double) -> String {
        let names = ["east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast"]
        let a = atan2(dy, dx) * 180 / .pi
        return names[(Int(((a + 360).truncatingRemainder(dividingBy: 360) + 22.5) / 45) % 8)]
    }
}
