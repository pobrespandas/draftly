import Foundation
import Darwin
import AgentContracts

// Local connection metadata only. Credentials never belong in this file.
@MainActor final class AgentConnectionFile {
    private let directory: Int32
    private static let filename = "connections.json"
    private static let maximumBytes = AgentRequest.maximumBytes

    init(parentDirectory: URL) throws {
        guard parentDirectory.isFileURL else { throw AgentErrorCode.invalidInput }
        // Resolve only the trusted parent; Foundation can abbreviate /private/var to /var.
        guard let physical = realpath(parentDirectory.path, nil) else { throw AgentErrorCode.storageError }
        defer { free(physical) }
        let parentFD = Darwin.open(physical, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard parentFD >= 0 else { throw AgentErrorCode.storageError }
        defer { Darwin.close(parentFD) }
        var info = stat()
        guard fstat(parentFD, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & mode_t(0o022) == 0 else { throw AgentErrorCode.permissionDenied }
        try Self.verifyACL(parentFD)
        guard mkdirat(parentFD, "Agents", mode_t(0o700)) == 0 || errno == EEXIST else { throw AgentErrorCode.storageError }
        let descriptor = openat(parentFD, "Agents", O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard descriptor >= 0 else { throw AgentErrorCode.permissionDenied }
        do { try Self.verify(descriptor, directory: true) }
        catch { Darwin.close(descriptor); throw error }
        directory = descriptor
    }

    deinit { Darwin.close(directory) }

    func read() throws -> Data? { try locked { try readUnlocked() } }

    func replace(_ data: Data, expected: Data?) throws {
        guard data.count <= Self.maximumBytes else { throw AgentErrorCode.invalidInput }
        try locked {
            guard try readUnlocked() == expected else { throw AgentErrorCode.versionConflict }
            let temporary = ".connections-" + UUID().uuidString
            let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW_ANY | O_CLOEXEC, mode_t(0o600))
            guard descriptor >= 0 else { throw AgentErrorCode.storageError }
            defer { Darwin.close(descriptor); unlinkat(directory, temporary, 0) }
            guard fchmod(descriptor, mode_t(0o600)) == 0 else { throw AgentErrorCode.storageError }
            try Self.verify(descriptor, directory: false)
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw AgentErrorCode.storageError }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0 else { throw AgentErrorCode.storageError }
            guard renameat(directory, temporary, directory, Self.filename) == 0 else { throw AgentErrorCode.storageError }
            // A failure after rename has an uncertain durability outcome.
            guard fsync(directory) == 0 else { throw AgentErrorCode.outcomeUnknown }
        }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try Self.verify(directory, directory: true)
        var descriptor = openat(directory, "connections.lock", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW_ANY | O_CLOEXEC, mode_t(0o600))
        if descriptor >= 0 {
            guard fchmod(descriptor, mode_t(0o600)) == 0 else { Darwin.close(descriptor); throw AgentErrorCode.storageError }
        } else if errno == EEXIST {
            descriptor = openat(directory, "connections.lock", O_RDWR | O_NONBLOCK | O_NOFOLLOW_ANY | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw AgentErrorCode.permissionDenied }
        defer { Darwin.close(descriptor) }
        try Self.verify(descriptor, directory: false)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw errno == EWOULDBLOCK ? AgentErrorCode.busy : .storageError
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func readUnlocked() throws -> Data? {
        let descriptor = openat(directory, Self.filename, O_RDONLY | O_NONBLOCK | O_NOFOLLOW_ANY | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw AgentErrorCode.permissionDenied }
        defer { Darwin.close(descriptor) }
        try Self.verify(descriptor, directory: false)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size >= 0, info.st_size <= Self.maximumBytes else {
            throw AgentErrorCode.storageError
        }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw AgentErrorCode.storageError }
            if count == 0 { return result }
            guard result.count + count <= Self.maximumBytes else { throw AgentErrorCode.storageError }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func verify(_ descriptor: Int32, directory: Bool) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(directory ? S_IFDIR : S_IFREG),
              info.st_mode & mode_t(0o777) == mode_t(directory ? 0o700 : 0o600),
              directory || info.st_nlink == 1 else { throw AgentErrorCode.permissionDenied }
        try verifyACL(descriptor)
    }

    private static func verifyACL(_ descriptor: Int32) throws {
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            // The descriptor is valid; Darwin uses ENOENT when it has no extended ACL.
            if errno == ENOENT { return }
            throw AgentErrorCode.permissionDenied
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        var position = ACL_FIRST_ENTRY
        while acl_get_entry(acl, position.rawValue, &entry) == 0 {
            var tag = ACL_UNDEFINED_TAG
            guard let entry, acl_get_tag_type(entry, &tag) == 0, tag == ACL_EXTENDED_DENY else {
                throw AgentErrorCode.permissionDenied
            }
            position = ACL_NEXT_ENTRY
        }
        guard errno == EINVAL else { throw AgentErrorCode.permissionDenied }
    }
}
