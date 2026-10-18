import SwiftUI
import AppKit
import DraftlyCore

struct FolderControl: View {
    @Binding var folder: NoteFolder
    private let folders: [NoteFolder] = [.inbox, .flagged, .archive, .all, .trash]
    private let symbols = ["tray.and.arrow.down", "flag", "archivebox", "asterisk", "trash"]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(folders.enumerated()), id: \.offset) { index, item in
                Button { folder = item } label: {
                    Image(systemName: symbols[index])
                        .font(.system(size: 15, weight: .regular))
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background { if folder == item { Capsule().fill(Color.primary.opacity(0.09)) } }
                .help(item.title).accessibilityLabel(item.title)
                .accessibilityAddTraits(folder == item ? .isSelected : [])
                .overlay(alignment: .trailing) {
                    if index < folders.count - 1 && folder != item && folder != folders[index + 1] {
                        Rectangle().fill(Color.primary.opacity(0.22)).frame(width: 1, height: 16)
                    }
                }
            }
        }
        .foregroundStyle(.primary.opacity(0.85))
        .background(Color.primary.opacity(0.065), in: Capsule())
        .accessibilityElement(children: .contain).accessibilityLabel("Folder")
    }
}

struct ReferenceSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: UUID
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.controlSize = .large; field.font = .systemFont(ofSize: 14); field.focusRingType = .none
        field.sendsSearchStringImmediately = true; field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        if context.coordinator.token != focusToken {
            context.coordinator.token = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }
    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ReferenceSearchField
        var token: UUID?
        init(_ parent: ReferenceSearchField) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
    }
}

struct PanelIcon: View {
    var symbol: String
    var body: some View { Image(systemName: symbol).resizable().scaledToFit().fontWeight(.light).frame(width: 20, height: 20).frame(width: 28, height: 28) }
}

struct NativeTagsField: NSViewRepresentable {
    @Binding var tags: [String]
    var noteID: UUID?
    var suggestions: [String] = []
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.placeholderString = "Add tag…"; field.font = .systemFont(ofSize: 12)
        field.tokenStyle = .rounded; field.tokenizingCharacterSet = CharacterSet(charactersIn: ",")
        field.delegate = context.coordinator; field.target = context.coordinator; field.action = #selector(Coordinator.commit(_:))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTokenField, context: Context) {
        let coordinator = context.coordinator; coordinator.parent = self
        let changedNote = coordinator.noteID != noteID
        if changedNote || (field.currentEditor() == nil && field.objectValue as? [String] != tags) { field.objectValue = tags }
        coordinator.noteID = noteID
    }
    @MainActor final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: NativeTagsField
        var noteID: UUID?
        init(_ parent: NativeTagsField) { self.parent = parent }
        @objc func commit(_ field: NSTokenField) {
            guard noteID == parent.noteID else { return }
            let tags = TagRules.normalize(field.objectValue as? [String] ?? [])
            if tags != parent.tags { parent.tags = tags }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTokenField { commit(field) }
        }
        func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
            let expectedNoteID = noteID
            DispatchQueue.main.async { [weak self, weak tokenField] in
                guard let self, self.noteID == expectedNoteID, self.parent.noteID == expectedNoteID, let tokenField else { return }
                self.commit(tokenField)
            }
            return tokens
        }
        func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String,
                        indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
            let prefix = TagRules.normalize(substring)
            let existing = Set(parent.tags.map(TagRules.normalize))
            let options = parent.suggestions.map(TagRules.normalize).filter { $0.hasPrefix(prefix) && !existing.contains($0) }
            if !options.isEmpty { selectedIndex?.pointee = 0 }
            return options
        }
    }
}

