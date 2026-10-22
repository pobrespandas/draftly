import Foundation
import Testing
@testable import DraftlyCore

// These tests record Draftly behavior. They do not establish Drafts precedence.
@Suite("Included configuration characterization") @MainActor
struct IncludedConfigurationCharacterizationTests {
    @Test(arguments: [false, true], IncludedConfigurationRoute.allCases)
    func childSavedValueDoesNotReplaceItsDefaultInRootContext(asynchronous: Bool, route: IncludedConfigurationRoute) async throws {
        let f = try ScriptTestFixture(content: "Neutral source", host: APIContractHost())
        var child = DraftAction(name: "QA Child café 🐼", steps: [field("Child default"), script("qaIncludedObserve('child');")])
        child.configuredValues = ["label": "Child saved"]
        try f.library.saveAction(child)
        let root = try root(steps: [include(child, route), script("qaIncludedFinish();")])
        try await run(root, in: f, asynchronous: asynchronous,
            expected: [[.string("child"), .string("string"), .string("Child default")]])
        #expect(f.library.actions.first { $0.id == child.id }?.configuredValues["label"] == "Child saved")
    }

    @Test(arguments: [false, true], [false, true])
    func duplicateRootAndChildKeysKeepRoutePrecedenceAndRootSavedValues(asynchronous: Bool, dynamic: Bool) async throws {
        for savedRoot in [false, true] {
            let f = try ScriptTestFixture(content: "Neutral source", host: APIContractHost())
            let child = DraftAction(name: "QA Collision child", steps: [field("Child default"), script("qaIncludedObserve('child');")])
            try f.library.saveAction(child)
            var root = try root(steps: [field("Root default"), include(child, dynamic ? .template : .uuid), script("qaIncludedFinish();")])
            if savedRoot { root.configuredValues = ["label": "Root saved"] }
            let expected = savedRoot ? "Root saved" : dynamic ? "Root default" : "Child default"
            try await run(root, in: f, asynchronous: asynchronous,
                expected: [[.string("child"), .string("string"), .string(expected)]])
        }
    }

    @Test(arguments: [false, true], [false, true])
    func conflictingTypesKeepStaticConversionAndDynamicExistingType(asynchronous: Bool, dynamic: Bool) async throws {
        for type in ["number", "boolean"] {
            let f = try ScriptTestFixture(content: "Neutral source", host: APIContractHost())
            let childField = ActionStep("configurationKey", ["key": "label", "dataType": type,
                "defaultNumberValue": "7", "defaultBoolValue": "true", "requiresInitialConfiguration": "false"])
            let child = DraftAction(name: "QA Typed child", steps: [childField, script("qaIncludedObserve('child');")])
            try f.library.saveAction(child)
            let root = try root(steps: [field("Root text"), include(child, dynamic ? .template : .uuid), script("qaIncludedFinish();")])
            let value: JSONValue = dynamic ? .string("Root text") : type == "number" ? .number(7) : .bool(true)
            try await run(root, in: f, asynchronous: asynchronous,
                expected: [[.string("child"), .string(dynamic ? "string" : type), value]])
        }
    }

    @Test(arguments: [false, true], [false, true])
    func childConfigurationIsAvailableBeforeStaticButNotDynamicInclusion(asynchronous: Bool, dynamic: Bool) async throws {
        let f = try ScriptTestFixture(content: "Neutral source", host: APIContractHost())
        let child = DraftAction(name: "QA Visibility child", steps: [field("Child default"), script("qaIncludedObserve('child');")])
        try f.library.saveAction(child)
        let root = try root(steps: [script("qaIncludedObserve('before');"), include(child, dynamic ? .template : .uuid),
            script("qaIncludedObserve('after');qaIncludedFinish();")])
        try await run(root, in: f, asynchronous: asynchronous, expected: [
            [.string("before"), .string(dynamic ? "undefined" : "string"), dynamic ? .null : .string("Child default")],
            [.string("child"), .string("string"), .string("Child default")],
            [.string("after"), .string("string"), .string("Child default")]])
    }

    @Test(arguments: [false, true], [false, true])
    func repeatedSiblingConfigurationRetainsRuntimeEditsWithDifferentInitialWinners(asynchronous: Bool, dynamic: Bool) async throws {
        let f = try ScriptTestFixture(content: "Neutral source", host: APIContractHost())
        let first = DraftAction(name: "QA First sibling", steps: [field("First"), script("qaIncludedObserve('first');context.configuredValues.label+='!';")])
        let second = DraftAction(name: "QA Second sibling", steps: [field("Second"), script("qaIncludedObserve('second');context.configuredValues.label+='!';")])
        try f.library.saveAction(first); try f.library.saveAction(second)
        let route: IncludedConfigurationRoute = dynamic ? .template : .uuid
        let root = try root(steps: [include(first, route), include(first, route), include(second, route), include(second, route), script("qaIncludedFinish();")])
        let initial = dynamic ? "First" : "Second"
        let labels = ["first", "first", "second", "second"]
        let expected = labels.enumerated().map { index, label in
            [JSONValue.string(label), .string("string"), .string(initial + String(repeating: "!", count: index))]
        }
        try await run(root, in: f, asynchronous: asynchronous, expected: expected)
    }

    private func field(_ value: String) -> ActionStep {
        ActionStep("configurationKey", ["key": "label", "name": "Neutral label", "dataType": "string",
            "defaultStringValue": value, "requiresInitialConfiguration": "false"])
    }

    private func script(_ source: String) -> ActionStep { ActionStep("script", ["script": source]) }

    private func include(_ child: DraftAction, _ route: IncludedConfigurationRoute) -> ActionStep {
        switch route {
        case .uuid: ActionStep("includeAction", ["uuid": child.id.uuidString])
        case .name: ActionStep("includeAction", ["name": child.name])
        case .template: ActionStep("includeAction", ["name": child.name + "[[qaSuffix]]"])
        }
    }

    private func root(steps: [ActionStep]) throws -> DraftAction {
        let url = try #require(Bundle.module.url(forResource: "included-configuration-observer", withExtension: "js", subdirectory: "Fixtures"))
        let observer = try String(contentsOf: url, encoding: .utf8)
        let tags = "draft.setTemplateTag('qaSuffix','');"
        return DraftAction(name: "QA Included configuration root", steps: [script(observer + tags)] + steps)
    }

    private func run(_ root: DraftAction, in f: ScriptTestFixture<APIContractHost>, asynchronous: Bool, expected: [[JSONValue]]) async throws {
        try f.library.saveAction(root)
        let original = f.library.actions
        let report = asynchronous ? await f.runner.runAsync(root) : f.runner.runReport(root)
        #expect(report.reason == .success, Comment(rawValue: f.runner.message ?? ""))
        let observed = try JSONDecoder().decode([[JSONValue]].self, from: Data(f.editor.content.utf8))
        #expect(observed == expected)
        #expect(f.library.notes.first?.content == f.editor.content && f.library.notes.first?.isArchived == false)
        #expect(f.library.actions == original)
        #expect(f.library.runs.count == 1 && f.library.runs.first?.actionID == root.id)
        #expect(f.host.calls.isEmpty)
    }
}

enum IncludedConfigurationRoute: CaseIterable { case uuid, name, template }
