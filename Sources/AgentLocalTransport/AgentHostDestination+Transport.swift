import Foundation
import AgentContracts
import AgentLocalSecurity

package extension AgentHostDestination {
    struct Resolved: Sendable {
        package let socketPath: String
        package let expectedLibraryID: UUID?
    }

    @MainActor static func stateParentDirectory(_ override: String?) throws -> URL {
        if let override {
            guard absolutePath(override) else { throw AgentErrorCode.invalidInput }
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AgentErrorCode.unavailable
        }
        return support.appendingPathComponent("Draftly", isDirectory: true)
    }

    @MainActor func resolve() throws -> Resolved {
        switch self {
        case .socket(let path):
            guard Self.absolutePath(path) else { throw AgentErrorCode.invalidInput }
            return Resolved(socketPath: path, expectedLibraryID: nil)
        case .library(let id, let parent):
            do {
                let locator = try AgentHostLocator(parentDirectory: Self.stateParentDirectory(parent))
                let endpoint = try locator.endpoint(for: id)
                return Resolved(socketPath: endpoint.socketPath, expectedLibraryID: id)
            } catch AgentErrorCode.notFound { throw AgentErrorCode.unavailable }
        }
    }

    func connect(connectionID: UUID, credential: Data,
                 validateServer: @escaping @Sendable (Data) throws -> Void) async throws -> AgentLocalClient {
        let destination = try await resolve()
        return try await AgentLocalClient.connect(path: destination.socketPath, connectionID: connectionID, credential: credential,
            expectedLibraryID: destination.expectedLibraryID, validateServer: validateServer)
    }

    func pair(name: String, validateServer: @escaping @Sendable (Data) throws -> Void) async throws -> AgentPairingClient {
        let destination = try await resolve()
        return try await AgentPairingClient.connect(path: destination.socketPath, name: name,
            expectedLibraryID: destination.expectedLibraryID, validateServer: validateServer)
    }
}
