import Foundation

// A named tool cannot change its operation, library or authority.
package enum AgentToolInput {
    package static func name(for operation: String) -> String { "draftly_" + operation.replacingOccurrences(of: ".", with: "_") }
    package static func operation(named tool: String) -> AgentOperationDescriptor? {
        AgentOperationCatalog.operations.first { name(for: $0.name) == tool }
    }

    package static func schema(for operation: AgentOperationDescriptor, parameters: AgentJSONValue) -> AgentJSONValue {
        guard case .object(var root) = shape(operation).jsonSchema, case .object(var properties) = root["properties"] else { return .null }
        properties["parameters"] = parameters
        if case .object(var exact) = properties["parametersJSON"] {
            exact["description"] = .string("Use JSON object text instead of parameters when exact decimal values are needed. Do not supply both.")
            properties["parametersJSON"] = .object(exact)
        }
        if ["drafts.archive", "drafts.trash", "drafts.restore", "drafts.flag", "drafts.tags", "drafts.syntax", "drafts.merge"].contains(operation.name),
           case .object(var field) = properties["expectedVersion"] {
            field["description"] = .string("For one draft use its versionToken. For all drafts in one list or search page use that page's batchVersion. Read again after any change. Never reuse a page token for a subset or another target set.")
            properties["expectedVersion"] = .object(field)
        }
        root["properties"] = .object(properties)
        root["not"] = .object(["required": .array([.string("parameters"), .string("parametersJSON")])])
        return .object(root)
    }

    package static func request(operation: AgentOperationDescriptor, arguments: [String: AgentJSONValue]) throws -> AgentRequest {
        do {
            let values = try shape(operation).applyingDefaults(to: arguments)
            guard !(values["parameters"] != nil && values["parametersJSON"] != nil) else { throw AgentErrorCode.invalidInput }
            let parameters: [String: AgentJSONValue]
            if case .string(let text) = values["parametersJSON"] {
                guard text.utf8.count <= AgentRequest.maximumBytes,
                      case .object(let object) = try JSONDecoder().decode(AgentJSONValue.self, from: Data(text.utf8)) else {
                    throw AgentErrorCode.invalidInput
                }
                parameters = object
            } else if case .object(let object) = values["parameters"] { parameters = object }
            else { parameters = [:] }
            let targetValues: [AgentJSONValue]
            if case .array(let array) = values["targets"] { targetValues = array } else { targetValues = [] }
            let targets = try targetValues.map { value -> AgentResourceReference in
                guard case .object(let fields) = value, case .string(let kind) = fields["kind"],
                      let type = AgentResourceKind(rawValue: kind), case .string(let id) = fields["id"], let uuid = UUID(uuidString: id) else {
                    throw AgentErrorCode.invalidInput
                }
                return .init(kind: type, id: uuid)
            }
            guard operation.acceptsTargets(targets) else { throw AgentErrorCode.invalidInput }
            var requestID = UUID(), expectedVersion: String?, retryKey: String?
            if case .string(let text) = values["requestID"], let id = UUID(uuidString: text) { requestID = id }
            if case .string(let text) = values["expectedVersion"] { expectedVersion = text }
            if case .string(let text) = values["retryKey"] {
                guard text.utf8.count <= AgentRequest.maximumRetryKeyBytes else { throw AgentErrorCode.invalidInput }
                retryKey = text
            }
            return AgentRequest(requestID: requestID, libraryID: nil, operation: operation.name,
                                targets: targets, expectedVersion: expectedVersion, retryKey: retryKey, parameters: parameters)
        } catch { throw AgentErrorCode.invalidInput }
    }

    private static func shape(_ operation: AgentOperationDescriptor) -> AgentObjectShape {
        let kinds: [AgentResourceKind], minimum: Int, maximum: Int
        switch operation.targets {
        case .none: kinds = []; minimum = 0; maximum = 0
        case .one(let kind): kinds = [kind]; minimum = 1; maximum = 1
        case .many(let kind): kinds = [kind]; minimum = 1; maximum = AgentRequest.maximumTargets
        case .pair(let first, let second): kinds = [first, second]; minimum = 2; maximum = 2
        }
        let target = AgentObjectShape(fields: ["kind": .init(shape: .string(choices: (kinds.isEmpty ? AgentResourceKind.allCases : kinds).map(\.rawValue)), required: true),
            "id": .init(shape: .uuid, required: true)])
        var fields: [String: AgentFieldShape] = [
            "requestID": .init(shape: .uuid, required: !operation.isReadOnly),
            "targets": .init(shape: .array(.object(target), minimum: minimum, maximum: maximum), required: minimum > 0),
            "parameters": .init(shape: .object(.init(fields: [:], allowsAdditionalFields: true))),
            "parametersJSON": .init(shape: .string(maximum: AgentRequest.maximumBytes))
        ]
        if !operation.isReadOnly && operation.name != AgentMutationSchemas.name { fields["retryKey"] = .init(shape: .string(minimum: 1, maximum: AgentRequest.maximumRetryKeyBytes)) }
        if operation.requiresExpectedVersion { fields["expectedVersion"] = .init(shape: .string(minimum: 1, maximum: 4096), required: true) }
        return .init(fields: fields)
    }
}

package extension AgentOperationDescriptor {
    var summary: String {
        switch name {
        case "server.status": "Read the Draftly host version and access status."
        case "server.capabilities": "Read this connection's current permissions, resource scope and expiry."
        case "server.schemas": "Read operation schemas and current handler availability."
        case "editor.open": "Open an authorized draft in an explicit window and its current expectedWindowVersion, or request newWindow. Never choose an implicit active window. Saving pending text also requires drafts.write and source-draft scope. Focus defaults to false. Retrying recovers the original outcome without opening again."
        case "editor.navigate": "Move to the previous or next draft in the current visible list. Read the editor for its current version first. Both drafts must be in scope. Saving pending text also requires drafts.write. Retry the same request to recover its original outcome without navigating again."
        case "editor.preview": "Set Markdown preview visibility for the authorized current draft without saving pending text. Retrying reports the original outcome and does not change the view again."
        case "library.summary": "Count drafts inside the approved scope, including Trash."
        case "drafts.list": "List authorized draft metadata with filters, order and opaque pagination."
        case "drafts.search": "Search authorized drafts. Return metadata and matching previews."
        case "drafts.get": "Read authorized draft metadata and a bounded UTF-16 content chunk."
        case "drafts.merge": "Merge all target drafts in the explicit order into one new draft. Requires library scope. Archive, trash, or keep the originals atomically; preserve their pending editor text."
        case "drafts.syntax": "Change syntax for authorized drafts atomically. Use a built-in name, or an installed name or syntaxID with appearance.read permission and access to that syntax."
        case "drafts.versions": "Read versions of an authorized draft. Content is optional."
        default: "Request the named \(name) operation in Draftly."
        }
    }
}
