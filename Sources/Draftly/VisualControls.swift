import SwiftUI
import AppKit
import DraftlyCore

struct FolderControl: View {
    @Environment(\.controlActiveState) private var activeState
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
                .foregroundStyle(folder == item && activeState != .inactive ? Color.white : Color.primary.opacity(0.85))
                .background { if folder == item { Capsule().fill(activeState == .inactive ? Color.primary.opacity(0.09) : Color.accentColor) } }
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
        .accessibilityElement(children: .contain).accessibilityLabel("Draft View")
    }
}

struct ReferenceSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: UUID
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        if #available(macOS 26.0, *) { field.controlSize = .extraLarge } else { field.controlSize = .large }
        field.font = .systemFont(ofSize: 14); field.focusRingType = .none
        field.sendsSearchStringImmediately = true; field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        return field
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 30)
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
    @Binding var editing: Bool
    var focusToken: UUID
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
        if coordinator.focusToken != focusToken {
            coordinator.focusToken = focusToken
            if editing { DispatchQueue.main.async { field.window?.makeFirstResponder(field) } }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: NativeTagsField
        var noteID: UUID?
        var focusToken: UUID?
        init(_ parent: NativeTagsField) { self.parent = parent }
        @objc func commit(_ field: NSTokenField) {
            guard noteID == parent.noteID else { return }
            let tags = TagRules.normalize(field.objectValue as? [String] ?? [])
            if tags != parent.tags { parent.tags = tags }
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.editing = true }
        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTokenField { commit(field) }
            parent.editing = false
        }
        func tokenField(_ tokenField: NSTokenField, styleForRepresentedObject representedObject: Any) -> NSTokenField.TokenStyle { .rounded }
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

struct TagCapsuleField: View {
    @Binding var tags: [String]
    var noteID: UUID?
    var suggestions: [String]
    @State private var editing = false
    @State private var focusToken = UUID()
    var body: some View {
        ZStack(alignment: .leading) {
            NativeTagsField(tags: $tags, noteID: noteID, suggestions: suggestions, editing: $editing, focusToken: focusToken)
                .opacity(editing || tags.isEmpty ? 1 : 0)
                .allowsHitTesting(editing || tags.isEmpty)
                .accessibilityHidden(!editing && !tags.isEmpty)
            if !editing && !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag).font(.system(size: 12)).foregroundStyle(.primary).lineLimit(1)
                                .padding(.horizontal, 6).frame(height: 16)
                                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5))
                        }
                        Spacer(minLength: 12)
                    }.frame(height: 25).contentShape(Rectangle())
                }.contentShape(Rectangle()).onTapGesture { editing = true; focusToken = UUID() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Tags: " + tags.joined(separator: ", "))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { editing = true; focusToken = UUID() }
            }
        }.onChange(of: noteID) { _, _ in editing = false }
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
                ForEach(1...7, id: \.self) { flag in Button(flagName(flag)) { if let note = model.currentNote { model.change([note.id]) { $0.flag = flag } } } }
            } label: { Image(systemName: "chevron.down").font(.system(size: 10)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Flag Color")
            TagCapsuleField(tags: Binding(get: { model.currentNote?.tags ?? [] }, set: { tags in
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
    var isSection = false
    static var separator: PanelMenuItem { PanelMenuItem(title: "", action: nil) }
    static func section(_ title: String) -> PanelMenuItem { PanelMenuItem(title: title, isSection: true) }
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
                if entry.isSection {
                    menu.addItem(.sectionHeader(title: entry.title))
                } else if !entry.children.isEmpty {
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

// Shared dimensions for the main window.
enum MainWindowStyle {
    static let actionTitleSize: CGFloat = 13
    static let statusSymbolSize: CGFloat = 11
    static let utilityHeight: CGFloat = 48
    static let utilityInset: CGFloat = 9
    static let utilityLeadingSpacing: CGFloat = 12
    static let utilityTrailingSpacing: CGFloat = 6
    static let listSearchOffset: CGFloat = -2
    static let listControlOffset: CGFloat = 2
    static let tagsHeadingOffset: CGFloat = -2
    static let sidebarInset: CGFloat = 18
    static let editingBarHeight: CGFloat = 31
    static let footerHeight: CGFloat = 29
}

struct EditorStatusOverlay: View {
    let message: String
    @State private var visible = false
    var body: some View {
        Group {
            if visible && !message.isEmpty {
                Text(message).font(.caption).lineLimit(3)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    .padding(12)
                    .accessibilityLabel(message)
            }
        }
        .allowsHitTesting(false)
        .task(id: message) {
            visible = !message.isEmpty
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}

@MainActor
enum DraftListDefaults {
    static func load() -> DraftListOptions {
        let defaults = UserDefaults.standard
        var options = defaults.data(forKey: "list.options").flatMap { try? JSONDecoder().decode(DraftListOptions.self, from: $0) } ?? DraftListOptions()
        if defaults.object(forKey: "list.showPreview") != nil { options.showPreview = defaults.bool(forKey: "list.showPreview") }
        if defaults.object(forKey: "list.previewLines") != nil { options.previewLines = defaults.integer(forKey: "list.previewLines") }
        if defaults.object(forKey: "list.showTags") != nil { options.showTags = defaults.bool(forKey: "list.showTags") }
        if defaults.object(forKey: "list.showDate") != nil { options.showDate = defaults.bool(forKey: "list.showDate") }
        return options
    }
}
