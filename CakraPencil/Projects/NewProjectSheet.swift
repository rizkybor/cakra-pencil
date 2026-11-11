import CakraCore
import SwiftUI

/// FR-1.1: name, target scale, sketch dpi. Orientation and margin can still be changed before the area is locked.
/// "Indoor map (ISInOM)" makes the map follow ISInOM 6.7.3 (base 1:700) instead of ISOM / ISSprOM from the scale.
struct NewProjectSheet: View {
    var onCreate: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scale = 4000
    @State private var dpi = 900
    @State private var orientation = SheetOrientation.portrait
    @State private var margin = 0.0
    @State private var indoor = false
    /// The outdoor scale to return to when "Indoor map" is switched off again.
    @State private var outdoorScale = 4000

    private var sheet: SheetSpec {
        SheetSpec(orientation: orientation, marginMM: margin, scaleDenominator: scale, standardOverride: indoor ? .isinom : nil)
    }

    /// Indoor on: 1:700 (the ISInOM base scale) when the plan allows it, else the scale stays and the license sheet
    /// explains that indoor scales need a key. Off: back to the outdoor scale chosen before.
    private func setIndoor(_ on: Bool) {
        indoor = on
        if on {
            outdoorScale = scale
            if FreeLimits.allows(scale: MapStandard.isinom.baseScale) {
                scale = MapStandard.isinom.baseScale
            } else {
                LicenseManager.shared.require(.allScales)
            }
        } else if !MapPresets.scales.contains(scale) {
            scale = FreeLimits.allows(scale: outdoorScale) ? outdoorScale : FreeLimits.scales[0]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    Toggle("Indoor map (ISInOM)", isOn: Binding(get: { indoor }, set: { setIndoor($0) }))
                        .tint(CP.sage.strong)
                        .accessibilityIdentifier("newProjectIndoor")
                    Picker("Scale", selection: $scale) {
                        ForEach(FreeLimits.pickableScales(current: scale, indoor: indoor), id: \.self) { Text(verbatim: "1:\($0)").tag($0) }
                    }
                    .accessibilityIdentifier("newProjectScale")
                    // Starter: 1:4000 and 1:10000; the other scales come with a license key.
                    if !LicenseManager.shared.isPro {
                        Button {
                            LicenseManager.shared.require(.allScales)
                        } label: {
                            Label("More scales with a license", systemImage: "lock")
                                .font(.system(size: CP.fs(13)))
                        }
                        .accessibilityIdentifier("newProjectMoreScales")
                    }
                    Picker("Sketch resolution", selection: $dpi) {
                        ForEach(MapPresets.dpis, id: \.self) { Text(verbatim: "\($0) dpi").tag($0) }
                    }
                    Segmented("A4 orientation", selection: $orientation, [.init(.portrait, "Portrait"), .init(.landscape, "Landscape")])
                    Picker("Print margin", selection: $margin) {
                        ForEach(MapPresets.marginsMM, id: \.self) { Text(Fmt.mm($0, decimals: 0)).tag($0) }
                    }
                } header: {
                    Text("Sheet")
                } footer: {
                    Text(indoor
                         ? "Indoor orienteering (ISInOM 6.7.3): symbols and course sizes from the 1:700 base scale — enlarged on larger scales such as 1:500, never reduced on smaller ones. No contours; north orientation is not required."
                         : "Symbols follow \(sheet.mapStandard.label), chosen from the scale (sprint 1:5000 and larger, forest from 1:7500).")
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
                ToolbarItem(placement: .cancellationAction) { Group {
                    CloseIconButton(label: "Cancel") { dismiss() }
                }.buttonStyle(SecondaryButtonStyle(compact: true)) }.plainBar()
                ToolbarItem(placement: .sheetConfirm) { Group {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(Project(name: trimmed.isEmpty ? "Untitled project" : trimmed, sheet: sheet, sketchDPI: dpi))
                        dismiss()
                    }
                }.buttonStyle(PrimaryButtonStyle(compact: true)) }.plainBar()
            }
        }
    }
}
