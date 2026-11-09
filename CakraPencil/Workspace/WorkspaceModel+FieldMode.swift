import CakraCore
import CoreLocation
import UIKit

/// Ready-for-the-field check and field mode (iPad).
extension WorkspaceModel {
    struct FieldReadiness {
        var areaLocked: Bool
        var imagery: [(Basemap, Bool)]
        var contours: Bool
        var freeBytes: Int64?
        var battery: Float?
        var location: CLAuthorizationStatus

        var imageryReady: Bool { imagery.allSatisfy(\.1) }
        /// Everything needed offline is on the device.
        var offlineReady: Bool { areaLocked && imageryReady && contours }
        var lowStorage: Bool { (freeBytes ?? .max) < 500_000_000 }
        var lowBattery: Bool { (battery ?? 1) >= 0 && (battery ?? 1) < 0.3 }
    }

    func fieldReadiness() -> FieldReadiness {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let free = (try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        return FieldReadiness(areaLocked: project.areaLocked,
                              imagery: Basemap.allCases.map { ($0, hasImagery($0)) },
                              contours: dem != nil || importedContours != nil,
                              freeBytes: free,
                              battery: level < 0 ? nil : level,
                              location: recorder.authorization)
    }

    /// Download what is missing for offline use: HD images of all three types and the built-in contours.
    func downloadMissingForField() {
        refreshImagery()
        if dem == nil, importedContours == nil, LicenseManager.shared.isPro {
            Task { await downloadBuiltInContours() }
        }
        recorder.requestPermission()
    }

    func enterFieldMode() {
        guard !fieldMode, LicenseManager.shared.require(.fieldwork) else { return }
        fieldMode = true
        UIApplication.shared.isIdleTimerDisabled = true      // screen stays on
        showsMyLocation = true
        mapCommand = MapCommand(kind: .followUser)
        recorder.requestPermission()
    }

    func exitFieldMode() {
        guard fieldMode else { return }
        fieldMode = false
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
