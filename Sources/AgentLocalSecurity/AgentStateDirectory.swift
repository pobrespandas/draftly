import Foundation
import Darwin
import AgentContracts

// Device-local agent metadata only. Callers never put credentials here.
@MainActor package final class AgentStateDirectory {
    private let descriptor: Int32
    private let path: String

    package init(parentDirectory: URL) throws {
        guard parentDirectory.isFileURL else { throw AgentErrorCode.invalidInput }
        guard let physical = realpath(parentDirectory.path, nil) else { throw AgentErrorCode.storageError }
        defer { free(physical) }
        let parent = Darwin.open(physical, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard parent >= 0 else { throw AgentErrorCode.storageError }
        defer { Darwin.close(parent) }
        try AgentPrivateFilePolicy.validateTrustedParent(parent)
        guard mkdirat(parent, "Agents", mode_t(0o700)) == 0 || errno == EEXIST else { throw AgentErrorCode.storageError }
        let directory = openat(parent, "Agents", O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard directory >= 0 else { throw AgentErrorCode.permissionDenied }
        do { try AgentPrivateFilePolicy.validate(directory, kind: .directory) }
        catch { Darwin.close(directory); throw error }
        descriptor = directory; path = String(cString: physical) + "/Agents"
    }

    deinit { Darwin.close(descriptor) }

    package func read(_ name: String, lockName: String, maximumBytes: Int) throws -> Data? {
        try validateName(name)
        guard name != lockName else { throw AgentErrorCode.invalidInput }
        try validateBudget(maximumBytes)
        let lease = try acquireLock(lockName)
        return try withExtendedLifetime(lease) { try readUnlocked(name, maximumBytes: maximumBytes) }
    }

    package func replace(_ name: String, lockName: String, data: Data, expected: Data?, maximumBytes: Int) throws {
        try validateName(name)
        guard name != lockName else { throw AgentErrorCode.invalidInput }
        try validateBudget(maximumBytes)
        guard data.count <= maximumBytes else { throw AgentErrorCode.invalidInput }
        let lease = try acquireLock(lockName)
        try withExtendedLifetime(lease) {
            guard try readUnlocked(name, maximumBytes: maximumBytes) == expected else { throw AgentErrorCode.versionConflict }
            let temporary = ".state-" + UUID().uuidString
            let output = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW_ANY | O_CLOEXEC, mode_t(0o600))
            guard output >= 0 else { throw AgentErrorCode.storageError }
            defer { Darwin.close(output); unlinkat(descriptor, temporary, 0) }
            guard fchmod(output, mode_t(0o600)) == 0 else { throw AgentErrorCode.storageError }
            try AgentPrivateFilePolicy.validate(output, kind: .regular)
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(output, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw AgentErrorCode.storageError }
                    offset += count
                }
            }
            guard fsync(output) == 0 else { throw AgentErrorCode.storageError }
            guard renameat(descriptor, temporary, descriptor, name) == 0 else { throw AgentErrorCode.storageError }
            // Rename can succeed before the final durability check fails.
            guard fsync(descriptor) == 0 else { throw AgentErrorCode.outcomeUnknown }
        }
    }

    package func acquireLock(_ name: String) throws -> AgentStateFileLock {
        try validateName(name)
        try AgentPrivateFilePolicy.validate(descriptor, kind: .directory)
        var file = openat(descriptor, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW_ANY | O_CLOEXEC, mode_t(0o600))
        if file >= 0 {
            guard fchmod(file, mode_t(0o600)) == 0 else { Darwin.close(file); throw AgentErrorCode.storageError }
        } else if errno == EEXIST {
            file = openat(descriptor, name, O_RDWR | O_NONBLOCK | O_NOFOLLOW_ANY | O_CLOEXEC)
        }
        guard file >= 0 else { throw AgentErrorCode.permissionDenied }
        do {
            try AgentPrivateFilePolicy.validate(file, kind: .regular)
            guard flock(file, LOCK_EX | LOCK_NB) == 0 else { throw errno == EWOULDBLOCK ? AgentErrorCode.busy : .storageError }
            return AgentStateFileLock(descriptor: file, directory: self, name: name)
        } catch { Darwin.close(file); throw error }
    }

    // Long-lived owners also check that a held descriptor still names this path.
    package func validateCurrentLocation() throws {
        try AgentPrivateFilePolicy.validate(descriptor, kind: .directory)
        var held = stat(), current = stat()
        guard fstat(descriptor, &held) == 0, lstat(path, &current) == 0,
              current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              held.st_dev == current.st_dev, held.st_ino == current.st_ino else { throw AgentErrorCode.permissionDenied }
    }

    fileprivate func validateLock(_ file: Int32, name: String) throws {
        try validateCurrentLocation()
        try AgentPrivateFilePolicy.validate(file, kind: .regular)
        var held = stat(), current = stat()
        guard fstat(file, &held) == 0, fstatat(descriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_dev == current.st_dev, held.st_ino == current.st_ino else { throw AgentErrorCode.permissionDenied }
    }

    private func readUnlocked(_ name: String, maximumBytes: Int) throws -> Data? {
        try validateName(name)
        let file = openat(descriptor, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW_ANY | O_CLOEXEC)
        if file < 0, errno == ENOENT { return nil }
        guard file >= 0 else { throw AgentErrorCode.permissionDenied }
        defer { Darwin.close(file) }
        try AgentPrivateFilePolicy.validate(file, kind: .regular)
        var info = stat()
        guard fstat(file, &info) == 0, info.st_size >= 0, info.st_size <= maximumBytes else { throw AgentErrorCode.storageError }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress!, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw AgentErrorCode.storageError }
            if count == 0 { return result }
            guard result.count + count <= maximumBytes else { throw AgentErrorCode.storageError }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private func validateName(_ name: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 200,
              name.unicodeScalars.allSatisfy(allowed.contains) else { throw AgentErrorCode.invalidInput }
    }

    private func validateBudget(_ budget: Int) throws {
        guard budget > 0, budget <= AgentRequest.maximumBytes else { throw AgentErrorCode.invalidInput }
    }
}

@MainActor package final class AgentStateFileLock {
    private var descriptor: Int32?
    private let directory: AgentStateDirectory
    private let name: String

    fileprivate init(descriptor: Int32, directory: AgentStateDirectory, name: String) {
        self.descriptor = descriptor; self.directory = directory; self.name = name
    }
    deinit {
        if let descriptor { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
    }
    package func release() {
        guard let descriptor else { return }
        self.descriptor = nil; flock(descriptor, LOCK_UN); Darwin.close(descriptor)
        // Keep the lock file. Unlinking it could split ownership across inodes.
    }
    package func validate() throws {
        guard let descriptor else { throw AgentErrorCode.cancelled }
        try directory.validateLock(descriptor, name: name)
    }
}
