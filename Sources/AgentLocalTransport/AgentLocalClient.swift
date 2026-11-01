import Foundation
import AgentContracts

package actor AgentLocalClient {
    package let libraryID: UUID
    private let channel: AgentUnixChannel
    private var inFlight = false

    private init(channel: AgentUnixChannel, libraryID: UUID) { self.channel = channel; self.libraryID = libraryID }

    package static func connect(path: String, connectionID: UUID, credential: Data, expectedLibraryID: UUID? = nil,
                                validateServer: @escaping @Sendable (Data) throws -> Void) async throws -> AgentLocalClient {
        let hello = try AgentLocalHandshake.Hello(connectionID: connectionID, credential: credential, expectedLibraryID: expectedLibraryID)
        let channel = try await AgentUnixChannel.connect(path: path, validatePeer: validateServer)
        do {
            try await channel.writeFrame(JSONEncoder().encode(hello), timeout: 15)
            let welcome = try AgentLocalHandshake.Welcome.decode(await channel.readFrame(maximumBytes: AgentLocalHandshake.maximumBytes, timeout: 15))
            if let error = welcome.error { throw error }
            guard let libraryID = welcome.libraryID else { throw AgentErrorCode.invalidInput }
            guard expectedLibraryID == nil || expectedLibraryID == libraryID else { throw AgentErrorCode.permissionDenied }
            return AgentLocalClient(channel: channel, libraryID: libraryID)
        } catch { channel.close(); throw error }
    }

    package func close() { channel.close() }

    package func request(_ data: Data) async throws -> Data {
        guard !inFlight else { throw AgentErrorCode.busy }
        let parsed = try AgentRequest.decode(data)
        let bound = AgentRequest(requestID: parsed.requestID, libraryID: parsed.libraryID ?? libraryID,
            operation: parsed.operation, targets: parsed.targets, expectedVersion: parsed.expectedVersion, parameters: parsed.parameters)
        inFlight = true; defer { inFlight = false }
        do {
            try await channel.writeFrame(JSONEncoder().encode(bound))
            let result = try await channel.readFrame()
            let response: AgentResponse
            do { response = try JSONDecoder().decode(AgentResponse.self, from: result) }
            catch { throw AgentErrorCode.invalidInput }
            guard response.requestID == parsed.requestID else { throw AgentErrorCode.invalidInput }
            return result
        } catch { channel.close(); throw error }
    }
}