struct DraftTagStrip: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var session: EditorSession
    private var headings: [(String, NSRange)] {
        let text = session.content
        guard let regex = try? NSRegularExpression(pattern: "(?m)^#{1,6} .+$") else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).prefix(100).map {
            ((text as NSString).substring(with: $0.range), $0.range)
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let note = model.currentNote { model.change([note.id]) { $0.flag = $0.flag == 0 ? 1 : 0 } }
            } label: {
                Image(systemName: (model.currentNote?.flag ?? 0) > 0 ? "flag.fill" : "flag")
                    .foregroundStyle((model.currentNote?.flag ?? 0) > 0 ? flagColor(model.currentNote?.flag ?? 1) : .secondary)
            }.help("Flag")
            Menu {
                Button("No Flag") { if let note = model.currentNote { model.change([note.id]) { $0.flag = 0 } } }
                ForEach(1...6, id: \.self) { flag in Button(flagName(flag)) { if let note = model.currentNote { model.change([note.id]) { $0.flag = flag } } } }
            } label: { Image(systemName: "chevron.down").font(.system(size: 10)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Flag Color")
            NativeTagsField(tags: Binding(get: { model.currentNote?.tags ?? [] }, set: { tags in
                guard let noteID = session.noteID else { return }
                model.change([noteID]) { $0.tags = TagRules.normalize(tags) }
            }), noteID: session.noteID, suggestions: model.allTags).frame(height: 25)
            Menu {
                if headings.isEmpty { Text("No navigation markers") }
                ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                    Button(heading.0) { session.selection = heading.1; session.focusToken = UUID() }
                }
            } label: { Image(systemName: "arrowtriangle.down.fill").font(.system(size: 11)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Navigate")
        }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 45)
    }
}

struct DraftInfoView: View {
    var note: Note
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Draft Info").font(.title2); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            LabeledContent("Created", value: note.createdAt.formatted())
            LabeledContent("Modified", value: note.modifiedAt.formatted())
            LabeledContent("UUID", value: note.id.uuidString).textSelection(.enabled)
            LabeledContent("Tags", value: note.tags.joined(separator: ", "))
            LabeledContent("Characters", value: String(note.content.count))
        }.padding(24).frame(width: 530)
    }
}

struct PanelMenuItem {
    var title: String
    var isOn = false
    var children: [PanelMenuItem] = []
    var action: (() -> Void)?
    static var separator: PanelMenuItem { PanelMenuItem(title: "", action: nil) }
}

struct PanelMenu: NSViewRepresentable {
    var symbol: String
    var help: String
    var items: [PanelMenuItem]
    var title: String? = nil
    var showsChevron = true
    var symbolSize: CGFloat = 20
    var textSize: CGFloat = 11
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(), target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false; button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        let image = symbol.isEmpty ? nil : NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .light))
        image?.size = NSSize(width: symbolSize, height: symbolSize)
        button.image = image; button.toolTip = help; button.setAccessibilityLabel(help)
        if let title {
            button.imagePosition = showsChevron ? .imageRight : .noImage
            button.image = showsChevron ? NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)) : nil
            button.image?.size = NSSize(width: 9, height: 9)
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: textSize), .foregroundColor: NSColor.secondaryLabelColor
            ])
        }
    }
    @MainActor final class Coordinator: NSObject {
        var parent: PanelMenu
        init(_ parent: PanelMenu) { self.parent = parent }
        private var callbacks: [() -> Void] = []
        @objc func open(_ sender: NSButton) {
            callbacks = []
            let menu = makeMenu(parent.items)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
        }
        private func makeMenu(_ entries: [PanelMenuItem]) -> NSMenu {
            let menu = NSMenu(); menu.autoenablesItems = false
            for entry in entries {
                if !entry.children.isEmpty {
                    let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                    item.submenu = makeMenu(entry.children); menu.addItem(item)
                } else if let action = entry.action {
                    let item = NSMenuItem(title: entry.title, action: #selector(select(_:)), keyEquivalent: "")
                    item.target = self; item.tag = callbacks.count; item.state = entry.isOn ? .on : .off
                    callbacks.append(action); menu.addItem(item)
                } else { menu.addItem(.separator()) }
            }
            return menu
        }
        @objc func select(_ sender: NSMenuItem) {
            guard callbacks.indices.contains(sender.tag) else { return }
            callbacks[sender.tag]()
        }
    }
}
