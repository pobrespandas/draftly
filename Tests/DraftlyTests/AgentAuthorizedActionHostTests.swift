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
        func supportsAsync(_ operation: String) -> Bool { asyncOperations?.contains(operation) ?? true }
        func perform(_ operation: String, values: [String: Any]) throws -> Any? {
            calls += 1; operations.append(operation); onCall?()
            if let failure { throw failure }
            if operation == "device" { return ["systemName": "macOS", "model": "Mac", "systemVersion": "test"] }
            return "done"
        }
        func performAsync(_ operation: String, payload: String) async throws -> String {
            calls += 1; operations.append(operation); onCall?()
            if let failure { throw failure }
            if operation == "device" { return "{\"value\":{\"systemName\":\"macOS\",\"model\":\"Mac\",\"systemVersion\":\"test\"}}" }
            return "done"
        }
        func finishAction() { finished += 1 }
    }

    @Test func deniedNativeCallDoesNotReachHostAndCleanupStillRuns() throws {
        let host = Host()
        let guarded = AgentAuthorizedActionHost(host: host) { _, _ in throw AgentErrorCode.permissionDenied }
        #expect(throws: AgentErrorCode.permissionDenied) { try guarded.perform("share", values: ["text": "neutral"]) }
        #expect(host.calls == 0 && !guarded.hasUncertainOutcome)
        guarded.finishAction()
        #expect(host.finished == 1)
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
}
