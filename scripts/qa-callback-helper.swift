import AppKit

// Build this helper only for a separate, manual QA session.
@main @MainActor final class CallbackHelper: NSObject, NSApplicationDelegate {
    private static let delegate = CallbackHelper()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "draftly-engine-echo",
                  let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { continue }
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
                application.terminate(nil)
            }
        }
    }
}
