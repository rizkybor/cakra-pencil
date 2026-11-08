import Foundation

/// Fieldwork data of a project: GPS tracks walked, field notes (position, category, text, photos), and averaged
/// positions. Positions are UTM meters in the project's zone, like every other object. Stored as `field.json` in the
/// `.cakra` package (photos in `field-photos/`), so it travels with the `.occa` file between iPad and Mac.
public struct FieldData: Codable, Hashable, Sendable {
    public var tracks: [FieldTrack]
    public var notes: [FieldNote]
    /// Map display (field panel eye buttons).
    public var showTracks: Bool
    public var showNotes: Bool
    /// Survey coverage shading on the map (walked area within `coverageRadius` of the tracks).
    public var showCoverage: Bool?
    public var coverageRadiusM: Double?

    public init(tracks: [FieldTrack] = [], notes: [FieldNote] = [], showTracks: Bool = true, showNotes: Bool = true,
                showCoverage: Bool? = nil, coverageRadiusM: Double? = nil) {
        self.tracks = tracks
        self.notes = notes
        self.showTracks = showTracks
        self.showNotes = showNotes
        self.showCoverage = showCoverage
        self.coverageRadiusM = coverageRadiusM
    }

    /// What a mapper sees on each side while walking; 25 m suits most forest.
    public static let defaultCoverageRadiusM = 25.0
    public var coverageRadius: Double { coverageRadiusM ?? Self.defaultCoverageRadiusM }

    public var isEmpty: Bool { tracks.isEmpty && notes.isEmpty }

    /// File names of all photos referenced by the notes.
    public var photoFiles: [String] { notes.flatMap(\.photos) }
}

/// One recorded GPS track (a walk), or one imported from a GPX file.
public struct FieldTrack: Codable, Hashable, Identifiable, Sendable {
    public struct Point: Codable, Hashable, Sendable {
        public var position: Point2D
        public var time: Date?
        /// Horizontal accuracy in meters (nil for imported tracks without it).
        public var accuracyM: Double?
        public var elevationM: Double?
        /// First point after a pause (a new segment): not connected to the previous point, the gap isn't counted.
        public var startsSegment: Bool?

        public init(position: Point2D, time: Date? = nil, accuracyM: Double? = nil, elevationM: Double? = nil,
                    startsSegment: Bool? = nil) {
            self.position = position
            self.time = time
            self.accuracyM = accuracyM
            self.elevationM = elevationM
            self.startsSegment = startsSegment
        }
    }

    public var id: UUID
    public var name: String
    public var colorHex: String
    public var points: [Point]
    public var isVisible: Bool
    /// "gpx" for imported tracks, nil for tracks recorded in OCCA.
    public var source: String?

    public init(id: UUID = UUID(), name: String, colorHex: String = FieldTrack.palette[0], points: [Point] = [],
                isVisible: Bool = true, source: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.points = points
        self.isVisible = isVisible
        self.source = source
    }

    /// Track colors (magenta, cyan, orange, violet, lime): visible on satellite imagery and on the map colors.
    public static let palette = ["#E6007E", "#00B7EB", "#FF7A00", "#7B2FF7", "#7ED321"]

    /// The recorded parts: a pause and resume starts a new segment (the gap between them was not walked on record).
    public var segments: [[Point]] {
        var out: [[Point]] = []
        for p in points {
            if p.startsSegment == true || out.isEmpty { out.append([p]) } else { out[out.count - 1].append(p) }
        }
        return out
    }

    /// Recorded distance (m), without the gaps between segments.
    public var lengthM: Double {
        segments.reduce(0) { total, seg in
            total + zip(seg, seg.dropFirst()).reduce(0) { $0 + $1.0.position.distance(to: $1.1.position) }
        }
    }

    public var startTime: Date? { points.first?.time }
    public var endTime: Date? { points.last?.time }
    /// Recorded time: the sum of the segments (pauses not counted).
    public var duration: TimeInterval? {
        let parts = segments.compactMap { seg -> TimeInterval? in
            guard let a = seg.first?.time, let b = seg.last?.time else { return nil }
            return b.timeIntervalSince(a)
        }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    /// Median horizontal accuracy (m) of the points that have one.
    public var typicalAccuracyM: Double? {
        let a = points.compactMap(\.accuracyM).sorted()
        return a.isEmpty ? nil : a[a.count / 2]
    }
}

/// A field note: something seen in the field, at a position, with a category, text, and photos. Averaged positions
/// (stand still, average the GPS fixes) are notes with `averaging` filled in.
public struct FieldNote: Codable, Hashable, Identifiable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        case boulder, cliff, water, vegetation, path, fence, building, control, check, other

        public var label: String {
            switch self {
            case .boulder: return "Boulder / rock"
            case .cliff: return "Cliff / rock face"
            case .water: return "Water / marsh"
            case .vegetation: return "Vegetation"
            case .path: return "Path / road"
            case .fence: return "Fence / wall"
            case .building: return "Building / man-made"
            case .control: return "Control site"
            case .check: return "Check again"
            case .other: return "Other"
            }
        }

