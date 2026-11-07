import Foundation

/// A single sketch stroke. Points in project coordinates (UTM, meters); width in paper mm at the project scale.
/// width_mm is the source of truth: pixels are only computed at export (FR-3.7).
public struct Stroke: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var colorHex: String
    public var widthMM: Double
    public var pressureEnabled: Bool
    public var points: [Point2D]
    public var pressures: [Double]
    public var createdAt: Date

    public init(id: UUID = UUID(), colorHex: String, widthMM: Double, pressureEnabled: Bool = false, points: [Point2D], pressures: [Double] = [], createdAt: Date = Date()) {
        self.id = id
        self.colorHex = colorHex
        self.widthMM = widthMM
        self.pressureEnabled = pressureEnabled
        self.points = points
        self.pressures = pressures
        self.createdAt = createdAt
    }

    public var bounds: Rect2D? { Rect2D(points: points) }

    /// Shortest distance from a point to the stroke's centerline (meters).
    public func distance(to p: Point2D) -> Double {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return p.distance(to: first) }
        var best = Double.infinity
        for i in 1..<points.count {
            best = min(best, p.distance(toSegment: points[i - 1], points[i]))
        }
        return best
    }

    /// Width in the raster: mm × dpi / 25.4.
    public func pixelWidth(dpi: Int) -> Double { widthMM * Double(dpi) / 25.4 }
}

extension Stroke: Codable {
    // Points are stored as a flat array [x0, y0, x1, y1, ...] to keep the file compact.
    enum CodingKeys: String, CodingKey {
        case id, colorHex = "color", widthMM = "width_mm", pressureEnabled = "pressure_enabled", xy, pressures, createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        widthMM = try c.decode(Double.self, forKey: .widthMM)
        pressureEnabled = try c.decodeIfPresent(Bool.self, forKey: .pressureEnabled) ?? false
        let xy = try c.decode([Double].self, forKey: .xy)
        guard xy.count % 2 == 0 else {
            throw DecodingError.dataCorruptedError(forKey: .xy, in: c, debugDescription: "Odd number of coordinates")
        }
        points = stride(from: 0, to: xy.count, by: 2).map { Point2D(x: xy[$0], y: xy[$0 + 1]) }
        pressures = try c.decodeIfPresent([Double].self, forKey: .pressures) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(widthMM, forKey: .widthMM)
        try c.encode(pressureEnabled, forKey: .pressureEnabled)
        try c.encode(points.flatMap { [$0.x, $0.y] }, forKey: .xy)
        if !pressures.isEmpty { try c.encode(pressures, forKey: .pressures) }
        try c.encode(createdAt, forKey: .createdAt)
    }
}

/// Pen presets following ISOM colors and line widths (FR-3.4).
public struct PenPreset: Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var colorHex: String
    public var widthMM: Double

    public init(name: String, colorHex: String, widthMM: Double) {
        self.name = name
        self.colorHex = colorHex
        self.widthMM = widthMM
    }

    public static let widthRange: ClosedRange<Double> = 0.05...3.00

    public static let isom: [PenPreset] = [
        PenPreset(name: "Black", colorHex: "#000000", widthMM: 0.14),
        PenPreset(name: "Brown", colorHex: "#D15C00", widthMM: 0.14),
        PenPreset(name: "Blue", colorHex: "#00A0E6", widthMM: 0.18),
        PenPreset(name: "Yellow", colorHex: "#FFBA35", widthMM: 0.35),
        PenPreset(name: "Green", colorHex: "#3EB54A", widthMM: 0.35),
        PenPreset(name: "Red", colorHex: "#E30613", widthMM: 0.25),
    ]

    /// Clamp to 0.05–3.00 mm in steps of 0.01 mm (FR-3.2).
    public static func clampWidth(_ mm: Double) -> Double {
        (min(max(mm, widthRange.lowerBound), widthRange.upperBound) * 100).rounded() / 100
    }
}

/// Parse "#RRGGBB" into 0–1 components.
public func rgbComponents(hex: String) -> (r: Double, g: Double, b: Double)? {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}
