import Foundation
import Darwin
import AgentContracts
import AgentLocalSecurity
import AgentLocalTransport

@main struct DraftlyAgentMain {
    @MainActor static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] {
            print("Usage: draftly-agent json --connection UUID --socket ABSOLUTE_PATH < request.json")
            print("Local access requires a connection approved in Draftly. No credential belongs in arguments.")
            return
        }
        if args == ["--version"] { print("draftly-agent protocol 1"); return }
        do {
            guard args.count == 5, args[0] == "json", args[1] == "--connection", let id = UUID(uuidString: args[2]),
                  args[3] == "--socket" else { throw AgentErrorCode.invalidInput }
            var request = Data()
            while let part = try FileHandle.standardInput.read(upToCount: 65_536), !part.isEmpty {
                guard request.count + part.count <= AgentRequest.maximumBytes else { throw AgentErrorCode.invalidInput }
                request.append(part)
            }
            _ = try AgentRequest.decode(request)
            let store = AgentCredentialKeychain(role: .helper)
            guard let credential = try store.read(id) else { throw AgentErrorCode.permissionDenied }
            let client = try await AgentLocalClient.connect(path: args[4], connectionID: id, credential: credential,
                validateServer: { try AgentPeerIdentity.validate($0, role: .application) })
            do {
                let result = try await client.request(request)
                await client.close()
                let response = try JSONDecoder().decode(AgentResponse.self, from: result)
                try FileHandle.standardOutput.write(contentsOf: result + Data([10]))
                if case .error = response.outcome { exit(1) }
            } catch { await client.close(); throw error }
        } catch {
            let code = (error as? AgentErrorCode) ?? .unavailable
            let value = AgentJSONValue.object(["error": .string(code.rawValue)])
            if let data = try? JSONEncoder().encode(value) { try? FileHandle.standardOutput.write(contentsOf: data + Data([10])) }
            exit(1)
        }
    }
}
