import Foundation
import Testing
@testable import DraftlyCore

@Suite("AppleScript date transport")
struct AppleScriptValueTransportTests {
    @Test func rootDateSurvivesJSONAndKeepsMilliseconds() throws {
        let original = Date(timeIntervalSince1970: -123_456.789)
        let envelope = try AppleScriptValueTransport.encode(original)
        #expect(envelope["appleScriptDatePaths"] as? [String] == [""])
        #expect(envelope["value"] as? Double == original.timeIntervalSince1970 * 1_000)
        let restored = try #require(try roundTrip(envelope) as? Date)
        #expect(abs(restored.timeIntervalSince(original)) < 0.000_001)
    }

    @Test func nestedDatesUseEscapedPointersWithoutRecordTagCollisions() throws {
        let first = Date(timeIntervalSince1970: 1_000), second = Date(timeIntervalSince1970: 2_000.125)
        let original: [String: Any] = [
            "a/~": [first, ["": second]] as [Any],
            "appleScriptDatePaths": ["ordinary"], "value": "normal record field",
            "~1": "literal key", "text": "café 🐼", "number": 3.5,
            "enabled": false, "empty": NSNull(), "list": [] as [Any]
        ]
        let envelope = try AppleScriptValueTransport.encode(original)
        #expect(envelope["appleScriptDatePaths"] as? [String] == ["/a~1~0/0", "/a~1~0/1/"])
        let result = try #require(try roundTrip(envelope) as? [String: Any])
        let dates = try #require(result["a/~"] as? [Any])
        #expect(dates[0] as? Date == first)
        #expect((dates[1] as? [String: Any])?[""] as? Date == second)
        #expect(result["appleScriptDatePaths"] as? [String] == ["ordinary"])
        #expect(result["value"] as? String == "normal record field" && result["~1"] as? String == "literal key")
        #expect(result["text"] as? String == "café 🐼" && result["number"] as? Double == 3.5)
        #expect(result["enabled"] as? Bool == false && result["empty"] is NSNull)
        #expect((result["list"] as? [Any])?.isEmpty == true)
    }

    @Test func ordinaryPayloadHasNoMetadataAndNoImplicitDateConversion() throws {
        let original: [String: Any] = ["date": "2026-10-19T12:00:00Z", "epoch": 1_000, "array": [true, NSNull()] as [Any]]
        let envelope = try AppleScriptValueTransport.encode(original)
        #expect(envelope["appleScriptDatePaths"] == nil)
        let result = try #require(try roundTrip(envelope) as? [String: Any])
        #expect(result["date"] as? String == "2026-10-19T12:00:00Z")
        #expect(result["epoch"] as? Int == 1_000)
        #expect(try AppleScriptValueTransport.decode(["value": NSNull()]) is NSNull)
    }

    @Test func invalidMetadataFailsExplicitly() {
        let invalid: [[String: Any]] = [
            [:], ["value": 0, "appleScriptDatePaths": NSNull()],
            ["value": 0, "appleScriptDatePaths": [0]],
            ["value": 0, "appleScriptDatePaths": ["", ""]],
            ["value": 0, "appleScriptDatePaths": ["relative"]],
            ["value": ["x": 0], "appleScriptDatePaths": ["/x~"]],
            ["value": ["x": 0], "appleScriptDatePaths": ["/x~2"]],
            ["value": ["x": 0], "appleScriptDatePaths": ["/missing"]],
            ["value": [0], "appleScriptDatePaths": ["/1"]],
            ["value": [0], "appleScriptDatePaths": ["/00"]],
            ["value": [0], "appleScriptDatePaths": ["/-1"]],
            ["value": "1000", "appleScriptDatePaths": [""]],
            ["value": true, "appleScriptDatePaths": [""]],
            ["value": NSNull(), "appleScriptDatePaths": [""]],
            ["value": Double.infinity, "appleScriptDatePaths": [""]],
            ["value": Double.nan, "appleScriptDatePaths": [""]]
        ]
        for envelope in invalid {
            #expect(throws: AppleScriptValueTransport.TransportError.self) {
                try AppleScriptValueTransport.decode(envelope)
            }
        }
    }

    @Test func invalidEncodeValuesDoNotProduceAnInvalidJSONEnvelope() {
        for value: Any in [Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: .nan), Double.infinity, URL(fileURLWithPath: "/neutral")] {
            #expect(throws: AppleScriptValueTransport.TransportError.self) {
                try AppleScriptValueTransport.encode(value)
            }
        }
    }

    @Test func numericRecordKeysAndIntegerMillisecondsAreSupported() throws {
        let result = try #require(try AppleScriptValueTransport.decode([
            "value": ["01": NSNumber(value: Int8(7))], "appleScriptDatePaths": ["/01"]
        ]) as? [String: Any])
        #expect(result["01"] as? Date == Date(timeIntervalSince1970: 0.007))
    }

    private func roundTrip(_ envelope: [String: Any]) throws -> Any {
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try AppleScriptValueTransport.decode(decoded)
    }
}
