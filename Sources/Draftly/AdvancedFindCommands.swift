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

    func replaceAll(query: Result<EditorFindQuery, Error>, with replacement: String) {
        guard let query = try? query.get() else { return }
        editor.content = query.replacingAll(in: editor.content, with: replacement)
        editor.selection = editor.safeSelection
        editor.synchronizeScriptEdit?()
        model.contentChanged()
        _ = model.flush()
    }
}
