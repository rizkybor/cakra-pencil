import CakraCore
import Foundation

/// Basemap gambar ter-georeferensi (GeoTIFF) di tab Peta: impor, opacity, tampil/sembunyi, hapus.
/// Berkas disalin ke paket proyek, jadi ikut ke file .cpencil (iPad ↔ Mac).
extension WorkspaceModel {
    var basemapImageURL: URL? {
        project.basemapImage.map { url.appendingPathComponent($0.fileName) }
    }

    func importBasemapImage(from source: URL) async {
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
            notice = "Basemap gagal diimpor: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        case let .success(info):
            let old = basemapImageURL
            var next = project
            next.basemapImage = BasemapImage(fileName: fileName, originalName: source.lastPathComponent, crs: info.crs,
                                             originX: info.originX, originY: info.originY, pixelSizeX: info.pixelSizeX,
                                             pixelSizeY: info.pixelSizeY, width: info.width, height: info.height)
            apply(next, recordUndo: false)
            if let old { try? FileManager.default.removeItem(at: old) }
            var parts = ["Basemap \(source.lastPathComponent) diimpor"]
            if let zone, let image = project.basemapImage {
                let size = image.groundSizeM(in: zone)
                parts.append("\(Fmt.meters(size.width)) × \(Fmt.meters(size.height))")
                if let frame, let e = image.extent(in: zone), !e.intersects(frame.extent) {
                    parts.append("di luar frame peta")
                }
            }
            notice = parts.joined(separator: " · ") + "."
            zoomToBasemapImage()
        }
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
        notice = "Basemap gambar dihapus."
    }

    func zoomToBasemapImage() {
        guard let zone, let e = project.basemapImage?.extent(in: zone) else { return }
        mapCommand = MapCommand(kind: .zoomToExtent(e))
    }
}
