import Foundation
import Darwin
import AgentContracts
import AgentLocalSecurity

package final class AgentUnixListener: @unchecked Sendable {
    package let path: String
    private let directoryPath: String
    private let directory: Int32
    private let directoryIdentity: (dev_t, ino_t)
    private let socketIdentity: (dev_t, ino_t)
    private let socket: AgentIODescriptor
    private let queue = DispatchQueue(label: "com.pobrespandas.draftly.agent.accept", qos: .utility)
    private let cleanupLock = NSLock()
    private var cleaned = false

    package init(parentDirectory: URL) throws {
        guard parentDirectory.isFileURL, let parent = realpath(parentDirectory.path, nil) else { throw AgentErrorCode.invalidInput }
        defer { free(parent) }
        let parentFD = Darwin.open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard parentFD >= 0 else { throw AgentErrorCode.permissionDenied }
        defer { Darwin.close(parentFD) }
        try AgentPrivateFilePolicy.validateTrustedParent(parentFD)
        var template = Array((String(cString: parent) + "/da-XXXXXX").utf8CString)
        let root = try template.withUnsafeMutableBufferPointer { buffer -> String in
            guard let path = mkdtemp(buffer.baseAddress!) else { throw AgentErrorCode.storageError }
            return String(cString: path)
        }
        let rootFD = Darwin.open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard rootFD >= 0 else { rmdir(root); throw AgentErrorCode.permissionDenied }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { Darwin.close(rootFD); rmdir(root); throw AgentErrorCode.unavailable }
        let descriptor = AgentIODescriptor(fd), socketPath = root + "/s"
        var ownSocket: (dev_t, ino_t)?
        do {
            try AgentPrivateFilePolicy.validate(rootFD, kind: .directory)
            try AgentIODescriptor.configureSocket(fd)
            let address = try AgentUnixAddress(socketPath)
            var value = address.value
            let result = withUnsafePointer(to: &value) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, address.length) }
            }
            guard result == 0 else { throw AgentErrorCode.storageError }
            var bound = stat()
            guard fstatat(rootFD, "s", &bound, AT_SYMLINK_NOFOLLOW) == 0,
                  bound.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK), bound.st_uid == geteuid() else {
                throw AgentErrorCode.permissionDenied
            }
            ownSocket = (bound.st_dev, bound.st_ino)
            guard lchmod(socketPath, mode_t(0o600)) == 0 else { throw AgentErrorCode.storageError }
            let identity = try AgentPrivateFilePolicy.validateSocket(socketPath)
            guard Darwin.listen(fd, 16) == 0 else { throw AgentErrorCode.unavailable }
            var info = stat()
            guard fstat(rootFD, &info) == 0 else { throw AgentErrorCode.storageError }
            directoryIdentity = (info.st_dev, info.st_ino); socketIdentity = (identity.device, identity.inode)
            path = socketPath; directoryPath = root; directory = rootFD; socket = descriptor
        } catch {
            descriptor.close()
            var entry = stat(), original = stat()
            if let ownSocket, fstatat(rootFD, "s", &entry, AT_SYMLINK_NOFOLLOW) == 0,
               entry.st_dev == ownSocket.0 && entry.st_ino == ownSocket.1 { _ = unlinkat(rootFD, "s", 0) }
            if fstat(rootFD, &original) == 0, lstat(root, &entry) == 0,
               entry.st_dev == original.st_dev && entry.st_ino == original.st_ino { _ = rmdir(root) }
            Darwin.close(rootFD)
            throw error
        }
    }

    deinit { close(); Darwin.close(directory) }

    package func close() {
        socket.close()
        cleanupLock.lock(); defer { cleanupLock.unlock() }
        guard !cleaned else { return }; cleaned = true
        var entry = stat()
        if fstatat(directory, "s", &entry, AT_SYMLINK_NOFOLLOW) == 0,
           entry.st_dev == socketIdentity.0 && entry.st_ino == socketIdentity.1 {
            _ = unlinkat(directory, "s", 0)
        }
        if lstat(directoryPath, &entry) == 0, entry.st_dev == directoryIdentity.0 && entry.st_ino == directoryIdentity.1 {
            _ = rmdir(directoryPath)
        }
    }

    package func accept(timeout: TimeInterval = 1) async throws -> AgentUnixChannel {
        guard !Task.isCancelled else { throw AgentErrorCode.cancelled }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        let channel = try socket.use { fd in
                            let deadline = try AgentUnixChannel.deadline(timeout)
                            while true {
                                try socket.wait(fd, events: Int16(POLLIN), deadline: deadline)
                                let accepted = Darwin.accept(fd, nil, nil)
                                if accepted < 0, errno == EINTR || errno == EAGAIN { continue }
                                guard accepted >= 0 else { throw AgentErrorCode.unavailable }
                                return try AgentUnixChannel(descriptor: accepted)
                            }
                        }
                        continuation.resume(returning: channel)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.close() })
    }
}
