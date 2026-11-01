import Foundation
import MCP
import Logging
import AgentContracts
import AgentLocalTransport

// The SDK owns MCP dispatch. This transport adds byte and in-flight limits.
package actor AgentMCPStdioTransport: Transport {
    package nonisolated let logger = Logger(label: "draftly.agent.mcp", factory: { _ in SwiftLogNoOpLogHandler() })
    private let pipe: AgentPipeChannel
    private let stream: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private var reading: Task<Void, Never>?
    private var active: [Data: Int] = [:]
    private var started = false
    private var ended = false
    private var failure: AgentErrorCode?

    package init(input: Int32, output: Int32) throws {
        pipe = try AgentPipeChannel(input: input, output: output)
        (stream, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(16))
    }

    package func connect() async throws {
        guard !started else { return }; started = true
        reading = Task { [weak self, pipe] in
            do {
                while let data = try await pipe.readLine() {
                    guard let self else { break }
                    try await self.accept(data)
                }
                await self?.finish(nil)
            } catch { await self?.finish(error) }
        }
    }

    package func disconnect() async { reading?.cancel(); reading = nil; pipe.close(); finish(nil) }
    package func receive() -> AsyncThrowingStream<Data, any Error> { stream }
    package func terminalFailure() -> AgentErrorCode? { failure }

    package func send(_ data: Data) async throws {
        try await pipe.writeLine(data)
        if case .object(let root) = try? JSONDecoder().decode(AgentJSONValue.self, from: data), let id = root["id"] {
            active.removeValue(forKey: try JSONEncoder().encode(id))
        }
    }

    private func accept(_ data: Data) async throws {
        let parsed = try? JSONDecoder().decode(AgentJSONValue.self, from: data)
        if case .array = parsed {
            try await reject(nil, code: -32600, message: "invalid_input: batches are not supported")
            return
        }
        if case .object(let root) = parsed {
            if root["method"] == .string("tools/call"),
               case .object(let params) = root["params"], let arguments = params["arguments"] {
                let sdk = try JSONDecoder().decode(MCP.Value.self, from: JSONEncoder().encode(arguments))
                let roundTrip = try JSONDecoder().decode(AgentJSONValue.self, from: JSONEncoder().encode(sdk))
                if arguments != roundTrip {
                    try await reject(root["id"], code: -32602, message: "invalid_input: use parametersJSON for exact decimal values")
                    return
                }
            }
            if case .string = root["method"], let id = root["id"], Self.validID(id) {
                let key = try JSONEncoder().encode(id)
                guard active[key] == nil else {
                    try await reject(id, code: -32600, message: "invalid_input: duplicate request ID")
                    pipe.close(); finish(AgentErrorCode.invalidInput); return
                }
                guard active.count < 16, active.values.reduce(0, +) + data.count <= 16 * 1024 * 1024 else {
                    try await reject(id, code: -32000, message: "busy"); return
                }
                active[key] = data.count
            }
        }
        switch continuation.yield(data) {
        case .enqueued: return
        case .dropped, .terminated: throw AgentErrorCode.busy
        @unknown default: throw AgentErrorCode.unavailable
        }
    }

    private static func validID(_ value: AgentJSONValue) -> Bool {
        switch value { case .integer, .string: true; default: false }
    }

    private func reject(_ id: AgentJSONValue?, code: Int64, message: String) async throws {
        let error = AgentJSONValue.object(["jsonrpc": .string("2.0"), "id": id ?? .null,
            "error": .object(["code": .integer(code), "message": .string(message)])])
        try await pipe.writeLine(JSONEncoder().encode(error))
    }

    private func finish(_ error: (any Error)?) {
        guard !ended else { return }; ended = true
        if let error { failure = (error as? AgentErrorCode) ?? .unavailable }
        active.removeAll()
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }

    deinit { reading?.cancel(); pipe.close(); continuation.finish() }
}
