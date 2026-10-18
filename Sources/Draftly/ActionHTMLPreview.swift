import SwiftUI
import WebKit
import DraftlyCore

@MainActor final class ActionPreviewRequest: ObservableObject, Identifiable {
    let id = UUID(), html: String, hideInterface: Bool
    private(set) var result: Bool?
    var values: [String: Any] = [:]
    var onFinish: (() -> Void)?
    init(html: String, hideInterface: Bool) { self.html = html; self.hideInterface = hideInterface }
    func finish(_ success: Bool) { guard result == nil else { return }; result = success; onFinish?() }
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
        view.loadHTMLString(request.html, baseURL: nil); return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { view.configuration.userContentController.removeScriptMessageHandler(forName: "draftly") }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler {
        let request: ActionPreviewRequest
        init(_ request: ActionPreviewRequest) { self.request = request }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
            switch body["operation"] as? String {
            case "continue": request.finish(true)
            case "cancel": request.finish(false)
            case "send": if let key = body["key"] as? String { request.values[key] = body["value"] ?? NSNull() }
            default: break
            }
        }
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
