import Foundation
import AgentContracts
import DraftlyCore

// A parent operation owns approval, download identity and any later library effect.
@MainActor enum AgentHTTPSImport {
    static func isHTTPS(_ request: AgentRequest) -> Bool {
        guard case .object(let source) = request.parameters["source"] else { return false }
        return source["kind"] == .string("https")
    }

    static func sourceURL(_ request: AgentRequest, grant: AgentGrant) throws -> String {
        guard request.libraryID == grant.libraryID, grant.capabilities.contains(.nativeUse),
              let source = request.parameters["source"], try AgentImportSource.validate(source) == "https",
              case .object(let fields) = source, case .string(let url) = fields["url"] else { throw AgentErrorCode.permissionDenied }
        return url
    }

    static func download(_ url: String, maximumBytes: Int) async throws -> Data {
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: ["url": url, "method": "GET",
            "headersJSON": "{}", "followRedirects": true, "timeout": 60]), as: UTF8.self)
        let response = try await BoundedHTTP.request(payload, maximumBytes: maximumBytes)
        guard (200..<300).contains(response.statusCode) else { throw AgentErrorCode.unavailable }
        return response.data
    }

    static func read(_ request: AgentRequest, grant: AgentGrant, maximumBytes: Int,
                     environment: AgentNativeExecution.Environment, operations: AgentOperationRegistry,
                     operationID: UUID, validateIntent: () throws -> Void,
                     authorize: () throws -> Void) async throws -> Data {
        var submitted = false
        let effect = UUID()
        do {
            try Task.checkCancellation(); try authorize(); try validateIntent()
            let url = try sourceURL(request, grant: grant)
            guard let descriptor = AgentOperationCatalog.operation(named: request.operation) else { throw AgentErrorCode.unavailable }
            let purpose = ["themes.install": "Install the validated theme", "themes.replace": "Replace the selected theme",
                "backups.validate": "Validate the backup without restoring it", "backups.previewRestore": "Preview the backup without restoring it"][request.operation] ?? "Read the selected input"
            let effects = AgentApprovalStore.Effects(capabilities: descriptor.capabilities.union([.nativeUse]),
                targets: Set(request.targets), requiresLibraryScope: descriptor.requiresLibraryScope,
                snapshot: ["nativeOperation": .string("http"), "sourceImport": .bool(true),
                    "nativeParameters": .object(["url": .string(url), "method": .string("GET"),
                        "followRedirects": .bool(true), "maximumBytes": .integer(Int64(maximumBytes)),
                        "purpose": .string(purpose)])])
            try operations.setWaitingForUser(operationID, waiting: true)
            try await environment.approvals.waitForApproval(request, connectionID: grant.connectionID, resolveEffects: {
                try Task.checkCancellation(); try authorize(); try validateIntent()
                return effects
            })
            try operations.setWaitingForUser(operationID, waiting: false)
            try Task.checkCancellation(); try authorize(); try validateIntent()
            try operations.recordEffect(operationID, effectID: effect, kind: "input.https", outcome: "submitted")
            submitted = true
            let data = try await environment.fetchHTTPS(url, maximumBytes)
            try Task.checkCancellation(); try authorize()
            guard data.count <= maximumBytes else { throw AgentErrorCode.invalidInput }
            try operations.recordEffect(operationID, effectID: effect, kind: "input.https", outcome: "completed")
            return data
        } catch {
            if submitted {
                try? operations.recordEffect(operationID, effectID: effect, kind: "input.https", outcome: "unknown")
                throw AgentErrorCode.outcomeUnknown
            }
            throw AgentOperationRegistry.FailureBeforeEffects(code:
                error is CancellationError ? .cancelled : (error as? AgentErrorCode ?? .storageError))
        }
    }
}
