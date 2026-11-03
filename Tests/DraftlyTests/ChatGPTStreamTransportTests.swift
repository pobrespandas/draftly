import Foundation
import Network
import Testing
@testable import Draftly

@Suite("ChatGPT native stream transport") @MainActor
struct ChatGPTStreamTransportTests {
    @MainActor private final class Server {
        let listener: NWListener
        let body: String
        var connections: [NWConnection] = []
        var waiter: CheckedContinuation<URL, any Error>?
        init(body: String) throws {
            self.body = body
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }
        func start() async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self, let waiter = self.waiter else { return }
                        switch state {
                        case .ready:
                            self.waiter = nil
                            waiter.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)/responses")!)
                        case .failed(let error): self.waiter = nil; waiter.resume(throwing: error)
                        default: break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in self?.accept(connection) }
                }
                listener.start(queue: .main)
            }
        }
        private func accept(_ connection: NWConnection) {
            connections.append(connection)
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] _, _, _, _ in
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    let response = "HTTP/1.1 200 OK\r\nContent-Length: \(self.body.utf8.count)\r\nConnection: close\r\n\r\n" + self.body
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        func stop() {
            listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil; listener.cancel()
            connections.forEach { $0.cancel() }; connections = []
        }
    }

    @Test func acceptsValidatedSSEWhenHTTPContentTypeIsMissing() async throws {
        let server = try Server(body: "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n")
        defer { server.stop() }
        let url = try await server.start()
        var events: [Data] = []
        try await ChatGPTProvider.streamResponse(URLRequest(url: url)) { data in events.append(data); return true }
        #expect(events == [Data(#"{"type":"response.completed"}"#.utf8)])
    }
}
