import CakraCore
import Foundation

/// Course planner (seperti Purple Pen / OCAD Course Setting): kontrol dipakai bersama oleh banyak lintasan.
/// Alat Kontrol: ketuk peta = kontrol baru (masuk ke lintasan terpilih), ketuk kontrol yang ada = pakai ulang
/// di lintasan ini, tarik = pindahkan (semua lintasan ikut).
extension WorkspaceModel {
    var selectedCourse: Course? { selectedCourseID.flatMap { courseSet.course($0) } }

    var courseStyle: CourseStyle { .standard(scale: project.sheet.scaleDenominator) }

    /// Overprint yang tampil di peta: lintasan terpilih, atau semua kontrol.
    var currentOverprint: CourseOverprint {
        CourseOverprint.make(courseSet, course: selectedCourse, sheet: project.sheet)
    }

    /// Jari-jari kena-sentuh kontrol (m tanah) = jari-jari lingkaran kontrol (termasuk ukuran pilihan user).
    var controlHitRadiusM: Double {
        project.sheet.groundMeters(forPaperMM: courseStyle.controlDiameterMM / 2 * courseSet.effectiveAppearance.controlScale)
    }

    // MARK: Ukuran simbol (standar IOF = 100%)

    /// Ukuran satu kontrol (pengali; 1 = standar IOF). Satu langkah undo.
    func setControlSize(_ factor: Double, for id: UUID) {
        let k = (min(max(factor, ControlPoint.sizeRange.lowerBound), ControlPoint.sizeRange.upperBound) * 100).rounded() / 100
        updateControl(id) { $0.sizeFactor = abs(k - 1) < 0.001 ? nil : k }
    }

    func stepControlSize(_ delta: Double, for id: UUID) {
        guard let c = courseSet.control(id) else { return }
        setControlSize(c.effectiveSize + delta, for: id)
    }

    /// Ukuran semua simbol lintasan (lingkaran, nomor, garis).
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

    // MARK: PDF lintasan (pratinjau = export)

    /// Peta lintasan + lembar deskripsi, sama persis dengan file PDF export.
    func coursePDFRequest(for course: Course) -> GeoPDFRequest? {
        guard let frame, let zone else { return nil }
        let title = courseSet.eventTitle.isEmpty ? project.name : courseSet.eventTitle
        return GeoPDFRequest(title: "\(title) · \(course.name)", frame: frame, sheet: project.sheet, zone: zone,
                             strokes: sketchVisible ? strokes : [], features: contourExportFeatures + features, grid: project.grid,
                             overprint: CourseOverprint.make(courseSet, course: course, sheet: project.sheet),
                             descriptions: DescriptionSheet(courseSet, course: course))
    }

    // MARK: Halaman Course Planner

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

    /// Pilih alat di rail Course: navigasi, atau tempatkan start/kontrol/finish.
    func useCourseTool(_ kind: ControlKind?) {
        if let kind {
            controlPlacement = kind
            tool = .control
        } else {
            tool = .navigate
        }
    }

    func renumberControls() {
        editCourses { $0 = $0.renumbered() }
        notice = "Kode kontrol dinomori ulang mulai \(courseSet.firstCode)."
    }

    // MARK: Perubahan + undo

    func setCourses(_ next: CourseSet) {
        courseSet = next
        if let id = selectedCourseID, next.course(id) == nil { selectedCourseID = next.courses.first?.id }
        if let id = selectedControlID, next.control(id) == nil { selectedControlID = nil }
        coursesVersion += 1
        scheduleSave()
    }

    /// Satu langkah undo.
    func editCourses(_ change: (inout CourseSet) -> Void) {
        let before = courseSet
        var next = courseSet
        change(&next)
        guard next != before else { return }
        setCourses(next)
        record(.courses(before: before, after: next))
    }

