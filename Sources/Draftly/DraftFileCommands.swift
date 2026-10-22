import AppKit
import DraftlyCore

@MainActor
struct DraftFileCommands {
    unowned let model: WindowModel

    func importFile() {
        guard model.flush() else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [.json, .plainText, .data]
        guard panel.runModal() == .OK else { return }
        model.perform {
            let files = try panel.urls.map { url -> LibraryFileImport.File in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                return LibraryFileImport.File(data: data, fileExtension: url.pathExtension)
            }
            try LibraryFileImport.apply(files, to: model.library)
            model.status = "Import complete"
        }
    }
    func exportBackup() {
        guard model.flush() else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Draftly Backup.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform { try model.library.backupData().write(to: url, options: .atomic); model.status = "Backup saved" }
    }
    func exportNote() {
        guard model.flush(), let note = model.currentNote else { return }
        model.perform { _ = try model.host.perform("saveFile", values: ["text": note.content, "name": note.title + ".md"]) }
    }
    func importSyntax(asFile: Bool) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.message = asFile ? "Select a syntax file. File changes apply when the syntax is read." : "Import a Drafts syntax definition."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform {
            let active = url.startAccessingSecurityScopedResource(); defer { if active { url.stopAccessingSecurityScopedResource() } }
            let incoming = try SyntaxDefinition(data: Data(contentsOf: url), type: asFile ? "file" : "custom")
            guard let value = try SyntaxImportReview.resolve(incoming, library: model.library) else { return }
            if asFile { try SyntaxFileAccess.install(value, from: url, in: model.library) }
            else { try model.library.saveSyntax(value) }
        }
    }
}


enum SyntaxImportChoice {
    case replace
    case copy(String)
    case cancel
}

enum SyntaxImportPreparation {
    static func prepare(_ incoming: SyntaxDefinition, installed: [SyntaxDefinition], choice: SyntaxImportChoice) throws -> SyntaxDefinition? {
        switch choice {
        case .cancel: return nil
        case .replace:
            guard !ScriptSyntax.names.contains(incoming.name) else { throw DraftlyError.message("Built-in syntax cannot be replaced. Import a new copy with a different name.") }
            var result = incoming
            if let existing = installed.first(where: { $0.name == incoming.name }) { result.id = existing.id }
            return result
        case .copy(let proposed):
            let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !ScriptSyntax.names.contains(name), !installed.contains(where: { $0.name == name }) else {
                throw DraftlyError.message("Use a unique syntax name.")
            }
            guard incoming.type == "custom" else { throw DraftlyError.message("Rename the source file definition before adding another file syntax.") }
            var object = incoming.object
            object["name"] = name
            return try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), type: "custom")
        }
    }
}

@MainActor enum SyntaxImportReview {
    static func resolve(_ incoming: SyntaxDefinition, library: LibraryStore) throws -> SyntaxDefinition? {
        let before = library.syntaxes
        let builtIn = ScriptSyntax.names.contains(incoming.name)
        let collision = before.contains { $0.name == incoming.name }
        guard collision || builtIn else { return incoming }
        let alert = NSAlert()
        alert.messageText = "Import syntax “\(incoming.name)”?"
        if builtIn {
            alert.informativeText = incoming.type == "file"
                ? "The built-in syntax cannot be replaced. Change the name in the source file, then add it again."
                : "The built-in syntax will remain unchanged. Use a different name for the imported copy."
        }
        var choices: [SyntaxImportChoice] = []
        if !builtIn { alert.addButton(withTitle: "Replace"); choices.append(.replace) }
        if incoming.type == "custom" { alert.addButton(withTitle: "Import as New…"); choices.append(.copy("")) }
        alert.addButton(withTitle: "Cancel"); choices.append(.cancel)
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        let response = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard choices.indices.contains(response) else { return nil }
        var choice = choices[response]
        if case .copy = choice {
            let prompt = NSAlert(); prompt.messageText = "Name the imported syntax"
            let field = NSTextField(string: incoming.name + " Copy")
            field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            prompt.accessoryView = field; prompt.window.initialFirstResponder = field
            prompt.addButton(withTitle: "Import"); prompt.addButton(withTitle: "Cancel")
            prompt.buttons.last?.keyEquivalent = "\u{1b}"
            guard prompt.runModal() == .alertFirstButtonReturn else { return nil }
            choice = .copy(field.stringValue)
        }
        if case .cancel = choice { return nil }
        guard library.syntaxes == before else { throw DraftlyError.message("The installed syntaxes changed. Import again to review the current definitions.") }
        return try SyntaxImportPreparation.prepare(incoming, installed: before, choice: choice)
    }
}
