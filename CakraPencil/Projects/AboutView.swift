import CakraCore
import SwiftUI

/// About OCCA: version, credits (developer, supporting company with its logo), and third-party data notices.
/// Opened from the ⓘ button in the project list header or by tapping the credit footer.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var storage: StorageInfo?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CP.Space.xl) {
                    VStack(spacing: CP.Space.s) {
                        AppMark().frame(width: 84, height: 84)
                        Text(AppInfo.name)
                            .font(.system(size: CP.fs(30), weight: .bold))
                            .foregroundStyle(CP.ink)
                        Text(AppInfo.fullName)
                            .font(.system(size: CP.fs(15), weight: .medium))
                            .foregroundStyle(CP.inkMuted)
                        Text(version)
                            .font(CP.mono(12))
                            .foregroundStyle(CP.inkMuted)
                        Text(AppInfo.tagline)
                            .font(.system(size: CP.fs(14)))
                            .foregroundStyle(CP.ink)
                            .multilineTextAlignment(.center)
                            .padding(.top, CP.Space.xs)
                    }
                    .accessibilityElement(children: .combine)

                    card {
                        VStack(alignment: .leading, spacing: CP.Space.m) {
                            heading("Credits")
                            creditRow("Developed by", AppInfo.developer)
                            creditRow("Country", AppInfo.country)
                            Divider().overlay(CP.line)
                            VStack(alignment: .leading, spacing: CP.Space.s) {
                                Text("Supported by")
                                    .font(.system(size: CP.fs(13)))
                                    .foregroundStyle(CP.inkMuted)
                                Image("JCDLogo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 44)
                                    .accessibilityLabel(AppInfo.supporter)
                                    .accessibilityIdentifier("aboutSupporterLogo")
                                HStack(spacing: CP.Space.s) {
                                    Text(AppInfo.supporter)
                                        .font(.system(size: CP.fs(15), weight: .semibold))
                                        .foregroundStyle(CP.ink)
                                    if let url = URL(string: AppInfo.supporterURL) {
                                        Link("jcdigital.co.id", destination: url)
                                            .font(.system(size: CP.fs(13)))
                                            .tint(CP.sky.strong)
                                    }
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: CP.Space.s) {
                            heading("Release and platforms")
                            creditRow("Release", AppInfo.releaseStatus)
                            notice(AppInfo.publication)
                            creditRow("Supported on", AppInfo.supportedPlatforms)
                            notice(AppInfo.unsupportedPlatforms)
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: CP.Space.s) {
                            heading("Size and storage")
                            if let storage {
                                creditRow("App size", StorageInfo.format(storage.app))
                                creditRow("Projects", "\(StorageInfo.format(storage.projects)) · \(storage.projectCount) \(storage.projectCount == 1 ? "project" : "projects")")
                                creditRow("Symbol library", StorageInfo.format(storage.symbolSets))
                                creditRow("Caches and temporary files", StorageInfo.format(storage.other))
                                notice("Total on this device: \(StorageInfo.format(storage.app + storage.projects + storage.symbolSets + storage.other)). Map imagery is stored in each project; caches are managed by the system.")
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("aboutStorage")
                    }
                    .task { storage = await StorageInfo.measure() }

                    card {
                        VStack(alignment: .leading, spacing: CP.Space.m) {
                            heading("Supported files")
                            ForEach(AppInfo.supportedFiles, id: \.title) { f in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                                    Text(f.detail).font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .accessibilityIdentifier("aboutSupportedFiles")
                    }

                    card {
                        VStack(alignment: .leading, spacing: CP.Space.s) {
                            heading("Symbol sets and licenses")
                            ForEach(AppInfo.symbolSetCredits, id: \.title) { c in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(c.title).font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
                                    Text(c.source).font(.system(size: CP.fs(13))).foregroundStyle(CP.ink)
                                    Text(c.license).font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
                                    if let url = URL(string: c.url) {
                                        Link(c.url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "%20", with: " "), destination: url)
                                            .font(.system(size: CP.fs(12)))
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            NavigationLink {
                                LicenseTextView(title: "GPL-3.0", file: "LICENSE-GPL-3.0.txt")
                            } label: {
                                Label("GNU GPL v3.0 license text", systemImage: "doc.text")
                                    .font(.system(size: CP.fs(13), weight: .medium))
                            }
                            .accessibilityIdentifier("aboutGPLLicense")
                            notice(AppInfo.specificationCredit)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("aboutSymbolSets")
                    }

                    card {
                        VStack(alignment: .leading, spacing: CP.Space.s) {
                            heading("Data")
                            notice("Map imagery and data © Apple Maps, used under Apple's terms.")
                            notice("Elevation data: Terrain Tiles (AWS Open Data, Mapzen; SRTM, GMTED, NED, ETOPO1 and others).")
                        }
                    }

                    Text(AppInfo.copyright)
                        .font(CP.mono(11))
                        .foregroundStyle(CP.inkMuted)
                }
                .padding(CP.Space.xl)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(CP.paper2)
            .navigationTitle("About \(AppInfo.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(CP.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.panel))
            .overlay(RoundedRectangle(cornerRadius: CP.Radius.panel).strokeBorder(CP.line))
    }

    private func heading(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: CP.fs(12), weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(CP.inkMuted)
    }

    private func creditRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: CP.fs(13))).foregroundStyle(CP.inkMuted)
            Text(value).font(.system(size: CP.fs(15), weight: .semibold)).foregroundStyle(CP.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func notice(_ s: String) -> some View {
        Text(s)
            .font(.system(size: CP.fs(13)))
            .foregroundStyle(CP.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A license text shipped in the app bundle (e.g. GPL-3.0 for the OpenOrienteering symbol sets).
struct LicenseTextView: View {
    let title: String
    let file: String

    private var text: String {
        let name = (file as NSString).deletingPathExtension, ext = (file as NSString).pathExtension
        let url = Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "OpenOrienteering")
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "SymbolSets/OpenOrienteering")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "License text not found."
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(CP.mono(12))
                .foregroundStyle(CP.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CP.Space.l)
                .accessibilityIdentifier("licenseText")
        }
        .background(CP.paper2)
        .navigationTitle(title)
    }
}

/// Disk use shown in About: the app itself (bundle) and its data (projects, symbol library, other files and caches).
struct StorageInfo: Sendable {
    var app: Int64
    var projects: Int64
    var projectCount: Int
    var symbolSets: Int64
    var other: Int64

    static func measure() async -> StorageInfo {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let projectsDir = docs.appendingPathComponent("Projects", isDirectory: true)
            let projects = size(of: projectsDir)
            let count = ((try? fm.contentsOfDirectory(atPath: projectsDir.path)) ?? []).filter { $0.hasSuffix(".cakra") }.count
            let symbols = size(of: docs.appendingPathComponent("SymbolSets", isDirectory: true))
            let home = URL(fileURLWithPath: NSHomeDirectory())
            let other = max(size(of: home) - projects - symbols, 0)
            return StorageInfo(app: size(of: Bundle.main.bundleURL), projects: projects, projectCount: count,
                               symbolSets: symbols, other: other)
        }.value
    }

    /// Allocated size of a file or folder (bytes).
    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Decimal units like Finder / Files ("20.1 MB"), English number format like the rest of OCCA.
    static func format(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1e9 { return "\(Fmt.number(b / 1e9, decimals: 2)) GB" }
        if b >= 1e6 { return "\(Fmt.number(b / 1e6, decimals: 1)) MB" }
        return "\(Fmt.number(max(b / 1e3, 0), decimals: 0)) KB"
    }
}
