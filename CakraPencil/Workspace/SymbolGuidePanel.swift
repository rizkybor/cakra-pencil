import CakraCore
import SwiftUI
import WebKit

/// What the symbol guide shows: a symbol code (searched on the page) in one of the specifications.
struct SymbolGuideRequest: Equatable {
    var code: String
    var name: String
    var spec: SymbolGuide.Spec
}

/// Symbol guide panel next to the map: the ISOM / ISSprOM omapwiki page, scrolled to the symbol code and highlighted.
/// Follows the active symbol while open (unless the user is searching for another one). Same on iPad and Mac.
struct SymbolGuidePanel: View {
    @ObservedObject var model: WorkspaceModel
    @StateObject private var web = GuideWebState()
    @State private var query = ""

    private var request: SymbolGuideRequest? { model.symbolGuide }

    var body: some View {
        VStack(alignment: .leading, spacing: CP.Space.s) {
            HStack {
                Label("Symbol guide", systemImage: "book")
                    .font(.system(size: CP.fs(15), weight: .semibold))
                    .foregroundStyle(CP.ink)
                Spacer()
                Button { model.closeSymbolGuide() } label: { Image(systemName: "xmark") }
                    .buttonStyle(ToolButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close symbol guide")
                    .help("Close symbol guide (Esc)")
            }
            Segmented("Specification", selection: Binding(get: { request?.spec ?? .isom }, set: { model.setSymbolGuideSpec($0) }),
                      SymbolGuide.Spec.allCases.map { .init($0, $0.label) })
            .accessibilityIdentifier("guideSpec")

            HStack(spacing: CP.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: web.searchedTerm ?? request?.code ?? "")
                        .font(CP.mono(14, weight: .semibold)).foregroundStyle(CP.ink)
                        .accessibilityIdentifier("guideCode")
                    if let name = request?.name, web.searchedTerm == nil || web.searchedTerm == request?.code {
                        Text(name).font(.system(size: CP.fs(12))).foregroundStyle(CP.inkMuted).lineLimit(1)
                    }
                }
                Spacer()
                Text(web.status)
                    .font(.system(size: CP.fs(12)))
                    .foregroundStyle(web.matchCount == 0 && web.loaded ? CP.rose.strong : CP.inkMuted)
                    .accessibilityIdentifier("guideStatus")
                Button { web.step(backwards: true) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(web.matchCount < 2)
                    .accessibilityLabel("Previous match")
                Button { web.step(backwards: false) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(ToolButtonStyle())
                    .disabled(web.matchCount < 2)
                    .accessibilityLabel("Next match")
            }

            ZStack {
                GuideWebView(state: web)
                    .clipShape(RoundedRectangle(cornerRadius: CP.Radius.control))
                    .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
                if web.failed {
                    offline
                } else if !web.loaded {
                    ProgressView().controlSize(.large)
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: CP.Space.s) {
                HStack(spacing: CP.Space.xs) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CP.inkMuted)
                    TextField("Find symbol (e.g. 520 or 509.1)", text: $query)
                        .font(.system(size: CP.fs(13)))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { search() }
                        .accessibilityIdentifier("guideSearch")
                    if !query.isEmpty {
                        Button { query = ""; model.symbolGuideSearching = false; follow() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(CP.inkMuted)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, CP.Space.s)
                .frame(height: 34)
                .background(CP.paper, in: RoundedRectangle(cornerRadius: CP.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: CP.Radius.control).strokeBorder(CP.line))
                if let spec = request?.spec {
                    Link(destination: spec.url) { Label("Safari", systemImage: "arrow.up.right.square") }
                        .font(.system(size: CP.fs(13), weight: .medium))
                        .help("Open the full page in the browser")
                }
            }
        }
        .padding(CP.Space.m)
        // A container (keeps the children's own identifiers) that UI tests can find.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("symbolGuidePanel")
        .onAppear { follow() }
        .onChange(of: request) { _, _ in if !model.symbolGuideSearching { follow() } }
    }

    /// Load the spec page (if needed) and search for the requested symbol code.
    private func follow() {
        guard let r = request else { return }
        web.show(spec: r.spec, terms: SymbolGuide.searchTerms(for: r.code))
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let r = request else { return }
        model.symbolGuideSearching = true
        web.show(spec: r.spec, terms: SymbolGuide.searchTerms(for: q))
    }

    /// Offline / page failed: basic info OCCA has about the symbol.
    private var offline: some View {
        VStack(spacing: CP.Space.s) {
            Image(systemName: "wifi.slash").font(.system(size: 28)).foregroundStyle(CP.inkMuted)
            Text("The symbol guide needs an internet connection.")
                .font(.system(size: CP.fs(14), weight: .medium)).foregroundStyle(CP.ink)
                .multilineTextAlignment(.center)
            if let r = request, let s = model.symbolLookup?(r.code, r.name) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "\(s.code) \(s.name)").font(.system(size: CP.fs(13), weight: .semibold))
                    Text(verbatim: "\(s.kind.label) · \(Fmt.mm(s.drawingWidthMM)) · \(s.colorHex)")
                        .font(CP.mono(12)).foregroundStyle(CP.inkMuted)
                }
                .padding(CP.Space.s)
                .background(CP.paper2, in: RoundedRectangle(cornerRadius: CP.Radius.control))
            }
            Button("Try again") { web.reload() }
                .buttonStyle(.bordered)
        }
        .padding(CP.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CP.paper)
    }
}

