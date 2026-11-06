import CakraCore
import Foundation

/// Color Hierarchy (tabel warna OCAD): objek digambar menurut urutan warna simbolnya di set simbol,
/// bukan urutan objek. Warna lebih atas menimpa warna di bawahnya (ISOM/ISSprOM).
extension WorkspaceModel {
    /// Salinan objek dengan prioritas warna dari set simbol (untuk peta, export, dan memilih objek).
    func layered(_ list: [Feature]) -> [Feature] {
        guard let lookup = symbolLookup else { return list }
        return list.withColorPriorities(lookup)
    }

    var layeredFeatures: [Feature] { layered(features) }

    /// Objek yang terlihat paling atas lebih dulu (urutan untuk mengetuk/memilih objek).
    var featuresTopDown: [Feature] {
        let list = layeredFeatures
        return ColorHierarchy.topDownIndices(list).map { features[$0] }
    }
}