        /// SF Symbol for lists and the map pin.
        public var icon: String {
            switch self {
            case .boulder: return "mountain.2.fill"
            case .cliff: return "triangle.fill"
            case .water: return "drop.fill"
            case .vegetation: return "leaf.fill"
            case .path: return "point.topleft.down.to.point.bottomright.curvepath.fill"
            case .fence: return "square.split.1x2.fill"
            case .building: return "building.2.fill"
            case .control: return "circle.circle"
            case .check: return "questionmark"
            case .other: return "mappin"
            }
        }

        /// Point symbols that usually fit a note of this category (ISOM 2017-2 / ISSprOM 2019-2 codes, the first one
        /// found in the map's symbol set is suggested first). Lines and areas are drawn from the note instead.
        public var suggestedSymbolCodes: [String] {
            switch self {
            case .boulder: return ["204", "205", "207"]
            case .cliff: return ["203", "203.1", "203.2", "115"]
            case .water: return ["303", "311", "312", "313"]
            case .vegetation: return ["418", "417", "419"]
            case .path: return ["519", "512.1"]
            case .fence: return ["519", "522.1"]
            case .building: return ["526", "524", "525", "522.1", "530", "531"]
            case .control: return ["115", "313", "419", "530", "531"]
            case .check, .other: return ["115", "313", "419", "530", "531"]
            }
        }

        /// Pin color (ISOM-like: black rock and man-made, blue water, green vegetation, purple control).
        public var colorHex: String {
            switch self {
            case .boulder, .cliff, .path, .fence, .building: return "#3A3A3A"
            case .water: return "#0091D5"
            case .vegetation: return "#2E9E3E"
            case .control: return "#A626FF"
            case .check: return "#E8710F"
            case .other: return "#6B665E"
            }
        }
    }

    /// Averaged position: number of GPS fixes and the resulting accuracy.
    public struct Averaging: Codable, Hashable, Sendable {
        public var samples: Int
        public var accuracyM: Double
        public var durationS: Double

        public init(samples: Int, accuracyM: Double, durationS: Double) {
            self.samples = samples
            self.accuracyM = accuracyM
            self.durationS = durationS
        }
    }

    public var id: UUID
    public var position: Point2D
    public var createdAt: Date
    public var category: Category
    public var text: String
    /// Photo file names in the package's `field-photos/` folder.
    public var photos: [String]
    /// Compass heading of the camera when the photo was taken (degrees, 0 = north).
    public var photoHeadingDeg: Double?
    /// GPS accuracy (m) when the note was placed by GPS; nil when tapped on the map.
    public var accuracyM: Double?
    public var averaging: Averaging?
    /// Processed: turned into a map object (or otherwise handled).
    public var isDone: Bool
    /// The map object made from this note ("Make map object"), if any.
    public var featureID: UUID?
    /// Placed by bearing and distance from where the surveyor stood.
    public var offset: FieldOffset?
    /// Quick vegetation classification (runnability 401–410), a draft for an area drawn later.
    public var vegetation: VegetationClass?

    public init(id: UUID = UUID(), position: Point2D, createdAt: Date = Date(), category: Category = .other, text: String = "",
                photos: [String] = [], photoHeadingDeg: Double? = nil, accuracyM: Double? = nil, averaging: Averaging? = nil,
                isDone: Bool = false, featureID: UUID? = nil, offset: FieldOffset? = nil, vegetation: VegetationClass? = nil) {
        self.id = id
        self.position = position
        self.createdAt = createdAt
        self.category = category
        self.text = text
        self.photos = photos
        self.photoHeadingDeg = photoHeadingDeg
        self.accuracyM = accuracyM
        self.averaging = averaging
        self.isDone = isDone
        self.featureID = featureID
        self.offset = offset
        self.vegetation = vegetation
    }

    /// Title for lists: the text's first line, else the category.
    public var title: String {
        let first = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if first.isEmpty, let v = vegetation { return "\(v.code) \(v.label)" }
        return first.isEmpty ? (averaging != nil ? "Averaged position" : category.label) : first
    }
}

extension FieldData {
    /// Name for a new track: "Track 3" (one more than the highest number used).
    public func nextTrackName(prefix: String = "Track") -> String {
        let used = tracks.compactMap { t -> Int? in
            guard t.name.hasPrefix(prefix + " ") else { return nil }
            return Int(t.name.dropFirst(prefix.count + 1))
        }
        return "\(prefix) \((used.max() ?? 0) + 1)"
    }

    /// Color for a new track (cycles through the palette).
    public var nextTrackColor: String { FieldTrack.palette[tracks.count % FieldTrack.palette.count] }

    /// Bounding box of everything (for "zoom to field data").
    public var bounds: Rect2D? {
        let pts = tracks.flatMap { $0.points.map(\.position) } + notes.map(\.position)
        return pts.isEmpty ? nil : Rect2D(points: pts)
    }
}
