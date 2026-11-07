import CakraCore
import Foundation

/// Symbol guide: the IOF specification (ISOM for forest maps, ISSprOM for sprint maps) shown next to the map.
extension WorkspaceModel {
    /// Open (or switch) the guide to a symbol code; the specification follows the map scale unless the user picked one.
    func openSymbolGuide(_ code: String, name: String) {
        let spec = symbolGuide?.spec ?? SymbolGuide.Spec.for(scaleDenominator: project.sheet.scaleDenominator)
        symbolGuide = SymbolGuideRequest(code: code, name: name, spec: spec)
    }

    /// ⇧⌘/ and the guide buttons: open for the active symbol, else the selected object's symbol; close when open.
    func toggleSymbolGuide() {
        if symbolGuide != nil { closeSymbolGuide(); return }
        if let s = activeSymbol {
            openSymbolGuide(s.code, name: s.name)
        } else if let f = selectedFeature, let code = f.symbolCode {
            openSymbolGuide(code, name: f.symbolName ?? "")
        } else {
            openSymbolGuide("", name: "")
            notice = "Pick a symbol (or select an object) to jump to its rules in the guide."
        }
    }

    func closeSymbolGuide() {
        symbolGuide = nil
        symbolGuideSearching = false
    }

    func setSymbolGuideSpec(_ spec: SymbolGuide.Spec) {
        guard var g = symbolGuide, g.spec != spec else { return }
        g.spec = spec
        symbolGuide = g
    }
}
