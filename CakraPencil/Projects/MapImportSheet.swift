import CakraCore
import MapKit
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
    @StateObject private var check = ZoneLocationCheck()
    /// Set when the starting zone landed in the sea and a better zone was picked automatically.
    @State private var autoSuggested: String?
    @State private var suggestMessage: String?
    @State private var confirmSea = false
    @State private var didAutoSuggest = false

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
    private var center: LatLon? { center(in: zone) }

    private func center(in zone: UTMZone) -> LatLon? {
        pending.content.extent.map { zone.unproject(Point2D(x: ($0.minX + $0.maxX) / 2, y: ($0.minY + $0.maxY) / 2)) }
    }

    private var isInSea: Bool { if case .sea = check.result { return true } else { return false } }
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
                        Segmented("Hemisphere", selection: $isNorth, [.init(true, "North"), .init(false, "South")])
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
                        locationPreview(c)
                        placeRow
                        if !zoneIsFixed {
                            suggestButton
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text(zoneIsFixed
                         ? "The OOM file stores its location, so the zone is set automatically."
                         : "OCAD files store UTM coordinates but not the zone. Check that the pin and place name show where the map really is (e.g. Lombok = 50 South, Jakarta = 48 South); if not, use Suggest zone or change the zone.")
                }

                Section("Sheet") {
                    LabeledContent("Scale") { Text(verbatim: "1:\(sheetScale)").font(CP.mono(15)) }
                    if sheetScale != pending.content.scale {
                        Text("The map is 1:\(pending.content.scale); the project uses the nearest preset. Change it later in the Map tab.")
                            .font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                    }
                }
            }
            .onAppear { if let c = center { check.check(c) } }
            .onChange(of: zone) { _, _ in
                suggestMessage = nil
                if let c = center { check.check(c) }
            }
            .onChange(of: check.result) { _, r in
                // Only the starting zone (e.g. from the last project) is corrected automatically, so a zone the user
                // picks is never overridden; later results just show the warning.
                guard !didAutoSuggest, r != .checking else { return }
                didAutoSuggest = true
                if case .sea = r, !zoneIsFixed {
                    let from = zone.label
                    Task { await suggest(note: { "Zone changed from \(from) (the map center was in the sea) to \($0)." }) }
                }
            }
            .alert("Map center is in the sea", isPresented: $confirmSea) {
                Button("Create anyway") { create() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("With \(zone.label) the map lands in the sea, so the UTM zone is probably wrong. Create the project anyway?")
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
                    Button("Create") { if isInSea { confirmSea = true } else { create() } }
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

    /// Small map with a pin at the map center: shows at a glance whether the zone puts the map in the right place.
    private func locationPreview(_ c: LatLon) -> some View {
        let coord = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
        return Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 120_000, longitudinalMeters: 120_000)),
                   interactionModes: []) {
            Marker(name.isEmpty ? "Map" : name, coordinate: coord).tint(.orange)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: CP.Radius.control))
        .id("\(zone.label)")  // new camera when the zone changes
        .accessibilityLabel("Map center preview")
    }

    @ViewBuilder
    private var placeRow: some View {
        switch check.result {
        case .checking:
            HStack(spacing: CP.Space.s) {
                ProgressView().controlSize(.small)
                Text("Checking the location…").font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
            }
        case let .land(place):
            Label(place, systemImage: "checkmark.circle.fill")
                .font(.system(size: CP.fs(13), weight: .medium))
                .foregroundStyle(CP.sage.strong)
                .accessibilityIdentifier("mapImportPlace")
        case let .sea(ocean):
            Label("The map center is in the sea\(ocean.map { " (\($0))" } ?? ""). The UTM zone is probably wrong\(zoneIsFixed ? "." : " — use Suggest zone or change it."))",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: CP.fs(13), weight: .medium))
                .foregroundStyle(CP.rose.strong)
                .accessibilityIdentifier("mapImportWarning")
        case .unknown:
            Label("Couldn't check the location (offline?). Make sure the map preview shows the right place.", systemImage: "wifi.slash")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.butter.strong)
        }
        if let autoSuggested {
            Text(autoSuggested).font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
                .accessibilityIdentifier("mapImportAutoZone")
        }
    }

    private var suggestButton: some View {
        HStack {
            Button {
                Task { await suggest(note: nil) }
            } label: {
                Label("Suggest zone", systemImage: "location.magnifyingglass")
            }
            .disabled(check.isSuggesting)
            .accessibilityIdentifier("mapImportSuggest")
            if check.isSuggesting { ProgressView().controlSize(.small) }
            if let suggestMessage {
                Text(suggestMessage).font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted)
            }
        }
    }

    /// Try the neighboring zones (then the other hemisphere) until the map center lands on land.
    private func suggest(note: ((String) -> String)?) async {
        let start = zone
        guard let found = await check.suggest(MapFileImport.candidateZones(around: start), center: { center(in: $0) }) else {
            suggestMessage = "No zone nearby puts the map on land."
            return
        }
        zoneNumber = found.zone.number
        isNorth = found.zone.isNorth
        if let note { autoSuggested = note(found.zone.label) } else { suggestMessage = "\(found.zone.label): \(found.place)" }
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
