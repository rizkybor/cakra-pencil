import CakraCore
import CoreLocation
import Foundation

/// Checks where a map's center lands for a chosen UTM zone (Apple reverse geocoding): on land with a place name, or in
/// the sea / nowhere — which for an OCAD map usually means the zone is wrong. Also finds a zone that lands on land.
@MainActor
final class ZoneLocationCheck: ObservableObject {
    enum Result: Equatable {
        case checking
        /// Place name, e.g. "Mataram, West Nusa Tenggara, Indonesia".
        case land(String)
        /// In the sea (ocean name when known) or no place at all.
        case sea(String?)
        /// Couldn't check (offline or the service failed).
        case unknown
    }

    @Published private(set) var result = Result.checking
    @Published private(set) var isSuggesting = false
    private var task: Task<Void, Never>?

    func check(_ c: LatLon) {
        task?.cancel()
        result = .checking
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))  // zone stepper: wait until it settles
            guard !Task.isCancelled else { return }
            let r = await Self.lookup(c)
            guard !Task.isCancelled else { return }
            self?.result = r
        }
    }

    /// First zone among `candidates` whose map center lands on land; nil if none (or offline).
    func suggest(_ candidates: [UTMZone], center: (UTMZone) -> LatLon?) async -> (zone: UTMZone, place: String)? {
        isSuggesting = true
        defer { isSuggesting = false }
        for zone in candidates {
            guard let c = center(zone) else { continue }
            switch await Self.lookup(c) {
            case let .land(place): return (zone, place)
            case .unknown: return nil  // offline: stop instead of trying every zone
            default: break
            }
            // Apple's geocoder is rate limited.
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    static func lookup(_ c: LatLon) async -> Result {
        guard (-90...90).contains(c.lat), (-180...180).contains(c.lon) else { return .sea(nil) }
        do {
            let marks = try await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.lat, longitude: c.lon))
            guard let m = marks.first else { return .sea(nil) }
            // Open sea: an ocean but no country/locality.
            if m.country == nil || (m.ocean != nil && m.locality == nil && m.administrativeArea == nil) {
                return .sea(m.ocean ?? m.inlandWater)
            }
            var parts: [String] = []
            for p in [m.locality ?? m.subAdministrativeArea, m.administrativeArea, m.country] {
                if let p, !p.isEmpty, !parts.contains(p) { parts.append(p) }
            }
            return .land(parts.joined(separator: ", "))
        } catch let e as CLError where e.code == .geocodeFoundNoResult || e.code == .geocodeFoundPartialResult {
            return .sea(nil)
        } catch {
            return .unknown
        }
    }
}
