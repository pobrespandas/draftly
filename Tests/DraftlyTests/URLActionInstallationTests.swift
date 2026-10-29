import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Atomic action URL installation") @MainActor
struct URLActionInstallationTests {
    @Test func draftlyGroupLinkInstallsGroupAndOrderedActionsAtomically() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let groupID = UUID(), firstID = UUID(), separatorID = UUID()
        let payload: [String: Any] = ["name": "Neutral group", "uuid": groupID.uuidString,
            "icon": "symbol||star", "visibility": 2016, "future": ["keep": true],
            "actions": [["name": "First", "uuid": firstID.uuidString, "steps": []],
                        ["name": "Section", "uuid": separatorID.uuidString, "steps": [], "backingIsSeparator": true]]]
        var link = URLComponents(); link.scheme = "draftly"; link.host = "actionGroup"
        link.queryItems = [URLQueryItem(name: "data", value: String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self))]
        let url = try #require(link.url)
        library.beforeBatchCommit = { throw DraftlyError.message("Injected failure") }
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installActions(url, library: library) }
        library.beforeBatchCommit = nil
        #expect(library.actionGroups.isEmpty && library.actions.isEmpty)
        #expect(try ApplicationURLRouter.installActions(url, library: library))
        #expect(library.actionGroups.first?.id == groupID && library.actionGroups.first?.symbol == "star")
        #expect(library.orderedActions().map(\.name) == ["First", "Section"])
        #expect(library.orderedActions().last?.isSeparator == true)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.actionGroups == library.actionGroups && restored.orderedActions() == library.orderedActions())
    }
    private func link(_ entries: [[String: Any]]) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: entries)
        var url = URLComponents(); url.scheme = "draftly"; url.host = "action"
        url.queryItems = [URLQueryItem(name: "data", value: String(decoding: data, as: UTF8.self))]
        return try #require(url.url)
    }

    @Test func malformedLaterEntryLeavesExistingActionsUnchanged() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let existing = DraftAction(name: "Existing", steps: [])
        try library.saveAction(existing)
        let url = try link([["name": "Valid first", "steps": []], ["name": "Malformed later"]])
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installActions(url, library: library) }
        #expect(library.actions == [existing])
        try library.reload()
        #expect(library.actions == [existing])
    }

    @Test func failedBatchRestoresReplacedAndNewActions() throws {
        enum Failure: Error { case commit }
        let library = try LibraryStore(inMemory: true, seed: false)
        let existing = DraftAction(name: "Original", steps: [])
        try library.saveAction(existing)
        let url = try link([["name": "Replacement", "uuid": existing.id.uuidString, "steps": []], ["name": "New action", "steps": []]])
        library.beforeBatchCommit = { throw Failure.commit }
        defer { library.beforeBatchCommit = nil }
        #expect(throws: Failure.commit) { try ApplicationURLRouter.installActions(url, library: library) { _, _ in true } }
        #expect(library.actions == [existing])
        try library.reload()
        #expect(library.actions == [existing])
    }

    @Test func successfulBatchPreservesDisabledUnknownPayload() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let url = try link([
            ["name": "Unknown disabled", "unknown": ["keep": [false, "café 🐼"]], "steps": [["type": "futureNeutralStep", "isEnabled": false, "data": ["unknown": "Keep"]]]],
            ["name": "Second neutral action", "steps": []]
        ])
        try ApplicationURLRouter.installActions(url, library: library)
        try library.reload()
        #expect(library.actions.count == 2)
        let imported = try #require(library.actions.first { $0.name == "Unknown disabled" })
        #expect(imported.steps.first?.isEnabled == false)
        #expect(imported.steps.first?.type == "futureNeutralStep" && imported.steps.first?.values["unknown"] == "Keep")
        let payload = try #require(imported.rawPayload?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let unknown = try #require(object["unknown"] as? [String: Any])
        #expect((unknown["keep"] as? [Any])?.last as? String == "café 🐼")
    }

    @Test func emptyGroupInstallationPreservesRecordWithoutImportingUnrelatedBackupData() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var group = ActionGroupRecord(name: "Empty café 🐼")
        group.symbol = "folder.fill"; group.order = 9
        let backup = Backup(notes: [Note(content: "Not part of an action installation")],
            revisions: [], workspaces: [Workspace(name: "Unrelated")], actions: [], actionGroups: [group])
        let data = try JSONEncoder().encode(backup)
        var components = URLComponents(); components.scheme = "draftly"; components.host = "action"
        components.queryItems = [URLQueryItem(name: "data", value: data.base64EncodedString())]
        let url = try #require(components.url)
        let before = try library.backupData()
        library.beforeBatchCommit = { throw DraftlyError.message("Injected group installation failure") }
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installActions(url, library: library) }
        library.beforeBatchCommit = nil
        #expect(try library.backupData() == before)
        try ApplicationURLRouter.installActions(url, library: library)
        #expect(library.actionGroups == [group])
        #expect(library.actions.isEmpty && library.notes.isEmpty && library.workspaces.isEmpty)
        try ApplicationURLRouter.installActions(url, library: library)
        #expect(library.actionGroups == [group])
    }

    @Test func missingLibraryFailsExplicitly() throws {
        let url = try link([["name": "Neutral", "steps": []]])
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installActions(url, library: nil) }
    }

    @Test func replacementRequiresConfirmationAndKeepsBatchAtomic() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = DraftAction(name: "Original", steps: [])
        try library.saveAction(original)
        var replacement = original; replacement.name = "Changed 🐼"
        let added = DraftAction(name: "New", steps: [])
        let data = try JSONEncoder().encode([replacement, added])
        var components = URLComponents(); components.scheme = "draftly"; components.host = "action"
        components.queryItems = [URLQueryItem(name: "data", value: String(decoding: data, as: UTF8.self))]
        let url = try #require(components.url)
        let cancelled = try ApplicationURLRouter.installActions(url, library: library) { actions, groups in
            #expect(actions == [original]); #expect(groups.isEmpty); return false
        }
        #expect(!cancelled)
        try library.reload(); #expect(library.actions == [original])
        #expect(try ApplicationURLRouter.installActions(url, library: library) { _, _ in true })
        try library.reload()
        #expect(Set(library.actions.map(\.id)) == Set([original.id, added.id]))
        #expect(library.actions.first(where: { $0.id == original.id }) == replacement)
    }

    @Test func concurrentChangeDuringConfirmationAbortsInstallation() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = DraftAction(name: "Original", steps: [])
        try library.saveAction(original)
        let url = try link([["name": "Incoming", "uuid": original.id.uuidString, "steps": []]])
        var concurrent = original; concurrent.name = "Changed during review"
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installActions(url, library: library) { _, _ in
                try! library.saveAction(concurrent); return true
            }
        }
        try library.reload(); #expect(library.actions == [concurrent])
    }

    @Test func groupReplacementAndIdenticalLinkAreReviewedCorrectly() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = ActionGroupRecord(name: "Original group")
        try library.saveActionGroup(original)
        var changed = original; changed.symbol = "star"
        func url(_ group: ActionGroupRecord) throws -> URL {
            let backup = Backup(notes: [], revisions: [], workspaces: [], actions: [], actionGroups: [group])
            var components = URLComponents(); components.scheme = "draftly"; components.host = "action"
            components.queryItems = [URLQueryItem(name: "data", value: try JSONEncoder().encode(backup).base64EncodedString())]
            return try #require(components.url)
        }
        let same = try url(original)
        #expect(try ApplicationURLRouter.installActions(same, library: library) { _, _ in
            Issue.record("Identical records must not require confirmation"); return false
        })
        let changedURL = try url(changed)
        let cancelled = try ApplicationURLRouter.installActions(changedURL, library: library) { actions, groups in
            #expect(actions.isEmpty); #expect(groups == [original]); return false
        }
        #expect(!cancelled); try library.reload(); #expect(library.actionGroups == [original])
        #expect(try ApplicationURLRouter.installActions(changedURL, library: library) { _, _ in true })
        try library.reload(); #expect(library.actionGroups == [changed])
    }

    @Test func duplicateActionIdentitiesAreRejectedBeforeMutation() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let id = UUID().uuidString
        let url = try link([["name": "First", "uuid": id, "steps": []],
                            ["name": "Second", "uuid": id, "steps": []]])
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installActions(url, library: library) }
        #expect(library.actions.isEmpty)
    }

    @Test func groupNameCollisionWithAnotherIdentityRejectsEntireBatch() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let existing = ActionGroupRecord(name: "Neutral café 🐼")
        try library.saveActionGroup(existing)
        var incoming = ActionGroupRecord(name: existing.name); incoming.id = UUID()
        var member = DraftAction(name: "Must not import", steps: []); member.group = incoming.name
        let backup = Backup(notes: [], revisions: [], workspaces: [], actions: [member], actionGroups: [incoming])
        var components = URLComponents(); components.scheme = "draftly"; components.host = "action"
        components.queryItems = [URLQueryItem(name: "data", value: try JSONEncoder().encode(backup).base64EncodedString())]
        let url = try #require(components.url)
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installActions(url, library: library) { _, _ in true }
        }
        try library.reload()
        #expect(library.actionGroups == [existing]); #expect(library.actions.isEmpty)
    }

    @Test func implicitGroupIdentityConflictDoesNotChangeMembershipOrIdentity() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var member = DraftAction(name: "Existing implicit member", steps: []); member.group = "QA implicit café"
        try library.saveAction(member)
        #expect(library.actionGroups.isEmpty)
        let oldID = try #require(library.actionGroupIdentifiers[member.group])
        var incoming = ActionGroupRecord(name: member.group); incoming.id = UUID()
        let backup = Backup(notes: [], revisions: [], workspaces: [], actions: [], actionGroups: [incoming])
        var components = URLComponents(); components.scheme = "draftly"; components.host = "action"
        components.queryItems = [URLQueryItem(name: "data", value: try JSONEncoder().encode(backup).base64EncodedString())]
        let url = try #require(components.url)
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installActions(url, library: library) { _, _ in true } }
        try library.reload()
        #expect(library.actionGroupIdentifiers[member.group] == oldID)
        #expect(library.actionGroups.isEmpty); #expect(library.actions == [member])
        incoming.name = "Another group"; incoming.id = oldID
        let conflictingID = Backup(notes: [], revisions: [], workspaces: [], actions: [], actionGroups: [incoming])
        components.queryItems = [URLQueryItem(name: "data", value: try JSONEncoder().encode(conflictingID).base64EncodedString())]
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installActions(#require(components.url), library: library) { _, _ in true }
        }
        incoming.name = member.group
        let sameIdentity = Backup(notes: [], revisions: [], workspaces: [], actions: [], actionGroups: [incoming])
        components.queryItems = [URLQueryItem(name: "data", value: try JSONEncoder().encode(sameIdentity).base64EncodedString())]
        #expect(try ApplicationURLRouter.installActions(#require(components.url), library: library) { _, _ in true })
        try library.reload()
        #expect(library.actionGroupIdentifiers[member.group] == oldID && library.actions == [member])
    }

    @Test func replacingRenamedGroupKeepsExistingMembershipAndIsAtomic() throws {
        enum Failure: Error { case commit }
        let library = try LibraryStore(inMemory: true, seed: false)
        try library.saveActionGroup(ActionGroupRecord(name: "Original"))
        var member = DraftAction(name: "Existing", steps: []); member.group = "Original"
        try library.saveAction(member)
        let original = try #require(library.actionGroups.first)
        var renamed = original; renamed.name = "Renamed 🐼"
        let backup = Backup(notes: [], revisions: [], workspaces: [], actions: [], actionGroups: [renamed])
        var components = URLComponents(); components.scheme = "draftly"; components.host = "action"
        components.queryItems = [URLQueryItem(name: "data", value: try JSONEncoder().encode(backup).base64EncodedString())]
        let url = try #require(components.url)
        let cancelled = try ApplicationURLRouter.installActions(url, library: library) { _, _ in false }
        #expect(!cancelled); #expect(library.actions == [member]); #expect(library.actionGroups == [original])
        library.beforeBatchCommit = { throw Failure.commit }
        #expect(throws: Failure.commit) { try ApplicationURLRouter.installActions(url, library: library) { _, _ in true } }
        library.beforeBatchCommit = nil
        try library.reload(); #expect(library.actions == [member]); #expect(library.actionGroups == [original])
        #expect(try ApplicationURLRouter.installActions(url, library: library) { _, _ in true })
        try library.reload()
        member.group = renamed.name
        #expect(library.actions == [member]); #expect(library.actionGroups == [renamed])
        #expect(library.actionGroupIdentifiers[renamed.name] == original.id)
    }

    @Test func groupRenamePreservesImportedActionEditsAndUnrelatedGroups() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var group = ActionGroupRecord(name: "Before"); group.id = UUID()
        try library.saveActionGroup(group)
        var member = DraftAction(name: "Original", steps: []); member.group = group.name
        member.unknownFields = ["future": .string("preserve 🐼")]
        var unrelated = DraftAction(name: "Unrelated", steps: []); unrelated.group = "Other"
        try library.saveActions([member, unrelated])
        var renamed = group; renamed.name = "After"
        var edited = member; edited.name = "Edited"; edited.group = renamed.name
        let backup = Backup(notes: [], revisions: [], workspaces: [], actions: [edited], actionGroups: [renamed])
        var components = URLComponents(); components.scheme = "draftly"; components.host = "action"
        components.queryItems = [URLQueryItem(name: "data", value: try JSONEncoder().encode(backup).base64EncodedString())]
        let url = try #require(components.url)
        #expect(try ApplicationURLRouter.installActions(url, library: library) { _, _ in true })
        try library.reload()
        #expect(library.actions.first(where: { $0.id == member.id }) == edited)
        #expect(library.actions.first(where: { $0.id == unrelated.id }) == unrelated)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(restored.actions.first(where: { $0.id == member.id }) == edited)
        #expect(restored.actionGroupIdentifiers[renamed.name] == group.id)
    }
}