// MARK: - Web view

/// The page, the pending search, and the result (shared between the panel and the WKWebView coordinator).
@MainActor
final class GuideWebState: ObservableObject {
    @Published var loaded = false
    @Published var failed = false
    @Published var matchCount = 0
    @Published var matchIndex = 0
    @Published var searchedTerm: String?
    fileprivate weak var webView: WKWebView?
    private var spec: SymbolGuide.Spec?
    private var terms: [String] = []
    /// After a new symbol is requested, open its detail page once (the spec page lists summaries only).
    private var openDetail = false
    /// Back on the spec list for the current terms (the detail page couldn't be found).
    var onDetailPage: Bool { webView?.url.map { $0 != spec?.url } ?? false }

    var status: String {
        if failed { return "" }
        if !loaded { return "Loading…" }
        if matchCount == 0 { return terms.isEmpty ? "" : "Not found on this page" }
        return "\(matchIndex) of \(matchCount)"
    }

    func show(spec: SymbolGuide.Spec, terms: [String]) {
        self.terms = terms
        openDetail = true
        if self.spec != spec || webView?.url == nil || onDetailPage {
            self.spec = spec
            loaded = false
            failed = false
            matchCount = 0
            webView?.load(URLRequest(url: spec.url))
        } else if loaded {
            find()
        }
    }

    func reload() {
        guard let spec else { return }
        failed = false
        loaded = false
        webView?.load(URLRequest(url: spec.url))
    }

    func didLoad() {
        loaded = true
        failed = false
        find()
    }

    func didFail() {
        loaded = true
        failed = true
    }

    /// Count the code on the page and select (scroll to + highlight) its first occurrence; the first term that is
    /// found wins ("101.0", then "101").
    func find() {
        guard let webView, !terms.isEmpty else { return }
        // JSON-encoded so typed search text can never break out of the JavaScript string.
        let list = Self.jsonLiteral(terms).dropFirst().dropLast()
        let js = """
        (function(terms){
          const text = document.body ? document.body.innerText : '';
          for (const t of terms) {
            const esc = t.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
            const re = new RegExp('(^|[^0-9.])' + esc + '(?![0-9])', 'g');
            const m = text.match(re);
            if (m && m.length) {
              window.getSelection().removeAllRanges();
              window.find(t, false, false, true);
              // Link to the symbol's own page: a link whose text starts with the code ("505 Unpaved footpath…").
              let href = '';
              for (const a of document.querySelectorAll('a[href]')) {
                const s = (a.innerText || '').trim();
                if (s.startsWith(t + ' ') || s === t) { href = a.href; break; }
              }
              return t + '|' + href + '|' + m.length;
            }
          }
          return '||0';
        })([\(list)])
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self, let s = result as? String else { return }
            let parts = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            self.searchedTerm = parts.first.flatMap { $0.isEmpty ? nil : $0 }
            self.matchCount = Int(parts.last ?? "0") ?? 0
            self.matchIndex = self.matchCount > 0 ? 1 : 0
            if self.openDetail, parts.count == 3, let url = URL(string: parts[1]), url.host == self.spec?.url.host {
                self.openDetail = false
                self.loaded = false
                webView.load(URLRequest(url: url))
            } else {
                self.openDetail = false
            }
        }
    }

    /// `["a","b"]` as a JavaScript/JSON literal (strings escaped).
    static func jsonLiteral(_ strings: [String]) -> String {
        (try? JSONEncoder().encode(strings)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// Next / previous occurrence of the found term (wraps around).
    func step(backwards: Bool) {
        guard let webView, let t = searchedTerm, matchCount > 1 else { return }
        let js = "window.find(\(Self.jsonLiteral([t]).dropFirst().dropLast()), false, \(backwards), true)"
        webView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self else { return }
            self.matchIndex = backwards ? (self.matchIndex <= 1 ? self.matchCount : self.matchIndex - 1)
                                        : (self.matchIndex >= self.matchCount ? 1 : self.matchIndex + 1)
        }
    }
}

private struct GuideWebView: UIViewRepresentable {
    @ObservedObject var state: GuideWebState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // keeps pages cached while the app runs
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        state.webView = view
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let state: GuideWebState
        init(state: GuideWebState) { self.state = state }

        /// Only the omapwiki pages load in the panel; other links (IOF site, downloads) open in the browser.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            let host = SymbolGuide.Spec.isom.url.host
            if url.scheme == "https", url.host == host || action.targetFrame?.isMainFrame == false {
                decisionHandler(.allow)
            } else {
                if ["http", "https"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in state.didLoad() }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in state.didFail() }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in state.didFail() }
        }
    }
}
