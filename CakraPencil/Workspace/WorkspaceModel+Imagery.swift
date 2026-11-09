import CakraCore
import ImageIO
import MapKit
import UIKit
import UniformTypeIdentifiers

/// HD Apple Maps image of the locked area. Once the area is locked, one image of the frame (plus a small margin) is
/// captured for the current basemap type (Satellite/Hybrid/Standard) and shown instead of the live map, so the
/// basemap is a fixed picture that scales with the drawing (road widths no longer change with the zoom level).
/// Stored under `imagery/` in the project package as a local cache (not in .occa files; each device downloads its own).
/// Exports can include it as a georeferenced basemap (`exportBackgroundSource`).
extension WorkspaceModel {
    enum ImageryError: LocalizedError {
        case encoding
        var errorDescription: String? { "The image could not be saved." }
    }

    /// The HD image is shown in the workspace (area locked, HD image mode, no GeoTIFF basemap in use).
    var showsImagerySnapshot: Bool {
        imagerySnapshot != nil && project.areaLocked && !usesBasemapImage && !project.usesLiveBasemap
    }

    /// Basemap mode: HD image (saved, fixed) or Live (real-time Apple Maps). HD images keep downloading in Live mode,
    /// so switching back is instant and exports can still include the basemap.
    func setLiveBasemap(_ live: Bool) {
        guard project.usesLiveBasemap != live else { return }
        var next = project
        next.liveBasemap = live
        apply(next, recordUndo: false)
    }

    var imagerySnapshotURL: URL? { imagerySnapshot.map { url.appendingPathComponent($0.fileName) } }

