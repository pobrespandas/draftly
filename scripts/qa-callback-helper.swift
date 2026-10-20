import AppKit
import CoreGraphics

struct QAWindowInventory {
    struct Row {
        let number: Int
        let title: String?
        let layer: Int
        let onScreen: Bool
    }
    static func rows(_ windows: [[String: Any]], pid: pid_t) -> [Row] {
        windows.compactMap { values in
            guard (values[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let number = (values[kCGWindowNumber as String] as? NSNumber)?.intValue else { return nil }
            return Row(number: number, title: values[kCGWindowName as String] as? String,
                layer: (values[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                onScreen: (values[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
        }.sorted { $0.number < $1.number }
    }
    static func checkFixtures() -> Bool {
        let fixtures: [[String: Any]] = [
            [kCGWindowOwnerPID as String: 42, kCGWindowNumber as String: 2, kCGWindowLayer as String: 0, kCGWindowIsOnscreen as String: true, kCGWindowName as String: "Untitled"],
            [kCGWindowOwnerPID as String: 42, kCGWindowNumber as String: 1, kCGWindowLayer as String: 3, kCGWindowIsOnscreen as String: false, kCGWindowName as String: ""],
            [kCGWindowOwnerPID as String: 7, kCGWindowNumber as String: 99, kCGWindowIsOnscreen as String: true, kCGWindowName as String: "Foreign app"],
            [kCGWindowOwnerPID as String: 42, kCGWindowNumber as String: 3, kCGWindowLayer as String: 0, kCGWindowIsOnscreen as String: false],
            [kCGWindowOwnerPID as String: 42]
        ]
        let records = rows(fixtures, pid: 42)
        guard records.count == 3, records.map(\.number) == [1, 2, 3], records[0].title == "", records[2].title == nil else { return false }
        let text = summary(records, pid: 42)
        return text.contains("1 visible normal windows; 3 total window records.")
            && text.contains("<empty title>") && text.contains("<title unavailable>") && !text.contains("Foreign app")
    }
    static func summary(_ rows: [Row], pid: pid_t) -> String {
        let visible = rows.filter { $0.onScreen && $0.layer == 0 }.count
        let details = rows.prefix(10).map { row in
            let title = row.title.map { $0.isEmpty ? "<empty title>" : $0 } ?? "<title unavailable>"
            return "#\(row.number) layer=\(row.layer) \(row.onScreen ? "visible" : "offscreen") — \(title)"
        }
        return (["QA PID \(pid): \(visible) visible normal windows; \(rows.count) total window records."] + details
            + (rows.count > 10 ? ["Additional records: \(rows.count - 10)"] : [])).joined(separator: "\n")
    }
}

// Build this helper only for a separate, manual QA session.
@main @MainActor final class CallbackHelper: NSObject, NSApplicationDelegate {
    private static let delegate = CallbackHelper()
    private var panel: NSWindow?
    private let targetField = NSTextField(string: "draftly://create?text=Cold%20launch%20QA%20%F0%9F%90%BC")
    private let resultField = NSTextField(wrappingLabelWithString: "Open a neutral URL in the isolated QA app.")
    private let inventoryField = NSTextField(wrappingLabelWithString: "Window inventory is off. It does not activate or control the QA app.")
    private lazy var inventoryToggle = NSButton(checkboxWithTitle: "Monitor QA windows (read only)", target: self, action: #selector(toggleInventory))
    private lazy var refreshButton = NSButton(title: "Refresh window inventory", target: self, action: #selector(refreshInventory))
    private var inventoryTimer: Timer?

    static func main() {
        if ProcessInfo.processInfo.arguments.contains("--window-inventory-self-test") {
            exit(QAWindowInventory.checkFixtures() ? 0 : 1)
        }
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 390),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Draftly Automation QA Helper"
        window.isReleasedWhenClosed = false
        resultField.maximumNumberOfLines = 3
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 12
        let button = NSButton(title: "Open in QA", target: self, action: #selector(openInQA))
        stack.addArrangedSubview(targetField); stack.addArrangedSubview(button); stack.addArrangedSubview(resultField)
        let inventoryControls = NSStackView(views: [inventoryToggle, refreshButton]); inventoryControls.orientation = .horizontal
        refreshButton.isEnabled = false
        inventoryField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        stack.addArrangedSubview(inventoryControls); stack.addArrangedSubview(inventoryField)
        stack.frame = NSRect(x: 20, y: 20, width: 580, height: 350)
        targetField.widthAnchor.constraint(equalToConstant: 580).isActive = true
        resultField.widthAnchor.constraint(equalToConstant: 580).isActive = true
        inventoryField.widthAnchor.constraint(equalToConstant: 580).isActive = true
        window.contentView?.addSubview(stack)
        panel = window
        window.center(); window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func toggleInventory() {
        inventoryTimer?.invalidate(); inventoryTimer = nil
        refreshButton.isEnabled = inventoryToggle.state == .on
        guard inventoryToggle.state == .on else { inventoryField.stringValue = "Window inventory is off."; return }
        refreshInventory()
        inventoryTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(refreshInventory), userInfo: nil, repeats: true)
    }

    @objc private func refreshInventory() {
        guard inventoryToggle.state == .on else { return }
        let applications = NSWorkspace.shared.runningApplications.filter { application in
            guard application.bundleIdentifier == "com.andrestobelem.draftly.engine-qa", !application.isTerminated,
                  let url = application.bundleURL, let bundle = Bundle(url: url),
                  bundle.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true else { return false }
            return true
        }
        guard !applications.isEmpty else { inventoryField.stringValue = "The isolated QA app is not running."; return }
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            inventoryField.stringValue = "Window metadata is unavailable."; return
        }
        let summaries = applications.sorted { $0.processIdentifier < $1.processIdentifier }.map { application in
            QAWindowInventory.summary(QAWindowInventory.rows(windows, pid: application.processIdentifier), pid: application.processIdentifier)
        }
        inventoryField.stringValue = summaries.joined(separator: "\n\n") + "\nTitles may be hidden by macOS privacy controls. No permission is requested."
    }

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
