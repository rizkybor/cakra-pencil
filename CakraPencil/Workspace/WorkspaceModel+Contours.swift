import CakraCore
import Foundation
import ImageIO

/// Kontur (FR-8): sumber bawaan (Terrain Tiles), DEM user (GeoTIFF/ASCII Grid), atau garis kontur GeoJSON.
/// Data elevasi disimpan di paket proyek (dem.json + dem.bin / contours.json) agar tetap jalan offline.
extension WorkspaceModel {
    /// Area DEM: frame + buffer 50 m (FR-8.2).
    var demExtent: Rect2D? { frame.map { $0.extent.insetBy(-50) } }

    var contourSettings: ContourSettings { project.contours }

    var hasContourData: Bool { dem != nil || importedContours != nil }

    func loadContourData() {
        let url = self.url
        Task {
            let (grid, lines) = await Task.detached { () -> (DEMGrid?, [ContourLine]?) in
                ((try? DEMGrid.read(from: url)) ?? nil, ContourLine.readImported(from: url))
            }.value
            self.dem = grid
            self.importedContours = lines
            self.regenerateContours()
        }
    }

    /// Ubah pengaturan kontur (tampilan; tidak masuk undo) lalu hitung ulang.
    func updateContours(_ change: (inout ContourSettings) -> Void) {
        var next = project
        var c = project.contours
        change(&c)
        c.intervalM = min(max((c.intervalM * 10).rounded() / 10, ContourSettings.intervalRangeM.lowerBound), ContourSettings.intervalRangeM.upperBound)
        c.indexEvery = min(max(c.indexEvery, 2), 10)
        c.smoothing = min(max(c.smoothing, 0), 3)
        c.minLengthMM = min(max(c.minLengthMM, 0), 20)
        c.opacity = (min(max(c.opacity, ContourSettings.opacityRange.lowerBound), ContourSettings.opacityRange.upperBound) * 100).rounded() / 100
        let geometryChanged = c.geometry != project.contours.geometry
        next.contourSettings = c
        apply(next, recordUndo: false)
        if geometryChanged { regenerateContours() }
    }

    /// Naikkan/turunkan opacity kontur (langkah dalam pecahan, mis. 0,1 = 10%).
    func stepContourOpacity(by delta: Double) {
        updateContours { $0.opacity += delta }
    }

