import CakraCore
import Foundation

/// Georeferenced image basemap (GeoTIFF) in the Map tab: import, opacity, show/hide, delete.
/// The file is copied into the project package, so it travels with the .cpencil file (iPad ↔ Mac).
extension WorkspaceModel {
    var basemapImageURL: URL? {
        project.basemapImage.map { url.appendingPathComponent($0.fileName) }
    }

    /// Read the GeoTIFF georeference and copy the file into the project package. nil = failed (message in `notice`).
    private func copyBasemapImage(from source: URL) async -> BasemapImage? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.isEmpty ? "tif" : source.pathExtension.lowercased()
        let fileName = "basemap-\(UUID().uuidString.prefix(8)).\(ext)"
        let target = url.appendingPathComponent(fileName)
        let result = await Task.detached(priority: .userInitiated) { () -> Result<GeoTIFFGeoref.Info, Error> in
            Result {
                let data = try Data(contentsOf: source)
                let info = try GeoTIFFGeoref.read(data)
                try data.write(to: target, options: .atomic)
                return info
            }
        }.value
        switch result {
        case let .failure(error):
            notice = "Basemap import failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            return nil
        case let .success(info):
            var image = BasemapImage(fileName: fileName, originalName: source.lastPathComponent, crs: info.crs,
                                     originX: info.originX, originY: info.originY, pixelSizeX: info.pixelSizeX,
                                     pixelSizeY: info.pixelSizeY, width: info.width, height: info.height)
            image.dateTime = info.dateTime
            return image
        }
    }

    func importBasemapImage(from source: URL) async {
        guard let image = await copyBasemapImage(from: source) else { return }
        let old = basemapImageURL
        var next = project
        next.basemapImage = image
        apply(next, recordUndo: false)
        if let old { try? FileManager.default.removeItem(at: old) }
        var parts = ["Basemap \(source.lastPathComponent) imported"]
        if let zone {
            let size = image.groundSizeM(in: zone)
            parts.append("\(Fmt.meters(size.width)) × \(Fmt.meters(size.height))")
        }
        notice = parts.joined(separator: " · ") + "."
        // The area outside the frame is masked: an image that doesn't touch the frame won't be visible → offer to move the frame.
        if !basemapImageTouchesFrame {
            confirmMoveFrameToBasemap = true
        } else {
            mapCommand = MapCommand(kind: .zoomToFrame)
        }
    }

    /// The image basemap touches the map frame (so it is visible).
    var basemapImageTouchesFrame: Bool {
        guard let zone, let frame, let e = project.basemapImage?.extent(in: zone) else { return true }
        return e.intersects(frame.extent)
    }

    /// Move the frame (size and scale unchanged) to the center of the image basemap; one undo step.
    /// The project's UTM zone doesn't change, so existing objects keep their coordinates.
    func moveFrameToBasemapImage() {
        guard let zone, let image = project.basemapImage else { return }
        let center = zone.project(image.latLon(u: Double(image.width) / 2, v: Double(image.height) / 2))
        var next = project
        next.frameOrigin = MapFrame(center: center, sheet: project.sheet).snapped(toStep: project.snapStepM).origin
        apply(next)
        mapCommand = MapCommand(kind: .zoomToFrame)
        notice = "Frame moved to basemap \(image.originalName)."
    }

    /// Select Area skipped: the map area is taken from the GeoTIFF basemap. UTM zone from the image, frame (the
    /// currently selected scale and orientation) centered on the image, area locked right away, image becomes the basemap.
    func skipAreaSelection(withBasemap source: URL) async {
        guard !project.areaLocked, let image = await copyBasemapImage(from: source) else { return }
        let center = image.latLon(u: Double(image.width) / 2, v: Double(image.height) / 2)
        let zone: UTMZone
        if case let .utm(epsg) = image.crs, let z = UTMZone(epsg: epsg) { zone = z } else { zone = UTMZone(containing: center) }
        let old = basemapImageURL
        var next = project
        next.crsEPSG = zone.epsg
        next.frameOrigin = MapFrame(center: zone.project(center), sheet: project.sheet).snapped(toStep: project.snapStepM).origin
        next.basemapImage = image
        next.areaLocked = true
        next.areaBackup = nil
        apply(next)
        if let old { try? FileManager.default.removeItem(at: old) }
        tool = .pen
        mapCommand = MapCommand(kind: .zoomToFrame)
        let size = image.groundSizeM(in: zone)
        var parts = ["Area taken from basemap \(source.lastPathComponent) (\(Fmt.meters(size.width)) × \(Fmt.meters(size.height)))"]
        if let frame, size.width < frame.widthM || size.height < frame.heightM {
            parts.append("image is smaller than the 1:\(project.sheet.scaleDenominator) frame")
        }
        notice = parts.joined(separator: " · ") + "."
    }

    /// The image basemap (GeoTIFF) is in use: Apple imagery is hidden, opacity applies to the image.
    var usesBasemapImage: Bool { project.basemapImage?.isVisible == true }

    /// Opacity of the basemap in use (GeoTIFF when active, otherwise Satellite/Hybrid/Standard imagery).
    var activeBasemapOpacity: Double {
        usesBasemapImage ? (project.basemapImage?.opacityValue ?? 1) : project.basemapOpacityValue
    }

    func setActiveBasemapOpacity(_ value: Double) {
        if usesBasemapImage { setBasemapImageOpacity(value) } else { setBasemapOpacity(value) }
    }

    func setBasemapImageOpacity(_ value: Double) {
        guard var image = project.basemapImage else { return }
        image.opacity = (min(max(value, 0), 1) * 100).rounded() / 100
        var next = project
        next.basemapImage = image
        apply(next, recordUndo: false)
    }

    func setBasemapImageVisible(_ on: Bool) {
        guard var image = project.basemapImage else { return }
        image.isVisible = on
        var next = project
        next.basemapImage = image
        apply(next, recordUndo: false)
    }

    func removeBasemapImage() {
        guard let old = basemapImageURL else { return }
        var next = project
        next.basemapImage = nil
        apply(next, recordUndo: false)
        try? FileManager.default.removeItem(at: old)
        notice = "Image basemap deleted."
    }

    func zoomToBasemapImage() {
        guard let zone, let e = project.basemapImage?.extent(in: zone) else { return }
        mapCommand = MapCommand(kind: .zoomToExtent(e))
    }
}
