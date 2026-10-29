import AppKit
import DraftlyCore

@MainActor
struct ApplicationURLRouter {
    unowned let controller: AppController
    private var library: LibraryStore? { controller.library }
    private func show(_ id: UUID? = nil) { controller.show(id) }
    private func newDraft(content: String) { controller.newDraft(content: content) }
    private func capture(content: String) { controller.capture(content: content) }
    private func report(_ error: Error) {
        if let library { library.error = error.localizedDescription }
        else { NSApp.presentError(error) }
    }

    func handle(_ url: URL) {
        if ActionCallbackRouter.receive(url) { return }
        guard let url = Self.applicationURL(url, registeredScheme: ActionCallbackRouter.callbackScheme) else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func parameter(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let endpoint = url.host == "x-callback-url" ? String(url.path.dropFirst()) : url.host
        switch endpoint {
        case "workspace":
            do {
                if parameter("name") != nil {
                    guard parameter("data") == nil else { throw DraftlyError.message("The workspace link has conflicting destinations.") }
                    controller.openWorkspace(try Self.namedWorkspace(parameter("name"), library: library))
                } else {
                    let installed = try Self.installWorkspace(url, library: library) { existing in
                        let alert = NSAlert()
                        alert.messageText = "Replace workspace “\(existing.name)”?"
                        alert.informativeText = "Replace keeps the existing workspace identity."
                        alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                        alert.buttons.last?.keyEquivalent = "\u{1b}"
                        return alert.runModal() == .alertFirstButtonReturn
                    }
                    if installed { show() }
                }
            } catch { report(error) }
        case "action":
            do {
                let installed = try Self.installActions(url, library: library) { actions, groups in
                    let alert = NSAlert()
                    alert.messageText = "Replace installed actions or groups?"
                    let names = actions.map { "Action: \($0.name)" } + groups.map { "Group: \($0.name)" }
                    alert.informativeText = names.joined(separator: "\n")
                    alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                    alert.buttons.last?.keyEquivalent = "\u{1b}"
                    return alert.runModal() == .alertFirstButtonReturn
                }
                if installed { show() }
            } catch { report(error) }
        case "theme":
            do {
                let installed = try Self.installTheme(url, library: library) { existing in
                    let alert = NSAlert()
                    alert.messageText = "Replace theme “\(existing.name)”?"
                    alert.informativeText = "Replace keeps the existing theme identity."
                    alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                    alert.buttons.last?.keyEquivalent = "\u{1b}"
                    return alert.runModal() == .alertFirstButtonReturn
                }
                if installed { show() }
            } catch { report(error) }
        case "syntax":
            do {
                if let data = parameter("data") {
                    if try Self.installSyntax(Data(data.utf8), library: library, review: SyntaxImportReview.resolve) { show() }
                } else if let name = parameter("name"), ScriptSyntax.names.contains(name) { show() }
                else { throw DraftlyError.message("The syntax link is invalid.") }
            } catch { report(error) }
        case "create": newDraft(content: parameter("text") ?? "")
        case "capture": capture(content: parameter("text") ?? "")
        case "open":
            do {
                let parameters = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
                let note = try Self.openTarget(parameters: parameters, library: library) { title in
                    let alert = NSAlert()
                    alert.messageText = "Create draft “\(title)”?"
                    alert.informativeText = "No draft with this title was found."
                    alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel")
                    alert.buttons.last?.keyEquivalent = "\u{1b}"
                    return alert.runModal() == .alertFirstButtonReturn
                }
                show(note.id)
            } catch OpenTargetError.ambiguous(let title) {
                let alert = NSAlert()
                alert.messageText = "More than one draft matches “\(title)”."
                alert.informativeText = "Search to choose the draft to open."
                alert.addButton(withTitle: "Search")
                alert.runModal()
                controller.showQuickSearch(initialQuery: title)
            } catch OpenTargetError.cancelled { return }
            catch { library?.error = error.localizedDescription }
        case "quickSearch": controller.showQuickSearch(initialQuery: parameter("query") ?? "")
        case "run", "runAction":
            let callbackParameters = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
            let target: (action: DraftAction, note: Note)
            do { target = try Self.runTarget(parameters: callbackParameters, library: library) }
            catch {
                self.library?.error = error.localizedDescription
                if let callback = ActionExecutionResult.failure(error.localizedDescription).callbackURL(parameters: callbackParameters) { NSWorkspace.shared.open(callback) }
                return
            }
            guard let library else { return }
            let (action, note) = target
            let name = action.name
            let alert = NSAlert(); alert.messageText = "Run \(name)?"; alert.informativeText = "An external link requested this action on \(note.title)."
            alert.addButton(withTitle: "Run Action"); alert.addButton(withTitle: "Cancel")
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            let host = controller.makeActionHost()
            Task { @MainActor in
                do {
                    guard try await NativeAlertWait.present(alert) == .alertFirstButtonReturn else {
                        if let callback = ActionExecutionResult.cancelled.callbackURL(parameters: callbackParameters) { NSWorkspace.shared.open(callback) }
                        return
                    }
                    let output = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
                        models: controller.windows.allObjects, host: host)
                    if case .failure(let message) = output.report.result { library.error = message }
                    if output.report.result.succeeded, !output.presentationHandled,
                       !controller.windows.allObjects.contains(where: { $0.library === library && $0.editor.noteID == output.noteID && $0.window?.isVisible == true }) {
                        show(output.noteID)
                    }
                    if let callback = output.report.result.callbackURL(parameters: callbackParameters, successParameters: output.report.successParameters) { NSWorkspace.shared.open(callback) }
                } catch {
                    library.error = error.localizedDescription
                    let result: ActionExecutionResult = error is CancellationError ? .cancelled : .failure(error.localizedDescription)
                    if let callback = result.callbackURL(parameters: callbackParameters) { NSWorkspace.shared.open(callback) }
                }
            }
        default: break
        }
    }
    static func applicationURL(_ url: URL, registeredScheme: String) -> URL? {
        if url.scheme == "draftly" { return url }
        guard !registeredScheme.isEmpty, url.scheme == registeredScheme,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "draftly"
        return components.url
    }