    /// Hitung ulang garis kontur di background (debounce 150 ms agar slider/stepper tetap lancar).
    func regenerateContours() {
        contourTask?.cancel()
        let settings = project.contours, sheet = project.sheet, clip = frame?.extent
        let grid = dem, imported = importedContours
        guard grid != nil || imported != nil else {
            contourLines = []
            contourRelief = nil
            contoursChanged()
            return
        }
        contourTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if case .downloading = contourStatus {} else { contourStatus = .generating }
            let result = await Task.detached(priority: .userInitiated) { () -> ([ContourLine], (Double, Double)?) in
                if let imported {
                    let lines = ContourLine.classify(imported, settings: settings)
                    let e = lines.map(\.elevation)
                    return (lines, e.isEmpty ? nil : (e.min()!, e.max()!))
                }
                guard let grid else { return ([], nil) }
                let r = ContourGenerator.generate(grid, settings: settings, sheet: sheet, clip: clip)
                return (r.lines, (r.minElevation, r.maxElevation))
            }.value
            guard !Task.isCancelled else { return }
            contourLines = result.0
            contourRelief = result.1.map { (min: $0.0, max: $0.1) }
            if contourStatus == .generating { contourStatus = .idle }
            contoursChanged()
        }
    }

    // MARK: Sumber bawaan: AWS Terrain Tiles

    /// Unduh tile elevasi untuk frame + buffer, resample ke grid UTM, simpan di paket.
    func downloadBuiltInContours() async {
        guard let extent = demExtent, let zone else { return }
        // z15 (±4,8 m/piksel) untuk skala sprint, z14 (±9,6 m) untuk skala forest.
        let z = project.sheet.scaleDenominator <= 5000 ? 15 : 14
        let tiles = TerrainTiles.tiles(covering: extent, zone: zone, z: z)
        guard tiles.count <= 64 else {
            contourStatus = .failed("Area terlalu besar untuk diunduh (\(tiles.count) tile).")
            return
        }
        contourStatus = .downloading(done: 0, total: tiles.count)
        var mosaic = TerrainMosaic(z: z)
        do {
            try await withThrowingTaskGroup(of: (String, [Float]).self) { group in
                for t in tiles {
                    group.addTask {
                        let (data, response) = try await URLSession.shared.data(from: TerrainTiles.url(z: z, x: t.x, y: t.y))
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                        return ("\(t.x)/\(t.y)", try Self.decodeTerrarium(data))
                    }
                }
                for try await (key, values) in group {
                    mosaic.tiles[key] = values
                    contourStatus = .downloading(done: mosaic.tiles.count, total: tiles.count)
                }
            }
        } catch {
            contourStatus = .failed("Unduh data elevasi gagal. Periksa koneksi internet lalu coba lagi.")
            return
        }
        let cell = z == 15 ? 5.0 : 10.0
        let url = self.url
        let grid = await Task.detached(priority: .userInitiated) { () -> DEMGrid in
            // Data dasar Terrain Tiles di Indonesia sebagian besar SRTM ±30 m; dipakai untuk peringatan interval.
            let g = DEMGrid.resample(extent: extent, cellSize: cell, source: "Terrain Tiles (AWS) z\(z)", nativeResolutionM: 30) {
                mosaic.sample(zone.unproject($0))
            }
            try? g.write(to: url)
            return g
        }.value
        installDEM(grid)
    }

    /// PNG Terrarium 256×256 → elevasi.
    nonisolated static func decodeTerrarium(_ data: Data) throws -> [Float] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              image.width == 256, image.height == 256,
              let ctx = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw DEMReadError.corrupt("tile elevasi")
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(256 * 256)).map { TerrainTiles.elevation(r: p[$0 * 4], g: p[$0 * 4 + 1], b: p[$0 * 4 + 2]) }
    }

    // MARK: Upload sendiri

    /// DEM GeoTIFF (.tif/.tiff) atau ESRI ASCII Grid (.asc), atau garis kontur GeoJSON (.geojson/.json).
    func importContourFile(_ url: URL) async {
        guard let extent = demExtent, let zone else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        contourStatus = .importing
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        let packageURL = self.url
        do {
            if ext == "geojson" || ext == "json" {
                let lines = try await Task.detached(priority: .userInitiated) { () -> [ContourLine] in
                    let raw = try ContourGeoJSON.read(Data(contentsOf: url), zone: zone)
                    let lines = raw.map { ContourLine(elevation: $0.elevation, kind: .contour, points: $0.points,
                                                      isClosed: $0.points.count > 3 && $0.points.first == $0.points.last) }
                    try ContourLine.writeImported(lines, to: packageURL)
                    DEMGrid.remove(from: packageURL)
                    return lines
                }.value
                dem = nil
                importedContours = lines
                contourStatus = .idle
                enableContours()
                notice = "\(lines.count) garis kontur dari \(name) diimpor."
            } else {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                guard (attrs[.size] as? Int ?? 0) <= 2_000_000_000 else { throw DEMReadError.unsupported("file lebih dari 2 GB") }
                let grid = try await Task.detached(priority: .userInitiated) { () -> DEMGrid in
                    let data = try Data(contentsOf: url)
                    let raster: ElevationRaster
                    switch ext {
                    case "asc", "txt":
                        let prj = try? String(contentsOf: url.deletingPathExtension().appendingPathExtension("prj"), encoding: .utf8)
                        raster = try AsciiGridReader.read(data, prj: prj, projectZone: zone)
                    case "tif", "tiff":
                        raster = try GeoTIFFReader.read(data, projectZone: zone)
                    default:
                        throw DEMReadError.unsupported(".\(ext)")
                    }
                    let g = raster.grid(extent: extent, zone: zone, source: name)
                    guard g.range != nil else { throw DEMReadError.unsupported("DEM tidak menutupi area frame (cek CRS dan lokasi file)") }
                    try g.write(to: packageURL)
                    ContourLine.removeImported(from: packageURL)
                    return g
                }.value
                importedContours = nil
                installDEM(grid)
                notice = "DEM \(name) dimuat (±\(Fmt.number(grid.header.nativeResolutionM, decimals: 1)) m)."
            }
        } catch {
            contourStatus = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func installDEM(_ grid: DEMGrid) {
        dem = grid
        importedContours = nil
        contourStatus = .idle
        enableContours()
    }

    private func enableContours() {
        updateContours { $0.isEnabled = true }
    }

    func removeContourData() {
        DEMGrid.remove(from: url)
        ContourLine.removeImported(from: url)
        dem = nil
        importedContours = nil
        contourStatus = .idle
        updateContours { $0.isEnabled = false }
    }

    /// FR-8.14: jadikan garis kontur objek vektor yang bisa diedit (satu langkah undo); kontur otomatis disembunyikan
    /// agar tidak tampil dobel.
    func freezeContours() {
        let s = project.contours
        let features = contourLines.filter { $0.points.count >= 2 }.map { $0.feature(settings: s) }
        guard !features.isEmpty else { return }
        editFeatures { $0.insert(contentsOf: features, at: 0) }
        updateContours { $0.isEnabled = false }
        notice = "\(features.count) garis kontur jadi objek vektor (101.0/102.0/103.0) dan bisa diedit dengan alat Pilih."
    }

    /// Objek vektor kontur untuk export (bila tampil dan ikut export).
    var contourExportFeatures: [Feature] {
        let s = project.contours
        guard s.isEnabled, s.includeInExport else { return [] }
        return contourLines.map { $0.feature(settings: s) }
    }
}
