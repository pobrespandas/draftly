import Foundation
import Testing
import AgentContracts

@Suite("Exact agent JSON number decoding")
struct AgentJSONNumberTests {
    @Test func fractionsNearIntegersAreNotRoundedBeforeValidation() throws {
        for text in ["1.00000000000000001", "199.9999999999999999", "-1.00000000000000001"] {
            let value = try JSONDecoder().decode(AgentJSONValue.self, from: Data(text.utf8))
            #expect(value == .number(try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))))
            #expect(throws: AgentSchemaError.self) { try AgentValueShape.integer(minimum: .min, maximum: .max).validate(value) }
        }
    }
    @Test func exactIntegerBoundariesAndLargerIntegralNumbersKeepTheirMeaning() throws {
        for number in [Int64.min, -1, 0, 1, Int64.max] {
            #expect(try JSONDecoder().decode(AgentJSONValue.self, from: Data(String(number).utf8)) == .integer(number))
        }
        for text in ["9223372036854775808", "-9223372036854775809"] {
            let value = try JSONDecoder().decode(AgentJSONValue.self, from: Data(text.utf8))
            #expect(value == .number(try #require(Decimal(string: text))))
        }
        #expect(try JSONDecoder().decode(AgentJSONValue.self, from: Data("1.0".utf8)) == .integer(1))
    }
    @Test func numericStringsBooleansAndNullAreNotNumbers() throws {
        for (text, expected): (String, AgentJSONValue) in [(#""1.00000000000000001""#, .string("1.00000000000000001")),
                                                         ("true", .bool(true)), ("false", .bool(false)), ("null", .null)] {
            #expect(try JSONDecoder().decode(AgentJSONValue.self, from: Data(text.utf8)) == expected)
        }
    }
}
