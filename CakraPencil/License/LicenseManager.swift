import CakraCore
import CryptoKit
import Foundation
import Security
import SwiftUI
import UIKit

/// OCCA's license plan, from a license key issued in the Jendela Cakra Digital back office (HRIS › License Manager, product
/// `occa`).
///
/// Individual: Starter (free, no key) → Trial (every feature for a limited time) → Professional (paid per period) →
/// Lifetime (one-time payment, no end date).
/// Organization: teams, communities, clubs, and federations (one key, more devices).
/// Every key plan unlocks all features (`isPro`), Trial too while it runs; Starter has the `FreeLimits`.
///
/// Activation sends the key and this device's id to the back office; it answers with a token signed with Ed25519
/// (`payload.signature`, base64url). OCCA verifies the signature with the public key below, so the token can't be
/// forged or edited, and it works offline. The token is refreshed about weekly when online: a key that was switched
/// off or expired in the back office falls back to Free; after `offline_until` (≈ 30 days without a check) the app asks
/// to go online. Projects are never locked: on Free they still open and export to PDF.
///
/// Developer builds (Debug, or Release built with `OCCA_DEV`) are Lifetime unless "Simulate Starter" is on. Debug
/// launch argument `-cp-license starter|trial|professional|lifetime|organization|key` overrides (`free` / `pro` still
/// work; `key` = use the license key flow), `-cp-license-api <url>` the API.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    enum Plan: String, CaseIterable {
        case starter, trial, professional, lifetime, organization

        /// Value of the token's `plan`; "pro" is the old name of Professional.
        init(token: String) {
            switch token.lowercased() {
            case "trial": self = .trial
            // "enterprise" was the old name of Lifetime.
            case "lifetime", "enterprise": self = .lifetime
            case "organization", "organisation": self = .organization
            case "starter", "free": self = .starter
            default: self = .professional
            }
        }

        var title: String {
            switch self {
            case .starter: "Starter"
            case .trial: "Trial"
            case .professional: "Professional"
            case .lifetime: "Lifetime"
            case .organization: "Organization"
            }
        }

        var isPaid: Bool { self != .starter }

        /// Shown name: on iPad there is no free plan, so Starter reads "No license".
        var label: String { self == .starter && LicenseManager.requiresKey ? "No license" : title }
    }
    enum Source: String { case none, key, developer }

    /// The signed token's contents (see the back office's `docs/occa-license-api.md`).
    struct Payload: Codable, Equatable {
        var v: Int
        /// Product code in the License Manager (one back office for several apps); older tokens have none.
        var product: String?
        var lid: Int
        var key: String
        var plan: String
        /// "mac" | "ipad": the platform the key was issued for; older tokens have none.
        var platform: String?
        var type: String
        /// Lifetime: the major version the license covers (OCCA 1.x = 1); nil = every version while it runs.
        var updates_major: Int?
        var licensee: String?
        var expires_at: String?
        var device_id: String
        var iat: Int
        var refresh_after: Int
        var offline_until: Int

        var isLifetime: Bool { type == "lifetime" || expires_at == nil }
        var expiresAt: Date? { expires_at.flatMap { ISO8601DateFormatter().date(from: $0) } }
        var refreshAfter: Date { Date(timeIntervalSince1970: TimeInterval(refresh_after)) }
        var offlineUntil: Date { Date(timeIntervalSince1970: TimeInterval(offline_until)) }
    }

    /// Ed25519 public key of the back office (base64). Its secret key is only in the back office's `.env`.
    static let publicKeyBase64 = "BQ071uZquqpGTjCLIIefOpQ7BbV1dco0jyO2oa1vqcc="
    static let productionAPI = URL(string: "https://api.jcdigital.co.id")!
    /// This app's product code in the License Manager: tokens for other products are refused.
    static let productCode = "occa"

    @Published private(set) var plan: Plan = .starter
    @Published private(set) var source: Source = .none
    @Published private(set) var payload: Payload?
    /// Devices used / allowed, from the last activation or refresh (not in the token).
    @Published private(set) var devices: (used: Int, max: Int)?
    @Published private(set) var busy = false
    /// Message for the License screen (activation failed, key switched off, …).
    @Published var message: String?
    /// Developer builds: behave like Starter (to check limits and locks).
    @Published var simulateFree: Bool {
        didSet {
            UserDefaults.standard.set(simulateFree, forKey: Self.simulateFreeKey)
            resolve()
        }
    }

    private enum Mode: Equatable { case key, fixed(Plan) }
    private var mode: Mode = .key

    /// Any key plan (Trial, Professional, Lifetime, Organization): every feature, no limits.
    var isPro: Bool { plan.isPaid }

    /// iPad has no free plan: without a license key nothing can be created or edited; existing projects open view-only
    /// and still export to PDF. The Mac keeps Starter.
    nonisolated static var requiresKey: Bool { !CP.isMac }

    /// iPad without a license: view-only.
    var isUnlicensed: Bool { Self.requiresKey && !isPro }
    var usesKeys: Bool { mode == .key }

    static var isDeveloperBuild: Bool {
        #if DEBUG || OCCA_DEV
        true
        #else
        false
        #endif
    }

    private static let simulateFreeKey = "occa.license.simulateFree"
    private static let tokenItem = "occa.license.token"
    private static let deviceItem = "occa.license.device"

    var apiBase: URL {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-cp-license-api"), i + 1 < args.count, let u = URL(string: args[i + 1]) { return u }
        #endif
        return Self.productionAPI
    }

    private init() {
        simulateFree = UserDefaults.standard.bool(forKey: Self.simulateFreeKey)
        resolve()
    }

    /// At launch and whenever the app becomes active: refresh the token when it's due (online only).
    func start() {
        Task { await refreshIfDue() }
    }

    private func resolve() {
        var next: Mode = Self.isDeveloperBuild ? .fixed(simulateFree ? .starter : .lifetime) : .key
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-cp-license"), i + 1 < args.count {
            switch args[i + 1] {
            case "key": next = .key
            case "free", "starter": next = .fixed(.starter)
            case "pro": next = .fixed(.professional)
            case let v: if let p = Plan(rawValue: v) { next = .fixed(p) }
            }
        }
        #endif
        mode = next
        switch next {
        case let .fixed(p):
            plan = p
            source = p.isPaid ? .developer : .none
            payload = nil
        case .key:
            applyStoredToken()
        }
    }

    // MARK: Device

    /// Stable id of this installation (kept in the Keychain, so it survives app updates).
    var deviceID: String {
        if let id = Keychain.read(Self.deviceItem) { return id }
        let id = UUID().uuidString
        Keychain.write(id, for: Self.deviceItem)
        return id
    }

    var deviceName: String {
        #if targetEnvironment(macCatalyst)
        return ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
        #else
        return UIDevice.current.name
        #endif
    }

    var platformName: String { CP.isMac ? "macOS" : "iPadOS" }

    // MARK: Token

    private func applyStoredToken() {
        guard let token = Keychain.read(Self.tokenItem), let p = Self.verify(token, deviceID: deviceID) else {
            plan = .starter; source = .none; payload = nil
            return
        }
        apply(p)
    }

    private func apply(_ p: Payload) {
        payload = p
        let now = Date()
        let expired = p.expiresAt.map { $0 <= now } ?? false
        let stale = p.offlineUntil <= now
        let uncovered = !Self.covers(p)
        plan = (!expired && !stale && !uncovered) ? Plan(token: p.plan) : .starter
        source = plan.isPaid ? .key : .none
        if uncovered, let major = p.updates_major {
            message = "Your \(Plan(token: p.plan).title) license covers \(AppInfo.name) \(major).x. Upgrade it to use \(AppInfo.name) \(Self.appMajor), or keep using \(AppInfo.name) \(major)."
        } else if expired && Plan(token: p.plan) == .trial {
            message = "Your \(AppInfo.name) trial ended on \(p.expiresAt!.formatted(date: .long, time: .omitted)). You're on Starter now; projects stay as they are."
        } else if expired { message = "Your OCCA license expired on \(p.expiresAt!.formatted(date: .long, time: .omitted))." }
        else if stale { message = "Connect to the internet once so OCCA can check your license." }
    }

    /// Check the token's signature (Ed25519 over the base64url payload) and that it belongs to this device.
    static func verify(_ token: String, deviceID: String) -> Payload? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              let keyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signature = Data(base64URL: parts[1]),
              publicKey.isValidSignature(signature, for: Data(parts[0].utf8)),
              let json = Data(base64URL: parts[0]),
              let payload = try? JSONDecoder().decode(Payload.self, from: json),
              payload.device_id == deviceID,
              payload.product == nil || payload.product == productCode,
              payload.platform == nil || payload.platform == LicenseKey.Platform.current.rawValue else { return nil }
        return payload
    }

    // MARK: API

    private struct LicenseInfo: Decodable { var max_devices: Int?; var devices_used: Int? }
    private struct TokenResponse: Decodable { var token: String; var license: LicenseInfo? }
    private struct ErrorResponse: Decodable { var error: String?; var message: String? }

    enum APIError: Error { case server(code: String, message: String), network(String) }

    private func post(_ path: String, _ body: [String: String]) async throws -> Data {
        // License Manager public API, scoped to this product: /api/licenses/occa/{activate,refresh,deactivate}.
        var req = URLRequest(url: apiBase.appendingPathComponent("api/licenses/\(Self.productCode)/\(path)"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) } catch { throw APIError.network(error.localizedDescription) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let e = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw APIError.server(code: e?.error ?? "http_\(status)", message: e?.message ?? "The license server answered \(status).")
        }
        return data
    }

    private func receive(_ data: Data) throws {
        let r = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let p = Self.verify(r.token, deviceID: deviceID) else {
            throw APIError.server(code: "bad_token", message: "The license server's answer couldn't be verified.")
        }
        Keychain.write(r.token, for: Self.tokenItem)
        if let used = r.license?.devices_used, let max = r.license?.max_devices { devices = (used, max) }
        apply(p)
    }

    /// Activate a license key on this device.
    func activate(_ rawKey: String) async {
        let key = LicenseKey.format(rawKey)
        guard !key.isEmpty else { return }
        if let platform = LicenseKey.platform(of: key), platform != .current {
            message = Self.wrongPlatformMessage(platform)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let data = try await post("activate", ["key": key, "device_id": deviceID, "device_name": deviceName,
                                                   "platform": platformName, "app_version": Self.appVersion])
            try receive(data)
            message = isPro ? "\(AppInfo.name) \(plan.title) is active on this \(CP.isMac ? "Mac" : "iPad")." : message
        } catch {
            message = Self.describe(error)
        }
    }

    /// Ask the back office again (weekly, or from "Check now"). Network trouble keeps the current token.
    func refresh() async {
        guard usesKeys, let key = payload?.key else { return }
        busy = true
        defer { busy = false }
        do {
            try receive(try await post("refresh", ["key": key, "device_id": deviceID, "platform": platformName,
                                                  "app_version": Self.appVersion]))
        } catch let APIError.server(code, msg) where ["inactive", "expired", "invalid_key", "not_activated", "wrong_platform"].contains(code) {
            // Switched off, expired, or removed in the back office: back to Starter.
            Keychain.delete(Self.tokenItem)
            payload = nil; plan = .starter; source = .none; devices = nil
            message = msg
        } catch {
            if payload.map({ $0.offlineUntil <= Date() }) == true { message = Self.describe(error) }
        }
    }

    func refreshIfDue() async {
        guard usesKeys, let p = payload, Date() >= p.refreshAfter else { return }
        await refresh()
    }

    /// Release this device's seat (e.g. before moving to another Mac) and go back to Free.
    func deactivate() async {
        guard let key = payload?.key else { return }
        busy = true
        defer { busy = false }
        _ = try? await post("deactivate", ["key": key, "device_id": deviceID])
        Keychain.delete(Self.tokenItem)
        payload = nil; plan = .starter; source = .none; devices = nil
        message = "This device was released and is back on Starter. The key can now be used on another device."
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case let APIError.server(code, msg):
            switch code {
            case "invalid_key": return "This license key doesn't exist. Check it and try again."
            case "inactive": return "This license key is switched off. Contact Jendela Cakra Digital."
            case "expired": return "This license key has expired."
            case "wrong_platform":
                return wrongPlatformMessage(LicenseKey.Platform.current == .mac ? .ipad : .mac)
            case "device_limit": return "This key is already used on the maximum number of devices. Release one first."
            case "product_inactive": return "License activation for \(AppInfo.name) is paused. Contact Jendela Cakra Digital."
            case "invalid_product": return "This key isn't for \(AppInfo.name)."
            case "not_activated": return "This device isn't activated with this key any more. Enter the key again."
            case "invalid_request": return "Check the license key and try again."
            default: return msg
            }
        case let APIError.network(msg): return "Couldn't reach the license server: \(msg)"
        default: return error.localizedDescription
        }
    }

    /// A Mac key on an iPad or the other way round.
    static func wrongPlatformMessage(_ keyPlatform: LicenseKey.Platform) -> String {
        "This is a \(keyPlatform.label) license key. On this \(LicenseKey.Platform.current.label), use your \(LicenseKey.Platform.current.label) key (OC\(LicenseKey.Platform.current == .mac ? "3" : "5")…)."
    }

    /// Major version of this app (1 for 1.4.2).
    static var appMajor: Int { Int(appVersion.split(separator: ".").first ?? "1") ?? 1 }

    /// A Lifetime license covers one major version and its updates; other plans every version.
    static func covers(_ p: Payload) -> Bool {
        guard let major = p.updates_major else { return true }
        return appMajor <= major
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: Gate

    func allows(_ feature: ProFeature) -> Bool { isPro }

    /// Paid plan: true. Starter: shows the License screen for this feature and returns false.
    @discardableResult
    func require(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        LicensePresenter.present(feature)
        return false
    }

    /// For Starter limits: true while under the limit or on a paid plan; otherwise shows the License screen.
    /// iPad without a license: always the License screen (no free plan).
    @discardableResult
    func require(_ feature: ProFeature, when overLimit: Bool) -> Bool {
        overLimit || isUnlicensed ? require(feature) : true
    }

    /// iPad without a license: shows the License screen and returns false (any edit). Otherwise true.
    @discardableResult
    func requireEditing() -> Bool {
        guard isUnlicensed else { return true }
        LicensePresenter.present(nil)
        return false
    }

    /// At launch on iPad without a license: the License screen, once per launch.
    private var promptedAtLaunch = false
    func promptAtLaunchIfNeeded() {
        guard isUnlicensed, !promptedAtLaunch else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-cp-no-license-prompt") { return }
        #endif
        promptedAtLaunch = true
        LicensePresenter.present(nil)
    }
}

