import AppKit
import WebKit
import Testing
import DraftlyCore
@testable import Draftly

@MainActor struct MarkdownPreviewLayoutTests {
    @Test func processorLineBreakChoicesReachActualParagraphLayout() async throws {
        let soft = try ScriptMarkdown.render("One café 🐼\nTwo", engine: "github", options: ["hardBreaks": false])
        let hard = try ScriptMarkdown.render("One café 🐼\nTwo", engine: "github", options: ["hardBreaks": true])
        let escaped = try ScriptMarkdown.render("One café 🐼\\\nTwo", engine: "github", options: ["hardBreaks": false])
        let html = MarkdownRenderer.page("<section id='soft'>\(soft)</section><section id='hard'>\(hard)</section><section id='escaped'>\(escaped)</section><pre id='code'>One\n  Two</pre>")
        let page = PreviewLayoutProbe()
        try await page.load(html)
        func lines(_ selector: String) async throws -> Double {
            try await page.number("(()=>{let p=document.querySelector('\(selector)'),s=getComputedStyle(p);return (p.getBoundingClientRect().height-parseFloat(s.paddingTop)-parseFloat(s.paddingBottom)-parseFloat(s.borderTopWidth)-parseFloat(s.borderBottomWidth))/parseFloat(s.lineHeight)})()")
        }
        let softLines = try await lines("#soft p")
        let hardLines = try await lines("#hard p")
        let escapedLines = try await lines("#escaped p")
        let codeLines = try await lines("#code")
        #expect(abs(softLines - 1) < 0.05)
        #expect(abs(hardLines - 2) < 0.05)
        #expect(abs(escapedLines - 2) < 0.05)
        #expect(abs(codeLines - 2) < 0.05)
    }
}

@MainActor private final class PreviewLayoutProbe: NSObject, WKNavigationDelegate {
    private let web: WKWebView
    private var pending: CheckedContinuation<Void, any Error>?
    private var timeout: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        super.init()
        web.navigationDelegate = self
    }
    func load(_ html: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                self?.finish(.failure(DraftlyError.message("The local preview did not load.")))
            }
            if web.loadHTMLString(html, baseURL: nil) == nil {
                finish(.failure(DraftlyError.message("The local preview could not start.")))
            }
        }
    }
    func number(_ script: String) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let number = value as? NSNumber { continuation.resume(returning: number.doubleValue) }
                else { continuation.resume(throwing: DraftlyError.message("The preview measurement is not a number.")) }
            }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    private func finish(_ result: Result<Void, any Error>) {
        guard let continuation = pending else { return }
        pending = nil; timeout?.cancel(); timeout = nil
        continuation.resume(with: result)
    }
}
