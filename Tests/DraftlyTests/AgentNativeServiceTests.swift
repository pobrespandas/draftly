import Foundation
import Darwin
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
        var constructions = 0
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

    @Test(arguments: ["native.clipboardRead", "native.clipboardWrite", "native.htmlToMarkdown", "native.htmlPreview", "native.share", "native.print", "native.openURL", "native.speak", "native.dictate", "native.transcribe", "native.location", "native.shell", "native.appleScript", "native.shortcut", "native.http", "native.xmlrpc", "native.models"])
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
        let textOperations: Set<String> = ["native.clipboardRead", "native.htmlToMarkdown", "native.dictate", "native.transcribe", "native.shortcut"]
        let unrestricted: Set<String> = ["native.shell", "native.appleScript", "native.shortcut"]
        let isText = textOperations.contains(operation)
        var expected: [String: AgentJSONValue] = ["completed": .bool(true)]
        var resultField: String?
        if isText {
            host.response = "{\"value\":\"PRIVATE native café 🐼\"}"
            expected = ["text": .string("PRIVATE native café 🐼"), "resultAvailable": .bool(true)]; resultField = "text"
        } else if operation == "native.htmlPreview" {
            host.response = #"{"value":{"success":true,"values":{}}}"#
        } else if operation == "native.models" {
            host.response = #"{"value":["onDevice"]}"#
            expected = ["model": .object(["modes": .array([.string("onDevice")])]), "resultAvailable": .bool(true)]
            resultField = "model"
        } else if operation == "native.xmlrpc" {
            let response: AgentJSONValue = .object(["success": .bool(false), "statusCode": .integer(200),
                "paramsJSON": .string("[]"), "faultCode": .integer(23), "error": .string("PRIVATE fault")])
            host.response = String(decoding: try JSONEncoder().encode(AgentJSONValue.object(["value": response])), as: UTF8.self)
            expected = ["response": response, "resultAvailable": .bool(true)]; resultField = "response"
        } else if operation == "native.http" {
            let response: AgentJSONValue = .object(["success": .bool(false), "statusCode": .integer(503), "headersJSON": .string("{}"), "responseText": .string("PRIVATE HTTP café 🐼"), "bodyBase64": .string(Data("PRIVATE HTTP café 🐼".utf8).base64EncodedString())])
            host.response = String(decoding: try JSONEncoder().encode(AgentJSONValue.object(["value": response])), as: UTF8.self)
            expected = ["response": response, "resultAvailable": .bool(true)]; resultField = "response"
        } else if operation == "native.location" {
            host.response = #"{"value":{"latitude":42,"longitude":-71}}"#
            expected = ["coordinates": .object(["latitude": .integer(42), "longitude": .integer(-71)]), "resultAvailable": .bool(true)]; resultField = "coordinates"
        } else if operation == "native.shell" {
            host.response = #"{"value":{"status":7,"stdout":"PRIVATE stdout café 🐼","stderr":"PRIVATE stderr"}}"#
            expected = ["process": .object(["status": .integer(7), "stdout": .string("PRIVATE stdout café 🐼"), "stderr": .string("PRIVATE stderr")]), "resultAvailable": .bool(true)]; resultField = "process"
        } else if operation == "native.appleScript" {
            host.response = #"{"value":{"stamp":1700000000123.125,"text":"PRIVATE native value"},"appleScriptDatePaths":["/stamp"]}"#
            expected = ["valueJSON": .string(host.response), "resultAvailable": .bool(true)]; resultField = "valueJSON"
        }
        f.operations = operations; f.nativeExecution = .init(makeHost: { host.constructions += 1; return host }, approvals: approvals); f.service = try f.makeService(withoutEditors: true)
        let (record, session) = try f.connect(scope: unrestricted.contains(operation) ? .library : .resources([]),
            capabilities: unrestricted.contains(operation) ? [.nativeUse, .scriptsUnrestricted] : [.nativeUse])
        let parameters: [String: AgentJSONValue]
        switch operation {
        case "native.xmlrpc": parameters = ["url": .string("http://127.0.0.1:8080/RPC2"),
            "methodName": .string("fixture.echo"), "paramsJSON": .string(#"["PRIVATE <text> café 🐼"]"#)]
        case "native.http": parameters = ["url": .string("https://example.invalid/qa"), "method": .string("POST"), "bodyText": .string("PRIVATE request")]
        case "native.clipboardRead", "native.location", "native.models": parameters = [:]
        case "native.dictate", "native.transcribe": parameters = ["locale": .string("es-AR")]
        case "native.openURL": parameters = ["url": .string("https://example.com/qa")]
        case "native.htmlToMarkdown", "native.htmlPreview": parameters = ["html": .string("<b>PRIVATE input</b>")]
        case "native.shortcut": parameters = ["name": .string("QA Shortcut"), "text": .string("PRIVATE input")]
        case "native.shell": parameters = ["source": .string("PRIVATE source"), "arguments": .array([.string("café 🐼")])]
        case "native.appleScript": parameters = ["source": .string("PRIVATE source"), "subroutine": .string("qa"), "argumentsJSON": .string(#"["café 🐼",{"record":[true,null]}]"#)]
        default: parameters = ["text": .string("PRIVATE input café 🐼")]
        }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: operation, parameters: parameters)
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing native operation"); return }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        #expect(host.calls.isEmpty && host.constructions == 0 && review.operation == operation && review.effects.targets.isEmpty)
        try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: record.id).state.isTerminal {
            try await Task.sleep(for: .milliseconds(1))
        }
        let reply = try f.send(request, session: session)
        #expect(reply.outcome == .result(.object(expected)) && host.calls.count == 1 && host.finishes == 1 && host.constructions == 1)
        let mappings = ["native.clipboardRead": "getClipboard", "native.clipboardWrite": "clipboard", "native.htmlToMarkdown": "htmlToMarkdown",
            "native.share": "share", "native.print": "print", "native.openURL": "openURL", "native.speak": "speak", "native.dictate": "dictate",
            "native.transcribe": "transcribe", "native.location": "location", "native.shell": "shellScript", "native.appleScript": "appleScript", "native.shortcut": "shortcut", "native.http": "http", "native.xmlrpc": "xmlrpc", "native.models": "modelModes", "native.htmlPreview": "htmlPreview"]
        #expect(host.calls.first?.0 == mappings[operation])
        let payload = try JSONDecoder().decode([String: AgentJSONValue].self, from: Data(try #require(host.calls.first?.1).utf8))
        if operation == "native.htmlPreview" { #expect(payload["localContentOnly"] == .bool(true)) }
        if operation == "native.shortcut" { #expect(payload["waitForResponse"] == .bool(true)) }
        if operation == "native.appleScript" {
            #expect(payload["argumentsJSON"] == nil && payload["arguments"] == .array([.string("café 🐼"), .object(["record": .array([.bool(true), .null])])]))
        }
        if operation == "native.xmlrpc", case .string(let body) = payload["bodyText"] {
            #expect(body.contains("<methodName>fixture.echo</methodName>"))
            #expect(body.contains("PRIVATE &lt;text&gt; café 🐼"))
        }
        if ["native.shell", "native.http", "native.xmlrpc"].contains(operation) { #expect(try operations.snapshot(id, connectionID: record.id).effects.map(\.outcome) == ["failed"]) }
        #expect(try f.send(request, session: session) == reply && host.calls.count == 1)
        let changed = AgentRequest(requestID: request.requestID, libraryID: f.libraryID,
            operation: "native.clipboardWrite", parameters: ["text": .string("Changed intent")])
        #expect(try f.send(changed, session: session).outcome == .error(.versionConflict) && host.calls.count == 1)
        let saved = String(decoding: try Data(contentsOf: root.appendingPathComponent("Agents/operation-request-" + record.id.uuidString + "-" + request.requestID.uuidString + ".json")), as: UTF8.self)
        #expect(!saved.contains("PRIVATE"))
        if operation == "native.http" { #expect(!saved.contains(Data("PRIVATE HTTP café 🐼".utf8).base64EncodedString())) }
        let restarted = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: root))
        defer { restarted.cancelAll() }
        f.operations = restarted; f.service = try f.makeService(withoutEditors: true)
        let nextSession = try f.service.authenticate(connectionID: record.id, credential: #require(f.secrets[record.id]))
        let recovered = try f.send(request, session: nextSession)
        let recoveredResult: [String: AgentJSONValue] = resultField.map { [$0: .null, "resultAvailable": .bool(false)] } ?? expected
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
        defer { host.onCall = nil; host.afterCall = nil }
        f.operations = operations; f.nativeExecution = .init(makeHost: { host.constructions += 1; return host }, approvals: approvals); f.service = try f.makeService(withoutEditors: true)
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
        let madeHost = !["deny", "cancel", "session"].contains(decision)
        #expect(host.finishes == (madeHost ? 1 : 0) && host.constructions == (madeHost ? 1 : 0))
        let snapshot = try operations.snapshot(id, connectionID: record.id)
        if ["revokedAfterEffect", "malformedAfterEffect", "throwsAfterEffect"].contains(decision) {
            #expect(snapshot.state == .outcomeUnknown && snapshot.effects.map(\.outcome) == ["unknown"] && snapshot.result == nil)
        }
    }

    @Test func realShellUsesLiteralUnicodeArgumentsAndReturnsExitStatusWithoutLibraryWrites() async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let note = try f.note("Keep draft café 🐼")
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall })
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        defer { operations.cancelAll() }
        f.operations = operations; f.nativeExecution = .init(makeHost: { NativeActionHost() }, approvals: approvals)
        f.service = try f.makeService(withoutEditors: true)
        let (record, session) = try f.connect(capabilities: [.nativeUse, .scriptsUnrestricted])
        let argument = "café 🐼 e\u{301} $(literal)"
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "native.shell",
            parameters: ["source": .string("printf '%s' \"$1\"\nprintf '%s' 'neutral error' >&2\nexit 7"), "arguments": .array([.string(argument)])])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing Shell operation"); return }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        #expect(review.effects.requiresLibraryScope && review.effects.capabilities == [.nativeUse, .scriptsUnrestricted])
        try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        for _ in 0..<5000 where try !operations.snapshot(id, connectionID: record.id).state.isTerminal {
            try await Task.sleep(for: .milliseconds(1))
        }
        let reply = try f.send(request, session: session)
        guard case .result(.object(let result)) = reply.outcome, case .object(let process) = result["process"],
              case .string(let output) = process["stdout"] else { Issue.record("Missing Shell result: \(reply.outcome)"); return }
        #expect(Array(output.utf8) == Array(argument.utf8))
        #expect(process["status"] == .integer(7) && process["stderr"] == .string("neutral error"))
        #expect(f.library.notes == [note] && f.library.actions.isEmpty)
        #expect(try f.send(request, session: session) == reply)
    }

    @Test(arguments: [false, true], [false, true])
    func nativeToolDiscoveryKeepsUnrestrictedJobsOutOfScopedGrants(allResources: Bool, unrestricted: Bool) async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall })
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        defer { operations.cancelAll() }
        let host = DirectNativeHost()
        f.operations = operations; f.nativeExecution = .init(makeHost: { host.constructions += 1; return host }, approvals: approvals)
        f.service = try f.makeService(withoutEditors: true)
        let (_, session) = try f.connect(scope: allResources ? .library : .resources([]),
            capabilities: unrestricted ? [.nativeUse, .scriptsUnrestricted] : [.nativeUse])
        let tools = AgentChatToolSession(service: f.service, session: session)
        defer { tools.invalidate(revoke: false) }
        let names = Set(try await tools.tools().map(\.operation).filter { $0.hasPrefix("native.") })
        var expected: Set<String> = ["native.clipboardRead", "native.clipboardWrite", "native.htmlToMarkdown", "native.htmlPreview", "native.share",
            "native.print", "native.openURL", "native.speak", "native.dictate", "native.transcribe", "native.location", "native.http", "native.xmlrpc", "native.models"]
        if allResources && unrestricted { expected.formUnion(["native.shell", "native.appleScript", "native.shortcut"]) }
        #expect(names == expected && host.calls.isEmpty && approvals.pendingFromUserInterface().isEmpty)
    }

    @Test func cancellingARealShellJobWaitsForItsProcessGroupToExit() async throws {
        let f = try Fixture(); defer { f.cleanEditorPreferences() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-native-cancel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("started")
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) },
            validateHost: {}, isLocked: { false }, now: { f.wall })
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        defer { operations.cancelAll() }
        f.operations = operations; f.nativeExecution = .init(makeHost: { NativeActionHost() }, approvals: approvals)
        f.service = try f.makeService(withoutEditors: true)
        let (record, session) = try f.connect(capabilities: [.nativeUse, .scriptsUnrestricted])
        let source = #"""
        trap '' TERM
        /bin/sleep 30 &
        child=$!
        printf '%s\n%s' "$$" "$child" > "$1.pending"
        /bin/mv "$1.pending" "$1"
        wait
        """#
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "native.shell",
            parameters: ["source": .string(source), "arguments": .array([.string(marker.path)])])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing Shell operation"); return }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
        for _ in 0..<10_000 {
            let progress = try operations.snapshot(id, connectionID: record.id)
            if progress.state.isTerminal || !progress.effects.isEmpty { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let hadMarker = FileManager.default.fileExists(atPath: marker.path)
        let identifiers = hadMarker ? try String(contentsOf: marker, encoding: .utf8).split(separator: "\n").compactMap { Int32($0) } : []
        _ = try f.response("operations.cancel", session: session, targets: [.init(kind: .operation, id: id)])
        for _ in 0..<5000 where try !operations.snapshot(id, connectionID: record.id).state.isTerminal {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(hadMarker && identifiers.count == 2)
        #expect(identifiers.allSatisfy { getpgid($0) == -1 })
        let snapshot = try operations.snapshot(id, connectionID: record.id)
        #expect(snapshot.state == .outcomeUnknown && snapshot.result == nil)
        #expect(snapshot.effects.map(\.outcome) == ["unknown"])
        #expect(try f.send(request, session: session).outcome == .error(.outcomeUnknown))
        #expect(f.library.notes.isEmpty && f.library.actions.isEmpty)
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
        f.operations = operations; f.nativeExecution = .init(makeHost: { host.constructions += 1; return host }, approvals: approvals); f.service = try f.makeService(withoutEditors: true)
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
