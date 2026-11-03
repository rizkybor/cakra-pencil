import CakraCore
import MapKit
import SwiftUI

/// Saran lokasi selagi mengetik (MKLocalSearchCompleter), plus input koordinat lat/lon atau UTM.
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
        // Bias ke Indonesia; hasil luar negeri tetap muncul bila namanya cocok.
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

/// Kolom cari dengan daftar saran di bawahnya.
struct LocationSearchField: View {
    @ObservedObject var model: WorkspaceModel
    var prominent = false
    @StateObject private var search = LocationSearchModel()
    @FocusState private var focused: Bool

    private var showsList: Bool {
        focused && (search.coordinate != nil || !search.completions.isEmpty)
    }

    var body: some View {
        HStack(spacing: CP.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(CP.inkMuted)
            TextField("Cari tempat, alamat, lat, lon, atau UTM", text: $search.query)
                .font(.system(size: prominent ? 17 : 15))
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
                    .accessibilityLabel("Hapus pencarian")
            }
        }
        .padding(.horizontal, CP.Space.m)
        .frame(minHeight: prominent ? 48 : 36)
        .background(prominent ? CP.paper : CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(focused ? CP.sky.strong : CP.line, lineWidth: focused ? 1.5 : 1))
        .overlay(alignment: .topLeading) {
            if showsList {
                suggestions
                    .offset(y: (prominent ? 48 : 36) + CP.Space.xs)
            }
        }
        .zIndex(10)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let c = search.coordinate {
                row(title: "Koordinat", subtitle: Fmt.latLon(c), symbol: "scope") { go(c) }
            }
            ForEach(Array(search.completions.enumerated()), id: \.offset) { _, item in
                row(title: item.title, subtitle: item.subtitle, symbol: "mappin") {
                    Task {
                        if let c = await search.resolve(item) { go(c) } else { model.notice = "Lokasi tidak bisa dibuka. Cek koneksi internet." }
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
                    Text(title).font(.system(size: 15)).foregroundStyle(CP.ink).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 13)).foregroundStyle(CP.inkMuted).lineLimit(1)
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
