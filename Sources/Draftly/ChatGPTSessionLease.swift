import Foundation
import Darwin

/// A device-local lock. This file never contains credentials.
final class ChatGPTSessionLease {
    enum Failure: Error { case busy, unavailable }
    private let descriptor: Int32

    init(accountID: UUID, directory: URL? = nil) throws {
        let bundle = Bundle.main.bundleIdentifier ?? "com.pobrespandas.draftly"
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundle).appendingPathComponent("ChatGPT/Sessions")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let path = root.resolvingSymlinksInPath().appendingPathComponent(accountID.uuidString.lowercased() + ".lock").path
        var parent = stat()
        guard lstat(root.resolvingSymlinksInPath().path, &parent) == 0,
              parent.st_uid == getuid(), parent.st_mode & 0o077 == 0,
              parent.st_mode & S_IFMT == S_IFDIR else { throw Failure.unavailable }
        let file = Darwin.open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard file >= 0 else { throw Failure.unavailable }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0 else {
            Darwin.close(file); throw Failure.unavailable
        }
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else {
            let busy = errno == EWOULDBLOCK
            Darwin.close(file)
            throw busy ? Failure.busy : Failure.unavailable
        }
        descriptor = file
    }

    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
