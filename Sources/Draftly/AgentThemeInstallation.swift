import Foundation
import AgentContracts
import DraftlyCore

// The journal owns replay. A partial cross-store effect stays uncertain.
@MainActor enum AgentThemeInstallation {
    static let operationNames: Set<String> = ["themes.install", "themes.replace"]

    static func run(_ request: AgentRequest, input: AgentThemeImportPlanning.Input,
                    plan: AgentThemeImportPlanning.Plan, grant: AgentGrant,
                    identity: LibraryMutationIdentity, library: LibraryStore, reader: AgentThemeReading,
                    defaults: UserDefaults, storage: AgentPreferenceStorage, now: () -> Date,
                    operations: AgentOperationRegistry, operationID: UUID,
                    authorize: () throws -> Void) throws -> [String: AgentJSONValue] {
        let effect = UUID()
        var submitted = false
        func validate() throws {
            try Task.checkCancellation(); try authorize()
            try AgentThemeImportPlanning.validateSource(request, input: input, defaults: defaults, authorize: authorize)
            guard try AgentThemeImportPlanning.prepare(request, input: input, grant: grant,
                library: library, reader: reader, authorize: authorize) == plan else { throw AgentErrorCode.versionConflict }
        }
        func submit() throws {
            try Task.checkCancellation(); try authorize()
            if !submitted {
                try operations.recordEffect(operationID, effectID: effect, kind: request.operation, outcome: "submitted")
                submitted = true
            }
        }
        do {
            try validate()
            let before = try storage.snapshot()
            var changes: [String: AgentPreferenceBatch.StoredValue] = [:]
            var result: [String: AgentJSONValue] = ["selection": .null]
            if let name = plan.builtInName { result["builtInName"] = .string(name); result["resource"] = .null }
            if let appearance = plan.appearance {
                let reference: [String: Any]
                if let definition = plan.definition {
                    reference = ["type": definition.type, "uuid": definition.id.uuidString, "name": definition.name]
                } else if let name = plan.builtInName { reference = ["type": "builtIn", "name": name] }
                else { throw AgentErrorCode.invalidInput }
                let projected = library.themes.filter { $0.id != plan.definition?.id } + (plan.definition.map { [$0] } ?? [])
                let data = try EditorThemePreferences(defaults: defaults).selectionData(reference: reference,
                    dark: appearance == "dark", themes: projected, validateFile: { _ in
                        try AgentThemeImportPlanning.validateSource(request, input: input, defaults: defaults, authorize: authorize)
                    })
                changes[EditorThemePreferences.key] = .data(data)
            }
            if let definition = plan.definition {
                // Validate the response token before any durable change.
                let version = try reader.version(definition, filePermission: plan.bookmark)
                let receipt = try library.commitTheme(definition, mutation: identity, at: now(),
                    validateCommit: { try validate(); try submit() },
                    makeResource: { .init(id: $0.id, versionToken: version) })
                guard let resource = receipt.resources.first else { throw AgentErrorCode.storageError }
                result["resource"] = .object(["id": .string(resource.id.uuidString), "versionToken": .string(resource.versionToken)])
                if request.operation == "themes.install" { result["builtInName"] = .null }
                if let permission = plan.bookmark { changes[ThemeFileAccess.bookmarkKey(for: definition.id)] = .data(permission) }
            }
            if plan.definition != nil || !changes.isEmpty {
                changes[ThemeCatalog.revisionKey] = .scalar(.integer(Int64(defaults.integer(forKey: ThemeCatalog.revisionKey) &+ 1)))
                let committed = try storage.commit(changes, against: before, validateCommit: {
                    try Task.checkCancellation(); try authorize()
                    if plan.definition == nil { try validate() }
                    else {
                        try AgentThemeImportPlanning.validateSource(request, input: input, defaults: defaults, authorize: authorize)
                        if let definition = plan.definition {
                            guard let actual = library.themes.first(where: { $0.id == definition.id }),
                                  try reader.version(actual, filePermission: plan.bookmark) == reader.version(definition, filePermission: plan.bookmark) else { throw AgentErrorCode.versionConflict }
                        }
                    }
                    try submit()
                }, authorize: authorize)
                try Task.checkCancellation(); try authorize()
                guard try storage.snapshot().version == committed.version else { throw AgentErrorCode.outcomeUnknown }
            }
            if let appearance = plan.appearance {
                let selection = try reader.selection(appearance: appearance, grant: grant)
                guard let version = selection["versionToken"] else { throw AgentErrorCode.outcomeUnknown }
                result["selection"] = .object(["appearance": .string(appearance), "versionToken": version])
            }
            try Task.checkCancellation(); try authorize()
            try AgentAppearanceSchemas.validateResult(result, for: request)
            if submitted { try operations.recordEffect(operationID, effectID: effect, kind: request.operation, outcome: "completed") }
            return result
        } catch {
            if submitted {
                try? operations.recordEffect(operationID, effectID: effect, kind: request.operation, outcome: "unknown")
                throw AgentErrorCode.outcomeUnknown
            }
            throw AgentOperationRegistry.FailureBeforeEffects(code:
                error is CancellationError ? .cancelled : (error as? AgentErrorCode ?? .storageError))
        }
    }
}
