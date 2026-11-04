import CakraCore
import CoreGraphics
import Foundation

/// Objek tambahan di halaman Course (teks, persegi, ellipse, garis, gambar), seperti "special items" Purple Pen.
/// Disimpan di `courseSet.items`; perubahan memakai undo yang sama dengan kontrol/lintasan.
extension WorkspaceModel {
    var selectedCourseItem: CourseItem? {
        selectedCourseItemID.flatMap { id in courseSet.allItems.first { $0.id == id } }
    }

    /// Pilih alat objek di rail Course (nil = kembali menempatkan kontrol).
    func useCourseItemTool(_ kind: CourseItem.Kind?) {
        courseItemTool = kind
        tool = .control
        selectedControlID = nil
    }

    /// Objek baru tampil di lintasan yang sedang dibuka (atau semua lintasan pada tampilan "Semua kontrol").
    private var newItemScope: UUID? { selectedCourseID }

    func addCourseItem(_ item: CourseItem) {
        editCourses { set in set.items = set.allItems + [item] }
        selectedCourseItemID = item.id
        selectedControlID = nil
    }

    func placeCourseText(at p: Point2D) {
        addCourseItem(CourseItem(kind: .text, points: [p], text: CourseItem.placeholderText, courseID: newItemScope))
        notice = "Teks ditambahkan. Ubah isinya di tab Objek."
    }

    /// Persegi/ellipse dari dua pojok, garis dari titik awal ke akhir.
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

    /// Selama drag: tanpa undo; `commitCourseEdit(from:)` mencatat satu langkah di akhir.
    func moveCourseItemLive(_ original: CourseItem, by d: Point2D) {
        guard var items = courseSet.items, let i = items.firstIndex(where: { $0.id == original.id }) else { return }
        items[i] = original.moved(by: d)
        courseSet.items = items
        onLiveCourseChange?()
    }

    /// Objek paling atas yang kena sentuh (objek di lintasan lain tidak bisa dipilih).
    func courseItem(near p: Point2D, radiusM: Double) -> CourseItem? {
        courseSet.items(for: selectedCourse).reversed().first { $0.hitDistance(to: p, sheet: project.sheet) <= radiusM }
    }

    // MARK: Gambar

    /// Import JPG/PNG: validasi (format, ≤ 10 MB, ≤ 8000 px, maks. 10 gambar), diperkecil ke 2000 px,
    /// disimpan di paket proyek, lalu ditempatkan di tengah peta (lebar 30 mm di kertas) untuk digeser.
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
            notice = "Gambar \(prepared.width)×\(prepared.height) px ditambahkan. Tarik untuk memindah; atur lebar di tab Objek."
        case let .failure(error):
            notice = (error as? LocalizedError)?.errorDescription ?? "Gambar gagal dibaca."
        }
    }

    /// Gambar yang dipakai objek lintasan (dibaca dari paket sekali, lalu disimpan di cache).
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

    /// Isi file gambar untuk PDF/PNG lintasan `course`.
    func courseImageData(for course: Course?) -> [String: Data] {
        var out: [String: Data] = [:]
        for name in Set(courseSet.items(for: course).compactMap(\.imageName)) {
            out[name] = CourseImages.load(name, in: url)
        }
        return out
    }
}