    static func installWorkspace(_ url: URL, library: LibraryStore?,
                                 confirmReplacement: (Workspace) -> Bool) throws -> Bool {
        guard let library else { throw DraftlyError.message("The library is unavailable.") }
        let incoming = try WorkspaceInstallation.decode(url)
        if let existing = library.workspaces.first(where: { $0.id == incoming.id }) {
            if existing == incoming { return true }
            guard confirmReplacement(existing) else { return false }
            guard library.workspaces.first(where: { $0.id == incoming.id }) == existing else {
                throw DraftlyError.message("The installed workspace changed. Open the link again to review the replacement.")
            }
        }
        try library.saveWorkspace(incoming)
        return true
    }

    @discardableResult
    static func installSyntax(_ data: Data, library: LibraryStore?,
                              review: (SyntaxDefinition, LibraryStore) throws -> SyntaxDefinition?) throws -> Bool {
        let incoming = try SyntaxDefinition(data: data)
        guard let library else { throw DraftlyError.message("The library is unavailable.") }
        if library.syntaxes.contains(where: { $0.name == incoming.name && $0.type == "custom" && $0.source == incoming.source }) {
            return true
        }
        guard let syntax = try review(incoming, library) else { return false }
        try library.saveSyntax(syntax)
        return true
    }

    static func installTheme(_ url: URL, library: LibraryStore?,
                             confirmReplacement: (EditorThemeDefinition) -> Bool) throws -> Bool {
        guard let library else { throw DraftlyError.message("The library is unavailable.") }
        switch try ThemeInstallation(url: url) {
        case .builtIn: return true
        case .custom(var incoming):
            let identityMatch = library.themes.first { $0.id == incoming.id }
            let nameMatch = library.themes.first { $0.name == incoming.name && $0.type == incoming.type }
            if let identityMatch, identityMatch.type != incoming.type {
                throw DraftlyError.message("The theme identity belongs to a different theme type.")
            }
            if let identityMatch, let nameMatch, identityMatch.id != nameMatch.id {
                throw DraftlyError.message("The theme name belongs to a different installed theme.")
            }
            if let existing = identityMatch ?? nameMatch {
                incoming.id = existing.id
                if incoming == existing { return true }
                let beforeConfirmation = library.themes
                guard confirmReplacement(existing) else { return false }
                guard library.themes == beforeConfirmation else {
                    throw DraftlyError.message("The installed themes changed. Open the link again to review the replacement.")
                }
            }
            try library.saveTheme(incoming)
            return true
        }
    }

