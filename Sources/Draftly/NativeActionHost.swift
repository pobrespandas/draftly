import AppKit
import WebKit
import EventKit
import Security
import DraftlyCore

@MainActor
final class NativeActionHost: ActionHost {
    private var previewWindows: [NSWindow] = []
    let events = EKEventStore()
    let models = NativeModelAPI()
    var onMessage: ((String) -> Void)?
    var onActionPreview: ((ActionPreviewRequest) -> Void)?
    var testFileRoot: URL?
    var onPreview: ((String) -> Void)?

    func finishAction() { models.clear() }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        let text = values["text"] as? String ?? ""
        switch operation {
        case "clipboard": NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(text, forType: .string)
        case "getClipboard": return NSPasteboard.general.string(forType: .string) ?? ""
        case "getCredential": return try CredentialStore.read(values["name"] as? String ?? "")
        case "setCredential": try CredentialStore.write(values["name"] as? String ?? "", values: values["values"] as? [String: String] ?? [:]); return true
        case "forgetCredential": try CredentialStore.forget(values["name"] as? String ?? ""); return true
        case "htmlToClipboard":
            guard let data = (values["html"] as? String)?.data(using: .utf8) else { return false }
            let rich = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            let rtf = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(rtf, forType: .rtf)
            NSPasteboard.general.setData(data, forType: .html)
            NSPasteboard.general.setString(rich.string, forType: .string)
            return true
        case "markdown": return MarkdownRenderer.render(text)
        case "previewMarkdown": showHTML(MarkdownRenderer.page(MarkdownRenderer.render(text))); return true
        case "htmlPreview": return interactivePreview(values)
        case "openURL":
            guard let string = values["url"] as? String, let url = URL(string: string), let scheme = url.scheme,
                  !["javascript", "data", "file"].contains(scheme.lowercased()) else { throw DraftlyError.message("The action URL is invalid.") }
            guard NSWorkspace.shared.open(url) else { throw DraftlyError.message("No app could open this URL.") }
            return true
        case "alert":
            let alert = NSAlert(); alert.messageText = values["message"] as? String ?? "Draftly"; alert.runModal(); return true
        case "prompt": return prompt(values)
        case "selectPrompt": return selectPrompt(values)
        case "saveFile": return try saveFile(values)
        case "readFile", "writeFile", "fileExists":
            let root = try libraryFolder()
            let path = values["path"] as? String ?? ""
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let target = root.appendingPathComponent(relative).standardizedFileURL
            guard target.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw DraftlyError.message("The file path must stay inside the Draftly Library folder.") }
            if operation == "fileExists" { return FileManager.default.fileExists(atPath: target.path) }
            if operation == "readFile" { return try String(contentsOf: target, encoding: .utf8) }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: target, atomically: true, encoding: .utf8); return true
        case "share", "shareFile":
            let item: Any
            if operation == "shareFile" {
                let name = (values["name"] as? String ?? "Draft.txt").replacingOccurrences(of: "/", with: "-")
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(name); try text.write(to: url, atomically: true, encoding: .utf8); item = url
            } else { item = text }
            guard let view = NSApp.keyWindow?.contentView else { throw DraftlyError.message("Open a Draftly window before sharing.") }
            NSSharingServicePicker(items: [item]).show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 20, width: 1, height: 1), of: view, preferredEdge: .minY)
            return true
        case "shortcut": return try runShortcut(name: values["name"] as? String ?? "", input: text)
        case "appleScript": return try executeAppleScript(values)
        case "reminder":
            try requestAccess(reminders: true)
            guard let calendar = events.defaultCalendarForNewReminders() else { throw DraftlyError.message("No Reminders list is available.") }
            let reminder = EKReminder(eventStore: events); reminder.title = text.components(separatedBy: .newlines).first ?? text
            reminder.notes = text; reminder.calendar = calendar
            try events.save(reminder, commit: true); return true
        case "event":
            try requestAccess(reminders: false)
            guard let calendar = events.defaultCalendarForNewEvents else { throw DraftlyError.message("No Calendar is available.") }
            let alert = NSAlert(); alert.messageText = "Create calendar event"
            let picker = NSDatePicker(); picker.datePickerElements = [.yearMonthDay, .hourMinute]; picker.dateValue = Date()
            picker.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
            alert.informativeText = text.components(separatedBy: .newlines).first ?? text; alert.accessoryView = picker
            alert.addButton(withTitle: "Create Event"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { throw DraftlyError.message("Event creation cancelled.") }
            let event = EKEvent(eventStore: events); event.title = alert.informativeText; event.notes = text
            event.calendar = calendar; event.startDate = picker.dateValue; event.endDate = picker.dateValue.addingTimeInterval(3600)
            try events.save(event, span: .thisEvent); return true
        default: return try performAPI(operation, values: values)
        }
    }

    private func prompt(_ values: [String: Any]) -> Any? {
        let alert = NSAlert(); alert.messageText = values["title"] as? String ?? "Action"; alert.informativeText = values["message"] as? String ?? ""
        if let symbol = values["symbolName"] as? String { alert.icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        let help = PromptHelp(url: values["helpURL"] as? String); alert.delegate = help; alert.showsHelp = help.url != nil
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        var readers: [(String, () -> Any?)] = []
        var focus: NSView?
        for field in values["fields"] as? [[String: Any]] ?? [] {
            let key = field["key"] as? String ?? "", label = field["label"] as? String ?? key, kind = field["kind"] as? String ?? "text"
            if kind == "divider" { let box = NSBox(); box.boxType = .separator; stack.addArrangedSubview(box); continue }
            if kind != "switch" { let title = NSTextField(wrappingLabelWithString: label); if field["textSize"] as? String == "headline" { title.font = .boldSystemFont(ofSize: 14) }; stack.addArrangedSubview(title) }
            if kind == "label" { continue }
            switch kind {
            case "switch":
                let control = NSButton(checkboxWithTitle: label, target: nil, action: nil); control.state = field["value"] as? Bool == true ? .on : .off
                stack.addArrangedSubview(control); readers.append((key, { control.state == .on }))
            case "select" where field["multiple"] as? Bool == true:
                let selected = field["value"] as? [String] ?? [], options = field["options"] as? [String] ?? []
                var buttons: [NSButton] = []
                for option in options { let button = NSButton(checkboxWithTitle: option, target: nil, action: nil); button.state = selected.contains(option) ? .on : .off; stack.addArrangedSubview(button); buttons.append(button) }
                readers.append((key, { buttons.filter { $0.state == .on }.map(\.title) }))
            case "select", "segment":
                let control = NSPopUpButton(); let options = field["options"] as? [String] ?? []; control.addItems(withTitles: options)
                control.selectItem(withTitle: (field["value"] as? [String])?.first ?? field["value"] as? String ?? "")
                stack.addArrangedSubview(control); readers.append((key, { kind == "segment" ? (control.titleOfSelectedItem ?? "") as Any : [control.titleOfSelectedItem ?? ""] }))
            case "picker":
                let row = NSStackView(); var pickers: [NSPopUpButton] = []
                for (i, column) in (field["columns"] as? [[String]] ?? []).enumerated() {
                    let popup = NSPopUpButton(); popup.addItems(withTitles: column)
                    let selected = field["value"] as? [Int] ?? []; if selected.indices.contains(i), column.indices.contains(selected[i]) { popup.selectItem(at: selected[i]) }
                    pickers.append(popup); row.addArrangedSubview(popup)
                }
                stack.addArrangedSubview(row); readers.append((key, { pickers.map(\.indexOfSelectedItem) }))
            case "date":
                let picker = NSDatePicker(); let mode = field["mode"] as? String ?? "dateAndTime"
                picker.datePickerElements = mode == "date" ? [.yearMonthDay] : mode == "time" ? [.hourMinute] : [.yearMonthDay, .hourMinute]
                picker.dateValue = APIValues.parseDate(field["value"]) ?? Date(); picker.minDate = APIValues.parseDate(field["minimumDate"]); picker.maxDate = APIValues.parseDate(field["maximumDate"])
                stack.addArrangedSubview(picker); readers.append((key, { APIValues.date(picker.dateValue) }))
            case "textView":
                let text = NSTextView(); text.isRichText = false; text.string = field["value"] as? String ?? ""; text.font = .systemFont(ofSize: 13)
                let scroll = NSScrollView(); scroll.documentView = text; scroll.hasVerticalScroller = true
                scroll.widthAnchor.constraint(equalToConstant: 360).isActive = true; scroll.heightAnchor.constraint(equalToConstant: field["height"] as? CGFloat ?? 120).isActive = true
                stack.addArrangedSubview(scroll); readers.append((key, { text.string })); if field["wantsFocus"] as? Bool == true { focus = text }
            default:
                let value = field["value"] as? String ?? (field["value"] as? NSNumber)?.stringValue ?? ""
                let control: NSTextField = kind == "password" ? NSSecureTextField(string: value) : NSTextField(string: value)
                control.placeholderString = field["placeholder"] as? String; control.widthAnchor.constraint(equalToConstant: 360).isActive = true
                stack.addArrangedSubview(control)
                readers.append((key, {
                    if kind == "number" { let value = Double(control.stringValue); if field["allowDecimals"] as? Bool == false, let value, value.rounded() != value { return nil }; return value }
                    return control.stringValue
                }))
                if field["wantsFocus"] as? Bool == true { focus = control }
            }
        }
        stack.layoutSubtreeIfNeeded(); stack.frame = NSRect(x: 0, y: 0, width: 380, height: max(1, stack.fittingSize.height))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 390, height: min(540, stack.frame.height))); scroll.documentView = stack; scroll.hasVerticalScroller = true
        if !stack.arrangedSubviews.isEmpty { alert.accessoryView = scroll }
        let buttons = values["buttons"] as? [[String: Any]] ?? []
        for button in buttons {
            let control = alert.addButton(withTitle: button["title"] as? String ?? "Continue")
            control.hasDestructiveAction = button["isDestructive"] as? Bool ?? false
            if button["isDefault"] as? Bool == true { control.keyEquivalent = "\r"; control.keyEquivalentModifierMask = [.command] }
        }
        if buttons.isEmpty { alert.addButton(withTitle: "Continue") }
        if values["isCancellable"] as? Bool != false { let cancel = alert.addButton(withTitle: "Cancel"); cancel.keyEquivalent = "\u{1b}" }
        alert.window.initialFirstResponder = focus
        while true {
            let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            guard index >= 0, index < max(1, buttons.count) else { return nil }
            var result: [String: Any] = [:]; var invalid = false
            for (key, read) in readers { if let value = read() { result[key] = value } else { invalid = true } }
            if !invalid { return ["index": index, "fields": result] }
            let error = NSAlert(); error.messageText = "Enter a valid number."; error.runModal()
        }
    }

    private func selectPrompt(_ values: [String: Any]) -> Any? {
        let items = values["items"] as? [[String: Any]] ?? []
        guard !items.isEmpty else { return nil }
        let alert = NSAlert(); alert.messageText = values["title"] as? String ?? "Select a draft"
        if alert.messageText.isEmpty { alert.messageText = "Select a draft" }
        alert.informativeText = values["message"] as? String ?? ""
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 30))
        popup.addItems(withTitles: items.map { $0["title"] as? String ?? "Untitled" })
        alert.accessoryView = popup; alert.addButton(withTitle: "Select"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return ["index": popup.indexOfSelectedItem]
    }

    private func saveFile(_ values: [String: Any]) throws -> Bool {
        let text = values["text"] as? String ?? ""
        let name = (values["name"] as? String ?? "Draft.md").replacingOccurrences(of: "/", with: "-")
        let bookmarkName = values["bookmark"] as? String ?? ""
        let target: URL
        var scope: URL?
        if !bookmarkName.isEmpty {
            let key = "bookmark.\(bookmarkName)"
            var stale = false
            var root: URL?
            if let data = UserDefaults.standard.data(forKey: key) {
                root = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            }
            if root == nil || stale {
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
                panel.message = "Choose the folder for \(bookmarkName)."
                guard panel.runModal() == .OK, let url = panel.url else { throw DraftlyError.message("File export cancelled.") }
                root = url
                UserDefaults.standard.set(try url.bookmarkData(options: .withSecurityScope), forKey: key)
            }
            guard let root else { throw DraftlyError.message("The destination folder is unavailable.") }
            _ = root.startAccessingSecurityScopedResource(); scope = root
            let folder = root.appendingPathComponent(values["folder"] as? String ?? "").standardizedFileURL
            guard folder == root || folder.path.hasPrefix(root.path + "/") else { throw DraftlyError.message("The destination must stay inside the selected folder.") }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            target = folder.appendingPathComponent(name)
        } else {
            let panel = NSSavePanel(); panel.nameFieldStringValue = name
            guard panel.runModal() == .OK, let url = panel.url else { throw DraftlyError.message("File export cancelled.") }
            target = url
        }
        defer { scope?.stopAccessingSecurityScopedResource() }
        let mode = values["mode"] as? String ?? "create"
        guard ["create", "replace", "append", "prepend"].contains(mode) else { throw DraftlyError.message("Unsupported file write type: \(mode)") }
        if mode == "create", FileManager.default.fileExists(atPath: target.path), !bookmarkName.isEmpty {
            throw DraftlyError.message("A file with this name already exists. Choose another note title.")
        }
        var result = text
        if ["append", "prepend"].contains(mode), FileManager.default.fileExists(atPath: target.path) {
            let previous = try String(contentsOf: target, encoding: .utf8)
            result = mode == "append" ? previous + text : text + previous
        }
        try result.write(to: target, atomically: true, encoding: .utf8)
        return true
    }

    func libraryFolder() throws -> URL {
        let root = testFileRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draftly/Library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    func showHTML(_ html: String) {
        if let onPreview { onPreview(html); return }
        let config = WKWebViewConfiguration(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 680), configuration: config)
        view.loadHTMLString(html, baseURL: nil)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Preview — Draftly"; window.contentView = view; window.isReleasedWhenClosed = false
        window.center(); window.makeKeyAndOrderFront(nil)
        previewWindows.removeAll { !$0.isVisible }; previewWindows.append(window)
    }
    func requestAccess(reminders: Bool) throws {
        let entity: EKEntityType = reminders ? .reminder : .event
        if EKEventStore.authorizationStatus(for: entity) == .fullAccess { return }
        let result = AccessResult()
        if reminders { events.requestFullAccessToReminders { allowed, error in result.complete(allowed, error) } }
        else { events.requestFullAccessToEvents { allowed, error in result.complete(allowed, error) } }
        while !result.finished { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guard result.allowed else { throw DraftlyError.message(result.error?.localizedDescription ?? "Access was denied. Enable access in System Settings.") }
    }
    private func runShortcut(name: String, input: String) throws -> String {
        guard !name.isEmpty else { throw DraftlyError.message("Enter a Shortcut name in the action step.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("input.txt"); let output = root.appendingPathComponent("output.txt")
        let errors = root.appendingPathComponent("errors.txt")
        try input.write(to: source, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { try? errorHandle.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name, "--input-path", source.path, "--output-path", output.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = errorHandle
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        if process.isRunning { process.terminate(); throw DraftlyError.message("The Shortcut exceeded 60 seconds.") }
        guard process.terminationStatus == 0 else { throw DraftlyError.message((try? String(contentsOf: errors, encoding: .utf8)) ?? "The Shortcut failed.") }
        return (try? String(contentsOf: output, encoding: .utf8)) ?? ""
    }
}

private final class AccessResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (Bool, Error?)?
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }
    var allowed: Bool { lock.lock(); defer { lock.unlock() }; return result?.0 == true }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return result?.1 }
    func complete(_ allowed: Bool, _ error: Error?) { lock.lock(); result = (allowed, error); lock.unlock() }
}

@MainActor private final class PromptHelp: NSObject, NSAlertDelegate {
    let url: URL?
    init(url: String?) { self.url = url.flatMap(URL.init(string:)) }
    func alertShowHelp(_ alert: NSAlert) -> Bool { guard let url else { return false }; return NSWorkspace.shared.open(url) }
}
