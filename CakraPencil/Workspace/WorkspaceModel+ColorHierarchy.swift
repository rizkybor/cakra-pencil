import CakraCore
import Foundation

/// Color Hierarchy (OCAD color table): objects are drawn in the order of their symbol's color in the symbol set,
/// not in object order. Higher colors overprint the colors below them (ISOM/ISSprOM).
extension WorkspaceModel {
    /// Copy of the objects with color priority from the symbol set (for the map, export, and object selection).
    func layered(_ list: [Feature]) -> [Feature] {
        guard let lookup = symbolLookup else { return list }
        return list.withColorPriorities(lookup)
    }

    var layeredFeatures: [Feature] { layered(features) }

    /// Topmost visible objects first (order for tapping/selecting objects).
    var featuresTopDown: [Feature] {
        let list = layeredFeatures
        return ColorHierarchy.topDownIndices(list).map { features[$0] }
    }
}
