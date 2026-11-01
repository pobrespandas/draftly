import Foundation
import Darwin
import AgentContracts
import AgentLocalSecurity
import AgentLocalTransport
import AgentMCP

@main struct DraftlyAgentMain {
    @MainActor static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        _ = fcntl(STDOUT_FILENO, F_SETNOSIGPIPE, 1)
        if args == ["--help"] {
            print("Usage: draftly-agent {json|status|capabilities|mcp} --connection UUID --socket ABSOLUTE_PATH")
            print("       draftly-agent call OPERATION --connection UUID --socket ABSOLUTE_PATH < arguments.json")
            print("       draftly-agent connect --name CLIENT_NAME --socket ABSOLUTE_PATH")
            print("       draftly-agent discover [--state-parent ABSOLUTE_PATH]")
            print("Replace --socket PATH with --library UUID [--state-parent ABSOLUTE_PATH] for stable library selection.")
            print("json reads a full request from stdin. call reads targets and parameters, using shared tool schemas.")
            print("Local access requires approval in Draftly. Never put credentials in arguments or configuration.")
            return
        }
        if args == ["--version"] { print("draftly-agent protocol 1; MCP baseline 2025-11-25"); return }
        let isMCP = args.first == "mcp"
        do {
            if args.first == "discover" { try discover(args); return }
            if args.first == "connect" { try await pair(args); return }
            guard let mode = args.first, ["json", "status", "capabilities", "call", "mcp"].contains(mode) else { throw AgentErrorCode.invalidInput }
            let offset = mode == "call" ? 2 : 1
            guard (args.count == offset + 4 || args.count == offset + 6), args[offset] == "--connection",
                  let id = UUID(uuidString: args[offset + 1]) else { throw AgentErrorCode.invalidInput }
            let destination = try AgentHostDestination(cliArguments: Array(args.dropFirst(offset + 2)))
            let store = AgentCredentialKeychain(role: .helper)
            let connection = AgentHelperConnection(connect: {
                guard let credential = try await store.read(id) else { throw AgentErrorCode.permissionDenied }
                return try await destination.connect(connectionID: id, credential: credential,
                    validateServer: { try AgentPeerIdentity.validate($0, role: .application) })
            })
            if isMCP {
                let bridge = AgentMCPServer(backend: { try await connection.request($0) })
                let server = await bridge.makeServer()
                let transport = try AgentMCPStdioTransport(input: STDIN_FILENO, output: STDOUT_FILENO)
                do {
                    try await server.start(transport: transport)
                    await server.waitUntilCompleted()
                    let failure = await transport.terminalFailure()
                    await server.stop(); await connection.close()
                    if let failure { throw failure }
                } catch { await server.stop(); await connection.close(); throw error }
                return
            }
            let request: AgentRequest
            if mode == "json" { request = try AgentRequest.decode(readInput()) }
            else if mode == "call" {
                guard let operation = AgentOperationCatalog.operation(named: args[1]),
                      case .object(let arguments) = try JSONDecoder().decode(AgentJSONValue.self, from: readInput()) else {
                    throw AgentErrorCode.invalidInput
                }
                request = try AgentToolInput.request(operation: operation, arguments: arguments)
            } else {
                request = AgentRequest(requestID: UUID(), libraryID: nil, operation: mode == "status" ? "server.status" : "server.capabilities")
            }
            do {
                let result = try await connection.request(request)
                await connection.close()
                try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(result) + Data([10]))
                if case .error(let error) = result.outcome { exit(AgentCLIStatus.exitCode(error)) }
            } catch { await connection.close(); throw error }
        } catch {
            let code = (error as? AgentErrorCode) ?? (error is CancellationError ? .cancelled : error is DecodingError ? .invalidInput : .unavailable)
            if isMCP {
                try? FileHandle.standardError.write(contentsOf: Data((code.rawValue + "\n").utf8))
            } else if let data = try? JSONEncoder().encode(AgentJSONValue.object(["error": .string(code.rawValue)])) {
                try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
            }
            exit(AgentCLIStatus.exitCode(code))
        }
    }

    @MainActor private static func discover(_ args: [String]) throws {
        guard args.count == 1 || (args.count == 3 && args[1] == "--state-parent") else { throw AgentErrorCode.invalidInput }
        let parent = try AgentHostDestination.stateParentDirectory(args.count == 3 ? args[2] : nil)
        try AgentCredentialIdentity.validateCurrentProcess(.helper)
        let endpoints: [AgentHostLocator.Endpoint]
        do { endpoints = try AgentHostLocator(parentDirectory: parent).endpoints() }
        catch AgentErrorCode.notFound { endpoints = [] }
        // Stale hints are possible. Only a signed, authenticated socket can prove
        // that a discovered host is available to this connection.
        try FileHandle.standardOutput.write(contentsOf: JSONEncoder().encode(endpoints) + Data([10]))
    }

    @MainActor private static func pair(_ args: [String]) async throws {
        guard args.count >= 3, args[1] == "--name" else { throw AgentErrorCode.invalidInput }
        let destination = try AgentHostDestination(cliArguments: Array(args.dropFirst(3)))
        _ = try AgentPairingHandshake.encode(AgentPairingHandshake.Start(clientName: args[2]))
        // Verify this helper before asking the app to show any pairing request.
        try AgentCredentialIdentity.validateCurrentProcess(.helper)
        let client = try await destination.pair(name: args[2],
            validateServer: { try AgentPeerIdentity.validate($0, role: .application) })
        do {
            let challenge = await client.challenge
            guard let code = challenge.code else { throw AgentErrorCode.invalidInput }
            try FileHandle.standardError.write(contentsOf: Data(("Compare this code with the request shown by Draftly: " + code + "\n").utf8))
            let reply = try await client.waitForDecision()
            switch reply.state {
            case .approved:
                try FileHandle.standardOutput.write(contentsOf: AgentPairingHandshake.encode(reply) + Data([10]))
                await client.close()
            case .cancelled: throw AgentErrorCode.cancelled
            case .expired: throw AgentErrorCode.timeout
            case .failed: throw reply.error ?? AgentErrorCode.storageError
            case .denied, .invalidated: throw AgentErrorCode.permissionDenied
            case .pending, nil: throw AgentErrorCode.invalidInput
            }
        } catch { await client.close(); throw error }
    }

    private static func readInput() throws -> Data {
        var data = Data()
        while let part = try FileHandle.standardInput.read(upToCount: 65_536), !part.isEmpty {
            guard data.count + part.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.invalidInput }
            data.append(part)
        }
        return data
    }
}
