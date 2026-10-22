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
            var value = try SyntaxDefinition(data: Data(contentsOf: url), type: asFile ? "file" : "custom")
            if let existing = model.library.syntaxes.first(where: { $0.name == value.name }) {
                let alert = NSAlert(); alert.messageText = "Replace syntax “\(value.name)”?"
                alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                value.id = existing.id
            }
            if asFile { try SyntaxFileAccess.install(value, from: url, in: model.library) }
            else { try model.library.saveSyntax(value) }
        }
    }
}
