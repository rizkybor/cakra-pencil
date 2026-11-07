import CakraCore
import SwiftUI

/// A map file (OCAD .ocd / OOM .omap, .xmap) picked from Open file in the project list, waiting to become a project.
struct PendingMapImport: Identifiable {
    let id = UUID()
    var fileName: String
    var content: MapFileContent
}

/// New project from a map file: name, UTM zone (OCAD files don't store it; OOM files do), and a location preview so the
/// zone can be checked. The project is created with its area locked on the map, objects and courses included.
struct MapImportSheet: View {
    let pending: PendingMapImport
    /// Zone to start with for OCAD files (e.g. the zone of the latest project).
    let suggestedZone: UTMZone
    var onCreate: (ProjectDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var zoneNumber: Int
    @State private var isNorth: Bool

    init(pending: PendingMapImport, suggestedZone: UTMZone, onCreate: @escaping (ProjectDocument) -> Void) {
        self.pending = pending
        self.suggestedZone = suggestedZone
        self.onCreate = onCreate
        let zone = pending.content.knownZone ?? suggestedZone
        _name = State(initialValue: (pending.fileName as NSString).deletingPathExtension)
        _zoneNumber = State(initialValue: zone.number)
        _isNorth = State(initialValue: zone.isNorth)
    }

    private var zone: UTMZone { UTMZone(number: zoneNumber, isNorth: isNorth) ?? suggestedZone }
    private var zoneIsFixed: Bool { pending.content.knownZone != nil }
    private var center: LatLon? {
        pending.content.extent.map { zone.unproject(Point2D(x: ($0.minX + $0.maxX) / 2, y: ($0.minY + $0.maxY) / 2)) }
    }
    private var sheetScale: Int { MapFileImport.sheetScale(for: pending.content.scale) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("mapImportName")
                } footer: {
                    Text(summary)
                }

                Section {
                    if zoneIsFixed {
                        LabeledContent("UTM zone") { Text(verbatim: zone.label).font(CP.mono(15)) }
                    } else {
                        Stepper(value: $zoneNumber, in: 1...60) {
                            LabeledContent("UTM zone") { Text(verbatim: "\(zoneNumber)").font(CP.mono(15)) }
                        }
                        .accessibilityIdentifier("mapImportZone")
                        Picker("Hemisphere", selection: $isNorth) {
                            Text("North").tag(true)
                            Text("South").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("mapImportHemisphere")
                    }
                    if let c = center {
                        LabeledContent("Map center") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.latLon(c)).font(CP.mono(13))
                                Text(Fmt.dms(c)).font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                            }
                        }
                        .accessibilityIdentifier("mapImportCenter")
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text(zoneIsFixed
                         ? "The OOM file stores its location, so the zone is set automatically."
                         : "OCAD files store UTM coordinates but not the zone. Choose the zone so the map center above is the right place (e.g. Lombok = 50 South, Jakarta = 48 South).")
                }

                Section("Sheet") {
                    LabeledContent("Scale") { Text(verbatim: "1:\(sheetScale)").font(CP.mono(15)) }
                    if sheetScale != pending.content.scale {
                        Text("The map is 1:\(pending.content.scale); the project uses the nearest preset. Change it later in the Map tab.")
                            .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    }
                }
            }
            #if DEBUG
            // `-cp-map-import-create`: press Create right away (Mac checks without UI automation).
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-cp-map-import-create") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { create() }
                }
            }
            #endif
            .navigationTitle("New project from map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                    .accessibilityIdentifier("mapImportCreate")
                }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(MapFileImport.document(name: trimmed.isEmpty ? "Imported map" : trimmed, content: pending.content, zone: zone))
        dismiss()
    }

    private var summary: String {
        let c = pending.content
        var parts = ["\(pending.fileName) · \(c.features.count) objects"]
        if let courses = c.courses { parts.append("\(courses.courses.count) courses, \(courses.controls.count) controls") }
        if c.report.skippedText > 0 { parts.append("\(c.report.skippedText) texts skipped") }
        if c.report.skippedPoints > 0 { parts.append("\(c.report.skippedPoints) point objects skipped") }
        return parts.joined(separator: " · ")
    }
}
