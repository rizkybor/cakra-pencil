import CakraCore
import CoreLocation
import Foundation

/// GPS for fieldwork on iPad: records tracks (keeps running with the screen off), averages positions, and gives the
/// current position for field notes. Separate from the map's position radar. Uses "when in use" permission; while
/// a track is recording, iOS keeps location updates running in the background (blue status bar indicator).
///
/// DEBUG: `-cp-fake-gps <lat>,<lon>` feeds synthetic fixes walking north-east from that point (UI tests, simulator).
@MainActor
final class FieldRecorder: NSObject, ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case saver = "Battery saver", normal = "Normal", detail = "Detailed"
        var id: String { rawValue }
        /// Minimum distance between recorded points (m).
        var distanceFilter: CLLocationDistance { self == .saver ? 10 : self == .normal ? 3 : 1 }
        var accuracy: CLLocationAccuracy { self == .saver ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyBest }
    }

    struct AveragingState {
        var averager = PositionAverager()
        var started = Date()
        var targetS: Double
        var progress: Double { min(1, Date().timeIntervalSince(started) / targetS) }
    }

    @Published private(set) var recordingTrackID: UUID?
    @Published private(set) var isPaused = false
    @Published var mode: Mode = .normal { didSet { applyMode() } }
    @Published private(set) var lastFix: CLLocation?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var averaging: AveragingState?
    @Published private(set) var averagingResult: PositionAverager.Result?
    /// Updated with each recorded point (for the REC indicator).
    @Published private(set) var recordedPoints = 0
    @Published private(set) var recordingStarted: Date?

    var zone: UTMZone?
    var onTrackPoint: ((FieldTrack.Point) -> Void)?

    /// Set on resume: the next recorded point starts a new segment (the paused stretch isn't drawn or counted).
    private var segmentBreak = false
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0

    /// Time recorded so far, without the pauses.
    var recordingElapsed: TimeInterval {
        guard let start = recordingStarted else { return 0 }
        let pausedNow = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
        return max(0, Date().timeIntervalSince(start) - pausedTotal - pausedNow)
    }

    private let manager = CLLocationManager()
    private var wantsNoteFix = false
    private var timer: Timer?
    private var fakeOrigin: LatLon?
    private var fakeStep = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
        applyMode()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-cp-fake-gps"), i + 1 < args.count {
            let v = args[i + 1].split(separator: ",").compactMap { Double($0) }
            if v.count == 2 { fakeOrigin = LatLon(lat: v[0], lon: v[1]); authorization = .authorizedWhenInUse }
        }
        #endif
    }

    var isRecording: Bool { recordingTrackID != nil }

    /// The fix comes from an external receiver (Bluetooth / Lightning GNSS such as Bad Elf or Garmin GLO): iOS feeds
    /// accessory positions into Core Location, so tracks, notes and averaging use it automatically.
    var isExternalGNSS: Bool { lastFix?.sourceInformation?.isProducedByAccessory ?? false }

    /// GPS fixes are expected on this device: iPad with location services (Wi-Fi iPads without GPS give poor fixes).
    var hasFix: Bool { lastFix.map { Date().timeIntervalSince($0.timestamp) < 15 } ?? false }

    /// Current position in the project's zone, with accuracy (m).
    var currentPosition: (Point2D, Double)? {
        guard let f = lastFix, hasFix, let zone else { return nil }
        return (zone.project(LatLon(lat: f.coordinate.latitude, lon: f.coordinate.longitude)), f.horizontalAccuracy)
    }

    // MARK: Track

    func startTrack(id: UUID) {
        recordingTrackID = id
        isPaused = false
        recordedPoints = 0
        segmentBreak = false
        pausedAt = nil
        pausedTotal = 0
        recordingStarted = Date()
        updateRunning()
    }

    func pause() {
        if !isPaused { pausedAt = Date() }
        isPaused = true
        updateRunning()
    }
    func resume() {
        if isPaused, recordedPoints > 0 { segmentBreak = true }
        if let p = pausedAt { pausedTotal += Date().timeIntervalSince(p); pausedAt = nil }
        isPaused = false
        updateRunning()
    }

    func stopTrack() {
        recordingTrackID = nil
        isPaused = false
        recordingStarted = nil
        updateRunning()
    }

    // MARK: Averaging

    func startAveraging(seconds: Double) {
        averagingResult = nil
        averaging = AveragingState(targetS: seconds)
        updateRunning()
    }

    func cancelAveraging() {
        averaging = nil
        averagingResult = nil
        updateRunning()
    }

    /// Clears the finished result after it was saved.
    func clearAveragingResult() { averagingResult = nil }

    // MARK: Notes

    /// Keep GPS running while the new-note sheet is open (for its position).
    func setWantsNoteFix(_ on: Bool) {
        wantsNoteFix = on
        updateRunning()
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    // MARK: Engine

    private func applyMode() {
        manager.distanceFilter = isRecording ? mode.distanceFilter : kCLDistanceFilterNone
        manager.desiredAccuracy = averaging != nil || wantsNoteFix ? kCLLocationAccuracyBest : mode.accuracy
    }

    private func updateRunning() {
        let tracking = isRecording && !isPaused
        let needed = tracking || averaging != nil || wantsNoteFix
        applyMode()
        #if !targetEnvironment(macCatalyst)
        manager.allowsBackgroundLocationUpdates = tracking
        manager.showsBackgroundLocationIndicator = tracking
        #endif
        if fakeOrigin != nil {
            timer?.invalidate()
            timer = needed ? Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.emitFakeFix() }
            } : nil
            return
        }
        if needed {
            requestPermission()
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    private func emitFakeFix() {
        guard let o = fakeOrigin else { return }
        fakeStep += 1
        // Walk ~4 m per fix north-east while tracking; jitter around one spot while averaging.
        let walking = isRecording && !isPaused && averaging == nil
        let d = walking ? Double(fakeStep) * 4 : 0
        let jitter = averaging != nil ? Double((fakeStep * 7) % 5 - 2) : 0
        let lat = o.lat + (d * 0.7 + jitter) / 111_320
        let lon = o.lon + (d * 0.7 - jitter) / (111_320 * cos(o.lat * .pi / 180))
        handle(CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 40,
                          horizontalAccuracy: 4, verticalAccuracy: 6, timestamp: Date()))
    }

    fileprivate func handle(_ loc: CLLocation) {
        guard loc.horizontalAccuracy > 0 else { return }
        lastFix = loc
        guard let zone else { return }
        let p = zone.project(LatLon(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude))
        if isRecording, !isPaused, loc.horizontalAccuracy <= 30 {
            onTrackPoint?(FieldTrack.Point(position: p, time: loc.timestamp, accuracyM: loc.horizontalAccuracy,
                                           elevationM: loc.verticalAccuracy > 0 ? loc.altitude : nil,
                                           startsSegment: segmentBreak ? true : nil))
            segmentBreak = false
            recordedPoints += 1
        }
        if var a = averaging {
            a.averager.add(.init(position: p, accuracyM: loc.horizontalAccuracy, time: loc.timestamp))
            averaging = a
            if a.progress >= 1 {
                averagingResult = a.averager.result
                averaging = nil
                updateRunning()
            }
        }
    }
}

extension FieldRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { for l in locations { handle(l) } }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { authorization = status }
    }
}
