import AppKit
import DraftlyCore

@MainActor
struct ApplicationURLRouter {
    unowned let controller: AppController
    private var library: LibraryStore? { controller.library }
    private func show(_ id: UUID? = nil) { controller.show(id) }
    private func newDraft(content: String) { controller.newDraft(content: content) }
    private func capture(content: String) { controller.capture(content: content) }

    func handle(_ url: URL) {
        if ActionCallbackRouter.receive(url) { return }
        guard url.scheme == "draftly" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func parameter(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let endpoint = url.host == "x-callback-url" ? String(url.path.dropFirst()) : url.host
        switch endpoint {
        case "workspace":
            do {
                let workspace = try WorkspaceInstallation.decode(url)
                try library?.saveWorkspace(workspace)
                show()
            } catch { library?.error = error.localizedDescription }
        case "action":
            do { try Self.installActions(url, library: library); show() }
            catch { library?.error = error.localizedDescription }
        case "syntax":
            do {
                if let data = parameter("data") {
                    var syntax = try SyntaxDefinition(data: Data(data.utf8))
                    if let existing = library?.syntaxes.first(where: { $0.name == syntax.name }) {
                        if existing.source != syntax.source {
                            let alert = NSAlert(); alert.messageText = "Replace syntax “\(syntax.name)”?"
                            alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
                            guard alert.runModal() == .alertFirstButtonReturn else { return }
                        }
                        syntax.id = existing.id
                    }
                    try library?.saveSyntax(syntax); show()
                } else if let name = parameter("name"), ScriptSyntax.names.contains(name) { show() }
                else { throw DraftlyError.message("The syntax link is invalid.") }
            } catch { library?.error = error.localizedDescription }
        case "create": newDraft(content: parameter("text") ?? "")
        case "capture": capture(content: parameter("text") ?? "")
        case "open": if let id = parameter("uuid").flatMap(UUID.init(uuidString:)) { show(id) }
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
                    if output.report.result.succeeded,
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
    static func installActions(_ url: URL, library: LibraryStore?) throws {
        guard let library else { throw DraftlyError.message("The library is unavailable.") }
        let actions = try ActionImporter.installationActions(url)
        try library.saveActions(actions)
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
