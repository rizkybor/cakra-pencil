import Foundation

/// World file 6 baris (ESRI): A, D, B, E, C, F.
/// C, F = koordinat PUSAT piksel kiri atas, sesuai konvensi yang dibaca OCAD dan OOM.
public struct WorldFile: Hashable, Sendable {
    public var pixelSizeX: Double   // A
    public var rotationY: Double    // D
    public var rotationX: Double    // B
    public var pixelSizeY: Double   // E (negatif untuk north-up)
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

    /// World file untuk raster north-up yang pojok kiri atasnya = pojok kiri atas frame.
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

    /// Koordinat dunia untuk posisi piksel (kolom, baris); (0,0) = pusat piksel kiri atas.
    public func world(col: Double, row: Double) -> Point2D {
        Point2D(x: pixelSizeX * col + rotationX * row + upperLeftX,
                y: rotationY * col + pixelSizeY * row + upperLeftY)
    }
}
