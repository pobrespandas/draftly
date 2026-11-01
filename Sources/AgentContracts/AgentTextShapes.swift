import Foundation

// Wire ranges use UTF-16 offsets and lengths. Live content checks belong to the handler.
package enum AgentTextShapes {
    private static func r(_ shape: AgentValueShape) -> AgentFieldShape { .init(shape: shape, required: true) }
    package static let range = AgentObjectShape(fields: [
        "offset": r(.integer(minimum: 0)), "length": r(.integer(minimum: 0))
    ])
    package static let chunk = AgentObjectShape(fields: [
        "text": r(.string()), "offset": r(.integer(minimum: 0)),
        "length": r(.integer(minimum: 0, maximum: 65_536)),
        "totalLength": r(.integer(minimum: 0)), "hasMore": r(.boolean)
    ])
    package static let chunkParameters = AgentObjectShape(fields: [
        "offset": .init(shape: .integer(minimum: 0), defaultValue: .integer(0)),
        "length": .init(shape: .integer(minimum: 1, maximum: 65_536), defaultValue: .integer(65_536))
    ])

    package static func isScalarBoundary(_ index: Int, in text: NSString) -> Bool {
        guard index >= 0, index <= text.length else { return false }
        return index == 0 || index == text.length
            || !(0xD800...0xDBFF).contains(text.character(at: index - 1))
            || !(0xDC00...0xDFFF).contains(text.character(at: index))
    }

    package static func count(_ value: AgentJSONValue?) throws -> Int64 {
        guard let value else { throw AgentSchemaError.invalidValue }
        try AgentValueShape.integer(minimum: 0).validate(value)
        switch value {
        case .integer(let value): return value
        case .number(let value): return NSDecimalNumber(decimal: value).int64Value
        default: throw AgentSchemaError.invalidValue
        }
    }

    package static func bounds(_ value: AgentJSONValue?, totalLength: Int64? = nil) throws -> (offset: Int64, end: Int64) {
        guard case .object(let fields) = value else { throw AgentSchemaError.invalidValue }
        try range.validate(fields)
        let offset = try count(fields["offset"]), length = try count(fields["length"])
        let (end, overflow) = offset.addingReportingOverflow(length)
        guard !overflow, totalLength.map({ end <= $0 }) ?? true else { throw AgentSchemaError.invalidValue }
        return (offset, end)
    }

    package static func validateChunk(_ value: AgentJSONValue?) throws -> Int64 {
        guard case .object(let fields) = value else { throw AgentSchemaError.invalidValue }
        try chunk.validate(fields)
        let total = try count(fields["totalLength"]), length = try count(fields["length"])
        let range = try bounds(.object(["offset": fields["offset"] ?? .null, "length": fields["length"] ?? .null]), totalLength: total)
        guard case .string(let text) = fields["text"], case .bool(let hasMore) = fields["hasMore"],
              Int64(text.utf16.count) == length, hasMore == (range.end < total) else {
            throw AgentSchemaError.invalidValue
        }
        return total
    }
}
