import Foundation
import Darwin
import AgentContracts

package enum AgentPrivateFilePolicy {
    package enum Kind { case directory, regular }

    package static func validate(_ descriptor: Int32, kind: Kind) throws {
        var info = stat()
        let isDirectory = kind == .directory
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(isDirectory ? S_IFDIR : S_IFREG),
              info.st_mode & mode_t(0o777) == mode_t(isDirectory ? 0o700 : 0o600),
              isDirectory || info.st_nlink == 1 else { throw AgentErrorCode.permissionDenied }
        try validateACL(descriptor)
    }

    package static func validateTrustedParent(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & mode_t(0o022) == 0 else { throw AgentErrorCode.permissionDenied }
        try validateACL(descriptor)
    }

    package static func validateSocket(_ path: String) throws -> (device: dev_t, inode: ino_t) {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == geteuid(), info.st_nlink == 1,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK),
              info.st_mode & mode_t(0o777) == mode_t(0o600) else { throw AgentErrorCode.permissionDenied }
        try validate(acl_get_link_np(path, ACL_TYPE_EXTENDED))
        return (info.st_dev, info.st_ino)
    }

    private static func validateACL(_ descriptor: Int32) throws { try validate(acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED)) }

    private static func validate(_ acl: acl_t?) throws {
        guard let acl else {
            // Darwin uses ENOENT for no extended ACL on a valid descriptor or path.
            if errno == ENOENT { return }
            throw AgentErrorCode.permissionDenied
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?, position = ACL_FIRST_ENTRY
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
