import CakraCore
import SwiftUI

/// FR-1.1: name, target scale, sketch dpi. Orientation and margin can still be changed before the area is locked.
struct NewProjectSheet: View {
    var onCreate: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scale = 4000
    @State private var dpi = 900
    @State private var orientation = SheetOrientation.portrait
    @State private var margin = 0.0

    private var sheet: SheetSpec {
        SheetSpec(orientation: orientation, marginMM: margin, scaleDenominator: scale)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Sheet") {
                    Picker("Scale", selection: $scale) {
                        ForEach(MapPresets.scales, id: \.self) { Text(verbatim: "1:\($0)").tag($0) }
                    }
                    Picker("Sketch resolution", selection: $dpi) {
                        ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                    }
                    Segmented("A4 orientation", selection: $orientation, [.init(.portrait, "Portrait"), .init(.landscape, "Landscape")])
                    Picker("Print margin", selection: $margin) {
                        ForEach(MapPresets.marginsMM, id: \.self) { Text(Fmt.mm($0, decimals: 0)).tag($0) }
                    }
                }
                Section("Area size") {
                    LabeledContent("Ground") {
                        Text("\(Fmt.meters(sheet.groundWidthM, decimals: 1)) × \(Fmt.meters(sheet.groundHeightM, decimals: 1))").font(CP.mono(15))
                    }
                    LabeledContent("Paper") {
                        Text("\(Fmt.mm(sheet.mappingWidthMM, decimals: 0)) × \(Fmt.mm(sheet.mappingHeightMM, decimals: 0))").font(CP.mono(15))
                    }
                    LabeledContent("Raster") {
                        let d = sheet.pixelDimensions(dpi: dpi)
                        Text(Fmt.pixels(d.width, d.height)).font(CP.mono(15))
                    }
                    LabeledContent("Pixel on ground") {
                        Text(Fmt.meters(sheet.pixelSizeM(dpi: dpi), decimals: 3)).font(CP.mono(15))
                    }
                }
            }
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(Project(name: trimmed.isEmpty ? "Untitled project" : trimmed, sheet: sheet, sketchDPI: dpi))
                        dismiss()
                    }
                }
            }
        }
    }
}
