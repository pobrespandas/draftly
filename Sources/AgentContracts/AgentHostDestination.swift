import Foundation

// A connection destination, not a grant. CLI formatting stays pure so client
// configuration can use the same argument contract without filesystem access.
package enum AgentHostDestination: Equatable, Sendable {
    case socket(String)
    case library(UUID, stateParent: String?)

    package init(cliArguments args: [String]) throws {
        guard args.count == 2 || args.count == 4 else { throw AgentErrorCode.invalidInput }
        if args[0] == "--socket", args.count == 2 {
            guard Self.absolutePath(args[1]) else { throw AgentErrorCode.invalidInput }
            self = .socket(args[1]); return
        }
        guard args[0] == "--library", let id = UUID(uuidString: args[1]) else { throw AgentErrorCode.invalidInput }
        if args.count == 4 {
            guard args[2] == "--state-parent", Self.absolutePath(args[3]) else { throw AgentErrorCode.invalidInput }
            self = .library(id, stateParent: args[3])
        } else { self = .library(id, stateParent: nil) }
    }

    package var cliArguments: [String] {
        switch self {
        case .socket(let path): ["--socket", path]
        case .library(let id, let parent): ["--library", id.uuidString] + (parent.map { ["--state-parent", $0] } ?? [])
        }
    }

    package static func absolutePath(_ path: String) -> Bool { path.hasPrefix("/") && !path.utf8.contains(0) }
}
