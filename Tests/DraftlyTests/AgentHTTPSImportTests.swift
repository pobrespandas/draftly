import Foundation
import Testing
import AgentContracts
import DraftlyCore
@testable import Draftly

@Suite("Reviewed HTTPS import inputs") @MainActor
struct AgentHTTPSImportTests {
    @Test(arguments: ["themes.install", "themes.replace", "backups.validate", "backups.previewRestore"], ["approve", "deny", "cancel", "readFailure", "stopWork", "invalidJSON"])
    func inputDownloadsRequireReviewAndNeverReplay(operation: String, decision: String) async throws {
        let f = try AgentCommandServiceTests.Fixture(); defer { f.operations?.cancelAll(); f.nativeExecution = nil; f.operations = nil; f.service = nil; f.cleanEditorPreferences() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) }, validateHost: {}, isLocked: { false }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: root))
        defer { operations.cancelAll(); f.operations?.cancelAll() }
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        let incoming = EditorThemeDefinition(name: "PRIVATE downloaded café 🐼"), original = EditorThemeDefinition(name: "Original")
        if operation == "themes.replace" { try f.library.saveTheme(original) }
        _ = try f.note("Keep stored draft")
        let before = try f.library.backupData()
        let bytes = operation.hasPrefix("themes.") ? try JSONEncoder().encode(incoming) : before
        var downloads = 0
        f.operations = operations
        f.nativeExecution = .init(makeHost: { Issue.record("Download must not create a native UI host"); return AgentNativeServiceTests.DirectNativeHost() }, approvals: approvals, fetchHTTPS: { url, maximum in
            downloads += 1
            #expect(url == "https://fixture.invalid/input?token=PRIVATE_SOURCE")
            #expect(maximum == (operation.hasPrefix("themes.") ? AgentRequest.maximumBytes : AgentTransferSchemas.maximumBytes))
            if decision == "readFailure" { throw AgentErrorCode.storageError }
            if decision == "stopWork" { f.service.invalidateAll() }
            if decision == "invalidJSON" { return Data("invalid input".utf8) }
            return bytes
        })
        try f.enablePreferenceWrites()
        let (connection, session) = try f.connect(capabilities: [.appearanceRead, .appearanceManage, .filesRead, .nativeUse, .backupsRestore])
        var expected: String?
        if operation == "themes.replace" {
            guard case .array(let rows) = try f.values("themes.list", session: session)["items"], case .object(let row) = rows.first, case .string(let token) = row["versionToken"] else { Issue.record("Missing version"); return }
            expected = token
        }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: operation, targets: operation == "themes.replace" ? [.init(kind: .theme, id: original.id)] : [], expectedVersion: expected,
            parameters: ["source": .object(["kind": .string("https"), "url": .string("https://fixture.invalid/input?token=PRIVATE_SOURCE")])])
        guard case .accepted(let id, _) = try f.send(request, session: session).outcome else { Issue.record("Missing accepted download"); return }
        for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
        let review = try #require(approvals.pendingFromUserInterface().first)
        #expect(downloads == 0 && review.effects.capabilities.contains(.nativeUse))
        #expect(try f.library.backupData() == before)
        if decision == "cancel" {
            _ = try f.values("operations.cancel", session: session, targets: [.init(kind: .operation, id: id)])
        } else if decision == "deny" { try approvals.denyFromUserInterface(review.id) }
        else { try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint) }
        for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection.id).state.isTerminal { try await Task.sleep(for: .milliseconds(1)) }
        let terminal = try operations.snapshot(id, connectionID: connection.id)
        if decision == "approve" {
            #expect(terminal.state == .succeeded && downloads == 1)
            if operation.hasPrefix("themes.") {
                #expect(f.library.themes.count == 1 && f.library.themes.first?.name == incoming.name)
                if operation == "themes.replace" { #expect(f.library.themes.first?.id == original.id) }
            } else { #expect(try f.library.backupData() == before) }
        } else {
            #expect(terminal.error == (decision == "cancel" ? .cancelled : decision == "deny" ? .permissionDenied : .outcomeUnknown))
            #expect(downloads == (["deny", "cancel"].contains(decision) ? 0 : 1))
            #expect(try f.library.backupData() == before)
        }
        let readable = decision == "stopWork" ? try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id])) : session
        let repeated = try f.send(request, session: readable)
        let reopened = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) }, validateHost: {}, isLocked: { false }, now: { f.wall }, journal: try AgentOperationJournal(parentDirectory: root))
        f.operations = reopened; f.nativeExecution = nil; f.service = try f.makeService()
        let next = try f.service.authenticate(connectionID: connection.id, credential: #require(f.secrets[connection.id]))
        #expect(try f.send(request, session: next).outcome == repeated.outcome)
        let changed = AgentRequest(requestID: request.requestID, libraryID: f.libraryID, operation: operation,
            targets: request.targets, expectedVersion: expected, parameters: ["source": .object(["kind": .string("inline"), "text": .string(String(decoding: bytes, as: UTF8.self))])])
        #expect(try f.send(changed, session: next).outcome == .error(.versionConflict))
        #expect(downloads == (["deny", "cancel"].contains(decision) ? 0 : 1))
        let saved = String(decoding: try Data(contentsOf: root.appendingPathComponent("Agents/operation-request-" + connection.id.uuidString + "-" + request.requestID.uuidString + ".json")), as: UTF8.self)
        #expect(!saved.contains("PRIVATE"))
    }
    @Test(arguments: ["nativeUse", "staleBefore", "staleReview"])
    func incompleteAuthorityOrStaleIntentCannotStartADownload(reason: String) async throws {
        let f = try AgentCommandServiceTests.Fixture(); defer { f.operations?.cancelAll(); f.nativeExecution = nil; f.operations = nil; f.service = nil; f.cleanEditorPreferences() }
        let operations = AgentOperationRegistry(currentGrant: { try f.connections.grantForAuthenticatedConnection($0) }, validateHost: {}, isLocked: { false }, now: { f.wall })
        defer { operations.cancelAll() }
        let approvals = AgentApprovalStore(now: { f.wall }, currentGrant: { try? f.connections.grantForAuthenticatedConnection($0) }, isLocked: { false })
        var downloads = 0
        f.operations = operations; f.nativeExecution = .init(makeHost: { AgentNativeServiceTests.DirectNativeHost() }, approvals: approvals, fetchHTTPS: { _, _ in downloads += 1; return Data() })
        try f.enablePreferenceWrites()
        var theme = EditorThemeDefinition(name: "Keep source")
        try f.library.saveTheme(theme)
        let caps: Set<AgentCapability> = reason == "nativeUse" ? [.appearanceRead, .appearanceManage, .filesRead] : [.appearanceRead, .appearanceManage, .filesRead, .nativeUse]
        let (connection, session) = try f.connect(capabilities: caps)
        guard case .array(let rows) = try f.values("themes.list", session: session)["items"], case .object(let row) = rows.first, case .string(let version) = row["versionToken"] else { Issue.record("Missing version"); return }
        let request = AgentRequest(requestID: UUID(), libraryID: f.libraryID, operation: "themes.replace", targets: [.init(kind: .theme, id: theme.id)], expectedVersion: version, parameters: ["source": .object(["kind": .string("https"), "url": .string("https://fixture.invalid/theme")])])
        if reason == "staleBefore" { theme.background = "123456"; try f.library.saveTheme(theme) }
        let response = try f.send(request, session: session)
        if reason == "staleReview" {
            guard case .accepted(let id, _) = response.outcome else { Issue.record("Missing review operation"); return }
            for _ in 0..<1000 where approvals.pendingFromUserInterface().isEmpty { await Task.yield() }
            let review = try #require(approvals.pendingFromUserInterface().first)
            theme.background = "123456"; try f.library.saveTheme(theme)
            try approvals.approveFromUserInterface(review.id, reviewedFingerprint: review.fingerprint)
            for _ in 0..<1000 where try !operations.snapshot(id, connectionID: connection.id).state.isTerminal { try await Task.sleep(for: .milliseconds(1)) }
            #expect(try operations.snapshot(id, connectionID: connection.id).error == .versionConflict)
        } else { #expect(response.outcome == .error(reason == "nativeUse" ? .permissionDenied : .versionConflict)) }
        #expect(downloads == 0 && f.library.themes == [theme])
    }

}
