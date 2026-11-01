import Foundation

package enum AgentSchemaError: Error { case invalidValue }

// The subset used by agent contracts. Validation and exported schemas share these rules.
package indirect enum AgentValueShape: Sendable {
    private static let utcPattern = #"^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?Z$"#
    case string(minimum: Int = 0, maximum: Int? = nil, choices: [String]? = nil)
    case uuid
    case utcDate
    case integer(minimum: Int64 = .min, maximum: Int64 = .max)
    case number(minimum: Decimal? = nil, exclusiveMinimum: Decimal? = nil, maximum: Decimal? = nil)
    case null
    case boolean
    case array(AgentValueShape, minimum: Int = 0, maximum: Int)
    case object(AgentObjectShape)
    case map(AgentValueShape)
    case nullable(AgentValueShape)
    case oneOf([AgentValueShape])

    package func validate(_ value: AgentJSONValue) throws {
        switch (self, value) {
        case let (.string(minimum, maximum, choices), .string(text)):
            let length = text.unicodeScalars.count
            guard length >= minimum, maximum.map({ length <= $0 }) ?? true,
                  choices.map({ $0.contains(text) }) ?? true else { throw AgentSchemaError.invalidValue }
        case (.uuid, .string(let text)):
            guard UUID(uuidString: text) != nil else { throw AgentSchemaError.invalidValue }
        case (.utcDate, .string(let text)):
            guard text.hasSuffix("Z"), text.range(of: Self.utcPattern, options: .regularExpression) != nil else {
                throw AgentSchemaError.invalidValue
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            // Check calendar components without rounding a valid fractional second.
            let seconds = String(text.prefix(19)) + "Z"
            guard let date = formatter.date(from: seconds), formatter.string(from: date) == seconds else {
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
        case let (.number(minimum, exclusiveMinimum, maximum), _):
            let number: Decimal
            switch value {
            case .integer(let value): number = Decimal(value)
            case .number(let value): number = value
            default: throw AgentSchemaError.invalidValue
            }
            guard !number.isNaN, minimum.map({ number >= $0 }) ?? true,
                  exclusiveMinimum.map({ number > $0 }) ?? true,
                  maximum.map({ number <= $0 }) ?? true else { throw AgentSchemaError.invalidValue }
        case (.null, .null), (.boolean, .bool): break
        case let (.array(shape, minimum, maximum), .array(items)):
            guard items.count >= minimum, items.count <= maximum else { throw AgentSchemaError.invalidValue }
            for item in items { try shape.validate(item) }
        case let (.object(shape), .object(fields)): try shape.validate(fields)
        case let (.map(shape), .object(fields)):
            for value in fields.values { try shape.validate(value) }
        case (.oneOf(let shapes), _):
            var matches = 0
            for shape in shapes {
                if (try? shape.validate(value)) != nil { matches += 1 }
            }
            guard matches == 1 else { throw AgentSchemaError.invalidValue }
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
            return .object(["type": .string("string"), "format": .string("date-time"), "pattern": .string(Self.utcPattern)])
        case let .integer(minimum, maximum):
            return .object(["type": .string("integer"), "minimum": .integer(minimum), "maximum": .integer(maximum)])
        case let .number(minimum, exclusiveMinimum, maximum):
            var fields: [String: AgentJSONValue] = ["type": .string("number")]
            if let minimum { fields["minimum"] = .number(minimum) }
            if let exclusiveMinimum { fields["exclusiveMinimum"] = .number(exclusiveMinimum) }
            if let maximum { fields["maximum"] = .number(maximum) }
            return .object(fields)
        case .null: return .object(["type": .string("null")])
        case .boolean: return .object(["type": .string("boolean")])
        case let .array(shape, minimum, maximum):
            return .object(["type": .string("array"), "items": shape.jsonSchema, "minItems": .integer(Int64(minimum)), "maxItems": .integer(Int64(maximum))])
        case .object(let shape): return shape.jsonSchema
        case .map(let shape):
            return .object(["type": .string("object"), "additionalProperties": shape.jsonSchema])
        case .nullable(let shape):
            return .object(["anyOf": .array([shape.jsonSchema, .object(["type": .string("null")])])])
        case .oneOf(let shapes): return .object(["oneOf": .array(shapes.map(\.jsonSchema))])
        }
    }
}

package struct AgentFieldShape: Sendable {
    package let shape: AgentValueShape
    package var required = false
    package var defaultValue: AgentJSONValue? = nil

    package init(shape: AgentValueShape, required: Bool = false, defaultValue: AgentJSONValue? = nil) {
        self.shape = shape; self.required = required; self.defaultValue = defaultValue
    }
}

package struct AgentObjectShape: Sendable {
    package let fields: [String: AgentFieldShape]
    package var allowsAdditionalFields = false
    package var minimumFields = 0

    package init(fields: [String: AgentFieldShape], allowsAdditionalFields: Bool = false, minimumFields: Int = 0) {
        self.fields = fields; self.allowsAdditionalFields = allowsAdditionalFields; self.minimumFields = minimumFields
    }

    package func validate(_ values: [String: AgentJSONValue]) throws {
        guard values.count >= minimumFields,
              allowsAdditionalFields || Set(values.keys).isSubset(of: Set(fields.keys)) else {
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
            "additionalProperties": .bool(allowsAdditionalFields), "minProperties": .integer(Int64(minimumFields))])
    }
}
