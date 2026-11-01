import Foundation

// Preserve unknown resource fields without passing Foundation objects across actors.
package enum AgentJSONValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Decimal)
    case string(String)
    case array([AgentJSONValue])
    case object([String: AgentJSONValue])

    package init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode(Decimal.self), !item.isNaN {
            var input = item, rounded = Decimal()
            NSDecimalRound(&rounded, &input, 0, .plain)
            // Integer decoding can round a near-integer JSON token. Check Decimal first.
            if rounded == item, item >= Decimal(Int64.min), item <= Decimal(Int64.max) {
                self = .integer(NSDecimalNumber(decimal: item).int64Value)
            } else { self = .number(item) }
        }
        else if let item = try? value.decode([AgentJSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: AgentJSONValue].self)) }
    }

    package func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let item): try value.encode(item)
        case .integer(let item): try value.encode(item)
        case .number(let item):
            guard !item.isNaN else {
                throw EncodingError.invalidValue(item, .init(codingPath: encoder.codingPath,
                    debugDescription: "Agent JSON numbers must be finite."))
            }
            try value.encode(item)
        case .string(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .object(let item): try value.encode(item)
        }
    }
}
