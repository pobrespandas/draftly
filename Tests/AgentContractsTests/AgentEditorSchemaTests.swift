import Foundation
import Testing
import DraftlyCore
@testable import AgentContracts

@Suite("Agent editor contracts")
struct AgentEditorSchemaTests {
    private let window = AgentResourceReference(kind: .window, id: UUID())
    private let draft = AgentResourceReference(kind: .draft, id: UUID())
    private func request(_ operation: String, parameters: [String: AgentJSONValue] = [:],
                         targets: [AgentResourceReference]? = nil) -> AgentRequest {
        AgentRequest(requestID: UUID(), libraryID: UUID(), operation: operation,
            targets: targets ?? [window], expectedVersion: "snapshot", parameters: parameters)
    }
    private func range(_ offset: Int64, _ length: Int64) -> AgentJSONValue {
        .object(["offset": .integer(offset), "length": .integer(length)])
    }
    private var snapshot: [String: AgentJSONValue] {
        ["windowID": .string(window.id.uuidString), "draftID": .string(draft.id.uuidString), "versionToken": .string("snapshot")]
    }
    private func page(_ items: [AgentJSONValue]) -> [String: AgentJSONValue] {
        snapshot.merging(["items": .array(items), "nextCursor": .null], uniquingKeysWith: { _, new in new })
    }
    private func editResult(_ selection: AgentJSONValue) -> [String: AgentJSONValue] {
        snapshot.merging(["selection": selection], uniquingKeysWith: { _, new in new })
    }

    @Test func everyEditorOperationHasASchema() {
        let names = Set(AgentOperationCatalog.operations.filter { $0.name.hasPrefix("editor.") }.map(\.name))
        #expect(names == AgentEditorSchemas.operationNames)
        #expect(names.count == 15)
    }

