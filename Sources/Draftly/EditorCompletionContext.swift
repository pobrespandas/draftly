import Foundation
import DraftlyCore

struct EditorCompletionContext {
    var currentDraft: Note?
    var drafts: [Note]

    func completion(in source: String, selection: NSRange, definition: SyntaxDefinition,
                    noteID: UUID?) -> SyntaxCompletionRequest? {
        var current = currentDraft ?? Note(content: source)
        current.content = source
        if let noteID { current.id = noteID }
        return definition.completion(in: source, selection: selection, drafts: drafts, current: current)
    }
}
