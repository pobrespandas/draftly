import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Reviewed direct native services") @MainActor
struct AgentNativeServiceTests {
    private typealias Fixture = AgentCommandServiceTests.Fixture
    @MainActor final class DirectNativeHost: ActionHost {
        var calls: [(String, String)] = []
        var finishes = 0
        var response = "{\"value\":true}"
        var onCall: (() throws -> Void)?
        var afterCall: (() async throws -> Void)?
        func supportsAsync(_ operation: String) -> Bool { true }
        func perform(_ operation: String, values: [String: Any]) throws -> Any? { throw AgentErrorCode.unavailable }
        func performAsync(_ operation: String, payload: String) async throws -> String {
            calls.append((operation, payload)); try onCall?(); try await afterCall?(); return response
        }
        func finishAction() { finishes += 1 }
    }

    @Test(arguments: ["native.clipboardRead", "native.clipboardWrite", "native.htmlToMarkdown", "native.share", "native.print", "native.openURL", "native.speak"])
    func directNativeRequestsRequireReviewAndNeverReplay(operation: String) async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let journal = try AgentOperationJournal(parentDirectory: root)
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall }, journal: journal)
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        defer { operations.cancelAll() }
        let host = DirectNativeHost()
        let isText = AgentNativeSchemas.transientTextOperations.contains(operation)
        if isText { host.response = "{\"value\":\"PRIVATE native café 🐼\"}" }
        f.operations = operations; f.nativeExecution = .init(makeHost: { host }, approvals: approvals); f.service = try f.makeService(withoutEditors: true)
        let (record, session) = try f.connect(scope: .resources([]), capabilities: [.nativeUse])
        let parameters: [String: AgentJSONValue] = operation == "native.clipboardRead" ? [:] :
            operation == "native.openURL" ? ["url": .string("https://example.com/qa")] :
            operation == "native.htmlToMarkdown" ? ["html": .string("<b>PRIVATE input</b>")] : ["text": .string("PRIVATE input café 🐼")]
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: operation, parameters: parameters)
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing native operation"); return }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        #expect(host.calls.isEmpty && review.operation == operation && review.effects.targets.isEmpty)
        try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: record.id).state.isTerminal {
            try await Task.sleep(for: .milliseconds(1))
        }
        let reply = try f.send(request, session: session)
        let expected: [String: AgentJSONValue] = isText ? ["text": .string("PRIVATE native café 🐼"), "resultAvailable": .bool(true)] : ["completed": .bool(true)]
        #expect(reply.outcome == .result(.object(expected)) && host.calls.count == 1 && host.finishes == 1)
        #expect(try f.send(request, session: session) == reply && host.calls.count == 1)
        let changed = AgentRequest(requestID: request.requestID, libraryID: f.libraryID,
            operation: "native.clipboardWrite", parameters: ["text": .string("Changed intent")])
        #expect(try f.send(changed, session: session).outcome == .error(.versionConflict) && host.calls.count == 1)
        let saved = String(decoding: try Data(contentsOf: root.appendingPathComponent("Agents/operations.json")), as: UTF8.self)
        #expect(!saved.contains("PRIVATE"))
        let restarted = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: root))
        defer { restarted.cancelAll() }
        f.operations = restarted; f.service = try f.makeService(withoutEditors: true)
        let nextSession = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recovered = try f.send(request, session: nextSession)
        let recoveredResult: [String: AgentJSONValue] = isText ? ["text": .null, "resultAvailable": .bool(false)] : expected
        #expect(recovered.outcome == .result(.object(recoveredResult)) && host.calls.count == 1)
    }

    @Test(arguments: ["deny", "cancel", "session", "revokedAfterEffect", "malformedAfterEffect", "throwsAfterEffect", "declined"])
    func directNativeFailuresDoNotRepeatAnExternalEffect(decision: String) async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall })
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        defer { operations.cancelAll() }
        let host = DirectNativeHost()
        f.operations = operations; f.nativeExecution = .init(makeHost: { host }, approvals: approvals); f.service = try f.makeService(withoutEditors: true)
        let (record, session) = try f.connect(capabilities: [.nativeUse])
        if decision == "revokedAfterEffect" { host.onCall = { f.service.invalidateAll() } }
        if decision == "malformedAfterEffect" { host.response = "not JSON" }
        if decision == "throwsAfterEffect" { host.onCall = { throw AgentErrorCode.timeout } }
        if decision == "declined" { host.response = "{\"value\":false}" }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "native.share", parameters: ["text": .string("Neutral")])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing native operation"); return }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        if decision == "deny" { try approvals.denyFromUserInterface(review.id) }
        else if decision == "cancel" { _ = try operations.cancel(id, connectionID: record.id) }
        else {
            if decision == "session" { f.service.invalidateAll() }
            try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        }
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: record.id).state.isTerminal {
            try await Task.sleep(for: .milliseconds(1))
        }
        let nextSession = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let reply = try f.send(request, session: nextSession)
        if decision == "declined" { #expect(reply.outcome == .result(.object(["completed": .bool(false)]))) }
        else {
            let code: AgentErrorCode = decision == "deny" || decision == "session" ? .permissionDenied : decision == "cancel" ? .cancelled : .outcomeUnknown
            #expect(reply.outcome == .error(code))
        }
        #expect(host.calls.count == (["deny", "cancel", "session"].contains(decision) ? 0 : 1))
        #expect(try f.send(request, session: nextSession) == reply)
        #expect(host.finishes == 1)
        let snapshot = try operations.snapshot(id, connectionID: record.id)
        if ["revokedAfterEffect", "malformedAfterEffect", "throwsAfterEffect"].contains(decision) {
            #expect(snapshot.state == .outcomeUnknown && snapshot.effects.map(\.outcome) == ["unknown"] && snapshot.result == nil)
        }
    }

    @Test func cancellingAnApprovedNativeCallDrainsTheHostAndWithholdsLateResults() async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall })
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        defer { operations.cancelAll() }
        let host = DirectNativeHost(), gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        host.afterCall = { for await _ in gate.stream { break } }
        f.operations = operations; f.nativeExecution = .init(makeHost: { host }, approvals: approvals); f.service = try f.makeService(withoutEditors: true)
        let (record, session) = try f.connect(capabilities: [.nativeUse])
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "native.share", parameters: ["text": .string("Neutral")])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing native operation"); return }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        for _ in 0..<1000 where host.calls.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
        #expect(host.calls.count == 1 && host.finishes == 0)
        #expect(try operations.cancel(id, connectionID: record.id))
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: record.id).state.isTerminal {
            try await Task.sleep(for: .milliseconds(1))
        }
        let snapshot = try operations.snapshot(id, connectionID: record.id)
        #expect(snapshot.state == .outcomeUnknown && snapshot.result == nil && host.finishes == 1)
        #expect(snapshot.effects.map(\.outcome) == ["unknown"])
        #expect(try f.send(request, session: session).outcome == .error(.outcomeUnknown) && host.calls.count == 1)
    }

}
