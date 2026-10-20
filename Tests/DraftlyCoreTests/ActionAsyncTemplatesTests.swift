import Foundation
import Testing
@testable import DraftlyCore

@MainActor @Suite struct ActionAsyncTemplatesTests {
    @Test func nestedTemplatesResolveDynamicTagsAtTheirActualPosition() async throws {
        var calls: [String] = []
        let result = try await Templates.renderAsyncConfigured("[[template|outer]]", note: Note(content: "Title"), loadTemplate: { name in
            calls.append(name)
            return name == "outer" ? "[[latitude]] [[template|inner]]" : "[[longitude]]"
        }, resolveTag: { key in
            if key == "latitude" || key == "longitude" { calls.append(key); return key == "latitude" ? "1" : "2" }
            return nil
        })
        #expect(result == "1 2")
        #expect(calls == ["outer", "inner", "longitude", "latitude"])
    }

    @Test func overridesAndEscapesDoNotPerformNativeOperations() async throws {
        var loads = 0
        var dynamic: [String] = []
        let result = try await Templates.renderAsyncConfigured("\\[[latitude]] [[latitude]] [[template|ignored]]", note: Note(content: ""), custom: ["latitude": "custom", "template": "override"], loadTemplate: { _ in loads += 1; return nil }, resolveTag: { dynamic.append($0); return nil })
        #expect(result == "[[latitude]] custom override")
        #expect(loads == 0)
        #expect(dynamic.isEmpty)
    }

    @Test func recursionLimitStopsLoadingAndKeepsUnresolvedSource() async throws {
        var loads = 0
        let result = try await Templates.renderAsyncConfigured("[[template|loop]]", note: Note(content: ""), loadTemplate: { _ in loads += 1; return "[[template|loop]]" }, resolveTag: { _ in nil })
        #expect(loads == 20)
        #expect(result == "[[template|loop]]")
    }

    @Test func missingFileRemainsLiteralAndHostErrorsPropagate() async throws {
        let result = try await Templates.renderAsyncConfigured("[[template|missing]]", note: Note(content: ""), loadTemplate: { _ in nil }, resolveTag: { _ in nil })
        #expect(result == "[[template|missing]]")
        await #expect(throws: CancellationError.self) {
            try await Templates.renderAsyncConfigured("[[template|failed]]", note: Note(content: ""), loadTemplate: { _ in throw CancellationError() }, resolveTag: { _ in nil })
        }
    }

    @Test func builtinsTransformsAndUnicodeMatchSynchronousRendering() async throws {
        let note = Note(content: "Título 🐼\nSecond line\nThird", tags: ["café", "work"])
        let source = "[[title]]|[[body]]|[[line|-1]]|[[selection_length]]|[[tags]]|{{[[title]]}}|%%**[[title]]**%%|\\{{plain}}|\\%%plain%%"
        let expected = try Templates.renderConfigured(source, note: note, selection: "🐼", selectionRange: NSRange(location: 7, length: 2))
        let result = try await Templates.renderAsyncConfigured(source, note: note, selection: "🐼", selectionRange: NSRange(location: 7, length: 2), loadTemplate: { _ in nil }, resolveTag: { _ in nil })
        #expect(result == expected)
    }

    @Test func customReplacementIsNotRecursivelyExpanded() async throws {
        var calls = 0
        let result = try await Templates.renderAsyncConfigured("[[custom]]", note: Note(content: ""), custom: ["custom": "[[latitude]]"], loadTemplate: { _ in nil }, resolveTag: { _ in calls += 1; return "1" })
        #expect(result == "[[latitude]]")
        #expect(calls == 0)
    }
}
