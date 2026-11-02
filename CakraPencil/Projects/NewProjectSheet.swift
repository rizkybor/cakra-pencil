import CakraCore
import SwiftUI

/// FR-1.1: nama, skala target, dpi sketsa. Orientasi dan margin bisa diubah lagi sebelum area dikunci.
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
                    TextField("Nama proyek", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Lembar") {
                    Picker("Skala", selection: $scale) {
                        ForEach(MapPresets.scales, id: \.self) { Text(verbatim: "1:\($0)").tag($0) }
                    }
                    Picker("Resolusi sketsa", selection: $dpi) {
                        ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                    }
                    Picker("Orientasi A4", selection: $orientation) {
                        Text("Portrait").tag(SheetOrientation.portrait)
                        Text("Landscape").tag(SheetOrientation.landscape)
                    }
                    .pickerStyle(.segmented)
                    Picker("Margin cetak", selection: $margin) {
                        ForEach(MapPresets.marginsMM, id: \.self) { Text(Fmt.mm($0, decimals: 0)).tag($0) }
                    }
                }
                Section("Ukuran area") {
                    LabeledContent("Tanah") {
                        Text("\(Fmt.meters(sheet.groundWidthM, decimals: 1)) × \(Fmt.meters(sheet.groundHeightM, decimals: 1))").font(CP.mono(15))
                    }
                    LabeledContent("Kertas") {
                        Text("\(Fmt.mm(sheet.mappingWidthMM, decimals: 0)) × \(Fmt.mm(sheet.mappingHeightMM, decimals: 0))").font(CP.mono(15))
                    }
                    LabeledContent("Raster") {
                        let d = sheet.pixelDimensions(dpi: dpi)
                        Text(Fmt.pixels(d.width, d.height)).font(CP.mono(15))
                    }
                    LabeledContent("Piksel di tanah") {
                        Text(Fmt.meters(sheet.pixelSizeM(dpi: dpi), decimals: 3)).font(CP.mono(15))
                    }
                }
            }
            .navigationTitle("Proyek baru")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Buat") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(Project(name: trimmed.isEmpty ? "Proyek tanpa nama" : trimmed, sheet: sheet, sketchDPI: dpi))
                        dismiss()
                    }
                }
            }
        }
    }
}
