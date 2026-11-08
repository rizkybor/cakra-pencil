import CakraCore
import CoreGraphics
import Foundation

/// Extra objects on the Course page (text, rectangle, ellipse, line, image), like Purple Pen's "special items".
/// Stored in `courseSet.items`; changes use the same undo as controls/courses.
extension WorkspaceModel {
    var selectedCourseItem: CourseItem? {
        selectedCourseItemID.flatMap { id in courseSet.allItems.first { $0.id == id } }
    }

    /// Select an object tool in the Course rail (nil = back to placing controls).
    func useCourseItemTool(_ kind: CourseItem.Kind?) {
        courseItemTool = kind
        tool = .control
        selectedControlID = nil
    }

    /// A new object appears in the open course (or in all courses in the "All controls" view).
    private var newItemScope: UUID? { selectedCourseID }

    func addCourseItem(_ item: CourseItem) {
        editCourses { set in set.items = set.allItems + [item] }
        selectedCourseItemID = item.id
        selectedControlID = nil
    }

    func placeCourseText(at p: Point2D) {
        addCourseItem(CourseItem(kind: .text, points: [p], text: CourseItem.placeholderText, courseID: newItemScope))
        notice = "Text added. Edit its content in the Object tab."
    }

    /// IOF course point symbol (702 map issue, 710 crossing, 712 first aid, 713 refreshment, 715 map exchange) at `p`.
    func placeCourseSymbol(_ kind: CourseItem.Kind, at p: Point2D) {
        addCourseItem(CourseItem(kind: kind, points: [p], courseID: newItemScope))
        notice = "\(kind.label) added."
    }

    /// Rectangle/ellipse from two corners, line from start point to end point.
    func addCourseShape(_ kind: CourseItem.Kind, from a: Point2D, to b: Point2D) {
        guard a.distance(to: b) > project.sheet.groundMeters(forPaperMM: 1) else { return }
        addCourseItem(CourseItem(kind: kind, points: [a, b], courseID: newItemScope))
    }

    func updateCourseItem(_ id: UUID, _ change: (inout CourseItem) -> Void) {
        editCourses { set in
            guard var items = set.items, let i = items.firstIndex(where: { $0.id == id }) else { return }
            change(&items[i])
            set.items = items
        }
    }

    func deleteCourseItem(_ id: UUID) {
        editCourses { set in
            set.items = set.allItems.filter { $0.id != id }
            if set.items?.isEmpty == true { set.items = nil }
        }
        if selectedCourseItemID == id { selectedCourseItemID = nil }
    }

    /// During a drag: no undo; `commitCourseEdit(from:)` records one step at the end.
    func moveCourseItemLive(_ original: CourseItem, by d: Point2D) {
        guard var items = courseSet.items, let i = items.firstIndex(where: { $0.id == original.id }) else { return }
        items[i] = original.moved(by: d)
        courseSet.items = items
        onLiveCourseChange?()
    }

    /// Topmost object hit by the touch (objects in other courses can't be selected).
    func courseItem(near p: Point2D, radiusM: Double) -> CourseItem? {
        courseSet.items(for: selectedCourse).reversed().first { $0.hitDistance(to: p, sheet: project.sheet) <= radiusM }
    }

    // MARK: Images

    /// Import JPG/PNG: validate (format, ≤ 10 MB, ≤ 8000 px, max. 10 images), downscale to 2000 px,
    /// store in the project package, then place at the map center (30 mm wide on paper) to be moved.
    func importCourseImage(from url: URL, at center: Point2D?) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let used = Set(courseSet.allItems.compactMap(\.imageName))
        guard used.count < CourseImages.maxImagesPerProject else {
            notice = CourseImages.ImageError.tooMany.errorDescription
            return
        }
        let package = self.url
        let id = UUID()
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(String, CourseImages.Prepared), Error> in
            Result {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > CourseImages.maxFileBytes { throw CourseImages.ImageError.tooLarge(bytes: size) }
                let prepared = try CourseImages.prepare(Data(contentsOf: url))
                return (try CourseImages.store(prepared, id: id, in: package), prepared)
            }
        }.value
        switch result {
        case let .success((name, prepared)):
            guard let c = center ?? frame?.center else { return }
            addCourseItem(CourseItem(id: id, kind: .image, points: [c], imageName: name, imageAspect: prepared.aspect,
                                     widthMM: CourseItem.defaultImageWidthMM, courseID: newItemScope))
            notice = "\(prepared.width)×\(prepared.height) px image added. Drag to move; set the width in the Object tab."
        case let .failure(error):
            notice = (error as? LocalizedError)?.errorDescription ?? "Couldn't read the image."
        }
    }

    /// Image used by course objects (read from the package once, then cached).
    var courseImages: [String: CGImage] {
        var out: [String: CGImage] = [:]
        for name in Set(courseSet.allItems.compactMap(\.imageName)) {
            if let img = courseImageCache[name] {
                out[name] = img
            } else if let data = CourseImages.load(name, in: url), let img = CourseImages.cgImage(data) {
                courseImageCache[name] = img
                out[name] = img
            }
        }
        return out
    }

    /// Image file contents for the PDF/PNG of course `course`.
    func courseImageData(for course: Course?) -> [String: Data] {
        var out: [String: Data] = [:]
        for name in Set(courseSet.items(for: course).compactMap(\.imageName)) {
            out[name] = CourseImages.load(name, in: url)
        }
        return out
    }
}