    /// Use the saved images for the current area, and download the missing ones: all three basemap types
    /// (Satellite, Hybrid, Standard), the current type first. `force` = download all three again.
    /// While a type is downloading, or when it fails (e.g. offline), the live map is shown for that type.
    func refreshImagery(force: Bool = false) {
        if force, !LicenseManager.shared.require(.hdImagery) { return }
        guard project.areaLocked, let frame, let zone else {
            cancelImageryDownload()
            imagerySnapshot = nil
            return
        }
        let corners = frame.corners.map(zone.unproject)
        let fitting = { (type: Basemap) in self.loadImagerySnapshot(type).flatMap { $0.fits(corners) ? $0 : nil } }
        let current = force ? nil : fitting(basemap)
        if imagerySnapshot != current { imagerySnapshot = current }

        let key = corners.map { "\($0.lat),\($0.lon)" }.joined(separator: ";")
        // Switching basemap type while the same area is downloading: keep that download going.
        if !force, imageryTask != nil, imageryTaskKey == key { return }
        cancelImageryDownload()
        let order = [basemap] + Basemap.allCases.filter { $0 != basemap }
        let missing = force ? order : order.filter { fitting($0) == nil }
        guard !missing.isEmpty else {
            imageryError = nil
            return
        }
        // Free plan: no HD download, the live map is shown; HD images saved earlier (e.g. on Pro) are still used.
        guard LicenseManager.shared.isPro else { return }
        #if DEBUG
        // `-cp-no-imagery`: keep the live map (UI tests, no download).
        if ProcessInfo.processInfo.arguments.contains("-cp-no-imagery") { return }
        #endif
        imageryError = nil
        isCapturingImagery = true
        imageryTaskKey = key
        let package = url
        imageryTask = Task { [weak self] in
            // Let quick changes settle first (e.g. scale changes).
            try? await Task.sleep(for: .milliseconds(400))
            var failures: [String] = []
            for (i, type) in missing.enumerated() {
                guard !Task.isCancelled else { return }
                self?.imageryProgress = "\(type.label) \(i + 1)/\(missing.count)"
                do {
                    let s = try await Self.captureImagery(type, corners: corners, package: package)
                    guard !Task.isCancelled, let self else { return }
                    if self.basemap == type { self.imagerySnapshot = s }
                } catch {
                    failures.append("\(type.label): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.isCapturingImagery = false
            self.imageryProgress = nil
            self.imageryTask = nil
            self.imageryTaskKey = nil
            if !failures.isEmpty {
                self.imageryError = "HD image could not be downloaded (\(failures.joined(separator: "; "))). Showing the live map."
            }
        }
    }

    private func cancelImageryDownload() {
        imageryTask?.cancel()
        imageryTask = nil
        imageryTaskKey = nil
        isCapturingImagery = false
        imageryProgress = nil
    }

    /// The saved HD image of `type` covers the current locked area (offline check for fieldwork).
    func hasImagery(_ type: Basemap) -> Bool {
        guard project.areaLocked, let frame, let zone else { return false }
        let corners = frame.corners.map(zone.unproject)
        return loadImagerySnapshot(type)?.fits(corners) ?? false
    }

    private func loadImagerySnapshot(_ type: Basemap) -> ImagerySnapshot? {
        let meta = url.appendingPathComponent(ImagerySnapshot.metadataPath(for: type.rawValue))
        guard let data = try? Data(contentsOf: meta),
              let s = try? JSONDecoder().decode(ImagerySnapshot.self, from: data),
              s.isValid, s.mapType == type.rawValue,
              FileManager.default.fileExists(atPath: url.appendingPathComponent(s.fileName).path) else { return nil }
        return s
    }

    /// Capture the area around `corners` with MKMapSnapshotter (light appearance) and save it.
    private static func captureImagery(_ type: Basemap, corners: [LatLon], package: URL) async throws -> ImagerySnapshot {
        let pts = corners.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        var rect = MKMapRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        rect = rect.insetBy(dx: -rect.width * 0.05, dy: -rect.height * 0.05)
        let mpp = MKMetersPerMapPointAtLatitude(MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude)
        let px = ImagerySnapshot.pixelSize(widthM: rect.width * mpp, heightM: rect.height * mpp)

        // MapKit renders at the screen scale (2× on iPad, also on Mac), so ask for points = pixels / scale.
        let scale = max(1, (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.scale ?? 2)
        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = CGSize(width: Double(px.width) / scale, height: Double(px.height) / scale)
        options.traitCollection = UITraitCollection { t in
            t.displayScale = scale
            t.userInterfaceStyle = .light
        }
        switch type {
        case .satellite: options.preferredConfiguration = MKImageryMapConfiguration()
        case .hybrid: options.preferredConfiguration = MKHybridMapConfiguration()
        case .standard: options.preferredConfiguration = MKStandardMapConfiguration()
        }
        let shot = try await MKMapSnapshotter(options: options).start()
        let image = shot.image
        let w = Double(image.size.width * image.scale), h = Double(image.size.height * image.scale)

        // Exact bounds from the snapshot itself (MapKit may adjust the rect slightly): Web Mercator is linear in
        // map points, so two known corners give the map point of every pixel.
        let nw = MKMapPoint(x: rect.minX, y: rect.minY), se = MKMapPoint(x: rect.maxX, y: rect.maxY)
        let p1 = shot.point(for: nw.coordinate), p2 = shot.point(for: se.coordinate)
        let sx = (se.x - nw.x) / Double(p2.x - p1.x), sy = (se.y - nw.y) / Double(p2.y - p1.y)
        let topLeft = MKMapPoint(x: nw.x - Double(p1.x) * sx, y: nw.y - Double(p1.y) * sy).coordinate
        let bottomRight = MKMapPoint(x: nw.x + (Double(image.size.width) - Double(p1.x)) * sx,
                                     y: nw.y + (Double(image.size.height) - Double(p1.y)) * sy).coordinate

        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { throw ImageryError.encoding }
        let snapshot = ImagerySnapshot(mapType: type.rawValue, fileName: ImagerySnapshot.imagePath(for: type.rawValue),
                                       north: topLeft.latitude, south: bottomRight.latitude,
                                       west: topLeft.longitude, east: bottomRight.longitude,
                                       width: Int(w.rounded()), height: Int(h.rounded()))
        let meta = try JSONEncoder().encode(snapshot)
        try await Task.detached(priority: .utility) {
            let dir = package.appendingPathComponent(ImagerySnapshot.folder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try jpeg.write(to: package.appendingPathComponent(snapshot.fileName), options: .atomic)
            try meta.write(to: package.appendingPathComponent(ImagerySnapshot.metadataPath(for: type.rawValue)), options: .atomic)
        }.value
        return snapshot
    }
}

// MARK: Basemap in exports

/// Basemap to include in an export: the GeoTIFF basemap when in use, otherwise the HD Apple Maps image of the current
/// type. Loaded off the main thread (`load()`); a GeoTIFF is converted to JPEG so PDF and OMAP/DXF can use it.
struct ExportBackgroundSource: Sendable {
    var label: String
    var fileURL: URL
    var pixelWidth: Int
    var pixelHeight: Int
    var corners: [Point2D]
    var opacity: Double
    var attribution: String?
    var convertToJPEG: Bool

    func load() throws -> ExportBackground {
        var data = try Data(contentsOf: fileURL)
        if convertToJPEG {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw WorkspaceModel.ImageryError.encoding }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw WorkspaceModel.ImageryError.encoding
            }
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw WorkspaceModel.ImageryError.encoding }
            data = out as Data
        }
        return ExportBackground(imageData: data, pixelWidth: pixelWidth, pixelHeight: pixelHeight, corners: corners,
                                opacity: opacity, attribution: attribution, fileExtension: "jpg")
    }
}

extension WorkspaceModel {
    /// The basemap currently shown in the workspace, for exports; nil when there is none (live map only).
    var exportBackgroundSource: ExportBackgroundSource? {
        guard let zone else { return nil }
        if usesBasemapImage, let image = project.basemapImage, let fileURL = basemapImageURL {
            return ExportBackgroundSource(label: "Image basemap \(image.originalName)", fileURL: fileURL,
                                          pixelWidth: image.width, pixelHeight: image.height, corners: image.corners(in: zone),
                                          opacity: image.opacityValue, attribution: nil, convertToJPEG: true)
        }
        // The HD image is exported in Live mode too (a live map can't be exported).
        if project.areaLocked, !usesBasemapImage, let s = imagerySnapshot, let fileURL = imagerySnapshotURL {
            let corners = [LatLon(lat: s.north, lon: s.west), LatLon(lat: s.north, lon: s.east),
                           LatLon(lat: s.south, lon: s.east), LatLon(lat: s.south, lon: s.west)].map(zone.project)
            return ExportBackgroundSource(label: "\(basemap.label) HD image", fileURL: fileURL, pixelWidth: s.width,
                                          pixelHeight: s.height, corners: corners, opacity: project.basemapOpacityValue,
                                          attribution: basemap == .standard ? "Map © Apple Maps" : "Imagery © Apple Maps",
                                          convertToJPEG: false)
        }
        return nil
    }
}
