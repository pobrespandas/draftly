import AppKit
import DraftlyCore

@MainActor
extension WindowModel {
    @discardableResult func changeLibraryTag(_ old: String, to replacement: String?) -> Bool {
        let windows = dependencies.windowModels().filter { $0.library === library }
        guard flush(), windows.allSatisfy({ $0 === self || $0.flush() }) else { return false }
        do {
            _ = try library.changeTag(old, to: replacement)
            for model in windows + [self] { model.updateTagFilters(old, replacement: replacement) }
            return true
        } catch { library.error = error.localizedDescription; return false }
    }
    func updateTagFilters(_ oldValue: String, replacement: String?) {
        let old = TagRules.normalize(oldValue), replacement = replacement.map(TagRules.normalize)
        if selectedTags.remove(old) != nil, let replacement { selectedTags.insert(replacement) }
        if excludedTags.remove(old) != nil, let replacement { excludedTags.insert(replacement) }
        tagsText = currentNote?.tags.joined(separator: ", ") ?? ""
    }
    func promptRenameTag(_ tag: String) {
        let alert = NSAlert(); alert.messageText = "Rename Tag"
        alert.informativeText = "Rename this tag in all drafts and saved workspaces."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24)); field.stringValue = tag
        alert.accessoryView = field; alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = changeLibraryTag(tag, to: field.stringValue)
    }
    func promptDeleteTag(_ tag: String) {
        let count = library.notes.filter { $0.tags.contains(tag) }.count
        let alert = NSAlert(); alert.messageText = "Delete Tag “\(tag)”?"
        alert.informativeText = "Remove this tag from \(count) drafts and saved workspace filters. The drafts will be kept."
        alert.addButton(withTitle: "Delete Tag"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = changeLibraryTag(tag, to: nil)
    }
}