/// Shows the License screen on top of whatever is on screen (workspace, a sheet), on iPad and Mac.
@MainActor
enum LicensePresenter {
    static func present(_ feature: ProFeature?) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        guard var top = window?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        if top is LicenseHostingController { return }
        if top.modalPresentationStyle == .popover, let parent = top.presentingViewController {
            top.dismiss(animated: false)
            top = parent
        }
        let host = LicenseHostingController(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(LicenseView(feature: feature) { [weak host] in host?.dismiss(animated: true) })
        host.modalPresentationStyle = .formSheet
        host.preferredContentSize = CGSize(width: 600, height: 780)
        top.present(host, animated: true)
    }
}

final class LicenseHostingController: UIHostingController<AnyView> {}

/// Small Keychain wrapper (generic passwords for this app).
enum Keychain {
    private static let service = "id.cakrapencil.app.license"

    static func read(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func write(_ value: String, for account: String) {
        delete(account)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

extension Data {
    /// base64url without padding (RFC 4648 §5).
    init?(base64URL s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}

/// OCCA license keys: `OC{platform}{plan}-XXXX-XXXX-XXXX-{sequence}`, e.g. `OC32-7KQM-2XRT-9HZP-0001`.
/// Platform digit: 3 Mac, 5 iPad; plan digit: 1 Trial, 2 Professional, 3 Lifetime, 4 Organization (Mac 31-34,
/// iPad 52-54: no Trial on iPad). A key only activates on its own platform. The last group is the license's number
/// within its platform (also the certificate reference `LIC-OCCA-MAC-0001`).
enum LicenseKey {
    enum Platform: String {
        case mac, ipad
        var label: String { self == .mac ? "Mac" : "iPad" }
        /// The platform this app runs on.
        static var current: Platform { CP.isMac ? .mac : .ipad }
    }

    static let platformCodes: [Character: Platform] = ["3": .mac, "5": .ipad]
    static let planDigits: [Character: LicenseManager.Plan] = ["1": .trial, "2": .professional, "3": .lifetime, "4": .organization]

    /// Keys from the back office are always 5 groups of 4 (OC01-7KQM-2XRT-9HZP-0001): 20 characters. The back office
    /// keeps the last group (the license number) at 4 digits.
    static let groupLength = 4
    static let groupCount = 5
    static let length = groupLength * groupCount

    /// Uppercase, drop spaces and stray characters, keep at most 20 characters, and group them 4-4-4-4-4 while
    /// typing or after a paste.
    static func format(_ raw: String) -> String {
        let chars = raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(length)
        var groups: [String] = []
        var rest = Substring(chars)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(groupLength)))
            rest = rest.dropFirst(groupLength)
        }
        return groups.joined(separator: "-")
    }

    /// Exactly five groups of 4 characters.
    static func isComplete(_ key: String) -> Bool {
        let g = key.split(separator: "-")
        return g.count == groupCount && g.allSatisfy { $0.count == groupLength }
    }

    /// The two-digit code of a key (`OC32-…` → "32"), nil when the key doesn't start with OC + two digits.
    private static func code(of key: String) -> (Character, Character)? {
        let first = key.split(separator: "-").first.map(String.init) ?? ""
        guard first.count == 4, first.hasPrefix("OC") else { return nil }
        let c = Array(first.suffix(2))
        return (c[0], c[1])
    }

    /// The platform a key was issued for (`OC3…` Mac, `OC5…` iPad).
    static func platform(of key: String) -> Platform? {
        code(of: key).flatMap { platformCodes[$0.0] }
    }

    /// The plan a key was issued for (`OC32-…` Professional); nil for unknown codes.
    static func plan(of key: String) -> LicenseManager.Plan? {
        guard let (p, d) = code(of: key), let platform = platformCodes[p], let plan = planDigits[d] else { return nil }
        return platform == .ipad && plan == .trial ? nil : plan
    }

    /// Certificate reference: `LIC-OCCA-MAC-0001` / `LIC-OCCA-IPAD-0001`.
    static func reference(of key: String) -> String? {
        guard let platform = platform(of: key), plan(of: key) != nil,
              let last = key.split(separator: "-").last, last.allSatisfy(\.isNumber) else { return nil }
        return "LIC-OCCA-\(platform.rawValue.uppercased())-\(last)"
    }
}
