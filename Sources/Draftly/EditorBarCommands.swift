import AppKit
import DraftlyCore

@MainActor enum EditorBarCommand: String, CaseIterable {
    case undo, redo, moveLeft, moveRight, wordLeft, wordRight, find, advancedFind
    case makeTasks, toggleTasks, insertDate, insertDictation, dictateNewDraft
    case copySelection, pastePlainText, indent, outdent, moveLineUp, moveLineDown
    case duplicateLine, previousMarker, nextMarker, toggleTheme, preview

    var title: String {
        switch self {
        case .undo: "Undo"
        case .redo: "Redo"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .wordLeft: "Move Back by Word"
        case .wordRight: "Move Forward by Word"
        case .find: "Find"
        case .advancedFind: "Advanced Find"
        case .makeTasks: "Make Tasks"
        case .toggleTasks: "Toggle Tasks"
        case .insertDate: "Insert Date"
        case .insertDictation: "Insert Dictation"
        case .dictateNewDraft: "Dictate New Draft"
        case .copySelection: "Copy Selection"
        case .pastePlainText: "Paste as Plain Text"
        case .indent: "Indent"
        case .outdent: "Outdent"
        case .moveLineUp: "Move Line Up"
        case .moveLineDown: "Move Line Down"
        case .duplicateLine: "Duplicate Line"
        case .previousMarker: "Previous Marker"
        case .nextMarker: "Next Marker"
        case .toggleTheme: "Toggle Theme"
        case .preview: "Preview"
        }
    }
    var symbol: String {
        switch self {
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .moveLeft: "chevron.left"
        case .moveRight: "chevron.right"
        case .wordLeft: "chevron.left.2"
        case .wordRight: "chevron.right.2"
        case .find: "magnifyingglass"
        case .advancedFind: "plus.magnifyingglass"
        case .makeTasks: "checkmark.square"
        case .toggleTasks: "checklist"
        case .insertDate: "calendar.badge.plus"
        case .insertDictation: "mic.badge.plus"
        case .dictateNewDraft: "mic"
        case .copySelection: "doc.on.doc"
        case .pastePlainText: "doc.on.clipboard"
        case .indent: "increase.indent"
        case .outdent: "decrease.indent"
        case .moveLineUp: "arrow.up.to.line"
        case .moveLineDown: "arrow.down.to.line"
        case .duplicateLine: "plus.square.on.square"
        case .previousMarker: "arrow.up.to.line.compact"
        case .nextMarker: "arrow.down.to.line.compact"
        case .toggleTheme: "circle.lefthalf.filled"
        case .preview: "eye"
        }
    }
    func perform(model: WindowModel, session: EditorSession, responder: NSResponder? = nil) {
        func native(_ name: String) {
            let selector = NSSelectorFromString(name)
            if let responder { _ = responder.tryToPerform(selector, with: nil) }
            else { NSApp.sendAction(selector, to: nil, from: nil) }
        }
        switch self {
        case .undo:
            if responder != nil { session.performUndo?(false) } else { native("undo:") }
        case .redo:
            if responder != nil { session.performUndo?(true) } else { native("redo:") }
        case .moveLeft: Self.move(-1, session: session)
        case .moveRight: Self.move(1, session: session)
        case .wordLeft: native("moveWordLeft:")
        case .wordRight: native("moveWordRight:")
        case .find: model.perform { _ = try model.actionUIOperation(["operation": "showFind", "args": []]) }
        case .advancedFind: model.perform { _ = try model.actionUIOperation(["operation": "showFind", "args": [true]]) }
        case .makeTasks: model.edit(EditingScripts.makeTasks)
        case .toggleTasks: model.edit(EditingScripts.toggleTasks)
        case .insertDate: model.edit(EditingScripts.insertDate)
        case .insertDictation: model.perform { _ = try model.actionUIOperation(["operation": "showDictate"]) }
        case .dictateNewDraft: if model.create() { model.perform { _ = try model.actionUIOperation(["operation": "showDictate"]) } }
        case .copySelection: model.perform { _ = try model.host.perform("clipboard", values: ["text": session.selectedText.isEmpty ? session.content : session.selectedText]) }
        case .pastePlainText: native("pasteAsPlainText:")
        case .indent: model.edit(EditingScripts.indent)
        case .outdent: model.edit(EditingScripts.outdent)
        case .moveLineUp: Self.moveLine(-1, model: model, session: session)
        case .moveLineDown: Self.moveLine(1, model: model, session: session)
        case .duplicateLine: Self.duplicateLine(model: model, session: session)
        case .previousMarker: Self.moveToMarker(-1, model: model, session: session)
        case .nextMarker: Self.moveToMarker(1, model: model, session: session)
        case .toggleTheme:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            model.darkTheme = !(model.darkTheme ?? isDark)
        case .preview: model.preview()
        }
    }
    static func move(_ offset: Int, session: EditorSession) {
        if let selection = EditorBarTextCommands.move(in: session.content, selection: session.safeSelection, offset: offset) {
            session.selection = selection
        }
        session.focusToken = UUID()
    }
    static func moveLine(_ direction: Int, model: WindowModel, session: EditorSession) {
        guard let change = EditorBarTextCommands.moveLine(in: session.content, selection: session.safeSelection, direction: direction) else { return }
        apply(change, model: model, session: session)
    }
    static func duplicateLine(model: WindowModel, session: EditorSession) {
        guard let change = EditorBarTextCommands.duplicateLine(in: session.content, selection: session.safeSelection) else { return }
        apply(change, model: model, session: session)
    }
    private static func apply(_ change: EditorBarTextChange, model: WindowModel, session: EditorSession) {
        session.content = change.content; session.selection = change.selection
        session.focusToken = UUID(); model.contentChanged()
    }
    static func moveToMarker(_ direction: Int, model: WindowModel, session: EditorSession) {
        model.perform {
            let definition = try model.library.syntaxDefinition(named: model.currentNote?.syntax ?? "Markdown")
            let ranges = definition.markers(in: session.content).compactMap { marker -> NSRange? in
                guard let location = marker["location"] as? Int, let length = marker["length"] as? Int else { return nil }
                return NSRange(location: location, length: length)
            }
            guard let selection = EditorBarTextCommands.marker(in: ranges, selection: session.safeSelection, direction: direction) else { return }
            session.selection = selection
            session.synchronizeScriptEdit?()
            session.focusToken = UUID()
        }
    }
}
