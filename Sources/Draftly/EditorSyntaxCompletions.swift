import AppKit
import SwiftUI
import DraftlyCore

@MainActor final class EditorSyntaxCompletions {
    private(set) var request: SyntaxCompletionRequest?
    private(set) var selectedIndex = 0
    private var source = ""
    private var selection = NSRange(location: 0, length: 0)
    private var noteID: UUID?
    private weak var textView: DraftTextView?
    private var panel: CompletionPanel?

    func begin(_ request: SyntaxCompletionRequest, source: String, selection: NSRange, noteID: UUID?) {
        self.request = request.items.isEmpty ? nil : request
        self.source = source; self.selection = selection; self.noteID = noteID
        selectedIndex = 0
    }
    func move(_ direction: Int) {
        guard let request, !request.items.isEmpty else { return }
        selectedIndex = max(0, min(request.items.count - 1, selectedIndex + direction))
        render()
    }
    func value(source: String, selection: NSRange, noteID: UUID?, index: Int? = nil) -> (NSRange, String)? {
        guard let request, self.source == source, self.selection == selection, self.noteID == noteID,
              request.items.indices.contains(index ?? selectedIndex),
              request.range.location >= 0, request.range.length >= 0,
              request.range.location <= source.utf16.count,
              request.range.length <= source.utf16.count - request.range.location,
              NSMaxRange(request.range) == selection.location else { return nil }
        return (request.range, request.items[index ?? selectedIndex].value)
    }
    func invalidate(source: String, selection: NSRange, noteID: UUID?) {
        if self.source != source || self.selection != selection || self.noteID != noteID { dismiss() }
    }
    func dismiss() {
        request = nil
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil; textView = nil
    }
    func present(for textView: DraftTextView) {
        guard request != nil, let window = textView.window, window.isVisible,
              window.firstResponder === textView else { return }
        self.textView = textView
        let panel = panel ?? CompletionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
        panel.hasShadow = true; panel.isOpaque = false; panel.backgroundColor = .clear
        render()
        let caret = textView.firstRect(forCharacterRange: selection, actualRange: nil)
        let screen = window.screen?.visibleFrame ?? window.frame
        let width = min(400.0, max(220.0, window.frame.width - 24))
        let height = CGFloat(min(request?.items.count ?? 0, 8)) * 34 + 12
        let x = min(max(screen.minX, caret.minX), screen.maxX - width)
        let y = caret.minY - height >= screen.minY ? caret.minY - height : min(caret.maxY, screen.maxY - height)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }
    func handle(_ event: NSEvent) -> Bool {
        guard request != nil, panel?.isVisible == true else { return false }
        switch event.charactersIgnoringModifiers {
        case "\u{F700}": move(-1)
        case "\u{F701}": move(1)
        case "\r", "\n", "\t": accept()
        case "\u{1B}": dismiss()
        default: return false
        }
        return true
    }
    private func accept(index: Int? = nil) {
        guard let textView else { dismiss(); return }
        accept(in: textView, index: index)
    }
    func accept(in textView: DraftTextView, index: Int? = nil) {
        let edit = value(source: textView.string, selection: textView.selectedRange(), noteID: textView.completionNoteID, index: index)
        textView.cancelSyntaxCompletions()
        dismiss()
        if let edit { textView.insertSyntaxCompletion(edit.1, range: edit.0) }
    }
    private func render() {
        guard let panel, let request else { return }
        panel.contentView = NSHostingView(rootView: CompletionList(items: request.items, selectedIndex: selectedIndex) { [weak self] index in
            self?.accept(index: index)
        })
    }
}

private final class CompletionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct CompletionList: View {
    let items: [SyntaxCompletion]
    let selectedIndex: Int
    let select: (Int) -> Void
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Button { select(index) } label: {
                            Text(item.label).font(.system(size: 13)).lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : .clear)
                        }.buttonStyle(.plain).id(index)
                    }
                }
            }.onAppear { proxy.scrollTo(selectedIndex, anchor: .center) }
                .onChange(of: selectedIndex) { _, value in proxy.scrollTo(value, anchor: .center) }
        }.padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
