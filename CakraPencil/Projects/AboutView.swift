import CakraCore
import SwiftUI

/// About OCCA: version, credits (developer, supporting company with its logo), and third-party data notices.
/// Opened from the ⓘ button in the project list header or by tapping the credit footer.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

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
                            creditRow("Released", AppInfo.releaseDate)
                            creditRow("Supported on", AppInfo.supportedPlatforms)
                            notice(AppInfo.unsupportedPlatforms)
                        }
                    }

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
                            heading("Data and symbols")
                            notice("ISSprOM 2019-2 symbol set (OCAD) published by British Orienteering; ISOM and ISSprOM specifications by the International Orienteering Federation (IOF).")
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
