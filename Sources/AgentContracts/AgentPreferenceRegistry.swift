import Foundation

package struct AgentPreferenceField: Sendable {
    package enum Context: Sendable {
        case device, syntax, syntaxFeature
        case command([String])
    }
    package enum DefaultSource: String, Sendable, CaseIterable {
        case literal, inherited, system, contextual
    }
    package let id: String
    package let title: String
    package let context: Context
    package let value: AgentValueShape
    package let defaultSource: DefaultSource
    package var defaultValue: AgentJSONValue? = nil
    package var writable = true
    package var requiresHumanApproval = false
    package var approvalCommands: Set<String> = []

    package init(id: String, title: String, context: Context, value: AgentValueShape,
                 defaultSource: DefaultSource, defaultValue: AgentJSONValue? = nil,
                 writable: Bool = true, requiresHumanApproval: Bool = false,
                 approvalCommands: Set<String> = []) {
        self.id = id; self.title = title; self.context = context; self.value = value
        self.defaultSource = defaultSource; self.defaultValue = defaultValue
        self.writable = writable; self.requiresHumanApproval = requiresHumanApproval
        self.approvalCommands = approvalCommands
    }
}

package struct AgentPreferenceAddress: Hashable, Sendable {
    package enum Syntax: Hashable, Sendable {
        case builtIn(String), installed(UUID)
    }
    package let id: String
    package let syntax: Syntax?
    package let command: String?
    package let feature: String?
}

// The host supplies this allowlist. Request data cannot register fields.
package struct AgentPreferenceRegistry: Sendable {
    package let fields: [AgentPreferenceField]
    package let builtInSyntaxNames: [String]
    private let byID: [String: Int]

    package init(fields: [AgentPreferenceField], builtInSyntaxNames: [String]) throws {
        guard !fields.isEmpty, Set(fields.map(\.id)).count == fields.count,
              Set(builtInSyntaxNames).count == builtInSyntaxNames.count,
              !builtInSyntaxNames.isEmpty, builtInSyntaxNames.allSatisfy({ !$0.isEmpty }) else {
            throw AgentSchemaError.invalidValue
        }
        for field in fields {
            guard !field.id.isEmpty, field.id.utf8.count <= 128, !field.title.isEmpty else { throw AgentSchemaError.invalidValue }
            if field.defaultSource == .literal {
                guard let value = field.defaultValue else { throw AgentSchemaError.invalidValue }
                try field.value.validate(value)
            } else if field.defaultValue != nil { throw AgentSchemaError.invalidValue }
            if case .command(let names) = field.context {
                guard !names.isEmpty, Set(names).count == names.count,
                      names.allSatisfy({ !$0.isEmpty }), field.approvalCommands.isSubset(of: Set(names)) else {
                    throw AgentSchemaError.invalidValue
                }
            } else if !field.approvalCommands.isEmpty { throw AgentSchemaError.invalidValue }
        }
        self.fields = fields; self.builtInSyntaxNames = builtInSyntaxNames
        byID = Dictionary(uniqueKeysWithValues: fields.enumerated().map { ($0.element.id, $0.offset) })
    }

    package func field(_ id: String) throws -> AgentPreferenceField {
        guard let index = byID[id] else { throw AgentSchemaError.invalidValue }
        return fields[index]
    }

    package func addressShape(_ field: AgentPreferenceField, extra: [String: AgentFieldShape] = [:]) -> AgentObjectShape {
        func r(_ value: AgentValueShape) -> AgentFieldShape { .init(shape: value, required: true) }
        var fields: [String: AgentFieldShape] = ["id": r(.string(choices: [field.id]))]
        switch field.context {
        case .device: break
        case .syntax, .syntaxFeature:
            fields["syntax"] = r(.oneOf([
                .object(.init(fields: ["type": r(.string(choices: ["builtIn"])), "name": r(.string(choices: builtInSyntaxNames))])),
                .object(.init(fields: ["type": r(.string(choices: ["installed"])), "id": r(.uuid)]))
            ]))
            if case .syntaxFeature = field.context { fields["feature"] = r(.string(minimum: 1)) }
        case .command(let names): fields["command"] = r(.string(choices: names))
        }
        fields.merge(extra) { _, new in new }
        return .init(fields: fields)
    }

    package func address(_ value: AgentJSONValue, extra: [String: AgentFieldShape] = [:]) throws -> AgentPreferenceAddress {
        guard case .object(let values) = value, case .string(let id) = values["id"] else { throw AgentSchemaError.invalidValue }
        let field = try field(id)
        try addressShape(field, extra: extra).validate(values)
        let syntax: AgentPreferenceAddress.Syntax?
        if case .object(let reference) = values["syntax"] {
            if case .string(let rawID) = reference["id"], let id = UUID(uuidString: rawID) { syntax = .installed(id) }
            else if case .string(let name) = reference["name"] { syntax = .builtIn(name) }
            else { throw AgentSchemaError.invalidValue }
        } else { syntax = nil }
        func string(_ key: String) -> String? { if case .string(let value) = values[key] { return value }; return nil }
        return .init(id: id, syntax: syntax, command: string("command"), feature: string("feature"))
    }

    package func requiresHumanApproval(_ value: AgentJSONValue) throws -> Bool {
        guard case .object(var values) = value, case .string(let id) = values["id"] else { throw AgentSchemaError.invalidValue }
        values.removeValue(forKey: "value")
        let address = try address(.object(values)), field = try field(id)
        return field.requiresHumanApproval || address.command.map { field.approvalCommands.contains($0) } == true
    }

    package func descriptor(_ field: AgentPreferenceField) -> AgentJSONValue {
        let context: String
        switch field.context { case .device: context = "device"; case .syntax: context = "syntax"
        case .syntaxFeature: context = "syntaxFeature"; case .command: context = "command" }
        return .object(["id": .string(field.id), "title": .string(field.title), "context": .string(context),
            "addressSchema": addressShape(field).jsonSchema, "valueSchema": field.value.jsonSchema,
            "defaultSource": .string(field.defaultSource.rawValue), "defaultValue": field.defaultValue ?? .null,
            "writable": .bool(field.writable), "requiresHumanApproval": .bool(field.requiresHumanApproval),
            "approvalCommands": .array(field.approvalCommands.sorted().map(AgentJSONValue.string))])
    }
}
