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
            print("json reads a full request from stdin. call reads targets and parameters, using shared tool schemas.")
            print("Local access requires approval in Draftly. Never put credentials in arguments or configuration.")
            return
        }
        if args == ["--version"] { print("draftly-agent protocol 1; MCP baseline 2025-11-25"); return }
        let isMCP = args.first == "mcp"
        do {
            guard let mode = args.first, ["json", "status", "capabilities", "call", "mcp"].contains(mode) else { throw AgentErrorCode.invalidInput }
            let offset = mode == "call" ? 2 : 1
            guard args.count == offset + 4, args[offset] == "--connection", let id = UUID(uuidString: args[offset + 1]),
                  args[offset + 2] == "--socket" else { throw AgentErrorCode.invalidInput }
            let path = args[offset + 3], store = AgentCredentialKeychain(role: .helper)
            let connection = AgentHelperConnection(connect: {
                guard let credential = try await store.read(id) else { throw AgentErrorCode.permissionDenied }
                return try await AgentLocalClient.connect(path: path, connectionID: id, credential: credential,
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
            let code = (error as? AgentErrorCode) ?? (error is DecodingError ? .invalidInput : .unavailable)
            if isMCP {
                try? FileHandle.standardError.write(contentsOf: Data((code.rawValue + "\n").utf8))
            } else if let data = try? JSONEncoder().encode(AgentJSONValue.object(["error": .string(code.rawValue)])) {
                try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
            }
            exit(AgentCLIStatus.exitCode(code))
        }
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
