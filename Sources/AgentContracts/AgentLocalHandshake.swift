import Foundation

package enum AgentLocalHandshake {
    package static let maximumBytes = 1024

    package struct Hello: Codable, Sendable {
        package let apiVersion: Int
        package let connectionID: UUID
        package let credential: Data
        package let expectedLibraryID: UUID?

        package init(connectionID: UUID, credential: Data, expectedLibraryID: UUID? = nil) throws {
            guard credential.count == 32 else { throw AgentErrorCode.invalidInput }
            self.apiVersion = AgentRequest.version; self.connectionID = connectionID; self.credential = credential
            self.expectedLibraryID = expectedLibraryID
        }

        package static func decode(_ data: Data) throws -> Self {
            let root = try keys(data, required: ["apiVersion", "connectionID", "credential"], optional: ["expectedLibraryID"])
            if let expected = root["expectedLibraryID"] {
                guard let text = expected as? String, UUID(uuidString: text) != nil else { throw AgentErrorCode.invalidInput }
            }
            do {
                let value = try JSONDecoder().decode(Self.self, from: data)
                guard value.apiVersion == AgentRequest.version, value.credential.count == 32 else { throw AgentErrorCode.invalidInput }
                return value
            } catch { throw AgentErrorCode.invalidInput }
        }
    }

    package struct Welcome: Codable, Sendable {
        package let apiVersion: Int
        package let libraryID: UUID?
        package let error: AgentErrorCode?

        package init(libraryID: UUID) { apiVersion = AgentRequest.version; self.libraryID = libraryID; error = nil }
        package init(error: AgentErrorCode) { apiVersion = AgentRequest.version; libraryID = nil; self.error = error }

        package static func decode(_ data: Data) throws -> Self {
            guard data.count <= maximumBytes,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(root.keys) == ["apiVersion", "libraryID"] || Set(root.keys) == ["apiVersion", "error"] else {
                throw AgentErrorCode.invalidInput
            }
            do {
                let value = try JSONDecoder().decode(Self.self, from: data)
                guard value.apiVersion == AgentRequest.version, (value.libraryID == nil) != (value.error == nil) else {
                    throw AgentErrorCode.invalidInput
                }
                return value
            } catch { throw AgentErrorCode.invalidInput }
        }
    }

    private static func keys(_ data: Data, required: Set<String>, optional: Set<String> = []) throws -> [String: Any] {
        guard data.count <= maximumBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSuperset(of: required), Set(root.keys).isSubset(of: required.union(optional)) else {
            throw AgentErrorCode.invalidInput
        }
        return root
    }
}
