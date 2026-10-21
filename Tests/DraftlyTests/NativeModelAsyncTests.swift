import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous Apple model requests") @MainActor
struct NativeModelAsyncTests {
    @MainActor private final class BackendState {
        var modes = ["onDevice", "pcc"]
        var history: [String: [String]] = [:]
        var discarded: [String] = []
        var cleared = false
        var started = false
        var lastPayload: [String: Any] = [:]
        func backend() -> NativeModelAPI.Backend {
            NativeModelAPI.Backend(modes: { self.modes }, respond: { id, payload in
                self.started = true
                let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] ?? [:]
                self.lastPayload = values
                let prompt = values["prompt"] as? String ?? ""
                if prompt == "wait" { try await Task.sleep(for: .seconds(20)) }
                if prompt == "error" { throw NSError(domain: "ModelTest", code: 7) }
                self.history[id, default: []].append(prompt)
                let value: [String: Any] = ["response": ["answer": prompt], "transcript": self.history[id]!.joined(separator: "|")]
                return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            }, discard: { id in self.discarded.append(id); self.history.removeValue(forKey: id) }, clear: { self.cleared = true; self.history.removeAll() })
        }
    }
    private func payload(_ prompt: String, id: String = "neutral-session", mode: String = "onDevice") throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["sessionID": id, "prompt": prompt, "mode": mode]), as: UTF8.self)
    }
    private func waitUntilStarted(_ state: BackendState) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !state.started, ContinuousClock.now < deadline { await Task.yield() }
        #expect(state.started)
    }

    @Test func sessionContextAndStructuredResponsesSurviveMultipleRequests() async throws {
        let state = BackendState()
        let api = NativeModelAPI(backend: state.backend())
        _ = try await api.performAsync("modelRespond", payload: payload("First 🐼"))
        let encoded = try await api.performAsync("modelRespond", payload: payload("Second café"))
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        let value = try #require(envelope["value"] as? [String: Any])
        #expect((value["response"] as? [String: String])?["answer"] == "Second café")
        #expect(value["transcript"] as? String == "First 🐼|Second café")
    }

    @Test func optionsAndSchemaReachTheBackendWithoutFieldLoss() async throws {
        let state = BackendState()
        let api = NativeModelAPI(backend: state.backend())
        let values: [String: Any] = ["mode": "pcc", "sessionID": "options", "prompt": "Neutral", "instructions": ["Be concise"], "tools": ["draft.find"], "toolSets": ["editor"], "temperature": 0.7, "schema": ["fields": [["name": "answer", "type": "string", "options": ["yes", "no"]]]]]
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
        _ = try await api.performAsync("modelRespond", payload: encoded)
        #expect(NSDictionary(dictionary: values).isEqual(to: state.lastPayload))
    }

    @Test(arguments: ["onDevice", "pcc"])
    func unavailableModesReturnNoFabricatedSuccess(mode: String) async throws {
        let state = BackendState(); state.modes = []
        let api = NativeModelAPI(backend: state.backend())
        let modes = try await api.performAsync("modelModes", payload: "{}")
        #expect((try JSONSerialization.jsonObject(with: Data(modes.utf8)) as? [String: Any])?["value"] as? [String] == [])
        do { _ = try await api.performAsync("modelRespond", payload: payload("Neutral", mode: mode)); Issue.record("Unavailable model succeeded.") }
        catch { #expect(error.localizedDescription == "The selected Apple Intelligence model is unavailable on this Mac.") }
        #expect(!state.started)
    }

    @Test func cancellationDiscardsTheSessionAndAllowsANewRequest() async throws {
        let state = BackendState()
        let api = NativeModelAPI(backend: state.backend())
        let task = Task { try await api.performAsync("modelRespond", payload: payload("wait")) }
        await waitUntilStarted(state); task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled response succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(state.discarded == ["neutral-session"])
        _ = try await api.performAsync("modelRespond", payload: payload("New"))
        #expect(state.history["neutral-session"] == ["New"])
    }

    @Test func timeoutAndBackendErrorsDiscardTheirSessions() async throws {
        let state = BackendState()
        let api = NativeModelAPI(backend: state.backend()); api.responseTimeout = 0.02
        do { _ = try await api.performAsync("modelRespond", payload: payload("wait")); Issue.record("Timed out response succeeded.") }
        catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        do { _ = try await api.performAsync("modelRespond", payload: payload("error", id: "failure")); Issue.record("Failed response succeeded.") }
        catch { #expect((error as NSError).domain == "ModelTest") }
        #expect(state.discarded == ["neutral-session", "failure"])
    }

    @Test func toolsOnlyRunWhileTheirModelRequestIsActive() async throws {
        let state = BackendState()
        let api = NativeModelAPI(backend: state.backend())
        var calls = 0
        api.onTool = { _, _ in calls += 1; return "{}" }
        let task = Task { try await api.performAsync("modelRespond", payload: payload("wait")) }
        await waitUntilStarted(state)
        #expect(try api.performTool("draft.find", json: "{}", sessionID: "neutral-session") == "{}")
        #expect(throws: CancellationError.self) { try api.performTool("draft.find", json: "{}", sessionID: "unknown") }
        task.cancel()
        do { _ = try await task.value } catch { }
        #expect(throws: CancellationError.self) { try api.performTool("draft.find", json: "{}", sessionID: "neutral-session") }
        #expect(calls == 1)
    }

    @Test func clearingTheHostCancelsPendingResponsesAndSessionState() async throws {
        let state = BackendState()
        let api = NativeModelAPI(backend: state.backend())
        let task = Task { try await api.performAsync("modelRespond", payload: payload("wait")) }
        await waitUntilStarted(state); api.clear()
        do { _ = try await task.value; Issue.record("Cleared response succeeded.") }
        catch { #expect(error is CancellationError) }
        #expect(state.cleared && state.history.isEmpty)
    }
}
