import Foundation
import Testing
@testable import DraftlyCore

@Suite("Draft list option decoding")
struct DraftListOptionDecodingTests {
    @Test func missingFieldsKeepOtherSavedOptionsAndUseExistingDefaults() throws {
        let options = try JSONDecoder().decode(DraftListOptions.self, from: Data(#"{"showPreview":false,"showLastAction":true,"future":{"v":"🐼"}}"#.utf8))
        #expect(!options.showPreview && options.showLastAction)
        #expect(options.previewLines == DraftListOptions().previewLines)
        #expect(options.showTags == DraftListOptions().showTags)
    }

    @Test func emptyObjectUsesExistingDefaults() throws {
        #expect(try JSONDecoder().decode(DraftListOptions.self, from: Data("{}".utf8)) == DraftListOptions())
    }

    @Test func completeOptionsKeepTheirRoundTripAndKeys() throws {
        var options = DraftListOptions()
        options.showPreview = false; options.previewLines = 3; options.showTags = false; options.showDate = false
        options.searchTitlesOnly = true; options.caseSensitiveSearch = true; options.previewSearchMatches = true
        options.showLastAction = true; options.highlightFlagged = true
        let data = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(DraftListOptions.self, from: data) == options)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Set(["showPreview", "previewLines", "showTags", "showDate", "searchTitlesOnly",
            "caseSensitiveSearch", "previewSearchMatches", "showLastAction", "highlightFlagged"]))
    }

    @Test func presentInvalidValuesStillFailInsteadOfCoercing() {
        for json in [#"{"showPreview":null}"#, #"{"previewLines":"three"}"#, #"{"showTags":1}"#, "[]"] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(DraftListOptions.self, from: Data(json.utf8)) }
        }
    }
}
