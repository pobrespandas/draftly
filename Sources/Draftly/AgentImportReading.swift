import Foundation
import Darwin
import AgentContracts

// Local input stays within a saved directory and the connection's resource scope.
@MainActor enum AgentImportReading {
    struct Snapshot {
        let data: Data
        let filePermission: Data?
    }
    static func data(_ source: AgentJSONValue, grant: AgentGrant, defaults: UserDefaults,
                     transfers: AgentTransferStore, maximumBytes: Int,
                     authorize: () throws -> Void) throws -> Data {
        try snapshot(source, grant: grant, defaults: defaults, transfers: transfers,
                     maximumBytes: maximumBytes, captureFilePermission: false, authorize: authorize).data
    }
    static func snapshot(_ source: AgentJSONValue, grant: AgentGrant, defaults: UserDefaults,
                     transfers: AgentTransferStore, maximumBytes: Int, captureFilePermission: Bool,
                     authorize: () throws -> Void) throws -> Snapshot {
        guard maximumBytes > 0, maximumBytes <= AgentTransferSchemas.maximumBytes else { throw AgentErrorCode.invalidInput }
        try Task.checkCancellation(); try authorize()
        let kind = try AgentImportSource.validate(source)
        guard case .object(let fields) = source else { throw AgentErrorCode.invalidInput }
        let data: Data
        var filePermission: Data?
        guard !captureFilePermission || kind == "bookmark" else { throw AgentErrorCode.invalidInput }
        switch kind {
        case "inline":
            guard case .string(let text) = fields["text"], text.utf8.count <= maximumBytes else { throw AgentErrorCode.invalidInput }
            data = Data(text.utf8)
        case "transfer":
            guard case .string(let raw) = fields["transferID"], let id = UUID(uuidString: raw) else { throw AgentErrorCode.invalidInput }
            data = try transfers.importedData(id, grant: grant)
        case "bookmark":
            guard grant.capabilities.contains(.filesRead), case .string(let raw) = fields["bookmarkID"],
                  let id = UUID(uuidString: raw), grant.scope.permits(.init(kind: .bookmark, id: id)),
                  case .string(let path) = fields["path"] else { throw AgentErrorCode.permissionDenied }
            let snapshot = try withBookmark(id, defaults: defaults, authorize: authorize) { root, check in
                try read(path, under: root, limit: maximumBytes, captureFilePermission: captureFilePermission, authorize: check)
            }
            data = snapshot.data; filePermission = snapshot.filePermission
        case "https": throw AgentErrorCode.interactionRequired
        default: throw AgentErrorCode.invalidInput
        }
        guard data.count <= maximumBytes else { throw AgentErrorCode.invalidInput }
        try Task.checkCancellation(); try authorize()
        return Snapshot(data: data, filePermission: filePermission)
    }

    static func readText(_ path: String, bookmarkID: UUID, defaults: UserDefaults,
                         authorize: () throws -> Void) throws -> String {
        let snapshot = try withBookmark(bookmarkID, defaults: defaults, authorize: authorize) { root, check in
            try read(path, under: root, limit: 65_536, captureFilePermission: false, authorize: check)
        }
        guard let text = String(data: snapshot.data, encoding: .utf8) else { throw AgentErrorCode.invalidInput }
        return text
    }

    static func writeText(_ text: String, path: String, bookmarkID: UUID, defaults: UserDefaults,
                          authorize: () throws -> Void, beforePublish: () throws -> Void) throws {
        let bytes = Data(text.utf8)
        guard bytes.count <= 65_536, AgentImportSource.isRelativePath(path) else { throw AgentErrorCode.invalidInput }
        try withBookmark(bookmarkID, defaults: defaults, authorize: authorize) { root, check in
            var components = path.split(separator: "/", omittingEmptySubsequences: false)
            let name = String(components.removeLast())
            var descriptor = try openRoot(root, authorize: check)
            defer { Darwin.close(descriptor) }
            for component in components {
                try check()
                let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
                guard next >= 0 else { throw AgentErrorCode.permissionDenied }
                Darwin.close(descriptor)
                descriptor = next
            }
            var status = stat()
            guard fstatat(descriptor, name, &status, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                throw AgentErrorCode.versionConflict
            }
            let temporary = ".draftly-write-" + UUID().uuidString
            let output = openat(descriptor, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW_ANY | O_CLOEXEC, 0o600)
            guard output >= 0 else { throw AgentErrorCode.storageError }
            let handle = FileHandle(fileDescriptor: output, closeOnDealloc: true)
            defer { try? handle.close(); unlinkat(descriptor, temporary, 0) }
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
            try check()
            try beforePublish()
            guard renameatx_np(descriptor, temporary, descriptor, name, UInt32(RENAME_EXCL)) == 0,
                  fsync(descriptor) == 0 else { throw AgentErrorCode.outcomeUnknown }
        }
    }

