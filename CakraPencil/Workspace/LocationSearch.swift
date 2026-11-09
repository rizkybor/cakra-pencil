import CakraCore
import MapKit
import SwiftUI

/// Location suggestions while typing (MKLocalSearchCompleter), plus lat/lon or UTM coordinate input.
@MainActor
final class LocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { update() }
    }
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var coordinate: LatLon?
    @Published private(set) var isResolving = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        // Biased toward Indonesia; results abroad still appear when the name matches.
        completer.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -2.5, longitude: 118),
                                              span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 45))
    }

    private func update() {
        coordinate = CoordinateParser.parse(query)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.count < 2 || coordinate != nil {
            completer.cancel()
            completions = []
        } else {
            completer.queryFragment = q
        }
    }

    func clear() {
        query = ""
        completions = []
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { completions = Array(completer.results.prefix(6)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { completions = [] }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> LatLon? {
        isResolving = true
        defer { isResolving = false }
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first else {
            return nil
        }
        let c = item.placemark.coordinate
        return LatLon(lat: c.latitude, lon: c.longitude)
    }
}

/// Search field with a suggestion list below it.
struct LocationSearchField: View {
    @ObservedObject var model: WorkspaceModel
    var prominent = false
    @StateObject private var search = LocationSearchModel()
    @FocusState private var focused: Bool

    /// Compact in the top bar (same height as the button groups on Mac); a little taller while selecting the area.
    private var fieldHeight: CGFloat { prominent ? (CP.isMac ? 36 : 42) : (CP.isMac ? 28 : 34) }

    private var showsList: Bool {
        focused && (search.coordinate != nil || !search.completions.isEmpty)
    }

    var body: some View {
        HStack(spacing: CP.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(CP.inkMuted)
            TextField("Search place, address, lat, lon, or UTM", text: $search.query)
                .font(.system(size: prominent ? 16 : 14))
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .onSubmit(submit)
            if search.isResolving {
                ProgressView().controlSize(.small)
            } else if !search.query.isEmpty {
                Button { search.clear() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(CP.inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .help("Clear search")
            }
        }
        .padding(.horizontal, CP.Space.m)
        .frame(minHeight: fieldHeight)
        .searchFieldSurface(focused: focused)
        .overlay(alignment: .topLeading) {
            if showsList {
                suggestions
                    .offset(y: fieldHeight + CP.Space.xs)
            }
        }
        .zIndex(10)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let c = search.coordinate {
                row(title: "Coordinates", subtitle: Fmt.latLon(c), symbol: "scope") { go(c) }
            }
            ForEach(Array(search.completions.enumerated()), id: \.offset) { _, item in
                row(title: item.title, subtitle: item.subtitle, symbol: "mappin") {
                    Task {
                        if let c = await search.resolve(item) { go(c) } else { model.notice = "Couldn't open the location. Check your internet connection." }
                    }
                }
            }
        }
        .frame(minWidth: 320, maxWidth: 480, alignment: .leading)
        .cpPanel()
    }

    private func row(title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CP.Space.m) {
                Image(systemName: symbol).foregroundStyle(CP.sky.strong).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: CP.fs(15))).foregroundStyle(CP.ink).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CP.Space.m)
            .frame(minHeight: CP.hitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func go(_ c: LatLon) {
        focused = false
        model.goTo(c)
    }

    private func submit() {
        if let c = search.coordinate {
            go(c)
        } else if let first = search.completions.first {
            Task { if let c = await search.resolve(first) { go(c) } }
        } else {
            let q = search.query
            focused = false
            Task { await model.search(q) }
        }
    }
}