    @Test func editorReadsUseBoundedPagesAndSharedChunkDefaults() throws {
        for operation in ["editor.windows", "editor.markers", "editor.links", "editor.listTasks"] {
            let values = try AgentOperationSchemas.validatedParameters(for: request(operation, targets: operation == "editor.windows" ? [] : nil))
            #expect(values == ["limit": .integer(50)])
        }
        let values = try AgentOperationSchemas.validatedParameters(for: request("editor.get"))
        #expect(values == ["offset": .integer(0), "length": .integer(65_536)])
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("editor.get", parameters: ["length": .integer(65_537)]))
        }
    }

    @Test func findOptionsMapToTheExistingQueryWithoutSelectingAMatch() throws {
        let input = request("editor.find", parameters: ["query": .string("🐼"), "regularExpression": .bool(false), "caseSensitive": .bool(true)])
        let values = try AgentOperationSchemas.validatedParameters(for: input)
        #expect(values["query"] == .string("🐼"))
        #expect(values["limit"] == .integer(50))
        let matches = try EditorFindQuery("🐼", caseSensitive: true).matches(in: "a🐼\r\n🐼")
        let result = page(matches.map { .object(["range": range(Int64($0.location), Int64($0.length))]) })
        try AgentOperationSchemas.validateResult(result, for: input)
        #expect(matches == [NSRange(location: 1, length: 2), NSRange(location: 5, length: 2)])
        #expect(values["selection"] == nil)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("editor.find", parameters: ["query": .string("x"), "regularExpression": .string("true")]))
        }
    }

    @Test func editorChunksUseUTF16AndSelectionCannotExceedTheSnapshot() throws {
        var result = editResult(range(2, 1))
        result["content"] = .object(["text": .string("🐼é"), "offset": .integer(0), "length": .integer(3),
            "totalLength": .integer(3), "hasMore": .bool(false)])
        result["hasUnsavedChanges"] = .bool(true)
        try AgentOperationSchemas.validateResult(result, for: request("editor.get"))
        result["selection"] = range(3, 1)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: request("editor.get")) }
        result["selection"] = range(0, 0); result["draftID"] = .null
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: request("editor.get")) }
        result["content"] = .object(["text": .string(""), "offset": .integer(0), "length": .integer(0),
            "totalLength": .integer(0), "hasMore": .bool(false)])
        result["hasUnsavedChanges"] = .bool(false)
        try AgentOperationSchemas.validateResult(result, for: request("editor.get"))
    }

    @Test func rangeCommandsRejectOverflowAndKeepExplicitEmptyText() throws {
        let input = request("editor.replaceRange", parameters: ["range": range(2, 0), "text": .string("")])
        #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
        for operation in ["editor.replaceRange", "editor.setSelection"] {
            var parameters: [String: AgentJSONValue] = ["range": range(.max, 1)]
            if operation == "editor.replaceRange" { parameters["text"] = .string("🐼") }
            #expect(throws: AgentSchemaError.self) {
                try AgentOperationSchemas.validatedParameters(for: request(operation, parameters: parameters))
            }
        }
    }

    @Test func taskSnapshotsAndCommandsUseTheSharedSyntaxDefinition() throws {
        let syntax = try ScriptSyntax.definition("Markdown")
        let text = "🐼\r\n- [ ] Café"
        let task = try #require(syntax.tasks(in: text).first)
        var item: [String: AgentJSONValue] = [:]
        for key in ["line", "label", "state", "interactive"] { item[key] = .string(try #require(task[key] as? String)) }
        item["isCompleted"] = .bool(try #require(task["isCompleted"] as? Bool))
        for key in ["lineRange", "labelRange", "stateRange", "interactiveRange"] {
            let value = try #require(task[key] as? [Int]); item[key] = range(Int64(value[0]), Int64(value[1]))
        }
        try AgentOperationSchemas.validateResult(page([.object(item)]), for: request("editor.listTasks"))
        for operation in ["complete", "reset", "advance"] {
            let input = request("editor.tasks", parameters: ["stateRange": try #require(item["stateRange"]),
                "state": try #require(item["state"]), "operation": .string(operation)])
            #expect(try AgentOperationSchemas.validatedParameters(for: input) == input.parameters)
            let change = try syntax.taskChange(in: text, task: task, operation: operation)
            #expect(change.0 == NSRange(location: 6, length: 3))
        }
    }

    @Test func openingRequiresAnExplicitWindowOrANewWindowRequestAndNeverDefaultsToFocus() throws {
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validatedParameters(for: request("editor.open", targets: [draft])) }
        let existing: [String: AgentJSONValue] = ["windowID": .string(window.id.uuidString), "expectedWindowVersion": .string("window-snapshot")]
        let values = try AgentOperationSchemas.validatedParameters(for: request("editor.open", parameters: existing, targets: [draft]))
        #expect(values["focus"] == .bool(false))
        #expect(values["newWindow"] == .bool(false))
        let new = try AgentOperationSchemas.validatedParameters(for: request("editor.open", parameters: ["newWindow": .bool(true)], targets: [draft]))
        #expect(new["focus"] == .bool(false))
        #expect(new["windowID"] == nil)
        var ambiguous = existing; ambiguous["newWindow"] = .bool(true)
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("editor.open", parameters: ambiguous, targets: [draft]))
        }
    }

    @Test func resultsCannotSelectAnotherWindowOrOpenAnotherDraft() throws {
        var result = editResult(range(0, 0))
        try AgentOperationSchemas.validateResult(result, for: request("editor.undo"))
        result["windowID"] = .string(UUID().uuidString)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: request("editor.undo")) }
        let input = request("editor.open", parameters: ["windowID": .string(window.id.uuidString), "expectedWindowVersion": .string("snapshot")], targets: [draft])
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: input) }
        result["windowID"] = .string(window.id.uuidString); result["draftID"] = .string(UUID().uuidString)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: input) }
    }

    @Test func selectionAndPreviewRepliesMustReflectTheRequestedChange() throws {
        let input = request("editor.setSelection", parameters: ["range": range(1, 2)])
        try AgentOperationSchemas.validateResult(editResult(range(1, 2)), for: input)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(editResult(range(1, 0)), for: input) }
        let preview = request("editor.preview", parameters: ["visible": .bool(true)])
        var result: [String: AgentJSONValue] = ["windowID": .string(window.id.uuidString), "draftID": .string(draft.id.uuidString), "visible": .bool(true)]
        try AgentOperationSchemas.validateResult(result, for: preview)
        result["visible"] = .bool(false)
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(result, for: preview) }
    }

    @Test func emptyEditorsCannotReportTaskItemsAndWindowPagesCannotRepeatIdentities() {
        var tasks = page([.object(["range": range(0, 0)])]); tasks["draftID"] = .null
        #expect(throws: AgentSchemaError.self) { try AgentOperationSchemas.validateResult(tasks, for: request("editor.find", parameters: ["query": .string("")])) }
        let item = snapshot.merging(["title": .string("Neutral"), "hasUnsavedChanges": .bool(false)], uniquingKeysWith: { _, new in new })
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validateResult(["items": .array([.object(item), .object(item)]), "nextCursor": .null], for: request("editor.windows", targets: []))
        }
    }

    @Test func replacementsKeepLiteralAndRegexOptionsSeparate() throws {
        let parameters: [String: AgentJSONValue] = ["query": .string("(é)"), "replacement": .string("$1🐼"), "regularExpression": .bool(true)]
        let values = try AgentOperationSchemas.validatedParameters(for: request("editor.replaceAll", parameters: parameters))
        #expect(values["regularExpression"] == .bool(true))
        #expect(try EditorFindQuery("(é)", regularExpression: true).replacingAll(in: "é", with: "$1🐼") == "é🐼")
        #expect(try EditorFindQuery("é").replacingAll(in: "é", with: "$1🐼") == "$1🐼")
        #expect(throws: AgentSchemaError.self) {
            try AgentOperationSchemas.validatedParameters(for: request("editor.replaceAll", parameters: ["query": .string("é")]))
        }
    }
}
