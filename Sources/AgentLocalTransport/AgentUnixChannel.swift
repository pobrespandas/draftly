import Foundation
import Darwin
import AgentContracts
import AgentLocalSecurity

// Borrowing keeps a descriptor alive while close interrupts pending I/O.
package final class AgentSocketDescriptor: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32
    private var closed = false
    private var borrowers = 0

    package init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close() }

    package func close() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        _ = shutdown(descriptor, SHUT_RDWR)
        if borrowers == 0 { Darwin.close(descriptor); descriptor = -1 }
    }

    package var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }

    package func use<T>(_ operation: (Int32) throws -> T) throws -> T {
        lock.lock()
        guard !closed else { lock.unlock(); throw AgentErrorCode.cancelled }
        borrowers += 1
        let fd = descriptor
        lock.unlock()
        defer {
            lock.lock(); borrowers -= 1
            if closed && borrowers == 0 { Darwin.close(descriptor); descriptor = -1 }
            lock.unlock()
        }
        return try operation(fd)
    }

    package static func configure(_ fd: Int32) throws {
        var noSignal: Int32 = 1
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0,
              fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw AgentErrorCode.unavailable
        }
    }

    package func wait(_ fd: Int32, events: Int16, deadline: TimeInterval) throws {
        while true {
            guard !isClosed && !Task.isCancelled else { throw AgentErrorCode.cancelled }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw AgentErrorCode.timeout }
            var item = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&item, 1, Int32(min(100, max(1, remaining * 1000))))
            if result < 0, errno == EINTR { continue }
            guard result >= 0 else { throw AgentErrorCode.unavailable }
            if result > 0 {
                guard !isClosed && !Task.isCancelled else { throw AgentErrorCode.cancelled }
                guard item.revents & Int16(POLLNVAL) == 0 else { throw AgentErrorCode.unavailable }
                return
            }
        }
    }
}

package final class AgentUnixChannel: @unchecked Sendable {
    private let socket: AgentSocketDescriptor
    private let queue = DispatchQueue(label: "com.pobrespandas.draftly.agent.socket", qos: .utility)

    package init(descriptor: Int32) throws {
        do { try AgentSocketDescriptor.configure(descriptor) }
        catch { Darwin.close(descriptor); throw error }
        socket = AgentSocketDescriptor(descriptor)
    }

    package func close() { socket.close() }

    package static func connect(path: String, timeout: TimeInterval = 15,
                                validatePeer: @escaping @Sendable (Data) throws -> Void) async throws -> AgentUnixChannel {
        guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
        let task = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
            let address = try AgentUnixAddress(path)
            let parent = Darwin.open(URL(fileURLWithPath: path).deletingLastPathComponent().path,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
            guard parent >= 0 else { throw AgentErrorCode.permissionDenied }
            defer { Darwin.close(parent) }
            try AgentPrivateFilePolicy.validate(parent, kind: .directory)
            let before = try AgentPrivateFilePolicy.validateSocket(path)
            let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw AgentErrorCode.unavailable }
            let channel = try AgentUnixChannel(descriptor: fd)
            do {
                try channel.socket.use { descriptor in
                    var value = address.value
                    let result = withUnsafePointer(to: &value) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, address.length) }
                    }
                    if result < 0 {
                        guard errno == EINPROGRESS || errno == EAGAIN else { throw AgentErrorCode.unavailable }
                        try channel.socket.wait(descriptor, events: Int16(POLLOUT), deadline: try deadline(timeout))
                        var error: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
                        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else {
                            throw AgentErrorCode.unavailable
                        }
                    }
                    let after = try AgentPrivateFilePolicy.validateSocket(path)
                    guard before.device == after.device && before.inode == after.inode else { throw AgentErrorCode.permissionDenied }
                    try validatePeer(try channel.peerToken(descriptor))
                }
                guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
                return channel
            } catch { channel.close(); throw error }
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    package func validatePeer(_ validation: @escaping @Sendable (Data) throws -> Void) async throws {
        _ = try await perform { fd in try validation(self.peerToken(fd)); return Data() }
    }

    package func readFrame(maximumBytes: Int = AgentRequest.maximumBytes, timeout: TimeInterval = 30) async throws -> Data {
        guard maximumBytes > 0 && maximumBytes <= AgentRequest.maximumBytes else { throw AgentErrorCode.invalidInput }
        return try await perform { fd in
            let deadline = try Self.deadline(timeout)
            let header = try self.read(4, fd: fd, deadline: deadline)
            let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard count > 0 && Int(count) <= maximumBytes else { throw AgentErrorCode.invalidInput }
            return try self.read(Int(count), fd: fd, deadline: deadline)
        }
    }

    package func writeFrame(_ data: Data, timeout: TimeInterval = 30) async throws {
        guard !data.isEmpty, data.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.invalidInput }
        _ = try await perform { fd in
            let size = UInt32(data.count)
            var frame = Data([UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
            frame.append(data)
            let deadline = try Self.deadline(timeout)
            try frame.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    try self.socket.wait(fd, events: Int16(POLLOUT), deadline: deadline)
                    let count = send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                    if count < 0, errno == EINTR || errno == EAGAIN { continue }
                    guard count > 0 else { throw AgentErrorCode.unavailable }
                    offset += count
                }
            }
            return Data()
        }
    }

    private func perform(_ operation: @escaping @Sendable (Int32) throws -> Data) async throws -> Data {
        guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do { continuation.resume(returning: try socket.use(operation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.close() })
    }

    private func read(_ count: Int, fd: Int32, deadline: TimeInterval) throws -> Data {
        var result = Data(count: count)
        try result.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                try socket.wait(fd, events: Int16(POLLIN), deadline: deadline)
                let size = recv(fd, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
                if size < 0, errno == EINTR || errno == EAGAIN { continue }
                guard size > 0 else { throw AgentErrorCode.unavailable }
                offset += size
            }
        }
        return result
    }

    private func peerToken(_ fd: Int32) throws -> Data {
        var uid: uid_t = 0, gid: gid_t = 0, token = audit_token_t()
        var size = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid(),
              getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0,
              size == MemoryLayout<audit_token_t>.size else { throw AgentErrorCode.permissionDenied }
        return withUnsafeBytes(of: &token) { Data($0) }
    }

    static func deadline(_ timeout: TimeInterval) throws -> TimeInterval {
        guard timeout.isFinite && timeout > 0 && timeout <= 3600 else { throw AgentErrorCode.invalidInput }
        return ProcessInfo.processInfo.systemUptime + timeout
    }
}

package struct AgentUnixAddress: Sendable {
    package var value: sockaddr_un
    package let length: socklen_t
    package init(_ path: String) throws {
        let bytes = Array(path.utf8)
        var address = sockaddr_un()
        guard path.hasPrefix("/"), !bytes.contains(0), bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw AgentErrorCode.invalidInput
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in destination.copyBytes(from: bytes + [0]) }
        value = address; length = socklen_t(MemoryLayout<sockaddr_un>.size)
    }
}
