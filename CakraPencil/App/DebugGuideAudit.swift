#if DEBUG
import CakraCore
import Foundation
import WebKit

/// `-cp-guide-audit`: checks the Symbol Guide against every OCCA symbol. Loads the ISOM and ISSprOM omapwiki pages in a
/// web view (like the guide), runs the guide's own search for each symbol code of OCCA's sets, and writes
/// Documents/guide-audit.txt: found term, number of matches, the symbol's own page link, and whether its name matches.
/// The app quits when done.
@MainActor
final class DebugGuideAudit: NSObject, WKNavigationDelegate {
    static var shared: DebugGuideAudit?

    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-cp-guide-audit") else { return }
        let audit = DebugGuideAudit()
        shared = audit
        audit.start()
    }

    private var webView: WKWebView!
    private var window: UIWindow?
    private var queue: [SymbolGuide.Spec] = SymbolGuide.Spec.allCases
    private var report: [String] = []
    private var totals: [String] = []
    private var waiting: CheckedContinuation<Void, Never>?

    private func start() {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        webView.navigationDelegate = self
        // Keep it in a (hidden) window so the page's scripts and the site's browser check run normally.
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let w = UIWindow(windowScene: scene)
            w.frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
            w.rootViewController = UIViewController()
            w.rootViewController?.view.addSubview(webView)
            w.isHidden = false
            w.alpha = 0.01
            window = w
        }
        Task { await run() }
    }

    private func run() async {
        for spec in SymbolGuide.Spec.allCases {
            await audit(spec)
        }
        let text = (["Symbol Guide audit — \(Date())", ""] + totals + [""] + report).joined(separator: "\n")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("guide-audit.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        exit(0)
    }

    private func audit(_ spec: SymbolGuide.Spec) async {
        webView.load(URLRequest(url: spec.url))
        // Wait for the real page (the site may show a short browser check first).
        var page: (text: String, links: [[String]])?
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            let href = (try? await webView.evaluateJavaScript("location.href") as? String) ?? ""
            guard href.contains("/specifications/\(spec.rawValue)/") else { continue }
            if let p = await pageContent(), !p.text.contains("Just a moment"), p.text.count > 2000 { page = p; break }
        }
        guard let page else {
            totals.append("\(spec.label): PAGE NOT LOADED")
            return
        }
        let pageURL = (try? await webView.evaluateJavaScript("location.href") as? String) ?? ""
        let title = (try? await webView.evaluateJavaScript("document.title") as? String) ?? ""
        report.append("PAGE \(spec.label): url=\(pageURL) title=\(title) textChars=\(page.text.count) links=\(page.links.count)")
        let file = spec == .isom ? OccaStandardSymbols.isomFile() : OccaStandardSymbols.issprFile()
        var found = 0, linked = 0, nameOK = 0
        var missing: [String] = [], noLink: [String] = [], nameDiff: [String] = []
        report.append("== \(spec.label) (\(spec.url.absoluteString)) — \(file.symbols.count) symbols")
        for s in file.symbols {
            let terms = SymbolGuide.searchTerms(for: s.code)
            var hit: (term: String, count: Int)?
            for t in terms {
                let n = Self.count(t, in: page.text)
                if n > 0 { hit = (t, n); break }
            }
            guard let hit else {
                missing.append("\(s.code) \(s.name)")
                report.append("  ✗ \(s.code) \(s.name) — NOT FOUND (terms \(terms.joined(separator: ", ")))")
                continue
            }
            found += 1
            let link = page.links.first { l in l[0].hasPrefix(hit.term + " ") || l[0] == hit.term }
            if link != nil { linked += 1 } else { noLink.append("\(s.code) \(s.name)") }
            let linkName = link.map { String(($0[0].split(separator: "\n").first.map(String.init) ?? "").dropFirst(hit.term.count))
                .trimmingCharacters(in: .whitespaces) } ?? ""
            let same = !linkName.isEmpty && Self.similar(linkName, s.name)
            if same { nameOK += 1 } else if link != nil { nameDiff.append("\(s.code) OCCA “\(s.name)” vs guide “\(linkName)”") }
            report.append("  \(link == nil ? "~" : (same ? "✓" : "≠")) \(s.code) \(s.name) — “\(hit.term)” ×\(hit.count)"
                          + (link.map { " → \($0[0].split(separator: "\n").first.map(String.init) ?? "") [\($0[1])]" } ?? " (no own page link)"))
        }
        totals.append("\(spec.label): \(file.symbols.count) symbols · found \(found) · own page link \(linked) · same name \(nameOK)")
        if !missing.isEmpty { totals.append("  not found: " + missing.joined(separator: "; ")) }
        if !noLink.isEmpty { totals.append("  found but no own page link: " + noLink.joined(separator: "; ")) }
        if !nameDiff.isEmpty { totals.append("  name differs: " + nameDiff.joined(separator: "\n    ")) }
        report.append("")
    }

    /// Same rule as the guide's page search: the code not preceded by a digit or dot and not followed by a digit.
    static func count(_ term: String, in text: String) -> Int {
        let esc = NSRegularExpression.escapedPattern(for: term)
        guard let re = try? NSRegularExpression(pattern: "(^|[^0-9.])" + esc + "(?![0-9])") else { return 0 }
        return re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: ",", with: "")
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
        }
        let x = norm(a), y = norm(b)
        return x == y || x.hasPrefix(y) || y.hasPrefix(x)
    }

    private func pageContent() async -> (text: String, links: [[String]])? {
        let js = """
        JSON.stringify({ text: document.body ? document.body.innerText : '',
          links: Array.from(document.querySelectorAll('a[href]')).map(a => [(a.innerText || '').trim(), a.href]) })
        """
        guard let s = try? await webView.evaluateJavaScript(js) as? String, let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return ((o["text"] as? String) ?? "", (o["links"] as? [[String]]) ?? [])
    }
}
#endif
