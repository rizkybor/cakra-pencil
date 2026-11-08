import Darwin
import Foundation

/// What the device can do for fieldwork.
enum DeviceCapabilities {
    /// GPS track recording: only on iPad Wi-Fi + Cellular. Wi-Fi-only iPads have no GPS chip at all, and the Mac has
    /// none either; there the recorder and its buttons are not shown.
    ///
    /// Detection: a cellular iPad has a baseband modem, which iOS exposes as `pdp_ip` network interfaces (present even
    /// without a SIM); Wi-Fi-only iPads have none. Simulator: available for development (`-cp-wifi-only` hides it).
    static let canRecordTracks: Bool = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-cp-wifi-only") { return false }
        #endif
        if ProcessInfo.processInfo.isMacCatalystApp || ProcessInfo.processInfo.isiOSAppOnMac { return false }
        #if targetEnvironment(simulator)
        return true
        #else
        return hasCellularModem
        #endif
    }()

    private static var hasCellularModem: Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = p {
            if String(cString: ifa.pointee.ifa_name).hasPrefix("pdp_ip") { return true }
            p = ifa.pointee.ifa_next
        }
        return false
    }
}