    private static func withBookmark<T>(_ id: UUID, defaults: UserDefaults, authorize: () throws -> Void,
                                        use: (URL, () throws -> Void) throws -> T) throws -> T {
        try Task.checkCancellation(); try authorize()
        guard let record = try BookmarkPreferences.agentRecords(defaults: defaults).first(where: { $0.id == id }) else {
            throw AgentErrorCode.notFound
        }
        var stale = false
        let root: URL
        do { root = try URL(resolvingBookmarkData: record.data, options: [.withSecurityScope, .withoutUI],
                            relativeTo: nil, bookmarkDataIsStale: &stale) }
        catch { throw AgentErrorCode.permissionDenied }
        guard root.isFileURL else { throw AgentErrorCode.permissionDenied }
        let active = root.startAccessingSecurityScopedResource()
        defer { if active { root.stopAccessingSecurityScopedResource() } }
        return try withoutActuallyEscaping(authorize) { authorize in
            func check() throws {
                try Task.checkCancellation(); try authorize()
                guard try BookmarkPreferences.agentRecords(defaults: defaults).contains(where: { $0.id == id && $0.data == record.data }) else {
                    throw AgentErrorCode.permissionDenied
                }
            }
            let result = try use(root, check)
            try check()
            return result
        }
    }

    private static func openRoot(_ root: URL, authorize: () throws -> Void) throws -> Int32 {
        // Resolve the granted root once. Descendants never follow a symbolic link.
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR else {
            throw AgentErrorCode.permissionDenied
        }
        try Task.checkCancellation(); try authorize()
        guard let physical = realpath(root.path, nil) else { throw AgentErrorCode.permissionDenied }
        defer { free(physical) }
        let descriptor = Darwin.open(physical, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AgentErrorCode.permissionDenied }
        var openedRoot = stat()
        guard fstat(descriptor, &openedRoot) == 0, rootInfo.st_dev == openedRoot.st_dev,
              rootInfo.st_ino == openedRoot.st_ino else { Darwin.close(descriptor); throw AgentErrorCode.versionConflict }
        return descriptor
    }

    private static func read(_ path: String, under root: URL, limit: Int, captureFilePermission: Bool, authorize: () throws -> Void) throws -> Snapshot {
        guard AgentImportSource.isRelativePath(path) else { throw AgentErrorCode.invalidInput }
        var descriptor = try openRoot(root, authorize: authorize)
        defer { Darwin.close(descriptor) }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        for (index, component) in components.enumerated() {
            try Task.checkCancellation(); try authorize()
            let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (index == components.count - 1 ? 0 : O_DIRECTORY)
            let next = Darwin.openat(descriptor, String(component), flags)
            guard next >= 0 else { throw AgentErrorCode.permissionDenied }
            Darwin.close(descriptor); descriptor = next
        }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1 else { throw AgentErrorCode.permissionDenied }
        guard before.st_size >= 0, before.st_size <= limit else { throw AgentErrorCode.invalidInput }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        var data = Data()
        while data.count <= limit {
            try Task.checkCancellation(); try authorize()
            let bytes = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)) ?? Data()
            if bytes.isEmpty { break }
            data.append(bytes)
        }
        guard data.count <= limit else { throw AgentErrorCode.invalidInput }
        var after = stat()
        guard fstat(descriptor, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw AgentErrorCode.versionConflict
        }
        var permission: Data?
        if captureFilePermission {
            try Task.checkCancellation(); try authorize()
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard fcntl(descriptor, F_GETPATH, &pathBuffer) == 0,
                  let end = pathBuffer.firstIndex(of: 0),
                  let path = String(validating: pathBuffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self) else {
                throw AgentErrorCode.permissionDenied
            }
            let file = URL(fileURLWithPath: path)
            let bookmark = try file.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            var stale = false
            let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = resolved.startAccessingSecurityScopedResource()
            defer { if access { resolved.stopAccessingSecurityScopedResource() } }
            guard let physical = realpath(resolved.path, nil) else { throw AgentErrorCode.permissionDenied }
            defer { free(physical) }
            let checked = Darwin.open(physical, O_RDONLY | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC)
            guard checked >= 0 else { throw AgentErrorCode.permissionDenied }
            defer { Darwin.close(checked) }
            var info = stat()
            guard fstat(checked, &info) == 0, info.st_dev == before.st_dev, info.st_ino == before.st_ino,
                  info.st_size == before.st_size,
                  info.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec,
                  info.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec else {
                throw AgentErrorCode.versionConflict
            }
            permission = bookmark
        }
        return Snapshot(data: data, filePermission: permission)
    }
}
