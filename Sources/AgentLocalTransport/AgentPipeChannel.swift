import Foundation
import Darwin
import AgentContracts

// Own duplicates, not the caller's descriptors. Input and output must not share a queue.
package final class AgentPipeChannel: @unchecked Sendable {
    private let input: AgentIODescriptor
    private let output: AgentIODescriptor
    private let inputQueue = DispatchQueue(label: "draftly.agent.pipe.input", qos: .utility)
    private let outputQueue = DispatchQueue(label: "draftly.agent.pipe.output", qos: .utility)
    private var pending = Data() // Input queue only.
    private var scanned = 0

    package init(input: Int32, output: Int32) throws {
        func owned(_ source: Int32) throws -> AgentIODescriptor {
            let fd = fcntl(source, F_DUPFD_CLOEXEC, 0)
            guard fd >= 0 else { throw AgentErrorCode.unavailable }
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0, fcntl(fd, F_SETNOSIGPIPE, 1) == 0 else {
                Darwin.close(fd); throw AgentErrorCode.unavailable
            }
            return AgentIODescriptor(fd)
        }
        self.input = try owned(input); self.output = try owned(output)
    }

    package func close() { input.close(); output.close() }
    deinit { close() }

    package func readLine(timeout: TimeInterval? = nil) async throws -> Data? {
        guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                inputQueue.async { [self] in
                    do { continuation.resume(returning: try input.use { fd in
                        try nextLine(fd, deadline: timeout.map { try AgentUnixChannel.deadline($0) } ?? .greatestFiniteMagnitude)
                    }) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.close() })
    }

    private func nextLine(_ fd: Int32, deadline: TimeInterval) throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            if let newline = pending.dropFirst(scanned).firstIndex(of: 10) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                scanned = 0
                guard line.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.invalidInput }
                if !line.isEmpty { return line }; continue
            }
            scanned = pending.count
            guard pending.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.invalidInput }
            try input.wait(fd, events: Int16(POLLIN), deadline: deadline)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            guard count >= 0 else { throw AgentErrorCode.unavailable }
            if count == 0 {
                guard pending.isEmpty else { throw AgentErrorCode.invalidInput }
                return nil
            }
            pending.append(contentsOf: buffer.prefix(count))
        }
    }

    package func writeLine(_ data: Data) async throws {
        guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
        guard !data.isEmpty, data.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.invalidInput }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                outputQueue.async { [self] in
                    do {
                        try output.use { fd in
                            let bytes = data + Data([10]), deadline = try AgentUnixChannel.deadline(30)
                            try bytes.withUnsafeBytes { buffer in
                                var offset = 0
                                while offset < buffer.count {
                                    try output.wait(fd, events: Int16(POLLOUT), deadline: deadline)
                                    let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                                    if count < 0, errno == EINTR || errno == EAGAIN { continue }
                                    guard count > 0 else { throw AgentErrorCode.unavailable }
                                    offset += count
                                }
                            }
                        }
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.close() })
    }
}
