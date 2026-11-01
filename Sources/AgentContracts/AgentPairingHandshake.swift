import Foundation

package enum AgentConnectionName {
    package static func isValid(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 256
            && !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

// Pairing frames never carry credentials, grants or library contents.
package enum AgentPairingHandshake {
    package static let maximumBytes = 4096
    package enum State: String, Codable, Sendable { case pending, approved, denied, cancelled, expired, invalidated, failed }
    package enum Command: String, Codable, Sendable { case poll, cancel }

    package struct Start: Codable, Sendable {
        package let apiVersion: Int
        package let mode: String
        package let clientName: String
        package let expectedLibraryID: UUID?
        package init(clientName: String, expectedLibraryID: UUID? = nil) throws {
            guard AgentConnectionName.isValid(clientName) else { throw AgentErrorCode.invalidInput }
            apiVersion = AgentRequest.version; mode = "pair"; self.clientName = clientName
            self.expectedLibraryID = expectedLibraryID
        }
        package static func decode(_ data: Data) throws -> Self {
            let root = try fields(data, allowed: ["apiVersion", "mode", "clientName", "expectedLibraryID"])
            if let expected = root["expectedLibraryID"] {
                guard case .string(let text) = expected, UUID(uuidString: text) != nil else { throw AgentErrorCode.invalidInput }
            }
            guard let value = try? JSONDecoder().decode(Self.self, from: data), value.mode == "pair",
                  AgentConnectionName.isValid(value.clientName) else { throw AgentErrorCode.invalidInput }
            return value
        }
    }

    package enum Introduction: Sendable {
        case authenticate(AgentLocalHandshake.Hello)
        case pair(Start)
        package static func decode(_ data: Data) throws -> Self {
            guard data.count <= maximumBytes,
                  case .object(let root) = try? JSONDecoder().decode(AgentJSONValue.self, from: data) else {
                throw AgentErrorCode.invalidInput
            }
            if root["mode"] != nil { return .pair(try Start.decode(data)) }
            return .authenticate(try AgentLocalHandshake.Hello.decode(data))
        }
    }

    package struct Control: Codable, Sendable {
        package let apiVersion: Int
        package let pairingID: UUID
        package let command: Command
        package init(pairingID: UUID, command: Command) {
            apiVersion = AgentRequest.version; self.pairingID = pairingID; self.command = command
        }
        package static func decode(_ data: Data) throws -> Self {
            try fields(data, required: ["apiVersion", "pairingID", "command"])
            guard let value = try? JSONDecoder().decode(Self.self, from: data) else { throw AgentErrorCode.invalidInput }
            return value
        }
    }

    package struct Reply: Codable, Sendable {
        package let apiVersion: Int
        package let pairingID: UUID?
        package let code: String?
        // Seconds since the Unix epoch, used only to show the deadline.
        package let expiresAt: TimeInterval?
        package let libraryID: UUID?
        package let state: State?
        package let connectionID: UUID?
        package let error: AgentErrorCode?

        package init(pairingID: UUID, code: String, expiresAt: Date, libraryID: UUID? = nil) {
            apiVersion = AgentRequest.version; self.pairingID = pairingID; self.code = code
            self.expiresAt = expiresAt.timeIntervalSince1970; self.libraryID = libraryID; state = nil; connectionID = nil; error = nil
        }
        package init(pairingID: UUID, state: State, connectionID: UUID? = nil, error: AgentErrorCode? = nil) {
            apiVersion = AgentRequest.version; self.pairingID = pairingID; self.state = state
            self.connectionID = connectionID; self.error = error; code = nil; expiresAt = nil; libraryID = nil
        }
        package init(error: AgentErrorCode) {
            apiVersion = AgentRequest.version; self.error = error
            pairingID = nil; code = nil; expiresAt = nil; state = nil; connectionID = nil; libraryID = nil
        }

        package static func decode(_ data: Data) throws -> Self {
            let root = try fields(data, allowed: ["apiVersion", "pairingID", "code", "expiresAt", "libraryID", "state", "connectionID", "error"])
            guard let value = try? JSONDecoder().decode(Self.self, from: data) else { throw AgentErrorCode.invalidInput }
            let keys = Set(root.keys)
            if keys == ["apiVersion", "error"], value.error != nil { return value }
            let challengeKeys: Set<String> = ["apiVersion", "pairingID", "code", "expiresAt"]
            if (keys == challengeKeys || keys == challengeKeys.union(["libraryID"])),
               (root["libraryID"] == nil || value.libraryID != nil), value.pairingID != nil,
               let code = value.code, UUID(uuidString: code) != nil,
               let expiry = value.expiresAt, expiry.isFinite { return value }
            guard value.pairingID != nil, let state = value.state else { throw AgentErrorCode.invalidInput }
            switch state {
            case .approved:
                guard keys == ["apiVersion", "pairingID", "state", "connectionID"], value.connectionID != nil else { throw AgentErrorCode.invalidInput }
            case .failed:
                guard keys == ["apiVersion", "pairingID", "state", "error"], value.error != nil else { throw AgentErrorCode.invalidInput }
            default:
                guard keys == ["apiVersion", "pairingID", "state"] else { throw AgentErrorCode.invalidInput }
            }
            return value
        }
    }

    package static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw AgentErrorCode.invalidInput }
        return data
    }

    @discardableResult private static func fields(_ data: Data, required: Set<String>? = nil,
        allowed: Set<String>? = nil) throws -> [String: AgentJSONValue] {
        guard data.count <= maximumBytes,
              case .object(let root) = try? JSONDecoder().decode(AgentJSONValue.self, from: data),
              root["apiVersion"] == .integer(Int64(AgentRequest.version)),
              required.map({ Set(root.keys) == $0 }) ?? true,
              allowed.map({ Set(root.keys).isSubset(of: $0) }) ?? true else { throw AgentErrorCode.invalidInput }
        return root
    }
}