    /// Selama drag: perbarui tanpa undo; `commitCourseEdit(from:)` mencatat satu langkah di akhir.
    func moveControlLive(_ id: UUID, to p: Point2D) {
        guard let i = courseSet.controls.firstIndex(where: { $0.id == id }) else { return }
        courseSet.controls[i].position = p
        onLiveCourseChange?()
    }

    func commitCourseEdit(from before: CourseSet) {
        guard before != courseSet else { return }
        record(.courses(before: before, after: courseSet))
        coursesVersion += 1
        scheduleSave()
    }

    // MARK: Lintasan

    /// Lintasan baru langsung memakai start dan finish yang sudah ada (start/finish bersama, seperti Purple Pen),
    /// jadi tinggal mengetuk kontrol; tanpa start, alat mulai dari Start.
    func addCourse() {
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
        return "Lintasan \(courseSet.courses.count + 1)"
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
        guard var copy = courseSet.course(id) else { return }
        copy.id = UUID()
        copy.name += " (salinan)"
        editCourses { $0.courses.append(copy) }
        selectedCourseID = copy.id
    }

    func setEventTitle(_ title: String) {
        editCourses { $0.eventTitle = title }
    }

    // MARK: Kontrol

    /// Ketuk peta kosong dengan alat Kontrol.
    func placeControl(at p: Point2D) {
        let kind = controlPlacement
        var code: Int?
        if kind == .control {
            guard let next = courseSet.nextFreeCode() else {
                notice = "Kode kontrol 31–255 sudah habis."
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
        // Setelah start, lanjut menempatkan kontrol (seperti Purple Pen).
        if kind == .start { controlPlacement = .control }
    }

    /// Ketuk kontrol yang sudah ada: pakai di lintasan terpilih bila belum ada di sana, lalu pilih.
    func tapControl(_ id: UUID) {
        selectedControlID = id
        guard let c = courseSet.control(id), let course = selectedCourse, !course.controlIDs.contains(id) else { return }
        editCourses { set in
            guard let i = set.courses.firstIndex(where: { $0.id == course.id }) else { return }
            let lookup = set
            Self.insert(c, into: &set.courses[i]) { lookup.control($0)?.kind }
        }
    }

    /// Start di awal (ganti start lama), finish di akhir (ganti finish lama), kontrol sebelum finish.
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

    /// Hapus kontrol dari lintasan terpilih saja (posisi ke-i).
    func removeFromSelectedCourse(at index: Int) {
        guard let cid = selectedCourseID else { return }
        updateCourse(cid) { if $0.controlIDs.indices.contains(index) { $0.controlIDs.remove(at: index) } }
    }

    /// Hapus kontrol dari peta dan semua lintasan.
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

    /// Ganti kode; ditolak bila di luar 31–255 atau sudah dipakai kontrol lain.
    func setCode(_ code: Int, for id: UUID) {
        guard CourseSet.codeRange.contains(code) else {
            notice = "Kode kontrol harus 31–255 (batas unit punching)."
            return
        }
        if let other = courseSet.controls.first(where: { $0.code == code && $0.id != id }) {
            notice = "Kode \(code) sudah dipakai kontrol lain (\(other.label(in: courseSet)))."
            return
        }
        updateControl(id) { $0.code = code }
        if CourseSet.isAmbiguous(code) { notice = "Kode \(code) terbaca lain bila terbalik; sebaiknya diganti." }
    }

    /// Kontrol di dekat titik UTM (untuk alat Kontrol); `radiusM` minimal = jari-jari lingkaran.
    func control(near p: Point2D, radiusM: Double) -> ControlPoint? {
        courseSet.controls
            .map { ($0, $0.position.distance(to: p)) }
            .filter { $0.1 <= max(radiusM, controlHitRadiusM) }
            .min { $0.1 < $1.1 }?.0
    }

    /// Zoom ke semua kontrol lintasan terpilih.
    func zoomToCourse() {
        guard let b = currentOverprint.bounds else { return }
        mapCommand = MapCommand(kind: .zoomToExtent(b))
    }
}