    @discardableResult
    static func installActions(_ url: URL, library: LibraryStore?,
                               confirmReplacement: ([DraftAction], [ActionGroupRecord]) -> Bool = { _, _ in false }) throws -> Bool {
        guard let library else { throw DraftlyError.message("The library is unavailable.") }
        let data = try ActionImporter.installationData(url)
        let actions = try ActionImporter.decode(data)
        let groups = (try? JSONDecoder().decode(Backup.self, from: data))?.actionGroups ?? []
        guard Set(actions.map(\.id)).count == actions.count, Set(groups.map(\.id)).count == groups.count else {
            throw DraftlyError.message("The action link contains duplicate identifiers.")
        }
        if !groups.isEmpty {
            let replacedGroupIDs = Set(groups.map(\.id))
            let groupNames = groups.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            let existingNames = Set(library.actionGroups.filter { !replacedGroupIDs.contains($0.id) }
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
            guard !groupNames.contains(""), Set(groupNames).count == groupNames.count,
                  existingNames.isDisjoint(with: groupNames) else {
                throw DraftlyError.message("The action link contains a group name that conflicts with an installed group.")
            }
        }
        let oldActions = library.actions, oldGroups = library.actionGroups
        let replacements = oldActions.filter { existing in actions.contains { $0.id == existing.id && $0 != existing } }
        let groupReplacements = oldGroups.filter { existing in groups.contains { $0.id == existing.id && $0 != existing } }
        if !replacements.isEmpty || !groupReplacements.isEmpty {
            guard confirmReplacement(replacements, groupReplacements) else { return false }
            guard library.actions == oldActions, library.actionGroups == oldGroups else {
                throw DraftlyError.message("The installed actions or groups changed. Open the link again to review the replacement.")
            }
        }
        try LibraryFileImport.apply(data, fileExtension: "json", to: library)
        return true
    }

    enum OpenTargetError: Error, Equatable {
        case ambiguous(String)
        case cancelled
    }

    static func openTarget(parameters: [String: String], library: LibraryStore?,
                           confirmCreation: (String) -> Bool = { _ in false }) throws -> Note {
        guard let library else { throw DraftlyError.message("The library is unavailable.") }
        if let value = parameters["uuid"] {
            guard let id = UUID(uuidString: value), let note = library.notes.first(where: { $0.id == id }) else {
                throw DraftlyError.message("The draft in the link was not found.")
            }
            return note
        }
        guard let title = parameters["title"], !title.isEmpty else {
            throw DraftlyError.message("The draft link needs a title or UUID.")
        }
        let matches = library.notes.filter { $0.trashedAt == nil && $0.title == title }
        if matches.count > 1 { throw OpenTargetError.ambiguous(title) }
        if let note = matches.first { return note }
        guard parameters["allowCreate"] == "true" else {
            throw DraftlyError.message("The draft in the link was not found.")
        }
        guard confirmCreation(title) else { throw OpenTargetError.cancelled }
        return try library.createNote(content: title)
    }

    static func namedWorkspace(_ name: String?, library: LibraryStore?) throws -> Workspace {
        guard let library else { throw DraftlyError.message("The library is unavailable.") }
        guard let name, !name.isEmpty, let workspace = library.workspaces.first(where: { $0.name == name }) else {
            throw DraftlyError.message("The workspace in the link was not found.")
        }
        return workspace
    }

    static func runTarget(parameters: [String: String], library: LibraryStore?) throws -> (action: DraftAction, note: Note) {
        guard let library else { throw DraftlyError.message("The library is unavailable.") }
        guard let name = parameters["action"], !name.isEmpty,
              let action = library.actions.first(where: { $0.name == name }) else {
            throw DraftlyError.message("The action in the link was not found.")
        }
        guard let id = parameters["uuid"].flatMap(UUID.init(uuidString:)),
              let note = library.notes.first(where: { $0.id == id }) else {
            throw DraftlyError.message("The draft in the link was not found.")
        }
        return (action, note)
    }

}
