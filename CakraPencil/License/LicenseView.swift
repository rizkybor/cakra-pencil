import CakraCore
import SwiftUI

/// License screen: current plan, enter a license key (from Jendela Cakra Digital), this device's seat (release it to move the key
/// to another device), the plans (Starter, Trial, Professional, Lifetime, Organization), what the paid
/// plans unlock, and in developer builds "Simulate Starter". Opened from a locked feature (`feature` says which) or from
/// the plan chip in the project list. Same on iPad and Mac.
struct LicenseView: View {
    var feature: ProFeature?
    var onClose: () -> Void

    @ObservedObject private var license = LicenseManager.shared
    @State private var key = ""
    @State private var confirmRelease = false
    @State private var keyEditing = false
    @State private var showKey = false
    @State private var plansOpen = false
    @State private var featuresOpen = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingTerms = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CP.Space.xl) {
                    if let feature, !license.isPro { lockedNotice(feature) }
                    VStack(alignment: .leading, spacing: CP.Space.m) {
                        licenseCard
                        if license.payload != nil { seatActions }
                    }
                    if license.usesKeys && license.payload == nil { keyCard }
                    plansSection
                    featuresSection
                    footer
                    if LicenseManager.isDeveloperBuild { developerCard }
                }
                .padding(.horizontal, CP.Space.xl)
                .padding(.vertical, CP.Space.l)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(CP.paper)
            .navigationTitle("License")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseIconButton(label: "Close", action: onClose).accessibilityIdentifier("licenseClose")
                }
            }
            .alert(AppInfo.name, isPresented: Binding(get: { license.message != nil }, set: { if !$0 { license.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(license.message ?? "")
            }
            .sheet(isPresented: $showingTerms) { LicenseTermsView { showingTerms = false } }
            .alert("Release this device?", isPresented: $confirmRelease) {
                Button("Cancel", role: .cancel) {}
                Button("Release", role: .destructive) { Task { await license.deactivate() } }
            } message: {
                Text(LicenseManager.requiresKey
                     ? "This iPad goes back to no license (projects open view-only), and the key's seat can be used on another device. Your projects stay as they are."
                     : "\(AppInfo.name) goes back to the Starter plan here, and the key's seat can be used on another device. Your projects stay as they are.")
            }
        }
        .tint(CP.sage.strong)
        .accessibilityIdentifier("licenseScreen")
    }

    // MARK: License card

    private var tone: CP.Tone { PlanChip.tone(for: license.plan) ?? CP.sand }

    /// The current plan as a license card: plan, licensee, key, and the period, devices or Starter limits.
    /// Neutral card; paid plans get a holographic band in their colors, like the License Certificate.
    private var licenseCard: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: CP.Space.l) {
            HStack(spacing: CP.Space.s) {
                AppMark().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(AppInfo.name.uppercased())
                        .font(.system(size: CP.fs(13), weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(CP.ink)
                    Text("License")
                        .font(.system(size: CP.fs(11)))
                        .foregroundStyle(CP.inkMuted)
                }
                Spacer(minLength: CP.Space.s)
                PlanChip(plan: license.plan)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR PLAN")
                    .font(.system(size: CP.fs(11), weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(tone.strong.opacity(0.85))
                Text(planTitle)
                    .font(.system(size: CP.fs(28), weight: .bold))
                    .foregroundStyle(CP.ink)
                    .accessibilityIdentifier("licensePlanStatus")
                Text(planSubtitle)
                    .font(.system(size: CP.fs(14)))
                    .foregroundStyle(CP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let p = license.payload {
                HStack(spacing: CP.Space.s) {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(tone.strong)
                    Text(Self.masked(p.key))
                        .font(CP.mono(14, weight: .medium))
                        .foregroundStyle(CP.ink)
                    Spacer(minLength: CP.Space.s)
                    if let ref = LicenseKey.reference(of: p.key) {
                        Text(ref)
                            .font(CP.mono(11))
                            .foregroundStyle(CP.inkMuted)
                    }
                }
                .padding(.horizontal, CP.Space.m)
                .frame(height: 36)
                .background(CP.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            HStack(alignment: .top, spacing: CP.Space.s) {
                ForEach(stats, id: \.label) { stat in
                    statTile(stat)
                }
            }

            if license.payload != nil, license.plan == .organization {
                Label("Shared by your team: each member activates the same key.", systemImage: "person.3.fill")
                    .font(.system(size: CP.fs(12)))
                    .foregroundStyle(CP.inkMuted)
            }
        }
        .padding(CP.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                // Neutral card; only the foil band carries the plan's colors.
                shape.fill(CP.paper2)
                if license.plan.isPaid { HologramBand(plan: license.plan, dark: colorScheme == .dark).clipShape(shape) }
            }
        }
        .overlay(shape.strokeBorder(CP.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private struct Stat { let label: String; let value: String; var icon: String }

    /// Starter: its limits. Key plans: period, days left, devices.
    private var stats: [Stat] {
        guard let p = license.payload else {
            if license.isPro {
                return [Stat(label: "Features", value: "All", icon: "checkmark.seal"),
                        Stat(label: "Limits", value: "None", icon: "infinity")]
            }
            // iPad has no free plan: existing projects open view-only.
            if LicenseManager.requiresKey {
                return [Stat(label: "Projects", value: "View only", icon: "eye"),
                        Stat(label: "PDF export", value: "Yes", icon: "doc.richtext")]
            }
            return [Stat(label: "Projects", value: "\(FreeLimits.projects)", icon: "square.stack.3d.up"),
                    Stat(label: "Scales", value: FreeLimits.scalesLabel, icon: "ruler"),
                    Stat(label: "Courses", value: "\(FreeLimits.courses)", icon: "point.3.connected.trianglepath.dotted"),
                    Stat(label: "Field", value: "—", icon: "figure.walk")]
        }
        var out: [Stat] = []
        if let end = p.expiresAt {
            out.append(Stat(label: license.plan == .trial ? "Trial ends" : "Valid until",
                            value: end.formatted(.dateTime.day().month(.abbreviated).year()), icon: "calendar"))
            out.append(Stat(label: "Days left", value: "\(Self.daysLeft(until: end))", icon: "hourglass"))
        } else {
            out.append(Stat(label: "Valid until", value: "No end date", icon: "infinity"))
        }
        // Lifetime covers one major version and its updates (OCCA 1.x).
        if let major = p.updates_major {
            out.append(Stat(label: "Updates", value: "\(AppInfo.name) \(major).x", icon: "arrow.down.circle"))
        }
        if let d = license.devices {
            out.append(Stat(label: "Devices", value: "\(d.used) of \(d.max)", icon: "ipad.and.iphone"))
        }
        return out
    }

    /// Whole days still to go, rounded up (a fresh 14-day trial reads 14).
    static func daysLeft(until end: Date) -> Int { max(0, Int((end.timeIntervalSinceNow / 86_400).rounded(.up))) }

    private func statTile(_ s: Stat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(s.label, systemImage: s.icon)
                .font(.system(size: CP.fs(11)))
                .foregroundStyle(CP.inkMuted)
                .lineLimit(1)
            Text(s.value)
                .font(.system(size: CP.fs(15), weight: .semibold))
                .foregroundStyle(CP.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, CP.Space.m)
        .padding(.vertical, CP.Space.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CP.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var planTitle: String {
        let name = license.plan.label
        switch license.source {
        case .developer: return "\(name) · Developer build"
        case .key: return license.payload?.isLifetime == true && license.plan != .lifetime ? "\(name) · Lifetime" : name
        case .none: return name
        }
    }

    private var planSubtitle: String {
        if let p = license.payload {
            if let name = p.licensee, !name.isEmpty { return "Licensed to \(name)" }
            return "Every feature, no limits"
        }
        if license.isPro { return "Every feature, no limits" }
        if LicenseManager.requiresKey { return "Activate a license key to use \(AppInfo.name) on iPad" }
        return "Free · no license key needed"
    }

    /// OC32-ABCD-…-0001: first group (prefix + platform and plan code) and last group (sequence) only.
    static func masked(_ key: String) -> String {
        let groups = key.split(separator: "-").map(String.init)
        guard groups.count > 2 else { return key }
        return ([groups[0]] + Array(repeating: "••••", count: groups.count - 2) + [groups[groups.count - 1]]).joined(separator: "-")
    }

    /// Check now / Release this device, with the device count (kept as text for VoiceOver and tests).
    private var seatActions: some View {
        HStack(spacing: CP.Space.s) {
            Button { Task { await license.refresh() } } label: {
                HStack(spacing: 6) {
                    if license.busy { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    Text("Check now")
                }
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .disabled(license.busy)
            .accessibilityIdentifier("licenseCheck")
            Button { confirmRelease = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Release this device")
                }
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .disabled(license.busy)
            .accessibilityIdentifier("licenseRelease")
            Spacer(minLength: CP.Space.s)
            if let d = license.devices {
                Text("\(d.used) of \(d.max) device\(d.max == 1 ? "" : "s") in use")
                    .font(.system(size: CP.fs(12)))
                    .foregroundStyle(CP.inkMuted)
                    .lineLimit(1)
            }
        }
    }

    private func lockedNotice(_ f: ProFeature) -> some View {
        HStack(alignment: .center, spacing: CP.Space.m) {
            Image(systemName: f.icon)
                .font(.system(size: CP.fs(16), weight: .semibold))
                .foregroundStyle(CP.peach.strong)
                .frame(width: 36, height: 36)
                .background(CP.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title)
                    .font(.system(size: CP.fs(14), weight: .semibold))
                    .foregroundStyle(CP.ink)
                Text("Needs a license key: Trial, Professional, Lifetime, or Organization.")
                    .font(.system(size: CP.fs(12)))
                    .foregroundStyle(CP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ProLockBadge()
        }
        .padding(CP.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CP.peach.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("proLockedFeature")
    }

    // MARK: Key entry

    private var keyCard: some View {
        card {
            sectionTitle("Activate a license key", icon: "key.horizontal")
            Text("Paste the key from your License Certificate. It starts with OC and the plan number.")
                .font(.system(size: CP.fs(13)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            // Centered, dashes added while typing, hidden like a password unless the eye is on.
            HStack(spacing: 0) {
                Color.clear.frame(width: 32, height: 1)   // balances the eye button so the key stays centered
                LicenseKeyField(text: $key, revealed: showKey, editing: $keyEditing, onSubmit: activate)
                Button { showKey.toggle() } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .font(.system(size: CP.fs(15)))
                        .foregroundStyle(CP.inkMuted)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showKey ? "Hide license key" : "Show license key")
                .accessibilityIdentifier("licenseKeyReveal")
                .help(showKey ? "Hide key" : "Show key")
            }
            .padding(.horizontal, CP.Space.xs)
            .frame(height: CP.isMac ? 36 : 46)
            .searchFieldSurface(focused: keyEditing)
            if let keyPlatform = LicenseKey.platform(of: LicenseKey.format(key)), keyPlatform != .current {
                Label("This is a \(keyPlatform.label) key. Use your \(LicenseKey.Platform.current.label) key here.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: CP.fs(12)))
                    .foregroundStyle(CP.inkMuted)
                    .accessibilityIdentifier("licenseKeyWrongPlatform")
            } else if let plan = LicenseKey.plan(of: LicenseKey.format(key)) {
                HStack(spacing: CP.Space.s) {
                    PlanChip(plan: plan)
                    Text("\(plan.title) key · \(LicenseKey.Platform.current.label)")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("licenseKeyPlan")
            }
            Button(action: activate) {
                HStack {
                    if license.busy { ProgressView().tint(.white) }
                    Text("Activate")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(license.busy || !LicenseKey.isComplete(LicenseKey.format(key)) || LicenseKey.platform(of: LicenseKey.format(key)).map { $0 != .current } == true)
            .accessibilityIdentifier("licenseActivate")
            HStack(spacing: 4) {
                Text("By activating, you agree to the")
                    .foregroundStyle(CP.inkMuted)
                Button("\(AppInfo.name) License Terms") { showingTerms = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(CP.sky.strong)
                    .accessibilityIdentifier("licenseTermsLink")
            }
            .font(.system(size: CP.fs(12)))
            Divider().overlay(CP.line)
            Label("Activating needs the internet once. After that \(AppInfo.name) checks the key about once a week and keeps working offline for up to 30 days.", systemImage: "wifi")
                .font(.system(size: CP.fs(12)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func activate() {
        guard !license.busy else { return }
        Task {
            await license.activate(key)
            if license.isPro { key = "" }
        }
    }

    // MARK: Plans

    private var plansSection: some View {
        accordion("Plans", icon: "rectangle.stack", isOpen: $plansOpen, id: "licensePlans") {
            groupLabel("Individual")
            twoColumns(individualPlans, spacing: CP.Space.m) { planTile($0.plan, price: $0.price, note: $0.note) }
            groupLabel("Organization").padding(.top, CP.Space.xs)
            planTile(.organization, price: "Paid per period", note: "Teams, communities, clubs, and federations · one key for several devices")
        }
    }

    private struct PlanInfo: Identifiable {
        let plan: LicenseManager.Plan, price: String, note: String
        var id: String { plan.rawValue }
    }

    private var individualPlans: [PlanInfo] {
        var out: [PlanInfo] = []
        if !LicenseManager.requiresKey {
            out.append(PlanInfo(plan: .starter, price: "Free", note: "\(FreeLimits.projects) projects at 1:4000 or 1:10000, up to \(FreeLimits.courses) courses; no fieldwork, contours, live basemap, or my location"))
        }
        out.append(PlanInfo(plan: .trial, price: "Limited time", note: "Every feature, to try \(AppInfo.name) out"))
        out.append(PlanInfo(plan: .professional, price: "Paid per period", note: "Every feature, for one mapper or course setter"))
        out.append(PlanInfo(plan: .lifetime, price: "One-time payment", note: "Every feature, no end date"))
        return out
    }

    private func planTile(_ plan: LicenseManager.Plan, price: String, note: String) -> some View {
        let current = license.plan == plan
        let t = PlanChip.tone(for: plan) ?? CP.sand
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack {
                PlanChip(plan: plan)
                Spacer(minLength: CP.Space.s)
                if current {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.system(size: CP.fs(11), weight: .semibold))
                        .foregroundStyle(t.strong)
                        .accessibilityLabel("Current plan")
                }
            }
            Text(price)
                .font(.system(size: CP.fs(15), weight: .semibold))
                .foregroundStyle(CP.ink)
            Text(note)
                .font(.system(size: CP.fs(12)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(CP.Space.m)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(current ? t.fill.opacity(0.55) : CP.paper2, in: shape)
        .overlay(shape.strokeBorder(current ? t.strong.opacity(0.5) : CP.line, lineWidth: current ? 1.5 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("licensePlan-\(plan.rawValue)")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    // MARK: Features

    private var featuresSection: some View {
        accordion("Every license key includes", icon: "sparkles", isOpen: $featuresOpen, id: "licenseFeatures") {
            twoColumns(ProFeature.highlights, spacing: CP.Space.s) { f in
                    HStack(spacing: CP.Space.m) {
                        Image(systemName: f.icon)
                            .font(.system(size: CP.fs(14), weight: .medium))
                            .foregroundStyle(CP.sage.strong)
                            .frame(width: 32, height: 32)
                            .background(CP.sage.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text(f.title)
                            .font(.system(size: CP.fs(13)))
                            .foregroundStyle(CP.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
            }
            Label(LicenseManager.requiresKey
                  ? "Your projects always stay yours: without a license they still open (view only) and export to PDF."
                  : "Your projects always stay yours: on Starter, everything still opens and exports to PDF.", systemImage: "lock.open")
                .font(.system(size: CP.fs(12)))
                .foregroundStyle(CP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(CP.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CP.paper2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var footer: some View {
        HStack(spacing: CP.Space.m) {
            Button { showingTerms = true } label: {
                Label("\(AppInfo.name) License Terms v\(LicenseTerms.version)", systemImage: "doc.text")
            }
            .buttonStyle(.plain)
            .foregroundStyle(CP.sky.strong)
            .accessibilityIdentifier("licenseTermsButton")
            Spacer(minLength: CP.Space.s)
            Text("License keys by Jendela Cakra Digital")
                .foregroundStyle(CP.inkMuted)
        }
        .font(.system(size: CP.fs(12)))
        .padding(.top, CP.Space.xs)
    }

    private var developerCard: some View {
        card {
            Toggle(isOn: $license.simulateFree) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LicenseManager.requiresKey ? "Simulate no license" : "Simulate Starter plan").font(.system(size: CP.fs(14), weight: .medium))
                    Text("Developer build only. Distributed builds use license keys.")
                        .font(.system(size: CP.fs(12)))
                        .foregroundStyle(CP.inkMuted)
                }
            }
            .tint(CP.sage.strong)
            .disabled(license.usesKeys)
            .accessibilityIdentifier("licenseSimulateFree")
        }
    }

    // MARK: Building blocks

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label {
            Text(title).font(.system(size: CP.fs(16), weight: .semibold)).foregroundStyle(CP.ink)
        } icon: {
            // Same width for every icon, so the titles line up.
            Image(systemName: icon).font(.system(size: CP.fs(14))).foregroundStyle(CP.inkMuted)
                .frame(width: CP.fs(20))
        }
    }

    /// Collapsible section (closed by default): tap the header to open or close it.
    private func accordion<Content: View>(_ title: String, icon: String, isOpen: Binding<Bool>, id: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CP.Space.m) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.wrappedValue.toggle() }
            } label: {
                HStack {
                    sectionTitle(title, icon: icon)
                    Spacer(minLength: CP.Space.s)
                    Image(systemName: "chevron.right")
                        .font(.system(size: CP.fs(13), weight: .semibold))
                        .foregroundStyle(CP.inkMuted)
                        .rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
                }
                .padding(.horizontal, CP.Space.m)
                .frame(minHeight: CP.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CP.line))
            .accessibilityIdentifier(id)
            .accessibilityAddTraits(isOpen.wrappedValue ? .isSelected : [])
            .accessibilityHint(isOpen.wrappedValue ? "Collapses the section" : "Expands the section")
            // The header stays above the content while it slides in and out.
            .zIndex(1)
            if isOpen.wrappedValue {
                // One block, so the content opens and closes as a whole (not each row on its own), fading and
                // sliding a little under the header.
                VStack(alignment: .leading, spacing: CP.Space.m) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .compositingGroup()
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .clipped()
    }

    /// Two equal columns, laid out at once (not lazily), so an accordion opens and closes without rows piling up.
    private func twoColumns<Item: Identifiable, Cell: View>(_ items: [Item], spacing: CGFloat,
                                                            @ViewBuilder cell: @escaping (Item) -> Cell) -> some View {
        let rows = stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
        return Grid(alignment: .topLeading, horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(rows.indices, id: \.self) { r in
                GridRow(alignment: .top) {
                    ForEach(rows[r]) { cell($0).frame(maxWidth: .infinity, alignment: .topLeading) }
                    if rows[r].count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: CP.fs(11), weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(CP.inkMuted)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CP.Space.m, content: content)
            .padding(CP.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CP.paper2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(CP.line))
    }
}

/// License key field: centered, dashes added while typing (OC32-ABCD-…), masked like a password unless `revealed`.
/// A UIKit field so each keystroke and paste is handled in one place (SwiftUI reformatting dropped characters when
/// typing fast). The display has the same length and dash positions as the key, so edits map one to one.
private struct LicenseKeyField: UIViewRepresentable {
    @Binding var text: String
    var revealed: Bool
    @Binding var editing: Bool
    var onSubmit: () -> Void

    /// Key characters accepted: 20, the back office's key length (OC32 + 3 × 4 + a 4-digit number).
    static let maxCharacters = LicenseKey.length

    static func display(_ key: String, revealed: Bool) -> String {
        revealed ? key : String(key.map { $0 == "-" ? "-" : "•" })
    }

    private static func keyCharacters(_ s: String) -> String {
        s.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        let font = UIFont.monospacedSystemFont(ofSize: CP.fs(16), weight: .medium)
        tf.font = font
        tf.textAlignment = .center
        // White field in light and dark mode (searchFieldSurface), so the text is always black.
        tf.textColor = .black
        tf.tintColor = UIColor(red: 0x3F / 255, green: 0x6B / 255, blue: 0x4A / 255, alpha: 1)
        tf.autocapitalizationType = .allCharacters
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.smartInsertDeleteType = .no
        tf.keyboardType = .asciiCapable
        tf.returnKeyType = .go
        tf.attributedPlaceholder = NSAttributedString(string: CP.isMac ? "OC32-XXXX-XXXX-XXXX-0001" : "OC52-XXXX-XXXX-XXXX-0001", attributes: [
            .font: font, .foregroundColor: UIColor.black.withAlphaComponent(0.3),
        ])
        tf.accessibilityIdentifier = "licenseKeyField"
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        context.coordinator.parent = self
        let shown = Self.display(text, revealed: revealed)
        if tf.text != shown { tf.text = shown }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LicenseKeyField
        init(_ parent: LicenseKeyField) { self.parent = parent }

        func textField(_ tf: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = parent.text as NSString
            guard range.location + range.length <= current.length else { return false }
            let before = LicenseKeyField.keyCharacters(current.substring(to: range.location))
            let removed = current.substring(with: range)
            let inserted = LicenseKeyField.keyCharacters(string)
            let after = LicenseKeyField.keyCharacters(current.substring(from: range.location + range.length))
            var head = before
            // Backspace on a dash alone: delete the character in front of it.
            if string.isEmpty, removed == "-", !head.isEmpty { head.removeLast() }
            let room = max(0, LicenseKeyField.maxCharacters - head.count - after.count)
            head += String(inserted.prefix(room))
            let formatted = LicenseKey.format(head + after)
            parent.text = formatted
            tf.text = LicenseKeyField.display(formatted, revealed: parent.revealed)
            // Caret after the same number of key characters (dashes skipped).
            var offset = 0, seen = 0
            for ch in formatted where seen < head.count {
                offset += 1
                if ch != "-" { seen += 1 }
            }
            if let pos = tf.position(from: tf.beginningOfDocument, offset: offset) {
                tf.selectedTextRange = tf.textRange(from: pos, to: pos)
            }
            return false
        }

        func textFieldDidBeginEditing(_ tf: UITextField) { parent.editing = true }
        func textFieldDidEndEditing(_ tf: UITextField) { parent.editing = false }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

/// Holographic foil on the license card: fine diagonal stripes in each paid plan's colors (Trial gold, Professional
/// mint–sky, Lifetime pearl lavender, Organization blue–violet); Starter has none. The plan chip uses the same colors.
struct HologramBand: View {
    let plan: LicenseManager.Plan
    /// Passed in by the card (the band sits in a background, where the color scheme read as light).
    var dark = false

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    private var palette: [Color] { Self.palette(for: plan, dark: dark) }

    /// The foil colors of each paid plan; the plan chip uses them too.
    /// Dark mode uses deeper tones: the pale pastels read as plain grey on a dark card.
    static func palette(for plan: LicenseManager.Plan, dark: Bool = false) -> [Color] {
        let c = rgb
        if dark {
            switch plan {
            case .trial: return [c(0.85, 0.65, 0.20), c(0.95, 0.80, 0.35), c(0.75, 0.55, 0.15), c(0.90, 0.72, 0.30)]
            case .professional: return [c(0.25, 0.70, 0.50), c(0.25, 0.60, 0.80), c(0.35, 0.75, 0.55), c(0.30, 0.50, 0.85)]
            case .lifetime: return [c(0.60, 0.40, 0.95), c(0.85, 0.45, 0.75), c(0.70, 0.60, 1), c(0.45, 0.60, 0.95), c(0.60, 0.40, 0.95)]
            case .organization: return [c(0.35, 0.50, 0.95), c(0.55, 0.40, 0.95), c(0.30, 0.65, 0.95), c(0.50, 0.45, 0.90)]
            case .starter: return []
            }
        }
        switch plan {
        case .trial: return [c(1, 0.88, 0.58), c(1, 0.96, 0.84), c(0.96, 0.80, 0.52), c(1, 0.92, 0.72)]
        case .professional: return [c(0.78, 0.96, 0.86), c(0.80, 0.94, 0.98), c(0.86, 1, 0.90), c(0.76, 0.88, 1)]
        // Pearl: lavender with a soft hint of pink and sky (no green or yellow), so it stays calm.
        case .lifetime: return [c(0.90, 0.85, 1), c(0.97, 0.88, 0.95), c(0.95, 0.94, 1), c(0.86, 0.91, 1), c(0.90, 0.85, 1)]
        case .organization: return [c(0.78, 0.86, 1), c(0.86, 0.80, 1), c(0.78, 0.94, 1), c(0.84, 0.82, 1)]
        case .starter: return []
        }
    }

    var body: some View {
        GeometryReader { geo in
            if plan.isPaid { stripes(w: geo.size.width, h: geo.size.height) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Fine diagonal stripes in the plan's colors over the right half, fading out to the left.
    private func stripes(w: CGFloat, h: CGFloat) -> some View {
        Canvas { ctx, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height * 0.55, y: 0))
                x += 7
            }
            ctx.stroke(path, with: .linearGradient(Gradient(colors: palette), startPoint: .zero,
                                                   endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 3)
        }
        .mask(LinearGradient(colors: [.clear, .black.opacity(0.5), .black], startPoint: .leading, endPoint: .trailing))
        .opacity(dark ? 0.3 : 0.9)
        .blendMode(dark ? .normal : .multiply)
    }
}

/// Plan chip ("Starter", "Professional", …): a small capsule with the plan's symbol, like a system tag. License
/// screen, and the project list header (tap = License screen).
struct PlanChip: View {
    let plan: LicenseManager.Plan
    @Environment(\.colorScheme) private var scheme

    private var tone: CP.Tone? { Self.tone(for: plan) }

    static func tone(for plan: LicenseManager.Plan) -> CP.Tone? {
        switch plan {
        case .starter: nil
        case .trial: CP.butter
        case .professional: CP.sage
        case .lifetime: CP.lavender
        case .organization: CP.sky
        }
    }

    static func symbol(for plan: LicenseManager.Plan) -> String {
        switch plan {
        case .starter: "seal"
        case .trial: "clock"
        case .professional: "checkmark.seal.fill"
        case .lifetime: "infinity"
        case .organization: "person.2.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Self.symbol(for: plan))
                .font(.system(size: CP.fs(10), weight: .semibold))
            Text(plan.label)
                .font(.system(size: CP.fs(12), weight: .medium))
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(tone?.strong ?? CP.inkMuted)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background {
            // Paid plans: the license card's foil colors (Trial gold, Professional mint–sky, Lifetime rainbow,
            // Organization blue–violet); Starter neutral.
            let foil = HologramBand.palette(for: plan, dark: scheme == .dark)
            ZStack {
                Capsule().fill(tone?.fill ?? CP.ink.opacity(0.07))
                if !foil.isEmpty {
                    Capsule().fill(LinearGradient(colors: foil, startPoint: .leading, endPoint: .trailing))
                        .opacity(scheme == .dark ? 0.2 : (plan == .lifetime ? 0.7 : 0.85))
                }
            }
        }
        .overlay {
            if tone != nil { Capsule().strokeBorder(tone!.strong.opacity(scheme == .dark ? 0.3 : 0.18), lineWidth: 1) }
        }
    }
}

/// Small lock badge next to a paid feature (shown on Starter). "PRO" = Professional or higher.
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
