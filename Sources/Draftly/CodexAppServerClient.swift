import Foundation

/// Owns one local Codex process and its JSON-RPC connection.
@MainActor final class CodexAppServerClient {
    var onNotification: ((String, Data) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var diagnostics: FileHandle?
    private var buffer = Data()
    private var sequence = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var generation = UUID()

    func start(executable: URL, home: URL) throws {
        guard process == nil else { return }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let child = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = executable
        child.arguments = ["app-server", "--listen", "stdio://", "-c", "cli_auth_credentials_store=\"keyring\""]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        child.environment = environment
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        let token = UUID(); generation = token
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.receive(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.close(with: CodexConnectionError.disconnected)
            }
        }
        process = child; input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading; diagnostics = stderr.fileHandleForReading
        do { try child.run() }
        catch { close(with: error); throw error }
    }

    func request(_ method: String, params: Data = Data("{}".utf8), timeout: Duration = .seconds(60)) async throws -> Data {
        try Task.checkCancellation()
        guard process?.isRunning == true else { throw CodexConnectionError.disconnected }
        let object = try JSONSerialization.jsonObject(with: params)
        sequence += 1
        let id = sequence
        let token = generation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.generation == token, self.pending[id] != nil else { return }
                    self.close(with: CodexConnectionError.timeout)
                }
                do { try write(["id": id, "method": method, "params": object]) }
                catch { close(with: error) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.close(with: CancellationError())
            }
        }
    }

    func notify(_ method: String) throws { try write(["method": method]) }

    func close() { close(with: CodexConnectionError.disconnected) }

    private func close(with error: Error) {
        generation = UUID()
        output?.readabilityHandler = nil; diagnostics?.readabilityHandler = nil
        try? input?.close(); try? output?.close(); try? diagnostics?.close()
        input = nil; output = nil; diagnostics = nil; buffer.removeAll()
        let child = process; process = nil
        child?.terminationHandler = nil
        if child?.isRunning == true { child?.terminate() }
        deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        let waiting = pending.values; pending.removeAll()
        for continuation in waiting { continuation.resume(throwing: error) }
    }

    private func write(_ object: [String: Any]) throws {
        guard let input else { throw CodexConnectionError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        guard buffer.count <= 16 * 1024 * 1024 else { close(with: CodexConnectionError.invalidMessage); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw CodexConnectionError.invalidMessage
                }
                if let method = object["method"] as? String {
                    if let id = object["id"] {
                        // Requests need a UI handler before the client can authorize them.
                        try write(["id": id, "error": ["code": -32601, "message": "This request is not authorized by Draftly."]])
                    } else {
                        let params = try JSONSerialization.data(withJSONObject: object["params"] ?? [:])
                        onNotification?(method, params)
                    }
                } else if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                    deadlines.removeValue(forKey: id)?.cancel()
                    if let error = object["error"] as? [String: Any] {
                        continuation.resume(throwing: CodexConnectionError.remote(error["message"] as? String ?? "Codex request failed."))
                    } else if let result = object["result"] {
                        do { continuation.resume(returning: try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])) }
                        catch { continuation.resume(throwing: error); throw error }
                    } else { continuation.resume(throwing: CodexConnectionError.invalidMessage) }
                }
            } catch { close(with: error); return }
        }
    }
}

enum CodexConnectionError: LocalizedError {
    case disconnected, timeout, invalidMessage, remote(String)
    var errorDescription: String? {
        switch self {
        case .disconnected: "The Codex connection closed."
        case .timeout: "The Codex request timed out."
        case .invalidMessage: "Codex returned an invalid message."
        case .remote(let message): message
        }
    }
}
