import Foundation

/// 6-line world file (ESRI): A, D, B, E, C, F.
/// C, F = CENTER coordinate of the upper-left pixel, matching the convention OCAD and OOM read.
public struct WorldFile: Hashable, Sendable {
    public var pixelSizeX: Double   // A
    public var rotationY: Double    // D
    public var rotationX: Double    // B
    public var pixelSizeY: Double   // E (negative for north-up)
    public var upperLeftX: Double   // C
    public var upperLeftY: Double   // F

    public init(pixelSizeX: Double, rotationY: Double = 0, rotationX: Double = 0, pixelSizeY: Double, upperLeftX: Double, upperLeftY: Double) {
        self.pixelSizeX = pixelSizeX
        self.rotationY = rotationY
        self.rotationX = rotationX
        self.pixelSizeY = pixelSizeY
        self.upperLeftX = upperLeftX
        self.upperLeftY = upperLeftY
    }

    /// World file for a north-up raster whose upper-left corner = the frame's upper-left corner.
    public init(frame: MapFrame, pixelSize p: Double) {
        self.init(pixelSizeX: p, pixelSizeY: -p,
                  upperLeftX: frame.extent.minX + p / 2,
                  upperLeftY: frame.extent.maxY - p / 2)
    }

    public var text: String {
        [pixelSizeX, rotationY, rotationX, pixelSizeY, upperLeftX, upperLeftY]
            .map { String(format: "%.10f", locale: Locale(identifier: "en_US_POSIX"), $0) }
            .joined(separator: "\n") + "\n"
    }

    public init?(text: String) {
        let values = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(Double.init)
        guard values.count == 6, values.allSatisfy(\.isFinite), values[0] != 0, values[3] != 0 else { return nil }
        self.init(pixelSizeX: values[0], rotationY: values[1], rotationX: values[2],
                  pixelSizeY: values[3], upperLeftX: values[4], upperLeftY: values[5])
    }

    /// World coordinate for a pixel position (column, row); (0,0) = center of the upper-left pixel.
    public func world(col: Double, row: Double) -> Point2D {
        Point2D(x: pixelSizeX * col + rotationX * row + upperLeftX,
                y: rotationY * col + pixelSizeY * row + upperLeftY)
    }
}
