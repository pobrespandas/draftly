import Foundation
import Testing
import DraftlyCore
@testable import AgentContracts

@Suite("Agent import source contracts")
struct AgentImportSourceTests {
    @Test(arguments: ["/tmp/file", "../file", "a/../file", "a/./file", "a//file", "a\\file", "a/", "a\0file"])
    func bookmarkedInputsRejectPathEscapes(path: String) {
        let value: AgentJSONValue = .object(["kind": .string("bookmark"), "bookmarkID": .string(UUID().uuidString), "path": .string(path)])
        #expect(throws: AgentSchemaError.self) { try AgentImportSource.validate(value) }
    }

    @Test func installationLinksStayInTheirEndpointAndCannotBecomeActionURLs() throws {
        let url = try ThemeInstallation.builtIn("Dark").url.absoluteString
        let source: AgentJSONValue = .object(["kind": .string("installationURL"), "url": .string(url)])
        #expect(try AgentImportSource.validate(source, installationEndpoint: "theme") == "installationURL")
        for bad in ["draftly://run?action=Mail", "file:///tmp/theme", "draftly://theme?name=Dark&name=Light", "draftly://theme?name=Dark&x-success=https://example.com", "draftly://syntax?name=Markdown"] {
            #expect(throws: AgentSchemaError.self) {
                try AgentImportSource.validate(.object(["kind": .string("installationURL"), "url": .string(bad)]), installationEndpoint: "theme")
            }
        }
    }

    @Test func remoteSourcesRequireHTTPSWithoutEmbeddedCredentialsOrFragments() throws {
        let good: AgentJSONValue = .object(["kind": .string("https"), "url": .string("https://example.com:8443/theme.json")])
        #expect(try AgentImportSource.validate(good) == "https")
        for url in ["http://example.com/theme", "https://user:password@example.com/theme", "file:///tmp/theme", "https://example.com/theme#fragment"] {
            #expect(throws: AgentSchemaError.self) { try AgentImportSource.validate(.object(["kind": .string("https"), "url": .string(url)])) }
        }
    }

    @Test func exportedInputAlternativesDeclareTheirRequiredFields() {
        guard case .object(let root) = AgentImportSource.shape.jsonSchema,
              case .array(let alternatives) = root["oneOf"] else {
            Issue.record("The source schema must declare its input alternatives."); return
        }
        #expect(alternatives.count == 5)
        for alternative in alternatives {
            guard case .object(let object) = alternative, case .array(let required) = object["required"],
                  case .object(let properties) = object["properties"], case .object(let kind) = properties["kind"],
                  case .array(let choices) = kind["enum"], case .string(let name) = choices.first else {
                Issue.record("An input alternative needs a discriminator and required fields."); return
            }
            let expected: Set<String>
            switch name {
            case "inline": expected = ["kind", "text"]
            case "transfer": expected = ["kind", "transferID"]
            case "bookmark": expected = ["kind", "bookmarkID", "path"]
            default: expected = ["kind", "url"]
            }
            #expect(Set(required.compactMap { if case .string(let name) = $0 { return name }; return nil }) == expected)
            #expect(object["additionalProperties"] == .bool(false))
        }
    }

    @Test func exclusiveAlternativesRejectMultipleMatchesAndNoMatches() throws {
        try AgentValueShape.oneOf([.boolean, .string()]).validate(.bool(false))
        #expect(throws: AgentSchemaError.self) {
            try AgentValueShape.oneOf([.boolean, .boolean]).validate(.bool(false))
        }
        #expect(throws: AgentSchemaError.self) {
            try AgentValueShape.oneOf([.uuid, .integer()]).validate(.string("not-a-UUID"))
        }
    }
}
