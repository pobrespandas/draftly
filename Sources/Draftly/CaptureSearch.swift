import AppKit
import SwiftUI
import DraftlyCore

@MainActor
final class CaptureBuffer: ObservableObject {
    @Published var text: String { didSet { defaults.set(text, forKey: key) } }
    @Published var error: String?
    private let defaults: UserDefaults
    private let key: String
    init(defaults: UserDefaults = .standard, key: String = "capture.pendingText") {
        self.defaults = defaults; self.key = key
        text = defaults.string(forKey: key) ?? ""
    }
    func receive(_ incoming: String) {
        guard !incoming.isEmpty else { return }
        text += text.isEmpty ? incoming : "\n\n" + incoming
    }
    @discardableResult func save(using write: (String) throws -> Void) -> Bool {
        guard !text.isEmpty else { return false }
        do { try write(text); text = ""; error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func discard() { text = ""; error = nil }
}

@MainActor
final class CaptureController {
    let buffer: CaptureBuffer
    private let libraryProvider: () -> LibraryStore?
    private let windowProvider: () -> [WindowModel]
    private var panel: NSPanel?
    init(buffer: CaptureBuffer = CaptureBuffer(),
         libraryProvider: @escaping () -> LibraryStore? = { AppController.shared.library },
         windowProvider: @escaping () -> [WindowModel] = { AppController.shared.windows.allObjects }) {
        self.buffer = buffer
        self.libraryProvider = libraryProvider
        self.windowProvider = windowProvider
    }
    func captureDirectly(_ text: String) throws {
        do {
            guard !text.isEmpty else { throw DraftlyError.message("No text was provided.") }
            guard let library = libraryProvider() else { throw DraftlyError.message("The library is unavailable.") }
            _ = try library.createNote(content: text)
        } catch {
            buffer.receive(text)
            buffer.error = error.localizedDescription
            throw error
        }
    }
    func show(content: String = "") {
        buffer.receive(content)
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 360), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "Capture"; panel.identifier = NSUserInterfaceItemIdentifier("draftly.capture")
            panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false; panel.minSize = NSSize(width: 420, height: 280)
            panel.contentView = NSHostingView(rootView: CaptureView(buffer: buffer, save: { [weak self] target in self?.save(to: target) ?? false }))
            panel.center(); self.panel = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        focusPanelInput(panel)
    }
    @discardableResult func save(to target: UUID?) -> Bool {
        guard let library = libraryProvider() else { buffer.error = "The library is unavailable."; return false }
        let saved = buffer.save { text in
            if let target {
                let windows = windowProvider().filter { $0.library === library && $0.editor.noteID == target }
                let selections = windows.map { ($0, $0.editor.selection) }
                for model in windows {
                    guard model.flush() else { throw DraftlyError.message("Save the destination draft before adding text.") }
                }
                guard var note = library.notes.first(where: { $0.id == target && $0.trashedAt == nil }) else {
                    throw DraftlyError.message("The destination draft is no longer available.")
                }
                note.content += note.content.isEmpty ? text : "\n\n" + text
                try library.saveNote(note)
                for (model, selection) in selections where model.editor.noteID == target {
                    model.editor.content = note.content
                    model.editor.selection = selection
                    model.editor.synchronizeScriptEdit?()
                }
            } else { _ = try library.createNote(content: text) }
        }
        if saved { panel?.orderOut(nil) }
        return saved
    }
}

private struct CaptureView: View {
    @ObservedObject var buffer: CaptureBuffer
    @ObservedObject private var app = AppController.shared
    @State private var target: UUID?
    let save: (UUID?) -> Bool
    var body: some View {
        VStack(spacing: 0) {
            CaptureTextEditor(text: $buffer.text).padding(12).accessibilityLabel("Capture Text")
            Divider()
            HStack {
                Picker("Save to", selection: $target) {
                    Text("New Draft").tag(UUID?.none)
                    ForEach((app.library?.notes ?? []).filter { $0.trashedAt == nil }.sorted { $0.modifiedAt > $1.modifiedAt }) { note in
                        Text(note.title).tag(Optional(note.id))
                    }
                }.frame(maxWidth: 300)
                Spacer()
                Button("Discard") {
                    let alert = NSAlert(); alert.messageText = "Discard captured text?"
                    alert.addButton(withTitle: "Discard"); alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn { buffer.discard() }
                }.disabled(buffer.text.isEmpty)
                Button(target == nil ? "Save Draft" : "Append") { _ = save(target) }
                    .keyboardShortcut(.return, modifiers: .command).disabled(buffer.text.isEmpty)
            }.padding(12)
            if let error = buffer.error { Text(error).font(.caption).foregroundStyle(.red).padding([.horizontal, .bottom], 12) }
        }
    }
}

@MainActor
enum QuickSearch {
    static func results(in notes: [Note], query: String) -> [Note] {
        notes.filter { note in
            note.trashedAt == nil && (query.isEmpty || note.content.localizedStandardContains(query) || note.tags.contains { $0.localizedStandardContains(query) })
        }.sorted { a, b in a.modifiedAt == b.modifiedAt ? a.id.uuidString < b.id.uuidString : a.modifiedAt > b.modifiedAt }
    }
}

@MainActor
final class QuickSearchController {
    private var panel: NSPanel?
    func show() {
        guard let library = AppController.shared.library else { return }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 440), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            panel.title = "Quick Search"; panel.identifier = NSUserInterfaceItemIdentifier("draftly.quickSearch")
            panel.isReleasedWhenClosed = false; panel.minSize = NSSize(width: 420, height: 280)
            self.panel = panel
        }
        panel?.contentView = NSHostingView(rootView: QuickSearchView(library: library, open: { [weak self] id in
            if AppController.shared.openSearchResult(id) { self?.panel?.orderOut(nil) }
        }, cancel: { [weak self] in self?.panel?.orderOut(nil) }))
        NSApp.activate(ignoringOtherApps: true)
        panel?.center(); panel?.makeKeyAndOrderFront(nil)
        focusPanelInput(panel)
    }
}

