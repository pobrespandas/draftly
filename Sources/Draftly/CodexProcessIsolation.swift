import Foundation
import Darwin

struct CodexLaunchPlan {
    let executable: URL
    let arguments: [String]
}

enum CodexProcessIsolation {
    static func launch(executable: URL, home: URL) throws -> CodexLaunchPlan {
        let executable = try canonicalURL(executable)
        let home = try canonicalURL(home)
        let handle = try FileHandle(forReadingFrom: executable)
        defer { try? handle.close() }
        let magic = Array(try handle.read(upToCount: 4) ?? Data())
        guard [[0xcf, 0xfa, 0xed, 0xfe], [0xfe, 0xed, 0xfa, 0xcf],
               [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
               [0xca, 0xfe, 0xba, 0xbf], [0xbf, 0xba, 0xfe, 0xca]].contains(magic) else {
            throw CodexConnectionError.remote("Choose the native Codex executable. Script launchers are not supported.")
        }
        return CodexLaunchPlan(executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: ["-p", try profile(executable: executable, home: home), executable.path, "app-server", "--listen", "stdio://",
                        "-c", "cli_auth_credentials_store=\"keyring\"",
                        "-c", "features.shell_tool=false", "-c", "features.shell_snapshot=false",
                        "-c", "agents.enabled=false", "-c", "features.multi_agent_v2=false",
                        "-c", "web_search=\"disabled\""])
    }

    static func profile(executable: URL, home: URL) throws -> String {
        let executable = try canonicalURL(executable)
        let home = try canonicalURL(home)
        let roots = ["/System/Library", "/System/Cryptexes", "/usr/lib", "/usr/share", "/usr/bin", "/usr/libexec",
                     "/bin", "/sbin", "/private/etc", "/private/preboot", "/dev", home.path]
        let exclusions = try roots.map { "(require-not (subpath \(try quoted($0))))" }.joined(separator: " ")
        // Directory metadata stays available. Content reads and writes have explicit limits.
        return """
        (version 1)
        (allow default)
        (deny file-read-data (require-all (require-not (literal "/")) (require-not (literal \(try quoted(executable.path)))) \(exclusions)))
        (deny file-write* (require-not (subpath \(try quoted(home.path)))))
        (deny process-exec (require-not (literal \(try quoted(executable.path)))))
        """
    }

    private static func quoted(_ value: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value,
            options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
    }

    private static func canonicalURL(_ value: URL) throws -> URL {
        guard let path = realpath(value.path, nil) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL) }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
    }
}
