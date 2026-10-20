import AppKit
import DraftlyCore

@MainActor
struct NativePromptAdapter {
    static let operations: Set<String> = ["confirmAction", "alert", "prompt", "selectPrompt"]

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        switch operation {
        case "confirmAction":
            let alert = NSAlert(); alert.messageText = "Run " + (values["name"] as? String ?? "Action") + "?"
            alert.addButton(withTitle: "Run"); alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn

        case "alert":
            let alert = NSAlert(); alert.messageText = values["message"] as? String ?? "Draftly"; alert.runModal(); return true
        case "prompt": return try prompt(values)
        case "selectPrompt": return selectPrompt(values)
        default: throw DraftlyError.message("The native operation is unavailable.")
        }
    }

    func prompt(_ values: [String: Any]) throws -> Any? {
        let content = try preparePrompt(values)
        defer { withExtendedLifetime(content.retained) {} }
        while true {
            let index = content.alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            guard (0..<content.buttonCount).contains(index) else { return nil }
            if let fields = content.read() { return ["index": index, "fields": fields] }
            let error = NSAlert(); error.messageText = "Enter a valid number."; error.runModal()
        }
    }

    struct PromptContent {
        let alert: NSAlert
        let buttonCount: Int
        let read: () -> [String: Any]?
        let retained: [AnyObject]
    }

    func preparePrompt(_ values: [String: Any]) throws -> PromptContent {
        let alert = NSAlert(); alert.messageText = values["title"] as? String ?? "Action"; alert.informativeText = values["message"] as? String ?? ""
        if let symbol = values["symbolName"] as? String { alert.icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        let help = PromptHelp(url: values["helpURL"] as? String); alert.delegate = help; alert.showsHelp = help.url != nil
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        var readers: [(String, () -> Any?)] = []
        var datePolicies: [PromptDatePolicy] = []
        var focus: NSView?
        for field in values["fields"] as? [[String: Any]] ?? [] {
            let key = field["key"] as? String ?? "", label = field["label"] as? String ?? key, kind = field["kind"] as? String ?? "text"
            if kind == "divider" { let box = NSBox(); box.boxType = .separator; stack.addArrangedSubview(box); continue }
            if kind != "switch" { let title = NSTextField(wrappingLabelWithString: label); if field["textSize"] as? String == "headline" { title.font = .boldSystemFont(ofSize: 14) }; if field["textSize"] as? String == "caption" { title.font = .systemFont(ofSize: 11) }; stack.addArrangedSubview(title) }
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
            case "segment":
                let options = field["options"] as? [String] ?? []
                let control = NSSegmentedControl(labels: options, trackingMode: .selectOne, target: nil, action: nil)
                control.selectedSegment = options.firstIndex(of: field["value"] as? String ?? "") ?? (options.isEmpty ? -1 : 0)
                stack.addArrangedSubview(control)
                readers.append((key, { options.indices.contains(control.selectedSegment) ? options[control.selectedSegment] : "" }))
            case "select":
                let control = NSPopUpButton(); let options = field["options"] as? [String] ?? []; control.addItems(withTitles: options)
                control.selectItem(withTitle: (field["value"] as? [String])?.first ?? field["value"] as? String ?? "")
                stack.addArrangedSubview(control); readers.append((key, { control.titleOfSelectedItem.map { [$0] } ?? [] }))
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
                guard ["date", "time", "dateAndTime"].contains(mode), let initial = APIValues.parseDate(field["value"]) else { throw DraftlyError.message("The date picker needs a valid initial date and mode.") }
                for key in ["minimumDate", "maximumDate"] where field[key] != nil {
                    guard APIValues.parseDate(field[key]) != nil else { throw DraftlyError.message("The date picker bound is invalid.") }
                }
                if field["minuteInterval"] != nil && field["minuteInterval"] as? Int == nil { throw DraftlyError.message("The minute interval must be an integer.") }
                picker.datePickerElements = mode == "date" ? [.yearMonthDay] : mode == "time" ? [.hourMinute] : [.yearMonthDay, .hourMinute]
                let minimum = APIValues.parseDate(field["minimumDate"]), maximum = APIValues.parseDate(field["maximumDate"])
                if let minimum, let maximum, minimum > maximum { throw DraftlyError.message("The minimum date is after the maximum date.") }
                picker.minDate = minimum; picker.maxDate = maximum
                let policy = try PromptDatePolicy(interval: field["minuteInterval"] as? Int ?? 1)
                picker.dateValue = policy.normalize(initial)
                picker.target = policy; picker.action = #selector(PromptDatePolicy.changed(_:)); datePolicies.append(policy)
                stack.addArrangedSubview(picker); readers.append((key, { APIValues.date(min(max(policy.normalize(picker.dateValue), picker.minDate ?? .distantPast), picker.maxDate ?? .distantFuture)) }))
            case "textView":
                if field["height"] != nil && field["height"] as? NSNumber == nil { throw DraftlyError.message("The text view height must be a number.") }
                let height = CGFloat((field["height"] as? NSNumber)?.doubleValue ?? 120)
                guard height.isFinite, height > 0 else { throw DraftlyError.message("The text view height must be positive and finite.") }
                let text = NSTextView(); text.isRichText = false; text.isAutomaticSpellingCorrectionEnabled = field["autocorrect"] as? Bool ?? true; text.string = field["value"] as? String ?? ""; text.font = .systemFont(ofSize: 13)
                let scroll = NSScrollView(); scroll.documentView = text; scroll.hasVerticalScroller = true
                scroll.widthAnchor.constraint(equalToConstant: 360).isActive = true; scroll.heightAnchor.constraint(equalToConstant: field["height"] as? CGFloat ?? 120).isActive = true
                stack.addArrangedSubview(scroll); readers.append((key, { text.string })); if field["wantsFocus"] as? Bool == true { focus = text }
            default:
                let value = field["value"] as? String ?? (field["value"] as? NSNumber)?.stringValue ?? ""
                let control: NSTextField = kind == "password" ? NSSecureTextField(string: value) : PromptTextField(string: value)
                (control as? PromptTextField)?.autocorrect = field["autocorrect"] as? Bool ?? true
                control.isAutomaticTextCompletionEnabled = field["autocorrect"] as? Bool ?? true
                control.placeholderString = field["placeholder"] as? String; control.widthAnchor.constraint(equalToConstant: 360).isActive = true
                stack.addArrangedSubview(control)
                readers.append((key, {
                    if kind == "number" {
                        guard let value = Double(control.stringValue), value.isFinite else { return nil }
                        if field["allowDecimals"] as? Bool == false, value.rounded() != value { return nil }
                        return value
                    }
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
            control.keyEquivalent = ""
            control.hasDestructiveAction = button["isDestructive"] as? Bool ?? false
            let colors: [String: NSColor] = ["red": .systemRed, "orange": .systemOrange, "yellow": .systemYellow, "green": .systemGreen, "blue": .systemBlue, "indigo": .systemIndigo, "purple": .systemPurple, "pink": .systemPink, "brown": .systemBrown, "gray": .systemGray]
            if let name = button["tintColor"] as? String { control.contentTintColor = colors[name] }
        }
        if buttons.isEmpty { alert.addButton(withTitle: "Continue") }
        let defaultIndex = buttons.firstIndex { $0["isDefault"] as? Bool == true } ?? 0
        alert.buttons[defaultIndex].keyEquivalent = "\r"
        alert.buttons[defaultIndex].keyEquivalentModifierMask = []
        if values["isCancellable"] as? Bool != false { let cancel = alert.addButton(withTitle: "Cancel"); cancel.keyEquivalent = "\u{1b}" }
        alert.window.initialFirstResponder = focus
        return PromptContent(alert: alert, buttonCount: max(1, buttons.count), read: {
            var result: [String: Any] = [:]
            for (key, read) in readers {
                guard let value = read() else { return nil }
                result[key] = value
            }
            return result
        }, retained: [help] + datePolicies)
    }

    func selectPrompt(_ values: [String: Any]) -> Any? {
        guard let content = prepareSelection(values) else { return nil }
        guard content.alert.runModal() == .alertFirstButtonReturn, let index = content.choices.selectedIndex else { return nil }
        return ["index": index]
    }

    func prepareSelection(_ values: [String: Any]) -> (alert: NSAlert, choices: SearchablePromptChoices)? {
        let items = values["items"] as? [[String: Any]] ?? []
        guard !items.isEmpty else { return nil }
        let alert = NSAlert(); alert.messageText = values["title"] as? String ?? "Select a draft"
        if alert.messageText.isEmpty { alert.messageText = "Select a draft" }
        alert.informativeText = values["message"] as? String ?? ""
        let choices = SearchablePromptChoices(items: items)
        alert.accessoryView = choices.view; alert.window.initialFirstResponder = choices.search
        alert.addButton(withTitle: "Select"); alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return (alert, choices)
    }

}

@MainActor private final class PromptHelp: NSObject, NSAlertDelegate {
    let url: URL?
    init(url: String?) { self.url = url.flatMap(URL.init(string:)) }
    func alertShowHelp(_ alert: NSAlert) -> Bool { guard let url else { return false }; return NSWorkspace.shared.open(url) }
}


@MainActor final class SearchablePromptChoices: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    let view = NSStackView(), search = NSSearchField(), table = NSTableView()
    private let items: [[String: Any]]
    private(set) var visibleIndices: [Int] = []
    var selectedIndex: Int? { visibleIndices.indices.contains(table.selectedRow) ? visibleIndices[table.selectedRow] : nil }
    init(items: [[String: Any]]) {
        self.items = items; super.init()
        view.orientation = .vertical; view.alignment = .leading
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 340)
        search.placeholderString = "Search"; search.delegate = self
        search.widthAnchor.constraint(equalToConstant: 400).isActive = true
        view.addArrangedSubview(search)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")))
        table.headerView = nil; table.rowHeight = 48; table.dataSource = self; table.delegate = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.widthAnchor.constraint(equalToConstant: 400).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
        view.addArrangedSubview(scroll); filter("")
    }
    func filter(_ query: String) {
        let previous = selectedIndex
        visibleIndices = items.indices.filter { index in
            query.isEmpty || ["title", "subtitle"].contains { (items[index][$0] as? String ?? "").localizedStandardContains(query) }
        }
        table.reloadData()
        if let selected = previous.flatMap({ visibleIndices.firstIndex(of: $0) }) { table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false) }
        else if !visibleIndices.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
    }
    func controlTextDidChange(_ notification: Notification) { filter(search.stringValue) }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIndices.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[visibleIndices[row]], cell = NSTableCellView()
        let title = NSTextField(labelWithString: item["title"] as? String ?? "Untitled")
        let subtitle = NSTextField(labelWithString: item["subtitle"] as? String ?? "")
        title.font = .systemFont(ofSize: 13, weight: .medium); subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail; subtitle.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [title, subtitle]); labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 2
        var views: [NSView] = []
        if let name = item["symbolName"] as? String,
           let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let image = NSImageView(image: symbol)
            image.widthAnchor.constraint(equalToConstant: 24).isActive = true
            cell.imageView = image
            views.append(image)
        }
        views.append(labels)
        let stack = NSStackView(views: views); stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack); cell.textField = title
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6), stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
}


@MainActor final class PromptTextField: NSTextField {
    var autocorrect = true
    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        if let editor = currentEditor() as? NSTextView {
            editor.isAutomaticSpellingCorrectionEnabled = autocorrect
            editor.isAutomaticTextReplacementEnabled = autocorrect
        }
    }
}

@MainActor final class PromptDatePolicy: NSObject {
    let interval: Int
    init(interval: Int) throws {
        guard interval > 0, interval <= 30, 60 % interval == 0 else { throw DraftlyError.message("The minute interval must divide 60 and be between 1 and 30.") }
        self.interval = interval; super.init()
    }
    func normalize(_ value: Date, calendar: Calendar = .current) -> Date {
        guard interval > 1 else { return value }
        let minute = calendar.component(.minute, from: value)
        return calendar.date(bySettingHour: calendar.component(.hour, from: value), minute: minute - minute % interval, second: 0, of: value) ?? value
    }
    @objc func changed(_ sender: NSDatePicker) { sender.dateValue = normalize(sender.dateValue) }
}
