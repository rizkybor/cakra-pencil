import Foundation

public enum SheetOrientation: String, Codable, CaseIterable, Sendable {
    case portrait
    case landscape

    public var toggled: SheetOrientation { self == .portrait ? .landscape : .portrait }
}

/// Ukuran kertas dalam mm, selalu disimpan sisi pendek × sisi panjang.
public struct PaperSize: Codable, Hashable, Sendable {
    public var name: String
    public var shortMM: Double
    public var longMM: Double

    public static let a4 = PaperSize(name: "A4", shortMM: 210, longMM: 297)
}

/// Pilihan skala dan dpi dari FR-1.1 dan FR-3.1.
public enum MapPresets {
    /// 1:1000 sampai 1:15000, berjenjang kelipatan 500.
    public static let scales = Array(stride(from: 1000, through: 15000, by: 500))
    public static let dpis = [300, 600, 900]
    public static let marginsMM: [Double] = [0, 5, 10]
    public static let snapStepsM = [0, 10, 50, 100]
}

/// Lembar peta: kertas + orientasi + margin + skala. Semua turunan ukuran dihitung dari sini.
public struct SheetSpec: Codable, Hashable, Sendable {
    public var paper: PaperSize
    public var orientation: SheetOrientation
    public var marginMM: Double
    public var scaleDenominator: Int

    public init(paper: PaperSize = .a4, orientation: SheetOrientation = .portrait, marginMM: Double = 0, scaleDenominator: Int = 4000) {
        self.paper = paper
        self.orientation = orientation
        self.marginMM = marginMM
        self.scaleDenominator = scaleDenominator
    }

    /// Area mapping di kertas (mm) = kertas dikurangi margin di keempat sisi (FR-1.6).
    public var mappingWidthMM: Double {
        (orientation == .portrait ? paper.shortMM : paper.longMM) - 2 * marginMM
    }

    public var mappingHeightMM: Double {
        (orientation == .portrait ? paper.longMM : paper.shortMM) - 2 * marginMM
    }

    /// Ukuran tanah (m) untuk area mapping pada skala ini.
    public var groundWidthM: Double { mappingWidthMM / 1000 * Double(scaleDenominator) }
    public var groundHeightM: Double { mappingHeightMM / 1000 * Double(scaleDenominator) }

    /// Ukuran piksel di tanah (m) = skala × 0,0254 / dpi.
    public func pixelSizeM(dpi: Int) -> Double {
        Double(scaleDenominator) * 0.0254 / Double(dpi)
    }

    /// Dimensi raster area mapping pada dpi tertentu.
    public func pixelDimensions(dpi: Int) -> (width: Int, height: Int) {
        (Int((mappingWidthMM / 25.4 * Double(dpi)).rounded()),
         Int((mappingHeightMM / 25.4 * Double(dpi)).rounded()))
    }

    /// Meter di tanah untuk ukuran mm di kertas.
    public func groundMeters(forPaperMM mm: Double) -> Double {
        mm / 1000 * Double(scaleDenominator)
    }
}

/// Frame north-up terhadap grid UTM. origin = pojok kiri bawah (minX, minY).
public struct MapFrame: Codable, Hashable, Sendable {
    public var origin: Point2D
    public var widthM: Double
    public var heightM: Double

    public init(origin: Point2D, widthM: Double, heightM: Double) {
        self.origin = origin
        self.widthM = widthM
        self.heightM = heightM
    }

    public init(center: Point2D, sheet: SheetSpec) {
        self.init(origin: Point2D(x: center.x - sheet.groundWidthM / 2, y: center.y - sheet.groundHeightM / 2),
                  widthM: sheet.groundWidthM, heightM: sheet.groundHeightM)
    }

    public var extent: Rect2D { Rect2D(minX: origin.x, minY: origin.y, maxX: origin.x + widthM, maxY: origin.y + heightM) }
    public var center: Point2D { extent.center }

    /// Pojok searah jarum jam mulai kiri atas: KA, KaA, KaB, KB.
    public var corners: [Point2D] {
        let e = extent
        return [Point2D(x: e.minX, y: e.maxY), Point2D(x: e.maxX, y: e.maxY),
                Point2D(x: e.maxX, y: e.minY), Point2D(x: e.minX, y: e.minY)]
    }

    /// Geser pojok kiri bawah ke kelipatan `stepM` terdekat (FR-1.7). Ukuran tetap.
    public func snapped(toStep stepM: Int) -> MapFrame {
        guard stepM > 0 else { return self }
        let s = Double(stepM)
        var f = self
        f.origin = Point2D(x: (origin.x / s).rounded() * s, y: (origin.y / s).rounded() * s)
        return f
    }

    /// Frame baru dengan ukuran dari `sheet` dan titik tengah yang sama (ganti skala/orientasi, FR-1.4/1.5).
    public func resized(to sheet: SheetSpec) -> MapFrame {
        MapFrame(center: center, sheet: sheet)
    }
}
