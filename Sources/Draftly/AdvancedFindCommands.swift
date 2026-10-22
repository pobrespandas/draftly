import Foundation
import DraftlyCore

@MainActor
struct AdvancedFindCommands {
    let model: WindowModel
    private var editor: EditorSession { model.editor }

    func select(_ range: NSRange) {
        editor.selection = range
        editor.synchronizeScriptEdit?()
    }

    func navigate(in ranges: [NSRange], backward: Bool) {
        guard !ranges.isEmpty else { return }
        let selection = editor.safeSelection
        if backward { select(ranges.last { $0.location < selection.location } ?? ranges[ranges.count - 1]) }
        else { select(ranges.first { $0.location >= NSMaxRange(selection) && $0 != selection } ?? ranges[0]) }
    }

    func replace(query: Result<EditorFindQuery, Error>, range: NSRange, with replacement: String) {
        guard let query = try? query.get(),
              let value = query.replacement(in: editor.content, at: range, with: replacement) else { return }
        editor.content = (editor.content as NSString).replacingCharacters(in: range, with: value)
        editor.selection = NSRange(location: range.location, length: value.utf16.count)
        editor.synchronizeScriptEdit?()
        model.contentChanged()
        _ = model.flush()
    }

    func replaceAll(query: Result<EditorFindQuery, Error>, with replacement: String) {
        guard let query = try? query.get() else { return }
        editor.content = query.replacingAll(in: editor.content, with: replacement)
        editor.selection = editor.safeSelection
        editor.synchronizeScriptEdit?()
        model.contentChanged()
        _ = model.flush()
    }
}
