import Foundation

package enum AgentPreferenceSchemas {
    package static let operationNames: Set<String> = ["preferences.schema", "preferences.get", "preferences.update", "preferences.reset"]
    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    private static func o(_ shape: AgentValueShape, default value: AgentJSONValue? = nil) -> AgentFieldShape {
        .init(shape: shape, defaultValue: value)
    }
    private static let token = AgentResourceShapes.token
    private static let rawObject = AgentValueShape.object(.init(fields: [:], allowsAdditionalFields: true))
    private static let resolvedOrigins = ["stored", "default", "inherited", "system"]

    package static func schema(for operation: String, registry: AgentPreferenceRegistry) -> AgentOperationSchema? {
        let writable = registry.fields.filter(\.writable)
        let readAddresses = registry.fields.map { AgentValueShape.object(registry.addressShape($0)) }
        let mutationAddresses = writable.map { AgentValueShape.object(registry.addressShape($0)) }
        let receipts = writable.map { AgentValueShape.object(registry.addressShape($0, extra: ["versionToken": r(token)])) }
        let receiptResult = AgentObjectShape(fields: [
            "items": r(.array(.oneOf(receipts), minimum: 1, maximum: 200)), "versionToken": r(token)
        ])
        switch operation {
        case "preferences.schema":
            let descriptors = registry.fields.map { field -> AgentValueShape in
                let context: String
                switch field.context { case .device: context = "device"; case .syntax: context = "syntax"
                case .syntaxFeature: context = "syntaxFeature"; case .command: context = "command" }
                return .object(.init(fields: [
                    "id": r(.string(choices: [field.id])), "title": r(.string(minimum: 1)),
                    "context": r(.string(choices: [context])), "addressSchema": r(rawObject), "valueSchema": r(rawObject),
                    "defaultSource": r(.string(choices: [field.defaultSource.rawValue])),
                    "defaultValue": r(field.defaultSource == .literal ? field.value : .null),
                    "writable": r(.boolean), "requiresHumanApproval": r(.boolean),
                    "approvalCommands": r(.array(.string(), maximum: 200))
                ]))
            }
            return .init(parameters: .init(fields: [
                "ids": o(.array(.string(choices: registry.fields.map(\.id)), maximum: registry.fields.count)),
                "limit": o(.integer(minimum: 1, maximum: 200), default: .integer(50)), "cursor": o(token)
            ]), result: .init(fields: ["items": r(.array(.oneOf(descriptors), maximum: 200)), "nextCursor": r(.nullable(token))]))
        case "preferences.get":
            let values = registry.fields.flatMap { field -> [AgentValueShape] in
                [false, true].map { invalid in
                    .object(registry.addressShape(field, extra: [
                        "effectiveValue": r(invalid ? .nullable(field.value) : field.value),
                        "valueOrigin": r(.string(choices: invalid ? ["invalid"] : resolvedOrigins)),
                        "hasOverride": r(.boolean), "versionToken": r(token)
                    ]))
                }
            }
            return .init(parameters: .init(fields: ["items": r(.array(.oneOf(readAddresses), minimum: 1, maximum: 200))]),
                result: .init(fields: ["items": r(.array(.oneOf(values), minimum: 1, maximum: 200)), "versionToken": r(token)]))
        case "preferences.update":
            guard !writable.isEmpty else { return nil }
            let changes = writable.map { AgentValueShape.object(registry.addressShape($0, extra: ["value": r($0.value)])) }
            return .init(parameters: .init(fields: ["items": r(.array(.oneOf(changes), minimum: 1, maximum: 200)),
                "interactive": o(.boolean, default: .bool(false))]), result: receiptResult)
        case "preferences.reset":
            guard !writable.isEmpty else { return nil }
            return .init(parameters: .init(fields: ["items": r(.array(.oneOf(mutationAddresses), minimum: 1, maximum: 200)),
                "interactive": o(.boolean, default: .bool(false))]), result: receiptResult)
        default: return nil
        }
    }

    package static func validatedParameters(for request: AgentRequest, registry: AgentPreferenceRegistry) throws -> [String: AgentJSONValue] {
        guard let schema = schema(for: request.operation, registry: registry) else { throw AgentErrorCode.unavailable }
        let values = try schema.validatedParameters(request.parameters)
        if request.operation == "preferences.schema" {
            if case .array(let ids) = values["ids"] {
                let names = ids.compactMap { if case .string(let id) = $0 { return id }; return nil }
                guard Set(names).count == names.count else { throw AgentSchemaError.invalidValue }
            }
        } else {
            let addresses = try addresses(values["items"], registry: registry, changing: request.operation == "preferences.update")
            guard Set(addresses).count == addresses.count else { throw AgentSchemaError.invalidValue }
        }
        return values
    }

    package static func mutationRequiresHumanApproval(_ request: AgentRequest, registry: AgentPreferenceRegistry) throws -> Bool {
        guard request.operation == "preferences.update" || request.operation == "preferences.reset" else { return false }
        let values = try validatedParameters(for: request, registry: registry)
        guard case .array(let items) = values["items"] else { throw AgentSchemaError.invalidValue }
        return try items.contains { try registry.requiresHumanApproval($0) }
    }

    private static func addresses(_ value: AgentJSONValue?, registry: AgentPreferenceRegistry, changing: Bool) throws -> [AgentPreferenceAddress] {
        guard case .array(let items) = value else { throw AgentSchemaError.invalidValue }
        return try items.map { item in
            guard case .object(let values) = item, case .string(let id) = values["id"] else { throw AgentSchemaError.invalidValue }
            let extra: [String: AgentFieldShape] = changing ? ["value": r(try registry.field(id).value)] : [:]
            return try registry.address(item, extra: extra)
        }
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for operation: String, registry: AgentPreferenceRegistry) throws {
        guard let schema = schema(for: operation, registry: registry) else { throw AgentErrorCode.unavailable }
        try schema.result.validate(values)
        guard case .array(let items) = values["items"] else { throw AgentSchemaError.invalidValue }
        var addresses: [AgentPreferenceAddress] = []
        var descriptorIDs: [String] = []
        for item in items {
            guard case .object(var fields) = item, case .string(let id) = fields["id"] else { throw AgentSchemaError.invalidValue }
            let field = try registry.field(id)
            if operation == "preferences.schema" {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                guard let actual = try? encoder.encode(item), let expected = try? encoder.encode(registry.descriptor(field)),
                      actual == expected else { throw AgentSchemaError.invalidValue }
                descriptorIDs.append(id)
            } else {
                if operation == "preferences.get" {
                    guard case .string(let origin) = fields["valueOrigin"], case .bool(let override) = fields["hasOverride"] else {
                        throw AgentSchemaError.invalidValue
                    }
                    if origin == "stored" || origin == "invalid" {
                        guard override else { throw AgentSchemaError.invalidValue }
                    } else if override { throw AgentSchemaError.invalidValue }
                    if fields["effectiveValue"] != .null || origin != "invalid" {
                        try field.value.validate(fields["effectiveValue"] ?? .null)
                    }
                    fields.removeValue(forKey: "effectiveValue"); fields.removeValue(forKey: "valueOrigin")
                    fields.removeValue(forKey: "hasOverride")
                }
                fields.removeValue(forKey: "versionToken")
                addresses.append(try registry.address(.object(fields)))
            }
        }
        guard Set(addresses).count == addresses.count, Set(descriptorIDs).count == descriptorIDs.count else {
            throw AgentSchemaError.invalidValue
        }
    }

    package static func validateResult(_ values: [String: AgentJSONValue], for request: AgentRequest, registry: AgentPreferenceRegistry) throws {
        try validateResult(values, for: request.operation, registry: registry)
        if request.operation == "preferences.schema" {
            if case .array(let ids) = request.parameters["ids"], case .array(let items) = values["items"] {
                let allowed = Set(ids.compactMap { if case .string(let id) = $0 { return id }; return nil })
                for item in items {
                    guard case .object(let fields) = item, case .string(let id) = fields["id"], allowed.contains(id) else {
                        throw AgentSchemaError.invalidValue
                    }
                }
            }
        } else {
            let requested = try addresses(request.parameters["items"], registry: registry, changing: request.operation == "preferences.update")
            guard case .array(let items) = values["items"] else { throw AgentSchemaError.invalidValue }
            let returned = try items.map { item -> AgentPreferenceAddress in
                guard case .object(var fields) = item else { throw AgentSchemaError.invalidValue }
                for key in ["versionToken", "effectiveValue", "valueOrigin", "hasOverride"] { fields.removeValue(forKey: key) }
                return try registry.address(.object(fields))
            }
            guard Set(requested) == Set(returned), requested.count == returned.count else { throw AgentSchemaError.invalidValue }
        }
    }
}
