import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Agent native action host") @MainActor
struct AgentAuthorizedActionHostTests {
    private final class Host: ActionHost {
        var calls = 0
        var operations: [String] = []
        var failure: AgentErrorCode?
        var asyncOperations: Set<String>?
        var finished = 0
        var onCall: (() -> Void)?
        var asyncResult = "{\"value\":true}"
        func supportsAsync(_ operation: String) -> Bool { asyncOperations?.contains(operation) ?? true }
        func perform(_ operation: String, values: [String: Any]) throws -> Any? {
            calls += 1; operations.append(operation); onCall?()
            if let failure { throw failure }
            if operation == "device" { return ["systemName": "macOS", "model": "Mac", "systemVersion": "test"] }
            if operation == "prompt" { return ["index": 0, "fields": ["value": "neutral"]] }
            return "done"
        }
        func performAsync(_ operation: String, payload: String) async throws -> String {
            calls += 1; operations.append(operation); onCall?()
            if let failure { throw failure }
            if operation == "device" { return "{\"value\":{\"systemName\":\"macOS\",\"model\":\"Mac\",\"systemVersion\":\"test\"}}" }
            if operation == "prompt" { return "{\"value\":{\"index\":0,\"fields\":{\"value\":\"neutral\"}}}" }
            return asyncResult
        }
        func finishAction() { finished += 1 }
    }

    @Test(arguments: ["completed", "failed", "unknown", "malformed", "wrongType"], ["share", "shareFile", "print", "clipboard", "htmlToClipboard"])
    func nativeEffectsRecordHandoffAndItsOutcome(outcome: String, operation: String) async throws {
        let host = Host()
        if outcome == "failed" { host.asyncResult = "{\"value\":false}" }
        if outcome == "unknown" { host.failure = .timeout }
        if outcome == "malformed" { host.asyncResult = "invalid envelope" }
        if outcome == "wrongType" { host.asyncResult = "{\"value\":1}" }
        var events: [(UUID, String, String)] = []
        host.onCall = { #expect(events.count == 1 && events.first?.2 == "submitted") }
        let guarded = AgentAuthorizedActionHost(host: host,
            recordEffect: { events.append(($0, $1, $2)) }, authorize: { _, _ in })
        if outcome == "unknown" {
            await #expect(throws: AgentErrorCode.timeout) { try await guarded.performAsync(operation, payload: "{}") }
        } else { _ = try await guarded.performAsync(operation, payload: "{}") }
        let expected = ["malformed", "wrongType"].contains(outcome) ? "unknown" : outcome
        #expect(events.map { $0.2 } == ["submitted", expected])
        #expect(events.first?.0 == events.last?.0 && events.allSatisfy { $0.1 == operation })
        #expect(guarded.hasUncertainOutcome == (expected == "unknown"))
    }

    @Test func deniedNativeCallDoesNotReachHostAndCleanupStillRuns() throws {
        let host = Host()
        let guarded = AgentAuthorizedActionHost(host: host) { _, _ in throw AgentErrorCode.permissionDenied }
        #expect(throws: AgentErrorCode.permissionDenied) { try guarded.perform("share", values: ["text": "neutral"]) }
        #expect(host.calls == 0 && !guarded.hasUncertainOutcome)
        guarded.finishAction()
        #expect(host.finished == 1)
    }

    @Test func failedEffectRecordingPreventsNativeHandoff() async throws {
        let host = Host()
        let guarded = AgentAuthorizedActionHost(host: host,
            recordEffect: { _, _, _ in throw AgentErrorCode.storageError }, authorize: { _, _ in })
        await #expect(throws: AgentErrorCode.storageError) {
            try await guarded.performAsync("share", payload: "{}")
        }
        #expect(host.calls == 0 && !guarded.hasUncertainOutcome)
    }

