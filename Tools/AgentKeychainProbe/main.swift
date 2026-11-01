import Foundation
import CryptoKit
import Darwin
import AgentContracts
import AgentLocalSecurity

// Manual signed acceptance only. This program never enumerates Keychain items.
@main struct AgentKeychainProbe {
    @MainActor static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.count == 2, args[0] == "read", let id = UUID(uuidString: args[1]) {
                let expected = try readCredential()
                guard try AgentCredentialKeychain(role: .helper).read(id) == expected else {
                    throw AgentErrorCode.permissionDenied
                }
                print("matched")
            } else if args.count == 2, args[0] == "exercise", args[1].hasPrefix("/") {
                try exercise(helper: args[1])
                print("Signed adapter sharing and cleanup passed.")
            } else { throw AgentErrorCode.invalidInput }
        } catch {
            let code = error as? AgentErrorCode ?? .executionError
            FileHandle.standardError.write(Data((code.rawValue + "\n").utf8))
            exit(1)
        }
    }

    private static func readCredential() throws -> Data {
        let value = try FileHandle.standardInput.read(upToCount: 33) ?? Data()
        guard value.count == 32 else { throw AgentErrorCode.invalidInput }
        return value
    }

    @MainActor private static func exercise(helper: String) throws {
        let store = AgentCredentialKeychain(role: .application)
        let id = UUID(), value = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try store.create(id, credential: value)
        do {
            guard try store.read(id) == value else { throw AgentErrorCode.storageError }
            let input = Pipe(), output = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: helper)
            process.arguments = ["read", id.uuidString]
            process.standardInput = input; process.standardOutput = output
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: value)
            try input.fileHandleForWriting.close()
            let reply = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, reply == Data("matched\n".utf8) else {
                throw AgentErrorCode.permissionDenied
            }
        } catch {
            do { try store.remove(id) }
            catch {
                FileHandle.standardError.write(Data(("Cleanup failed for neutral connection " + id.uuidString + "\n").utf8))
                throw error
            }
            throw error
        }
        try store.remove(id)
        guard try store.read(id) == nil else { throw AgentErrorCode.storageError }
    }
}
