import Foundation
import AgentContracts
import DraftlyCore

// Internal bridge. The service must validate the request and own its lifetime.
@MainActor enum AgentReviewedActionExecution {
    static func run(action: DraftAction, draftID: UUID, request: AgentRequest, connectionID: UUID,
                    library: LibraryStore, models: [WindowModel], host: any ActionHost,
                    authority: AgentScriptAuthority, approvals: AgentApprovalStore,
                    currentSnapshot: @escaping () throws -> [String: AgentJSONValue],
                    resolveModel: AutomationActionExecution.ModelResolver = { AutomationActionExecution.visibleModel($0, noteID: $1) }) async throws -> AutomationActionExecution.Output {
        guard request.operation == "actions.run", let expected = request.expectedVersion,
              request.targets.count == 2,
              Set(request.targets) == Set([.init(kind: .action, id: action.id), .init(kind: .draft, id: draftID)]) else {
            throw AgentErrorCode.invalidInput
        }
        func checkedSnapshot() throws -> [String: AgentJSONValue] {
            try authority.authorizeNative("device", rootActionID: action.id)
            let snapshot = try currentSnapshot()
            guard snapshot["actionVersion"] == .string(expected),
                  case .string(let draftVersion) = snapshot["draftVersion"], !draftVersion.isEmpty else {
                throw AgentErrorCode.versionConflict
            }
            try authority.authorizeNative("device", rootActionID: action.id)
            return snapshot
        }
        _ = try checkedSnapshot()
        let guarded = AgentAuthorizedActionHost(host: host, approve: { operation, values in
            try await AgentNativeEffectApproval.wait(store: approvals, request: request, connectionID: connectionID,
                operation: operation, values: values, currentSnapshot: checkedSnapshot)
        }, requiresApproval: { $0 != "device" }, authorize: { operation, _ in
            try authority.authorizeNative(operation, rootActionID: action.id)
        })
        return try await AutomationActionExecution.run(action, noteID: draftID, library: library,
            models: models, host: host, hostOverride: guarded, editorScope: .targetDraft,
            scriptAuthorization: { try authority.authorize($0, payload: $1) },
            scriptDraftFilter: { try authority.visibleDrafts($0) },
            stepAuthorization: { try authority.authorizeStep(owner: $0, step: $1) },
            completionAuthorization: { try authority.authorizeCompletion($0, draftID: $1) },
            actionCatalogFilter: { try authority.visibleActions($0) },
            configurationAuthorization: { try authority.authorizeConfiguration($0) },
            configurationCommitted: { try authority.acceptConfiguredAction(before: $0, after: $1) },
            resolveModel: resolveModel)
    }
}