    @Test func humanDecisionIsRequiredBeforeNativeHandoff() async throws {
        let host = Host()
        var decisions = 0, checks = 0
        let guarded = AgentAuthorizedActionHost(host: host, approve: { operation, values in
            decisions += 1
            #expect(operation == "share" && values["text"] as? String == "neutral")
            throw AgentErrorCode.permissionDenied
        }, authorize: { _, _ in checks += 1 })
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await guarded.performAsync("share", payload: "{\"text\":\"neutral\"}")
        }
        #expect(decisions == 1 && checks == 1 && host.calls == 0 && !guarded.hasUncertainOutcome)
        #expect(throws: AgentErrorCode.interactionRequired) { try guarded.perform("share", values: [:]) }
        #expect(host.calls == 0)
    }

    @Test func authorityIsCheckedAgainAfterHumanDecision() async throws {
        let host = Host()
        var allowed = true
        let guarded = AgentAuthorizedActionHost(host: host, approve: { _, _ in allowed = false }, authorize: { _, _ in
            if !allowed { throw AgentErrorCode.permissionDenied }
        })
        await #expect(throws: AgentErrorCode.permissionDenied) {
            try await guarded.performAsync("share", payload: "{}")
        }
        #expect(host.calls == 0 && !guarded.hasUncertainOutcome)
    }

    @Test func approvedNativeCallChecksAuthorityBeforeAndAfterHandoff() async throws {
        let host = Host()
        var decisions = 0, checks = 0
        let guarded = AgentAuthorizedActionHost(host: host, approve: { _, _ in decisions += 1 },
            authorize: { _, _ in checks += 1 })
        let result = try await guarded.performAsync("share", payload: "{}")
        #expect(result == host.asyncResult && decisions == 1 && checks == 3 && host.calls == 1)
        #expect(!guarded.hasUncertainOutcome)
    }

    @Test func authorityLostAfterNativeHandoffReportsUnknownOutcome() async throws {
        let host = Host()
        var allowed = true
        host.onCall = { allowed = false }
        let guarded = AgentAuthorizedActionHost(host: host) { operation, values in
            #expect(operation == "share")
            #expect(values["text"] as? String == "neutral")
            if !allowed { throw AgentErrorCode.permissionDenied }
        }
        await #expect(throws: AgentErrorCode.outcomeUnknown) {
            try await guarded.performAsync("share", payload: "{\"text\":\"neutral\"}")
        }
        #expect(host.calls == 1 && guarded.hasUncertainOutcome)
    }

    @Test func malformedAsyncInputNeverReachesNativeHost() async throws {
        let host = Host()
        let guarded = AgentAuthorizedActionHost(host: host) { _, _ in Issue.record("Malformed input must not be authorized") }
        await #expect(throws: AgentErrorCode.invalidInput) { try await guarded.performAsync("share", payload: "[]") }
        #expect(host.calls == 0)
    }

    @Test func nativeFailureAfterHandoffLeavesAnUncertainOutcome() async throws {
        let host = Host(); host.failure = .timeout
        let guarded = AgentAuthorizedActionHost(host: host) { _, _ in }
        await #expect(throws: AgentErrorCode.timeout) { try await guarded.performAsync("share", payload: "{}") }
        #expect(host.calls == 1 && guarded.hasUncertainOutcome)
    }

    @Test(arguments: [false, true]) func guardedHostIsUsedWithOrWithoutVisibleEditor(visible: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let model = WindowModel(library: library); model.select(note.id)
        let native = Host()
        var checks = 0
        let guarded = AgentAuthorizedActionHost(host: native) { operation, _ in
            if operation == "device" { return }
            #expect(operation == "clipboard")
            checks += 1
            throw AgentErrorCode.permissionDenied
        }
        let action = DraftAction(name: "Copy", steps: [ActionStep("clipboard", ["template": "Neutral"])])
        let output = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: visible ? [model] : [], host: model.host, hostOverride: guarded,
            resolveModel: { models, _ in models.first })
        #expect(output.report.reason == .error)
        #expect(checks == 1 && native.operations == ["device"], "\(output.message), calls: \(native.operations), checks: \(checks)")
        #expect(model.runner.host === model.host)
    }

    @Test func uncertainNativeOutcomeSurvivesTheActionRunner() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let native = Host()
        var allowed = true
        native.onCall = { if native.operations.last == "clipboard" { allowed = false } }
        let guarded = AgentAuthorizedActionHost(host: native) { operation, _ in
            if operation != "device" && !allowed { throw AgentErrorCode.permissionDenied }
        }
        let action = DraftAction(name: "Copy", steps: [ActionStep("clipboard", ["template": "Neutral"])])
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [], host: native, hostOverride: guarded, editorScope: .targetDraft)
        #expect(native.operations.contains("clipboard"))
        #expect(guarded.hasUncertainOutcome && result.outcomeUnknown)
    }

    @Test func updateRemainsUncertainIfPermissionChangesAfterCommitEvenWhenScriptCatchesError() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let host = NativeActionHost()
        var updateChecks = 0
        let action = DraftAction(name: "Change", steps: [ActionStep("script", ["script":
            "draft.content='Changed'; try { draft.update(); } catch(e) {} "])])
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [], host: host, editorScope: .targetDraft, scriptAuthorization: { operation, _ in
                if operation == "updateDraft" {
                    updateChecks += 1
                    if updateChecks > 1 { throw AgentErrorCode.permissionDenied }
                }
            })
        #expect(updateChecks == 2)
        #expect(library.notes.first { $0.id == note.id }?.content == "Changed")
        #expect(result.outcomeUnknown)
    }

    @Test(arguments: [false, true]) func scriptAuthorizationStopsLibraryWrites(visible: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library); model.select(note.id)
        var denied = 0
        let action = DraftAction(name: "Change", steps: [ActionStep("script", ["script": "draft.content='Changed'; draft.update();"])])
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: visible ? [model] : [], host: model.host, editorScope: .targetDraft,
            scriptAuthorization: { operation, _ in
                if operation == "updateDraft" { denied += 1; throw AgentErrorCode.permissionDenied }
            }, resolveModel: { models, _ in models.first })
        #expect(denied == 1)
        #expect(result.report.reason == .error)
        #expect(library.notes.first { $0.id == note.id }?.content == "Original")
        #expect(model.runner.authorizeScriptOperation == nil)
    }

    @Test(arguments: [false, true]) func stepAuthorizationStopsNativeDraftCreation(visible: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library); model.select(note.id)
        let step = ActionStep("createDraft", ["template": "Created"])
        let action = DraftAction(name: "Create", steps: [step])
        var denied = 0
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: visible ? [model] : [], host: model.host, editorScope: .targetDraft,
            stepAuthorization: { owner, current in
                #expect(owner == action.id && current.id == step.id)
                denied += 1; throw AgentErrorCode.permissionDenied
            }, resolveModel: { models, _ in models.first })
        #expect(result.report.reason == .error && denied == 1)
        #expect(library.notes.count == 1 && library.notes.first?.content == "Original")
        #expect(model.runner.authorizeActionStep == nil)
    }

    @Test(arguments: [false, true]) func completionAuthorizationStopsFinalDisposition(visible: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library); model.select(note.id)
        var action = DraftAction(name: "Finish", steps: []); action.afterSuccess = "trash"
        var checks = 0
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: visible ? [model] : [], host: model.host, editorScope: .targetDraft,
            completionAuthorization: { candidate, id in
                #expect(candidate.id == action.id && id == note.id)
                checks += 1; throw AgentErrorCode.permissionDenied
            }, resolveModel: { models, _ in models.first })
        #expect(result.report.reason == .error && checks == 1)
        #expect(library.notes.first?.trashedAt == nil)
        #expect(model.runner.authorizeActionCompletion == nil)
    }

    @Test(arguments: [false, true]) func deniedPreflightDoesNotSavePendingEditorText(markedDirty: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library); model.select(note.id)
        model.editor.content = "Pending"
        if markedDirty { model.contentChanged() }
        let action = DraftAction(name: "Neutral", steps: [])
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [model], host: model.host, editorScope: .targetDraft,
            completionAuthorization: { _, _ in throw AgentErrorCode.permissionDenied },
            resolveModel: { models, _ in models.first })
        #expect(result.report.reason == .error)
        #expect(library.notes.first { $0.id == note.id }?.content == "Original")
        #expect(model.editor.content == "Pending")
    }

    @Test func permissionIsCheckedAgainWhenTheWindowStartsTheAction() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library); model.select(note.id)
        let action = DraftAction(name: "Neutral", steps: [])
        var checks = 0
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [model], host: model.host, editorScope: .targetDraft,
            completionAuthorization: { _, _ in
                checks += 1
                if checks > 1 { throw AgentErrorCode.permissionDenied }
            }, resolveModel: { models, _ in models.first })
        #expect(checks == 2 && result.report.reason == .error)
        #expect(library.notes.first?.content == "Original")
        #expect(library.runs.isEmpty)
    }

    @Test(arguments: [false, true]) func draftPolicyControlsScriptUpdate(canWrite: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let host = Host(), now = Date()
        host.asyncOperations = ["device", "queryDrafts", "updateDraft", "findDraft"]
        var capabilities: Set<AgentCapability> = [.actionsRun, .draftsRead]
        if canWrite { capabilities.insert(.draftsWrite) }
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: capabilities, scope: .resources([.init(kind: .draft, id: note.id)]))
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { id in library.notes.contains { $0.id == id } })
        let action = DraftAction(name: "Change", steps: [ActionStep("script", ["script": "draft.content='Changed'; draft.update();"])])
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [], host: host, editorScope: .targetDraft,
            scriptAuthorization: { operation, payload in try authority.authorize(operation, payload: payload) })
        #expect(result.report.reason == (canWrite ? .success : .error), "\(result.message)")
        #expect(!host.operations.contains("updateDraft"))
        #expect(library.notes.first { $0.id == note.id }?.content == (canWrite ? "Changed" : "Original"))
    }

    @Test(arguments: [false, true]) func scriptQueryFiltersBeforeEvaluation(installFilter: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let visible = try library.createNote(content: "Visible")
        let hidden = try library.createNote(content: "Hidden")
        let host = Host(), now = Date()
        host.asyncOperations = ["device", "queryDrafts", "updateDraft", "findDraft"]
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead, .draftsWrite],
            scope: .resources([.init(kind: .draft, id: visible.id)]))
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { id in library.notes.contains { $0.id == id } })
        let action = DraftAction(name: "Query", steps: [ActionStep("script", ["script":
            "draft.content=Draft.query('', 'all').map(x=>x.content).join('|'); draft.update();"])])
        var filterCalls = 0
        let filter: (([Note]) throws -> [Note])? = installFilter ? { notes in
            filterCalls += 1; return try authority.visibleDrafts(notes)
        } : nil
        let result = try await AutomationActionExecution.run(action, noteID: visible.id, library: library,
            models: [], host: host, editorScope: .targetDraft,
            scriptAuthorization: { operation, payload in try authority.authorize(operation, payload: payload) },
            scriptDraftFilter: filter)
        #expect(result.report.reason == (installFilter ? .success : .error), "\(result.message)")
        #expect(filterCalls == (installFilter ? 1 : 0))
        #expect(!host.operations.contains("queryDrafts"))
        #expect(library.notes.first { $0.id == visible.id }?.content == "Visible")
        #expect(library.notes.first { $0.id == hidden.id }?.content == "Hidden")
    }

    @Test(arguments: [false, true]) func scriptFindUsesScopedLibraryInsteadOfHost(allowOther: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let visible = try library.createNote(content: "Visible")
        let hidden = try library.createNote(content: "Hidden")
        let host = Host(), now = Date()
        host.asyncOperations = ["device", "findDraft"]
        var targets: Set<AgentResourceReference> = [.init(kind: .draft, id: visible.id)]
        if allowOther { targets.insert(.init(kind: .draft, id: hidden.id)) }
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead, .draftsWrite],
            scope: .resources(targets))
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { id in library.notes.contains { $0.id == id } })
        let action = DraftAction(name: "Lookup", steps: [ActionStep("script", ["script":
            "draft.content=Draft.find('\(hidden.id.uuidString)').content; draft.update();"])])
        let result = try await AutomationActionExecution.run(action, noteID: visible.id, library: library,
            models: [], host: host, editorScope: .targetDraft,
            scriptAuthorization: { operation, payload in try authority.authorize(operation, payload: payload) })
        #expect(result.report.reason == (allowOther ? .success : .error), "\(result.message)")
        #expect(!host.operations.contains("findDraft"))
        #expect(library.notes.first { $0.id == visible.id }?.content == (allowOther ? "Hidden" : "Visible"))
    }

    @Test(arguments: [false, true]) func includedActionRequiresCatalogScope(allowHelper: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Visible")
        let helper = DraftAction(name: "Helper", steps: [ActionStep("insertText", ["template": "Added"])])
        let root = DraftAction(name: "Root", steps: [ActionStep("includeAction", ["uuid": helper.id.uuidString])])
        try library.saveActions([root, helper])
        var targets: Set<AgentResourceReference> = [.init(kind: .draft, id: note.id), .init(kind: .action, id: root.id)]
        if allowHelper { targets.insert(.init(kind: .action, id: helper.id)) }
        let now = Date(), host = Host()
        host.asyncOperations = ["device"]
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead, .draftsWrite], scope: .resources(targets))
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { id in library.notes.contains { $0.id == id } },
            approvedActions: [root.id: root, helper.id: helper], currentAction: { id in library.actions.first { $0.id == id } })
        let result = try await AutomationActionExecution.run(root, noteID: note.id, library: library,
            models: [], host: host, editorScope: .targetDraft, stepAuthorization: { _, _ in },
            actionCatalogFilter: { try authority.visibleActions($0) })
        #expect(result.report.reason == (allowHelper ? .success : .error), "\(result.message)")
        #expect(library.notes.first { $0.id == note.id }?.content == (allowHelper ? "AddedVisible" : "Visible"))
    }

    @Test func scopedInitialConfigurationRequiresSeparateAuthority() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Visible"), host = Host()
        let action = DraftAction(name: "Configure", steps: [ActionStep("configurationKey", [
            "key": "secret", "requiresInitialConfiguration": "true"
        ])])
        try library.saveAction(action)
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [], host: host, editorScope: .targetDraft, stepAuthorization: { _, _ in },
            actionCatalogFilter: { $0 })
        #expect(result.report.reason == .error)
        #expect(host.calls == 0)
        #expect(library.actions.first { $0.id == action.id } == action)
    }

    @Test func unapprovedRootIsRejectedBeforeConfirmation() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Visible"), host = Host()
        var action = DraftAction(name: "Private", steps: [])
        action.presentation.confirmBeforeRun = true
        try library.saveAction(action)
        do {
            _ = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
                models: [], host: host, editorScope: .targetDraft, stepAuthorization: { _, _ in },
                actionCatalogFilter: { _ in [] })
            Issue.record("An unapproved Action must not run")
        } catch { #expect(host.calls == 0) }
        #expect(library.notes.first?.content == "Visible")
    }

    @Test func revocationDuringConfigurationDoesNotSaveTheResponse() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Visible"), host = Host(), now = Date()
        host.asyncOperations = ["device"]
        let action = DraftAction(name: "Configure", steps: [ActionStep("configurationKey", [
            "key": "value", "requiresInitialConfiguration": "true"
        ])])
        try library.saveAction(action)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead, .actionsManage],
            scope: .resources([.init(kind: .draft, id: note.id), .init(kind: .action, id: action.id)]))
        var current: AgentGrant? = grant
        host.onCall = { if host.operations.last == "prompt" { current = nil } }
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { current }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { $0 == note.id }, targetDraftID: note.id,
            approvedActions: [action.id: action], currentAction: { id in library.actions.first { $0.id == id } })
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [], host: host, editorScope: .targetDraft, stepAuthorization: { _, _ in },
            actionCatalogFilter: { try authority.visibleActions($0) },
            configurationAuthorization: { try authority.authorizeConfiguration($0) },
            configurationCommitted: { try authority.acceptConfiguredAction(before: $0, after: $1) })
        #expect(result.report.reason == .error)
        #expect(host.operations.contains("prompt"))
        #expect(library.actions.first { $0.id == action.id } == action)
    }

    @Test func authorizedConfigurationContinuesWithUpdatedDefinition() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Visible"), host = Host(), now = Date()
        host.asyncOperations = ["device"]
        let action = DraftAction(name: "Configure", steps: [ActionStep("configurationKey", [
            "key": "value", "requiresInitialConfiguration": "true"
        ])])
        try library.saveAction(action)
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: [.actionsRun, .draftsRead, .actionsManage],
            scope: .resources([.init(kind: .draft, id: note.id), .init(kind: .action, id: action.id)]))
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { $0 == note.id }, targetDraftID: note.id,
            approvedActions: [action.id: action], currentAction: { id in library.actions.first { $0.id == id } })
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [], host: host, editorScope: .targetDraft, stepAuthorization: { _, _ in },
            actionCatalogFilter: { try authority.visibleActions($0) },
            configurationAuthorization: { try authority.authorizeConfiguration($0) },
            configurationCommitted: { try authority.acceptConfiguredAction(before: $0, after: $1) })
        #expect(result.report.reason == .success, "\(result.message)")
        #expect(library.actions.first { $0.id == action.id }?.configuredValues["value"] == "neutral")
    }

    @Test func failedConfigurationRebindReportsAnUncertainOutcome() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Visible"), host = Host()
        host.asyncOperations = ["device"]
        let action = DraftAction(name: "Configure", steps: [ActionStep("configurationKey", [
            "key": "value", "requiresInitialConfiguration": "true"
        ])])
        try library.saveAction(action)
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [], host: host, editorScope: .targetDraft, stepAuthorization: { _, _ in },
            actionCatalogFilter: { $0 }, configurationAuthorization: { _ in },
            configurationCommitted: { _, _ in throw AgentErrorCode.permissionDenied })
        #expect(result.outcomeUnknown)
        #expect(library.actions.first { $0.id == action.id }?.configuredValues["value"] == "neutral")
    }

    @Test(arguments: [false, true]) func actionUsesCurrentStepAndCompletionAuthority(canWrite: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Original")
        let model = WindowModel(library: library); model.select(note.id)
        let action = DraftAction(name: "Insert", steps: [ActionStep("insertText", ["template": "Added"])])
        try library.saveAction(action)
        var capabilities: Set<AgentCapability> = [.actionsRun, .draftsRead]
        if canWrite { capabilities.insert(.draftsWrite) }
        let now = Date()
        let grant = AgentGrant(connectionID: UUID(), libraryID: UUID(), expiresAt: now.addingTimeInterval(60),
            capabilities: capabilities, scope: .resources([.init(kind: .draft, id: note.id), .init(kind: .action, id: action.id)]))
        let authority = AgentScriptAuthority(grant: grant, currentGrant: { grant }, validateHost: {},
            isLocked: { false }, now: { now }, draftExists: { $0 == note.id },
            targetDraftID: note.id, editorDraftID: { model.editor.noteID },
            approvedActions: [action.id: action], currentAction: { id in library.actions.first { $0.id == id } })
        let result = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: [model], host: model.host, editorScope: .targetDraft,
            scriptAuthorization: { try authority.authorize($0, payload: $1) },
            scriptDraftFilter: { try authority.visibleDrafts($0) },
            stepAuthorization: { try authority.authorizeStep(owner: $0, step: $1) },
            completionAuthorization: { try authority.authorizeCompletion($0, draftID: $1) },
            actionCatalogFilter: { try authority.visibleActions($0) },
            configurationAuthorization: { try authority.authorizeConfiguration($0) },
            resolveModel: { models, _ in models.first })
        #expect(result.report.reason == (canWrite ? .success : .error), "\(result.message)")
        #expect(library.notes.first?.content == (canWrite ? "AddedOriginal" : "Original"))
    }
}
