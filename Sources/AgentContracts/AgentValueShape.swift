import Foundation

package enum AgentSchemaError: Error { case invalidValue }

// The subset used by agent contracts. Validation and exported schemas share these rules.
package indirect enum AgentValueShape: Sendable {
    case string(minimum: Int = 0, maximum: Int? = nil, choices: [String]? = nil)
    case uuid
    case utcDate
    case integer(minimum: Int64 = .min, maximum: Int64 = .max)
    case boolean
    case array(AgentValueShape, maximum: Int)
    case object(AgentObjectShape)
    case map(AgentValueShape)
    case nullable(AgentValueShape)

    package func validate(_ value: AgentJSONValue) throws {
        switch (self, value) {
        case let (.string(minimum, maximum, choices), .string(text)):
            let length = text.unicodeScalars.count
            guard length >= minimum, maximum.map({ length <= $0 }) ?? true,
                  choices.map({ $0.contains(text) }) ?? true else { throw AgentSchemaError.invalidValue }
        case (.uuid, .string(let text)):
            guard UUID(uuidString: text) != nil else { throw AgentSchemaError.invalidValue }
        case (.utcDate, .string(let text)):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let precise = formatter.date(from: text)
            formatter.formatOptions = [.withInternetDateTime]
            guard text.hasSuffix("Z"), precise != nil || formatter.date(from: text) != nil else {
                throw AgentSchemaError.invalidValue
            }
        case let (.integer(minimum, maximum), .integer(number)):
            guard number >= minimum, number <= maximum else { throw AgentSchemaError.invalidValue }
        case let (.integer(minimum, maximum), .number(number)):
            guard !number.isNaN else { throw AgentSchemaError.invalidValue }
            var input = number, rounded = Decimal()
            NSDecimalRound(&rounded, &input, 0, .plain)
            guard rounded == number, number >= Decimal(minimum), number <= Decimal(maximum) else {
                throw AgentSchemaError.invalidValue
            }
        case (.boolean, .bool): break
        case let (.array(shape, maximum), .array(items)):
            guard items.count <= maximum else { throw AgentSchemaError.invalidValue }
            for item in items { try shape.validate(item) }
        case let (.object(shape), .object(fields)): try shape.validate(fields)
        case let (.map(shape), .object(fields)):
            for value in fields.values { try shape.validate(value) }
        case (.nullable, .null): break
        case (.nullable(let shape), _): try shape.validate(value)
        default: throw AgentSchemaError.invalidValue
        }
    }

    package var jsonSchema: AgentJSONValue {
        switch self {
        case let .string(minimum, maximum, choices):
            var fields: [String: AgentJSONValue] = ["type": .string("string"), "minLength": .integer(Int64(minimum))]
            if let maximum { fields["maxLength"] = .integer(Int64(maximum)) }
            if let choices { fields["enum"] = .array(choices.map(AgentJSONValue.string)) }
            return .object(fields)
        case .uuid: return .object(["type": .string("string"), "format": .string("uuid")])
        case .utcDate:
            return .object(["type": .string("string"), "format": .string("date-time"), "pattern": .string("Z$")])
        case let .integer(minimum, maximum):
            return .object(["type": .string("integer"), "minimum": .integer(minimum), "maximum": .integer(maximum)])
        case .boolean: return .object(["type": .string("boolean")])
        case let .array(shape, maximum):
            return .object(["type": .string("array"), "items": shape.jsonSchema, "maxItems": .integer(Int64(maximum))])
        case .object(let shape): return shape.jsonSchema
        case .map(let shape):
            return .object(["type": .string("object"), "additionalProperties": shape.jsonSchema])
        case .nullable(let shape):
            return .object(["anyOf": .array([shape.jsonSchema, .object(["type": .string("null")])])])
        }
    }
}

package struct AgentFieldShape: Sendable {
    package let shape: AgentValueShape
    package var required = false
    package var defaultValue: AgentJSONValue? = nil
}

package struct AgentObjectShape: Sendable {
    package let fields: [String: AgentFieldShape]
    package var allowsAdditionalFields = false

    package func validate(_ values: [String: AgentJSONValue]) throws {
        guard allowsAdditionalFields || Set(values.keys).isSubset(of: Set(fields.keys)) else {
            throw AgentSchemaError.invalidValue
        }
        for (key, field) in fields {
            if let value = values[key] { try field.shape.validate(value) }
            else if field.required { throw AgentSchemaError.invalidValue }
        }
    }

    package func applyingDefaults(to values: [String: AgentJSONValue]) throws -> [String: AgentJSONValue] {
        try validate(values)
        var result = values
        for (key, field) in fields where result[key] == nil {
            if let value = field.defaultValue {
                try field.shape.validate(value)
                result[key] = value
            }
        }
        return result
    }

    package var jsonSchema: AgentJSONValue {
        let properties = fields.mapValues { field -> AgentJSONValue in
            guard case .object(var schema) = field.shape.jsonSchema else { preconditionFailure("An agent shape must export an object.") }
            if let value = field.defaultValue { schema["default"] = value }
            return .object(schema)
        }
        return .object(["type": .string("object"), "properties": .object(properties),
            "required": .array(fields.filter { $0.value.required }.keys.sorted().map(AgentJSONValue.string)),
            "additionalProperties": .bool(allowsAdditionalFields)])
    }
}
