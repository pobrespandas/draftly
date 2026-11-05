import Foundation
import Network

/// A single browser authorization callback. Bind only to IPv4 loopback.
@MainActor final class ChatGPTCallbackListener {
    enum Failure: Error { case unavailable, timedOut, alreadyStarted, browserUnavailable }
    private var listener: NWListener?
    private var startWaiter: CheckedContinuation<UInt16, any Error>?
    private var codeWaiter: CheckedContinuation<ChatGPTAuthorization.Code, any Error>?
    private var authorization: ChatGPTAuthorization?
    private var connections: [UUID: NWConnection] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private var timeout: Task<Void, Never>?
    private var port: UInt16?
    private var started = false
    private var finished = false
    private let lifetime: Duration

    init(lifetime: Duration = .seconds(300)) { self.lifetime = lifetime }

    func start() async throws -> UInt16 {
        guard !started, !finished else { throw Failure.alreadyStarted }
        started = true
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                startWaiter = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self] state in
                        Task { @MainActor in self?.stateChanged(state) }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        Task { @MainActor in
                            guard let self else { connection.cancel(); return }
                            self.accept(connection)
                        }
                    }
                    timeout = Task { [weak self, lifetime] in
                        do { try await Task.sleep(for: lifetime) } catch { return }
                        self?.fail(Failure.timedOut)
                    }
                    listener.start(queue: .main)
                } catch { fail(error) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    func waitForCode(using authorization: ChatGPTAuthorization,
                     openBrowser: (URL) -> Bool) async throws -> ChatGPTAuthorization.Code {
        guard !finished, codeWaiter == nil, self.authorization == nil,
              port == authorization.redirectURI.port.map(UInt16.init) else { throw Failure.unavailable }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.authorization = authorization
                codeWaiter = continuation
                if !openBrowser(authorization.authorizationURL) { fail(Failure.browserUnavailable) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.cancel() } }
    }

    func cancel() { fail(CancellationError()) }

    private func stateChanged(_ state: NWListener.State) {
        guard !finished else { return }
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else { fail(Failure.unavailable); return }
            self.port = port
            let waiter = startWaiter; startWaiter = nil
            waiter?.resume(returning: port)
        case .failed(let error): fail(error)
        case .cancelled: fail(CancellationError())
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !finished, authorization != nil, connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        deadlines[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.close(id)
        }
        connection.start(queue: .main)
        receive(id, accumulated: Data())
    }

    private func receive(_ id: UUID, accumulated: Data) {
        guard let connection = connections[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                guard bytes.count <= 16384 else { self.reply(id, success: false); return }
                if bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.handle(id, bytes: bytes)
                } else if complete || error != nil { self.close(id) }
                else { self.receive(id, accumulated: bytes) }
            }
        }
    }

    private func handle(_ id: UUID, bytes: Data) {
        guard !finished, let authorization, let port,
              let url = Self.callbackURL(request: bytes, port: port) else { reply(id, success: false); return }
        do {
            let code = try authorization.validateCallback(url)
            // Consume the attempt before sending a reply. Concurrent callbacks cannot reuse it.
            finished = true
            let waiter = codeWaiter; codeWaiter = nil
            reply(id, success: true)
            stop(except: id)
            waiter?.resume(returning: code)
        } catch ChatGPTAuthorizationError.denied {
            reply(id, success: false)
            fail(ChatGPTAuthorizationError.denied, except: id)
        } catch {
            // Unrelated or forged requests must not end the pending browser login.
            reply(id, success: false)
        }
    }

    static func callbackURL(request: Data, port: UInt16) -> URL? {
        guard request.count <= 16384, let text = String(data: request, encoding: .utf8),
              let end = text.range(of: "\r\n\r\n"), end.upperBound == text.endIndex else { return nil }
        let lines = text[..<end.lowerBound].components(separatedBy: "\r\n")
        let first = lines.first?.components(separatedBy: " ") ?? []
        guard first.count == 3, first[0] == "GET", first[2] == "HTTP/1.1",
              first[1].hasPrefix("/auth/callback?"), !first[1].contains("#") else { return nil }
        var hosts: [String] = []
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { return nil }
            let name = line[..<separator].lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if name == "host" { hosts.append(value) }
            if name == "transfer-encoding" || name == "content-length" { return nil }
        }
        guard hosts == ["127.0.0.1:\(port)"] else { return nil }
        return URL(string: "http://127.0.0.1:\(port)" + first[1])
    }

    private func reply(_ id: UUID, success: Bool) {
        guard let connection = connections[id] else { return }
        let body = success ? "Return to Draftly to finish connecting." : "This sign-in callback was not accepted."
        let response = "HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close(id) }
        })
    }

    private func close(_ id: UUID) {
        deadlines.removeValue(forKey: id)?.cancel()
        connections.removeValue(forKey: id)?.cancel()
    }

    private func stop(except id: UUID? = nil) {
        timeout?.cancel(); timeout = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        authorization = nil
        for key in Array(connections.keys) where key != id { close(key) }
    }

    private func fail(_ error: any Error, except id: UUID? = nil) {
        guard !finished else { return }
        finished = true
        let start = startWaiter; startWaiter = nil
        let code = codeWaiter; codeWaiter = nil
        stop(except: id)
        start?.resume(throwing: error); code?.resume(throwing: error)
    }
}
