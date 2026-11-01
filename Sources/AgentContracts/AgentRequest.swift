import Foundation

package enum AgentErrorCode: String, Codable, Sendable, Error, CaseIterable {
    case invalidInput = "invalid_input"
    case permissionDenied = "permission_denied"
    case notFound = "not_found"
    case versionConflict = "version_conflict"
    case editorConflict = "editor_conflict"
    case busy
    case interactionRequired = "interaction_required"
    case unavailable
    case storageError = "storage_error"
    case executionError = "execution_error"
    case cancelled
    case timeout
    case outcomeUnknown = "outcome_unknown"
    case retryWindowExpired = "retry_window_expired"
}

package enum AgentResourceKind: String, Codable, Sendable, CaseIterable {
    case draft, revision, action, actionGroup, workspace, theme, syntax, window, bookmark, operation
}

package struct AgentResourceReference: Hashable, Codable, Sendable {
    package let kind: AgentResourceKind
    package let id: UUID

    package init(kind: AgentResourceKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

package struct AgentRequest: Codable, Equatable, Sendable {
    package static let version = 1
    package static let maximumBytes = 8 * 1024 * 1024
    package static let maximumTargets = 10_000
    package static let maximumRetryKeyBytes = 4096

    package let apiVersion: Int
    package let requestID: UUID
    package let libraryID: UUID?
    package let operation: String
    package let targets: [AgentResourceReference]
    package let expectedVersion: String?
    package let retryKey: String?
    package let parameters: [String: AgentJSONValue]

    package init(requestID: UUID, libraryID: UUID?, operation: String,
                 targets: [AgentResourceReference] = [], expectedVersion: String? = nil, retryKey: String? = nil,
                 parameters: [String: AgentJSONValue] = [:]) {
        apiVersion = Self.version
        self.requestID = requestID
        self.libraryID = libraryID
        self.operation = operation
        self.targets = targets
        self.expectedVersion = expectedVersion
        self.retryKey = retryKey
        self.parameters = parameters
    }

    // All incoming transports use this boundary before operation-specific validation.
    package static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw AgentErrorCode.invalidInput }
        do {
            let request = try JSONDecoder().decode(Self.self, from: data)
            guard request.apiVersion == version, !request.operation.isEmpty,
                  request.operation.utf8.count <= 128, request.targets.count <= maximumTargets,
                  Set(request.targets).count == request.targets.count,
                  request.expectedVersion.map({ !$0.isEmpty }) ?? true,
                  request.retryKey.map({ !$0.isEmpty && $0.utf8.count <= maximumRetryKeyBytes }) ?? true else {
                throw AgentErrorCode.invalidInput
            }
            return request
        } catch { throw AgentErrorCode.invalidInput }
    }
}

package enum AgentOperationState: String, Codable, Sendable, CaseIterable {
    case queued, running
    case waitingForUser = "waiting_for_user"
    case succeeded, failed, cancelled
    case timedOut = "timed_out"
    case outcomeUnknown = "outcome_unknown"

    package var isTerminal: Bool {
        switch self {
        case .queued, .running, .waitingForUser: false
        case .succeeded, .failed, .cancelled, .timedOut, .outcomeUnknown: true
        }
    }
}
