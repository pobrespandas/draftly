import SwiftUI
import WebKit
import DraftlyCore

@MainActor final class ActionPreviewRequest: ObservableObject, Identifiable {
    let id = UUID(), html: String, hideInterface: Bool
    private(set) var result: Bool?
    private(set) var error: Error?
    var values: [String: Any] = [:]
    var onFinish: (() -> Void)?
    private var observers: [() -> Void] = []
    private var cleanups: [() -> Void] = []
    init(html: String, hideInterface: Bool) { self.html = html; self.hideInterface = hideInterface }
    func finish(_ success: Bool) {
        guard result == nil else { return }
        result = success
        let cleanups = self.cleanups, observers = self.observers
        self.cleanups = []; self.observers = []
        cleanups.forEach { $0() }
        onFinish?()
        observers.forEach { $0() }
    }
    func fail(_ error: Error) {
        guard result == nil else { return }
        self.error = error; finish(false)
    }
    func observeFinish(_ observer: @escaping () -> Void) {
        if result != nil { observer() } else { observers.append(observer) }
    }
    func addCleanup(_ cleanup: @escaping () -> Void) {
        if result != nil { cleanup() } else { cleanups.append(cleanup) }
    }
    func receive(_ body: [String: Any], mainFrame: Bool = true) {
        guard result == nil, mainFrame else { return }
        switch body["operation"] as? String {
        case "continue": finish(true)
        case "cancel": finish(false)
        case "send": if let key = body["key"] as? String { values[key] = body["value"] ?? NSNull() }
        default: break
        }
    }
}

@MainActor enum NativeHTMLPreviewRequest {
    static func run(_ values: [String: Any], timeout: TimeInterval = 120,
                    present: @MainActor (ActionPreviewRequest) throws -> Void) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout > 0 else { throw DraftlyError.message("The HTML preview timeout must be positive and finite.") }
        let request = ActionPreviewRequest(html: values["html"] as? String ?? "", hideInterface: values["hideInterface"] as? Bool ?? false)
        var timeoutTask: Task<Void, Never>?
        defer { timeoutTask?.cancel() }
        let success: Bool = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.observeFinish {
                    if let error = request.error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: request.result == true) }
                }
                guard !Task.isCancelled else { request.fail(CancellationError()); return }
                do { try present(request) } catch { request.fail(error) }
                guard request.result == nil else { return }
                timeoutTask = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                    request.fail(ActionExecutionInterruption.timeout)
                }
            }
        } onCancel: { Task { @MainActor in request.fail(CancellationError()) } }
        try Task.checkCancellation()
        return ["success": success, "values": request.values]
    }
}

struct ActionPreviewPane: View {
    let request: ActionPreviewRequest
    var body: some View {
        VStack(spacing: 0) {
            ActionPreviewWebView(request: request)
            if !request.hideInterface {
                Divider()
                HStack { Button("Cancel") { request.finish(false) }; Spacer(); Button("Continue") { request.finish(true) }.keyboardShortcut(.defaultAction) }.padding(12)
            }
        }.onDisappear { request.finish(false) }
    }
}

struct ActionPreviewWebView: NSViewRepresentable {
    let request: ActionPreviewRequest
    func makeCoordinator() -> Coordinator { Coordinator(request) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "draftly")
        configuration.userContentController.addUserScript(WKUserScript(source: """
            window.Drafts = {
              send: (key,value) => window.webkit.messageHandlers.draftly.postMessage({operation:'send',key,value}),
              continue: () => window.webkit.messageHandlers.draftly.postMessage({operation:'continue'}),
              cancel: () => window.webkit.messageHandlers.draftly.postMessage({operation:'cancel'})
            };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration); view.setAccessibilityLabel("Action HTML Preview")
        view.navigationDelegate = context.coordinator
        request.addCleanup { [weak view, weak coordinator = context.coordinator] in
            if let view { coordinator?.detach(view) }
        }
        if request.result == nil { view.loadHTMLString(request.html, baseURL: nil) }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { coordinator.detach(view); coordinator.request.finish(false) }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let request: ActionPreviewRequest
        private var detached = false
        init(_ request: ActionPreviewRequest) { self.request = request }
        func detach(_ view: WKWebView) {
            guard !detached else { return }
            detached = true
            view.stopLoading(); view.navigationDelegate = nil
            view.configuration.userContentController.removeScriptMessageHandler(forName: "draftly")
            view.configuration.userContentController.removeAllUserScripts()
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            request.receive(body, mainFrame: message.frameInfo.isMainFrame)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { request.fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { request.fail(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { request.fail(DraftlyError.message("The HTML preview web process stopped.")) }

    }
}

@MainActor extension NativeActionHost {
    func interactivePreview(_ values: [String: Any]) -> [String: Any] {
        let request = ActionPreviewRequest(html: values["html"] as? String ?? "", hideInterface: values["hideInterface"] as? Bool ?? false)
        var standalone: NSWindow?
        if let onActionPreview { onActionPreview(request) }
        else {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Action Preview — Draftly"; window.contentView = NSHostingView(rootView: ActionPreviewPane(request: request)); window.isReleasedWhenClosed = false
            window.center(); window.makeKeyAndOrderFront(nil); standalone = window
        }
        while request.result == nil {
            if let standalone, !standalone.isVisible { request.finish(false); break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        standalone?.close()
        return ["success": request.result == true, "values": request.values]
    }
}

@MainActor extension NativeActionHost {
    func interactivePreviewAsync(_ values: [String: Any], timeout: TimeInterval = 120) async throws -> [String: Any] {
        try await NativeHTMLPreviewRequest.run(values, timeout: timeout) { request in
            if let onActionPreview { onActionPreview(request) }
            else { PreviewStandalonePresenter.show(request) }
        }
    }
}

@MainActor private final class PreviewStandalonePresenter: NSObject, NSWindowDelegate {
    weak var request: ActionPreviewRequest?
    init(_ request: ActionPreviewRequest) { self.request = request }
    static func show(_ request: ActionPreviewRequest) {
        let delegate = PreviewStandalonePresenter(request)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 680), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Action Preview — Draftly"; window.contentView = NSHostingView(rootView: ActionPreviewPane(request: request))
        window.isReleasedWhenClosed = false; window.delegate = delegate
        request.addCleanup { [window, delegate] in
            window.delegate = nil; window.close(); _ = delegate
        }
        window.center(); window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { request?.finish(false) }
}
