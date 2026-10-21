import Foundation

@MainActor extension ActionRunner {
    func perform(_ command: ScriptCommand) throws -> Any? {
        switch command {
        case .newDraft: return ActionScriptValues.noteValue(Note(), syntaxes: library.syntaxes)
        case .findDraft(let id):
            guard let id else { return nil }
            return library.notes.first(where: { $0.id == id }).map(noteValue)
        case .queryDrafts(let query):
            var notes = query.workspace.filter(library.notes).filter { !query.omitFlagged || $0.flag == 0 }
            if query.flaggedToTop { notes = notes.filter { $0.flag > 0 } + notes.filter { $0.flag == 0 } }
            return notes.map(noteValue)
        case .updateDraft(let input):
            let note = try input.resolve(in: library)
            try validateScriptNote(note.id)
            try library.saveNote(note, preserveDates: input.preserveDates)
            recordScriptSave(note)
            if editor.noteID == note.id {
                editor.content = note.content
                editor.acknowledgeSaved(note)
                editor.selection = editor.safeSelection
                editor.synchronizeScriptEdit?()
            }
            return library.notes.first(where: { $0.id == note.id }).map(noteValue)
        case .loadDraft(let input):
            try flushEditor()
            let requested = try input.resolve(in: library)
            guard let note = library.notes.first(where: { $0.id == requested.id }) else {
                throw DraftlyError.message("Save the draft before loading it into the editor.")
            }
            try library.recordAccess(note.id)
            editor.load(note)
            editor.synchronizeScriptEdit?()
            return true
        case .editorText: return editor.content
        case .setEditorText(let text):
            editor.content = text
            editor.selection = editor.safeSelection
            try commitScriptEdit()
            return true
        case .selection: return editor.selectedText
        case .selectionRange: return [editor.safeSelection.location, editor.safeSelection.length]
        case .lineRange(let input, let text):
            let text = text ?? editor.content
            let expanded = (text as NSString).lineRange(for: try input.validated(in: text))
            return [expanded.location, expanded.length]
        case .setSelection(let input):
            editor.selection = input.value
            editor.selection = editor.safeSelection
            editor.synchronizeScriptEdit?()
            return true
        case .replaceSelection(let text):
            try editor.replace(editor.safeSelection, with: text)
            try commitScriptEdit()
            return true
        case .textInRange(let input):
            return (editor.content as NSString).substring(with: try input.validated(in: editor.content))
        case .replaceRange(let input, let text):
            try editor.replace(input.validated(in: editor.content), with: text)
            try commitScriptEdit()
            return true
        case .template(let text, let input, let tags):
            return try renderTemplate(text, note: input.resolve(in: library), tags: tags)
        case .setTemplateTag(let key, let value): customTags[key] = value; return true
        case .activate:
            editor.focusToken = UUID()
            if let uiOperation { _ = try uiOperation(["operation": "activate"]) }
            return nil
        case .message(let message): appendScriptLog(message); return true
        case .displayMessage(let message, let severity):
            _ = try platform("displayMessage", ["message": message, "severity": severity])
            appendScriptLog(message)
            return nil
        case .findAction(let name):
            return library.actions.first(where: { $0.name == name }).map(actionValue)
        case .queueAction(let id, let input):
            guard let action = library.actions.first(where: { $0.id.uuidString == id }) else {
                throw DraftlyError.message("The queued action was not found.")
            }
            queued.append((action, try input.resolve(in: library)))
            return true
        case .findWorkspace(let name):
            return try library.workspaces.first(where: { $0.name == name }).map(workspaceValue)
        case .applyWorkspace(let input):
            guard let applyWorkspace else { throw DraftlyError.message("Workspace application requires an open window.") }
            try applyWorkspace(input.resolve())
            return true
        case .base64Encode(let text): return Data(text.utf8).base64EncodedString()
        case .base64Decode(let text): return Data(base64Encoded: text).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    private func commitScriptEdit() throws {
        try flushEditor()
        editor.synchronizeScriptEdit?()
    }
}
