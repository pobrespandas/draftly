import Foundation
import Combine

@MainActor
public final class EditorSession: ObservableObject {
    @Published public var noteID: UUID?
    @Published public var content = ""
    @Published public var selection = NSRange(location: 0, length: 0)
    @Published public var focusToken = UUID()
    @Published public var typewriterScrollingEnabled = false
    public var synchronizeScriptEdit: (() -> Void)?
    public var performUndo: ((Bool) -> Void)?
    public var focusForDictation: (() -> Bool)?
    public private(set) var recentNoteIDs: [UUID] = []
    private(set) var persistedDraft: (id: UUID, content: String)?
    public init() {}
    public func load(_ note: Note, focusEditor: Bool = true) { if let id = noteID, id != note.id { recentNoteIDs.removeAll { $0 == id }; recentNoteIDs.insert(id, at: 0) }; noteID = note.id; content = note.content; acknowledgeSaved(note); selection = NSRange(location: Int(note.scriptMetadata?["selectionStart"] ?? "0") ?? 0, length: Int(note.scriptMetadata?["selectionLength"] ?? "0") ?? 0); selection = safeSelection; if focusEditor { focusToken = UUID() } }
    public func acknowledgeSaved(_ note: Note) {
        guard noteID == note.id else { return }
        persistedDraft = (note.id, note.content)
    }
    public var safeSelection: NSRange {
        let count = (content as NSString).length
        let start = min(max(0, selection.location), count)
        return NSRange(location: start, length: min(max(0, selection.length), count - start))
    }
    public var selectedText: String { (content as NSString).substring(with: safeSelection) }
    public func replace(_ range: NSRange, with text: String) throws {
        guard range.location >= 0, range.length >= 0, range.location <= (content as NSString).length,
              range.length <= (content as NSString).length - range.location else { throw DraftlyError.message("The text range is outside the draft.") }
        content = (content as NSString).replacingCharacters(in: range, with: text)
        selection = NSRange(location: range.location + (text as NSString).length, length: 0)
    }
}
