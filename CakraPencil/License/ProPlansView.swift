import CakraCore
import StoreKit
import SwiftUI

/// Plans screen: current plan, what Pro unlocks, the App Store plans (6 months, yearly, lifetime), Restore
/// Purchases, Redeem code (Club / Education seats), and the subscription terms. Opened from a locked feature
/// (`feature` says which) or from the plan chip in the project list.
struct ProPlansView: View {
    var feature: ProFeature?
    var onClose: () -> Void

    @ObservedObject private var license = LicenseManager.shared
    @State private var selectedID = LicenseManager.yearlyID
    @State private var redeeming = false
    @State private var trialEligible = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CP.Space.l) {
                    header
                    if let feature, !license.isPro { lockedNotice(feature) }
                    statusCard
                    if license.mode == .store && license.source != .lifetime { plansCard }
                    featuresCard
                    if LicenseManager.isDeveloperBuild { developerCard }
                    legal
                }
                .padding(CP.Space.l)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(CP.paper)
            .navigationTitle("\(AppInfo.name) Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose).accessibilityIdentifier("proPlansClose")
                }
            }
            .alert("\(AppInfo.name) Pro", isPresented: Binding(get: { license.message != nil }, set: { if !$0 { license.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(license.message ?? "")
            }
            .offerCodeRedemption(isPresented: $redeeming) { _ in
                Task { await license.refreshEntitlements() }
            }
            .task {
                if license.products.isEmpty { await license.loadProducts() }
                await updateTrialEligibility()
            }
        }
        .tint(CP.sage.strong)
        .accessibilityIdentifier("proPlans")
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: CP.Space.m) {
            AppMark().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(AppInfo.name) Pro")
                    .font(.system(size: CP.fs(22), weight: .bold))
                    .foregroundStyle(CP.ink)
                Text("Every feature, on iPad and Mac. One purchase covers both.")
                    .font(.system(size: CP.fs(14)))
                    .foregroundStyle(CP.inkMuted)
            }
        }
    }

    private func lockedNotice(_ f: ProFeature) -> some View {
        HStack(alignment: .top, spacing: CP.Space.s) {
            Image(systemName: "lock.fill").foregroundStyle(CP.peach.strong)
            Text("\(f.title) is part of \(AppInfo.name) Pro.")
                .font(.system(size: CP.fs(14), weight: .medium))
                .foregroundStyle(CP.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(CP.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CP.peach.fill, in: RoundedRectangle(cornerRadius: CP.Radius.panel, style: .continuous))
        .accessibilityIdentifier("proLockedFeature")
    }

    private var statusCard: some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your plan")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                    Text(planTitle)
                        .font(.system(size: CP.fs(17), weight: .semibold))
                        .foregroundStyle(CP.ink)
                        .accessibilityIdentifier("proPlanStatus")
                    if let detail = planDetail {
                        Text(detail)
                            .font(.system(size: CP.fs(12)))
                            .foregroundStyle(CP.inkMuted)
                    }
                }
                Spacer()
                PlanChip(isPro: license.isPro)
            }
            if license.mode == .store {
                Divider().overlay(CP.line)
                HStack(spacing: CP.Space.s) {
                    Button { Task { await license.restore() } } label: { Text("Restore Purchases") }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                        .accessibilityIdentifier("proRestore")
                    Button { redeeming = true } label: { Text("Redeem code") }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                        .accessibilityIdentifier("proRedeem")
                        .help("Club, Education, and event codes")
                    if license.source == .subscription {
                        Button { Task { await license.manageSubscriptions() } } label: { Text("Manage") }
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                }
            }
        }
    }

    private var planTitle: String {
        switch license.source {
        case .lifetime: "Pro · Lifetime"
        case .subscription: "Pro · Subscription"
        case .developer: "Pro · Developer build"
        case .none: "Free"
        }
    }

    private var planDetail: String? {
        if let end = license.expiresAt { return "Renews or ends on \(end.formatted(date: .long, time: .omitted))" }
        if license.source == .none {
            return "\(FreeLimits.projects) projects · maps up to \(FreeLimits.areaLabel) · \(FreeLimits.courses) course · \(FreeLimits.notes) field notes"
        }
        return nil
    }

    @ViewBuilder
    private var plansCard: some View {
        card {
            Text("Choose a plan")
                .font(.system(size: CP.fs(15), weight: .semibold))
                .foregroundStyle(CP.ink)
            if license.products.isEmpty {
                if license.productsLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Plans aren't available right now. Check the internet connection and try again.")
                        .font(.system(size: CP.fs(13)))
                        .foregroundStyle(CP.inkMuted)
                    Button("Try again") { Task { await license.loadProducts() } }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            } else {
                ForEach(license.products, id: \.id) { p in planRow(p) }
                Button {
                    guard let p = license.products.first(where: { $0.id == selectedID }) else { return }
                    Task { await license.purchase(p) }
                } label: {
                    HStack {
                        if license.purchasing { ProgressView().tint(.white) }
                        Text(buttonTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(license.purchasing || license.isPro && selectedID != LicenseManager.lifetimeID)
                .accessibilityIdentifier("proPurchase")
            }
        }
    }

    private var buttonTitle: String {
        if selectedID == LicenseManager.lifetimeID { return "Buy lifetime" }
        return trialEligible ? "Start free trial" : "Subscribe"
    }

    private func planRow(_ p: Product) -> some View {
        let on = selectedID == p.id
        return Button { selectedID = p.id } label: {
            HStack(spacing: CP.Space.m) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(on ? CP.sage.strong : CP.inkMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(planName(p))
                        .font(.system(size: CP.fs(15), weight: .semibold))
                        .foregroundStyle(CP.ink)
                    Text(planNote(p))
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                }
                Spacer()
                Text(p.displayPrice)
                    .font(CP.mono(15))
                    .foregroundStyle(CP.ink)
            }
            .padding(CP.Space.m)
            .background(on ? CP.sage.fill.opacity(0.6) : CP.paper,
                        in: RoundedRectangle(cornerRadius: CP.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.control, style: .continuous)
                .strokeBorder(on ? CP.sage.strong : CP.line, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(planName(p)), \(p.displayPrice)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("proPlan-\(p.id)")
    }

    private func planName(_ p: Product) -> String {
        switch p.id {
        case LicenseManager.sixMonthsID: "6 months"
        case LicenseManager.yearlyID: "1 year"
        case LicenseManager.lifetimeID: "Lifetime"
        default: p.displayName
        }
    }

    private func planNote(_ p: Product) -> String {
        switch p.id {
        case LicenseManager.sixMonthsID: "One orienteering season"
        case LicenseManager.yearlyID: trialEligible ? "Best value · free trial first" : "Best value"
        case LicenseManager.lifetimeID: "Pay once · all 1.x updates · Family Sharing"
        default: p.description
        }
    }

    private func updateTrialEligibility() async {
        guard let sub = license.products.first(where: { $0.subscription != nil })?.subscription,
              sub.introductoryOffer != nil else { trialEligible = false; return }
        trialEligible = await sub.isEligibleForIntroOffer
    }

    private var featuresCard: some View {
        card {
            Text("Pro includes")
                .font(.system(size: CP.fs(15), weight: .semibold))
                .foregroundStyle(CP.ink)
            ForEach(ProFeature.highlights) { f in
                Label {
                    Text(f.title).font(.system(size: CP.fs(14))).foregroundStyle(CP.ink)
                } icon: {
                    Image(systemName: f.icon).foregroundStyle(CP.sage.strong)
                }
            }
            Text("Plus no limits on projects, map size, courses, or field notes. Your projects always stay yours: when Pro ends, everything still opens and exports to PDF.")
                .font(.system(size: CP.fs(12)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var developerCard: some View {
        card {
            Toggle(isOn: $license.simulateFree) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simulate Free plan").font(.system(size: CP.fs(14), weight: .medium))
                    Text("Developer build only. App Store builds use real purchases.")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                }
            }
            .tint(CP.sage.strong)
            .accessibilityIdentifier("proSimulateFree")
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Payment is charged to your Apple ID; manage or cancel in your Apple ID settings. A free trial, if offered, ends when you subscribe.")
                .font(.system(size: CP.fs(11)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: CP.Space.m) {
                if let terms = URL(string: AppInfo.termsURL) { Link("Terms of Use", destination: terms) }
                if let privacy = URL(string: AppInfo.privacyURL) { Link("Privacy Policy", destination: privacy) }
            }
            .font(.system(size: CP.fs(12)))
            .tint(CP.sky.strong)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CP.Space.m, content: content)
            .padding(CP.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.panel, style: .continuous))
    }
}

/// "Free" / "Pro" chip: plans screen status, and the project list header (tap = plans screen).
struct PlanChip: View {
    let isPro: Bool

    var body: some View {
        Text(isPro ? "PRO" : "FREE")
            .font(.system(size: CP.fs(11), weight: .bold))
            .tracking(0.6)
            .foregroundStyle(isPro ? CP.sage.strong : CP.inkMuted)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(isPro ? CP.sage.fill : CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.chip, style: .continuous).strokeBorder(isPro ? CP.sage.strong.opacity(0.4) : CP.line))
    }
}

/// Small lock badge next to a Pro feature (shown on the Free plan).
struct ProLockBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
            Text("PRO")
        }
        .font(.system(size: CP.fs(10), weight: .bold))
        .foregroundStyle(CP.peach.strong)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(CP.peach.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityLabel("Pro feature")
    }
}
