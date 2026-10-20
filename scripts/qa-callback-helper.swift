import AppKit

// Build this helper only for a separate, manual QA session.
@main @MainActor final class CallbackHelper: NSObject, NSApplicationDelegate {
    private static let delegate = CallbackHelper()
    private var panel: NSWindow?
    private let targetField = NSTextField(string: "draftly://create?text=Cold%20launch%20QA%20%F0%9F%90%BC")
    private let resultField = NSTextField(wrappingLabelWithString: "Open a neutral URL in the isolated QA app.")

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit QA Helper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Draftly Automation QA Helper"
        window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12
        let button = NSButton(title: "Open in QA", target: self, action: #selector(openInQA))
        stack.addArrangedSubview(targetField); stack.addArrangedSubview(button); stack.addArrangedSubview(resultField)
        stack.frame = NSRect(x: 20, y: 20, width: 580, height: 140)
        targetField.widthAnchor.constraint(equalToConstant: 580).isActive = true
        window.contentView?.addSubview(stack)
        panel = window
        window.center(); window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func openInQA() {
        panel?.makeFirstResponder(nil)
        guard let url = URL(string: targetField.stringValue), url.scheme == "draftly",
              ["open", "create", "capture", "run", "runAction", "action", "x-callback-url"].contains(url.host ?? ""),
              let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "draftly-engine-qa://callback")!),
              let bundle = Bundle(url: app), bundle.bundleIdentifier == "com.andrestobelem.draftly.engine-qa",
              bundle.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true else {
            resultField.stringValue = "The isolated QA app or URL is invalid."
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: .init()) { [weak self] _, error in
            let message = error?.localizedDescription ?? "Delivered: " + url.absoluteString
            Task { @MainActor in self?.resultField.stringValue = message }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "draftly-engine-echo",
                  let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { continue }
            if url.host == "received" {
                resultField.stringValue = query.map { $0.name + "=" + ($0.value ?? "") }.joined(separator: "\n")
                panel?.makeKeyAndOrderFront(nil)
                continue
            }
            func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
            let status = value("status") ?? "success"
            let key = ["success": "x-success", "cancelled": "x-cancel", "error": "x-error"][status]
            guard let key, let target = value(key),
                  var callback = URLComponents(string: target),
                  callback.scheme == "draftly-engine-qa", callback.host == "callback" else { continue }
            callback.queryItems = (callback.queryItems ?? []) + [URLQueryItem(name: "value", value: "Native café 🐼")]
            guard let destination = callback.url else { continue }
            let delay = min(10, max(0, Double(value("delay") ?? "0") ?? 0))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                NSWorkspace.shared.open(destination)
                if self.panel == nil { application.terminate(nil) }
            }
        }
    }
}
