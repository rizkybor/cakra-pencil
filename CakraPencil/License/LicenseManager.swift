import CakraCore
import Foundation
import StoreKit
import SwiftUI
import UIKit

/// OCCA's license: Free or Pro, from App Store purchases (StoreKit 2). One purchase covers iPad and Mac
/// (universal purchase). Works offline: StoreKit keeps verified transactions on the device, and the last known
/// state is cached so the app starts in the right plan before StoreKit answers.
///
/// Club / Education / Federation seats are App Store Offer Codes for the Pro subscription, redeemed in the app.
///
/// Developer builds (Debug, or Release built with `OCCA_DEV`) are Pro unless "Simulate Free" is on; App Store and
/// TestFlight builds always use StoreKit. Debug launch argument `-cp-license free|pro|store` overrides.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    enum Plan: String, Codable { case free, pro }
    enum Source: String, Codable { case none, subscription, lifetime, developer }

    /// Where the plan comes from.
    enum Mode: Equatable {
        /// App Store purchases.
        case store
        /// Fixed plan (developer build or launch argument).
        case fixed(Plan)
    }

    // Product identifiers (App Store Connect and Config/OCCA.storekit).
    static let sixMonthsID = "id.cakrapencil.app.pro.6months"
    static let yearlyID = "id.cakrapencil.app.pro.yearly"
    static let lifetimeID = "id.cakrapencil.app.pro.lifetime"
    static let productIDs = [sixMonthsID, yearlyID, lifetimeID]

    @Published private(set) var plan: Plan = .free
    @Published private(set) var source: Source = .none
    /// End of the current subscription period (nil for lifetime / free).
    @Published private(set) var expiresAt: Date?
    @Published private(set) var products: [Product] = []
    @Published private(set) var productsLoading = false
    @Published private(set) var purchasing = false
    /// Message for the plans screen (purchase failed, pending approval, restored, …).
    @Published var message: String?
    /// Developer builds: behave like the Free plan (to check limits and locks).
    @Published var simulateFree: Bool {
        didSet {
            UserDefaults.standard.set(simulateFree, forKey: Self.simulateFreeKey)
            resolveMode()
        }
    }

    private(set) var mode: Mode = .store
    private var updatesTask: Task<Void, Never>?

    var isPro: Bool { plan == .pro }

    static var isDeveloperBuild: Bool {
        #if DEBUG || OCCA_DEV
        true
        #else
        false
        #endif
    }

    private static let simulateFreeKey = "occa.license.simulateFree"
    private static let cacheKey = "occa.license.cache"

    private struct Cache: Codable {
        var plan: Plan
        var source: Source
        var expiresAt: Date?
    }

    private init() {
        simulateFree = UserDefaults.standard.bool(forKey: Self.simulateFreeKey)
        resolveMode()
    }

    /// Called once at launch: listen for purchases and renewals, then read the current entitlements and products.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached(priority: .background) {
            for await update in Transaction.updates {
                if case let .verified(t) = update { await t.finish() }
                await LicenseManager.shared.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    private func resolveMode() {
        var next: Mode = Self.isDeveloperBuild ? .fixed(simulateFree ? .free : .pro) : .store
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-cp-license"), i + 1 < args.count {
            switch args[i + 1] {
            case "free": next = .fixed(.free)
            case "pro": next = .fixed(.pro)
            case "store": next = .store
            default: break
            }
        }
        #endif
        mode = next
        switch next {
        case let .fixed(p):
            plan = p
            source = p == .pro ? .developer : .none
            expiresAt = nil
        case .store:
            applyCache()
            Task { await refreshEntitlements() }
        }
    }

    // MARK: Entitlements

    /// Last known state, so the app starts in the right plan offline; an expired subscription falls back to Free.
    private func applyCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let c = try? JSONDecoder().decode(Cache.self, from: data) else {
            plan = .free; source = .none; expiresAt = nil
            return
        }
        if c.source == .subscription, let end = c.expiresAt, end < Date() {
            plan = .free; source = .none; expiresAt = nil
        } else {
            plan = c.plan; source = c.source; expiresAt = c.expiresAt
        }
    }

    func refreshEntitlements() async {
        guard mode == .store else { return }
        var pro = false, src = Source.none, end: Date?
        for await result in Transaction.currentEntitlements {
            guard case let .verified(t) = result, t.revocationDate == nil, Self.productIDs.contains(t.productID) else { continue }
            switch t.productType {
            case .nonConsumable:
                pro = true; src = .lifetime; end = nil
            case .autoRenewable:
                guard src != .lifetime, let exp = t.expirationDate, exp > Date() else { continue }
                pro = true; src = .subscription; end = max(end ?? exp, exp)
            default:
                continue
            }
            if src == .lifetime { break }
        }
        plan = pro ? .pro : .free
        source = src
        expiresAt = end
        if let data = try? JSONEncoder().encode(Cache(plan: plan, source: source, expiresAt: expiresAt)) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    // MARK: Products and purchases

    func loadProducts() async {
        guard !productsLoading else { return }
        productsLoading = true
        defer { productsLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Self.productIDs.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            products = []
        }
    }

    func purchase(_ product: Product) async {
        guard !purchasing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(.verified(t)):
                await t.finish()
                await refreshEntitlements()
                message = isPro ? "Welcome to \(AppInfo.name) Pro." : nil
            case .success(.unverified):
                message = "The App Store couldn't verify this purchase. Try Restore Purchases."
            case .pending:
                message = "Purchase pending approval (Ask to Buy). Pro unlocks once it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Restore Purchases: sync with the App Store (asks for the Apple ID if needed).
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isPro ? "Purchases restored. \(AppInfo.name) Pro is active." : "No \(AppInfo.name) Pro purchase found for this Apple ID."
        } catch {
            message = "Couldn't restore: \(error.localizedDescription)"
        }
    }

    func manageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
        await refreshEntitlements()
    }

    // MARK: Gate

    func allows(_ feature: ProFeature) -> Bool { isPro }

    /// Pro: true. Free: shows the plans screen for this feature and returns false.
    @discardableResult
    func require(_ feature: ProFeature) -> Bool {
        if isPro { return true }
        PaywallPresenter.present(feature)
        return false
    }

    /// For Free limits: true while under the limit or on Pro; otherwise shows the plans screen.
    @discardableResult
    func require(_ feature: ProFeature, when overLimit: Bool) -> Bool {
        overLimit ? require(feature) : true
    }
}

/// Shows the plans screen on top of whatever is on screen (workspace, a sheet, a popover's window), on iPad and Mac.
@MainActor
enum PaywallPresenter {
    static func present(_ feature: ProFeature?) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        guard var top = window?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        if top is PlansHostingController { return }
        // A popover can't present a sheet on Mac: present from its presenter instead.
        if top.modalPresentationStyle == .popover, let parent = top.presentingViewController {
            top.dismiss(animated: false)
            top = parent
        }
        let host = PlansHostingController(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(ProPlansView(feature: feature) { [weak host] in host?.dismiss(animated: true) })
        host.modalPresentationStyle = .formSheet
        host.preferredContentSize = CGSize(width: 560, height: 760)
        top.present(host, animated: true)
    }
}

final class PlansHostingController: UIHostingController<AnyView> {}
