import DraftlyCore

@MainActor final class RunActionIntentEnvironment {
    let library: LibraryStore?
    let models: [WindowModel]
    let host: any ActionHost
    let resolveModel: AutomationActionExecution.ModelResolver

    init(library: LibraryStore?, models: [WindowModel], host: any ActionHost,
         resolveModel: @escaping AutomationActionExecution.ModelResolver = { AutomationActionExecution.visibleModel($0, noteID: $1) }) {
        self.library = library
        self.models = models
        self.host = host
        self.resolveModel = resolveModel
    }
}