private struct QuickSearchView: View {
    @ObservedObject var library: LibraryStore
    @State private var query = ""
    @State private var selection: UUID?
    @FocusState private var focused: Bool
    let open: (UUID) -> Void
    let cancel: () -> Void
    private var results: [Note] { QuickSearch.results(in: library.notes, query: query) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                QuickSearchInput(query: $query, move: moveSelection, open: openSelection, cancel: cancel)
                    .frame(height: 26)
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            List(selection: $selection) {
                ForEach(results) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title).font(.headline).lineLimit(1)
                        Text(note.preview).foregroundStyle(.secondary).lineLimit(2)
                    }.padding(.vertical, 4).tag(note.id)
                        .onTapGesture(count: 2) { open(note.id) }
                }
            }
            HStack { Text("\(results.count) " + (results.count == 1 ? "draft" : "drafts")); Spacer(); Button("Open") { openSelection() }.disabled(selection == nil) }
                .font(.caption).padding(12)
        }
        .onAppear { focused = true; selection = results.first?.id }
        .onChange(of: query) { _, _ in selection = results.first?.id }
        .onChange(of: library.notes) { _, _ in if !results.contains(where: { $0.id == selection }) { selection = results.first?.id } }
        .onMoveCommand { direction in
            let index = results.firstIndex { $0.id == selection } ?? 0
            if direction == .down, index + 1 < results.count { selection = results[index + 1].id }
            if direction == .up, index > 0 { selection = results[index - 1].id }
        }
        .onExitCommand(perform: cancel)
    }
    private func moveSelection(_ offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selection } ?? 0
        selection = results[min(max(0, current + offset), results.count - 1)].id
    }
    private func openSelection() { if let selection, results.contains(where: { $0.id == selection }) { open(selection) } }
}

@MainActor
private func focusPanelInput(_ panel: NSPanel?) {
    DispatchQueue.main.async { [weak panel] in
        guard let panel, let root = panel.contentView else { return }
        func input(in view: NSView) -> NSView? {
            if let text = view as? NSTextView, text.isEditable { return text }
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { input(in: $0) }.first
        }
        if let input = input(in: root) { panel.makeFirstResponder(input) }
    }
}

struct QuickSearchInput: NSViewRepresentable {
    @Binding var query: String
    let move: (Int) -> Void
    let open: () -> Void
    let cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = false; field.drawsBackground = false; field.focusRingType = .none
        field.placeholderString = "Search All Drafts"; field.font = .systemFont(ofSize: 18)
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != query { field.stringValue = query }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickSearchInput
        init(_ parent: QuickSearchInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.query = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch NSStringFromSelector(commandSelector) {
            case "moveDown:": parent.move(1)
            case "moveUp:": parent.move(-1)
            case "insertNewline:": parent.open()
            case "cancelOperation:": parent.cancel()
            default: return false
            }
            return true
        }
    }
}

private struct CaptureTextEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let editor = CaptureTextView(frame: .zero)
        editor.isRichText = false; editor.allowsUndo = true; editor.drawsBackground = false
        editor.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.string = text; editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let editor = scroll.documentView as? NSTextView, editor.string != text {
            editor.string = text; editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureTextEditor
        init(_ parent: CaptureTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}

private final class CaptureTextView: NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }
}
