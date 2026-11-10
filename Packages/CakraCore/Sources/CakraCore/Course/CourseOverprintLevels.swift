import Foundation

extension CourseOverprint {
    /// The overprint split by colour level (see `CourseLevel`): the lower purple part is painted inside the map's colour
    /// order, below black, blue and brown 100 %; the upper purple part on top of the map. This is how the IOF wants a
    /// course printed without a real overprint ("IOF Printing and Colour Definitions" Rev 4 §4: "place the lower purple
    /// track colour in the colour order below black, brown and blue 100 %"; multiply-style blending is not recommended).
    /// State marks (colour, font, width) go to both parts, so each part draws with the same styles as the whole.
    public var levels: (lower: CourseOverprint, upper: CourseOverprint) {
        var lower: [CourseMark] = [], upper: [CourseMark] = []
        var level = CourseLevel.lower
        for m in marks {
            switch m {
            case let .level(l): level = l ?? .lower
            case .color, .font, .width:
                lower.append(m)
                upper.append(m)
            default:
                if level == .upper { upper.append(m) } else { lower.append(m) }
            }
        }
        func drawn(_ list: [CourseMark]) -> [CourseMark] {
            list.contains { if case .color = $0 { return false }; if case .font = $0 { return false }; if case .width = $0 { return false }; return true } ? list : []
        }
        return (CourseOverprint(marks: drawn(lower), lineWidthM: lineWidthM, colorHex: colorHex),
                CourseOverprint(marks: drawn(upper), lineWidthM: lineWidthM, colorHex: colorHex))
    }
}
