import CakraCore
import SwiftUI

/// OCCA License Terms (the appendix of every License Certificate), bundled as `LicenseTerms.md`.
/// The text is a copy of the back office's `resources/license-products/terms/occa.md`; keep both the same version.
enum LicenseTerms {
    static var text: String {
        guard let url = Bundle.main.url(forResource: "LicenseTerms", withExtension: "md"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return s
    }

    /// "1.0", read from the "**Version 1.0 · …**" line.
    static var version: String {
        guard let line = text.split(separator: "\n").first(where: { $0.contains("Version ") }),
              let r = line.range(of: #"Version\s+([0-9.]+)"#, options: .regularExpression) else { return "1.0" }
        return String(line[r]).replacingOccurrences(of: "Version", with: "").trimmingCharacters(in: .whitespaces)
    }
}

/// Reads the terms: headings, paragraphs and bullet lists from the Markdown, with inline bold and italics.
struct LicenseTermsView: View {
    var onClose: () -> Void

    private enum Block: Hashable {
        case title(String), heading(String), paragraph(String), bullet(String)
    }

    private var blocks: [Block] {
        LicenseTerms.text.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("# ") { return .title(String(line.dropFirst(2))) }
            if line.hasPrefix("## ") { return .heading(String(line.dropFirst(3))) }
            if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
            return .paragraph(line)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CP.Space.s) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case let .title(t):
                            Text(inline(t))
                                .font(.system(size: CP.fs(20), weight: .bold))
                                .foregroundStyle(CP.ink)
                        case let .heading(t):
                            Text(inline(t))
                                .font(.system(size: CP.fs(15), weight: .semibold))
                                .foregroundStyle(CP.ink)
                                .padding(.top, CP.Space.m)
                        case let .paragraph(t):
                            Text(inline(t))
                                .font(.system(size: CP.fs(13)))
                                .foregroundStyle(CP.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        case let .bullet(t):
                            HStack(alignment: .firstTextBaseline, spacing: CP.Space.s) {
                                Text("•").foregroundStyle(CP.inkMuted)
                                Text(inline(t))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(size: CP.fs(13)))
                            .foregroundStyle(CP.ink)
                            .padding(.leading, CP.Space.s)
                        }
                    }
                }
                .textSelection(.enabled)
                .padding(CP.Space.l)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(CP.paper)
            .navigationTitle("License Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose).accessibilityIdentifier("licenseTermsClose")
                }
            }
        }
        .tint(CP.sage.strong)
        .accessibilityIdentifier("licenseTerms")
    }
}
