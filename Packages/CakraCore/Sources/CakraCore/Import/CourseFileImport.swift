import Foundation

/// "Import course" on the Course page: controls and courses from another file, placed in the current project's zone.
///
/// - `.occa` (and older `.coca` / `.cpencil`): the courses of that project, with control descriptions; positions are
///   converted when that project uses another UTM zone. Course objects (text, shapes, images) are not copied.
/// - `.ocd`: an OCAD course setting file (`OcadReader.courses`).
/// - `.omap` / `.xmap`: OOM has no course data, so start (701), control (702), and finish (706) symbols drawn on the map
///   become controls (without codes or course order).
public enum CourseFileImport {
    public static var fileExtensions: [String] { ProjectArchive.acceptedExtensions + ["ocd", "omap", "xmap"] }

    public enum ImportError: Error, LocalizedError, Equatable {
        case noCourses(String)
        case unsupportedExtension(String)

        public var errorDescription: String? {
            switch self {
            case let .noCourses(why): return why
            case let .unsupportedExtension(e): return "Unsupported course file (.\(e)). Use .occa, .ocd, .omap, or .xmap."
            }
        }
    }

    public static func read(_ data: Data, fileExtension: String, zone: UTMZone) throws -> OcadCourseImport {
        let ext = fileExtension.lowercased()
        let result: OcadCourseImport
        if ProjectArchive.acceptedExtensions.contains(ext) {
            result = try fromProjectArchive(data, zone: zone)
        } else if ext == "ocd" {
            result = try OcadReader.courses(data)
            guard !result.controls.isEmpty else {
                throw ImportError.noCourses("This OCAD file has no course setting data (it is a map). Use Import map for maps.")
            }
        } else if ext == "omap" || ext == "xmap" {
            result = try OmapReader.courseControls(data, zone: zone)
            guard !result.controls.isEmpty else {
                throw ImportError.noCourses("No course symbols (701 start, 702 control, 706 finish) in this OOM map.")
            }
        } else {
            throw ImportError.unsupportedExtension(ext)
        }
        return result
    }

    static func fromProjectArchive(_ data: Data, zone: UTMZone) throws -> OcadCourseImport {
        let entries = try ProjectArchive.entries(of: data)
        guard let projectData = entries[CakraPackage.projectFile] else { throw ProjectArchive.ArchiveError.missingProject }
        let project = try CakraPackage.decoder().decode(Project.self, from: projectData)
        guard let coursesData = entries[CakraPackage.coursesFile],
              let set = try? CakraPackage.decoder().decode(CakraPackage.CoursesEnvelope.self, from: coursesData).courses,
              !set.controls.isEmpty else {
            throw ImportError.noCourses("“\(project.name)” has no controls or courses.")
        }
        // Same place on the ground in the current project's zone.
        let source = project.zone ?? zone
        func convert(_ p: Point2D) -> Point2D { source == zone ? p : zone.project(source.unproject(p)) }
        var ids: [UUID: UUID] = [:]
        let controls = set.controls.map { c -> ControlPoint in
            var copy = c
            copy.id = UUID()
            copy.position = convert(c.position)
            ids[c.id] = copy.id
            return copy
        }
        let courses = set.courses.map { c -> Course in
            var copy = c
            copy.id = UUID()
            copy.controlIDs = c.controlIDs.compactMap { ids[$0] }
            return copy
        }
        return OcadCourseImport(controls: controls, courses: courses, skippedDescriptions: 0, missingReferences: 0)
    }
}
