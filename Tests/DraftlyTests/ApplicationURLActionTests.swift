import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Action URL targets") @MainActor
struct ApplicationURLActionTests {
    @Test func validTargetResolvesWithoutChangingTheLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral target")
        let action = DraftAction(name: "Neutral action", steps: [])
        try library.saveAction(action)
        let target = try ApplicationURLRouter.runTarget(parameters: ["action": action.name, "uuid": note.id.uuidString], library: library)
        #expect(target.action.id == action.id)
        #expect(target.note.id == note.id)
        #expect(library.runs.isEmpty)
    }

    @Test func invalidTargetsFailBeforeExecutionAndSupplyAnErrorCallback() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let action = DraftAction(name: "Neutral action", steps: [])
        try library.saveAction(action)
        let invalid: [[String: String]] = [[:], ["action": "Missing"], ["action": action.name, "uuid": "invalid"], ["action": action.name, "uuid": UUID().uuidString]]
        for parameters in invalid {
            do {
                _ = try ApplicationURLRouter.runTarget(parameters: parameters, library: library)
                Issue.record("An invalid action URL resolved.")
            } catch {
                let callback = ActionExecutionResult.failure(error.localizedDescription).callbackURL(parameters: ["x-error": "test-callback://error?existing=1"])
                let items = URLComponents(url: try #require(callback), resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(items.contains { $0.name == "errorMessage" && $0.value == error.localizedDescription })
                #expect(items.contains { $0.name == "existing" && $0.value == "1" })
            }
        }
        #expect(library.runs.isEmpty)
        #expect(throws: (any Error).self) { try ApplicationURLRouter.runTarget(parameters: [:], library: nil) }
    }
    @Test func titleLinksResolveOrCreateOnlyWhenAllowed() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let title = "Café 🐼 &/%"
        #expect(throws: (any Error).self) { try ApplicationURLRouter.openTarget(parameters: ["title": title], library: library) }
        #expect(library.notes.isEmpty)
        let created = try ApplicationURLRouter.openTarget(parameters: ["title": title, "allowCreate": "true"], library: library, confirmCreation: { $0 == title })
        #expect(created.content == title)
        let again = try ApplicationURLRouter.openTarget(parameters: ["title": title, "allowCreate": "true"], library: library, confirmCreation: { $0 == title })
        #expect(again.id == created.id && library.notes.count == 1)
        #expect(try ApplicationURLRouter.openTarget(parameters: ["uuid": created.id.uuidString, "title": "Other"], library: library).id == created.id)
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.openTarget(parameters: ["uuid": "invalid", "title": "Other", "allowCreate": "true"], library: library)
        }
        #expect(library.notes.count == 1)
        for parameters in [[:], ["title": ""], ["title": "Missing", "allowCreate": "false"]] {
            #expect(throws: (any Error).self) { try ApplicationURLRouter.openTarget(parameters: parameters, library: library) }
        }
        #expect(throws: (any Error).self) { try ApplicationURLRouter.openTarget(parameters: ["title": title], library: nil) }
    }

    @Test func namedWorkspaceLookupDoesNotInstallOrChangeRecords() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var workspace = Workspace(name: "Café 🐼")
        workspace.query = "neutral"
        try library.saveWorkspace(workspace)
        #expect(try ApplicationURLRouter.namedWorkspace(workspace.name, library: library).id == workspace.id)
        for name in [nil, "", "Missing", "café 🐼"] as [String?] {
            #expect(throws: (any Error).self) { try ApplicationURLRouter.namedWorkspace(name, library: library) }
        }
        #expect(library.workspaces.count == 1 && library.notes.isEmpty)
    }
    @Test func failedTitleCreationRetainsLibraryAndCanRetry() throws {
        enum Failure: Error { case storage }
        let library = try LibraryStore(inMemory: true, seed: false)
        library.beforeBatchCommit = { throw Failure.storage }
        #expect(throws: Failure.storage) {
            try ApplicationURLRouter.openTarget(parameters: ["title": "Neutral", "allowCreate": "true"], library: library, confirmCreation: { _ in true })
        }
        #expect(library.notes.isEmpty && library.revisions.isEmpty)
        library.beforeBatchCommit = nil
        let note = try ApplicationURLRouter.openTarget(parameters: ["title": "Neutral", "allowCreate": "true"], library: library, confirmCreation: { _ in true })
        #expect(library.notes.map(\.id) == [note.id])
    }

    @Test func titleLookupExcludesTrashAndRejectsAmbiguity() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var first = Note(content: "Neutral"), second = Note(content: "Neutral"), trash = Note(content: "Neutral")
        first.id = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        second.id = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        first.modifiedAt = Date(timeIntervalSince1970: 1)
        second.modifiedAt = first.modifiedAt
        trash.trashedAt = Date(); trash.modifiedAt = Date()
        try library.saveNotes([second, trash, first], preserveDates: true)
        var confirmationCount = 0
        #expect(throws: ApplicationURLRouter.OpenTargetError.ambiguous("Neutral")) {
            try ApplicationURLRouter.openTarget(parameters: ["title": "Neutral", "allowCreate": "true"], library: library) { _ in
                confirmationCount += 1
                return true
            }
        }
        #expect(confirmationCount == 0)
        first.trashedAt = Date()
        try library.saveNote(first, preserveDates: true)
        #expect(try ApplicationURLRouter.openTarget(parameters: ["title": "Neutral"], library: library).id == second.id)
        #expect(library.notes.count == 3)
    }
    @Test func decliningTitleCreationDoesNotChangeTheLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        var requested: [String] = []
        #expect(throws: ApplicationURLRouter.OpenTargetError.cancelled) {
            try ApplicationURLRouter.openTarget(parameters: ["title": "Neutral", "allowCreate": "true"], library: library) {
                requested.append($0)
                return false
            }
        }
        #expect(requested == ["Neutral"])
        #expect(library.notes.isEmpty && library.revisions.isEmpty)
    }
}
