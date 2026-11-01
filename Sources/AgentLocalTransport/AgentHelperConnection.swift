import Foundation
import AgentContracts

// One connection preserves cursor ownership. Never replay a failed request.
package actor AgentHelperConnection {
    private let connect: @Sendable () async throws -> AgentLocalClient
    private var client: AgentLocalClient?
    private var opening: Task<AgentLocalClient, any Error>?
    private var heartbeat: Task<Void, Never>?
    private var closed = false
    private var tail: (UUID, Task<Void, Never>)?
    private var queued = 0

    package init(connect: @escaping @Sendable () async throws -> AgentLocalClient) { self.connect = connect }

    package func request(_ request: AgentRequest) async throws -> AgentResponse {
        guard !closed else { throw AgentErrorCode.cancelled }
        guard queued < 16 else { throw AgentErrorCode.busy }
        queued += 1
        let previous = tail?.1, id = UUID()
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
            return try await perform(request)
        }
        tail = (id, Task { _ = try? await task.value })
        defer { queued -= 1; if tail?.0 == id { tail = nil } }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    private func perform(_ request: AgentRequest) async throws -> AgentResponse {
        guard !closed else { throw AgentErrorCode.cancelled }
        let current = try await connected()
        do {
            let bytes = try await current.request(JSONEncoder().encode(request))
            return try JSONDecoder().decode(AgentResponse.self, from: bytes)
        } catch AgentErrorCode.busy { throw AgentErrorCode.busy }
        catch {
            client = nil; heartbeat?.cancel(); heartbeat = nil
            await current.close(); throw error
        }
    }

    package func close() async {
        closed = true; opening?.cancel(); opening = nil
        heartbeat?.cancel(); heartbeat = nil
        let old = client; client = nil
        await old?.close()
    }

    private func connected() async throws -> AgentLocalClient {
        if let client { return client }
        let task: Task<AgentLocalClient, any Error>
        if let opening { task = opening }
        else { task = Task { try await connect() }; opening = task }
        do {
            let value = try await task.value
            opening = nil
            guard !closed else { await value.close(); throw AgentErrorCode.cancelled }
            client = value
            if heartbeat == nil {
                heartbeat = Task { [weak self] in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(10)) } catch { break }
                        await self?.pingHost()
                    }
                }
            }
            return value
        } catch { opening = nil; throw error }
    }

    package func pingHost() async {
        guard !closed, let client else { return }
        do {
            let request = AgentRequest(requestID: UUID(), libraryID: nil, operation: "server.status")
            let response = try await self.request(request)
            if case .error = response.outcome {
                self.client = nil; heartbeat?.cancel(); heartbeat = nil; await client.close()
            }
        } catch AgentErrorCode.busy { return }
        catch { self.client = nil; heartbeat?.cancel(); heartbeat = nil; await client.close() }
    }

    deinit { opening?.cancel(); heartbeat?.cancel() }
}
