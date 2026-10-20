import Foundation
import Testing
@testable import DraftlyCore

@Suite("Initial action catalog") @MainActor
struct DefaultActionCatalogTests {
    @Test func firstOpenInstallsSixRunnableActionsAndReopenPreservesEdits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let expected = ["Copy", "Share", "Add to Reminders", "Add Calendar Event", "Save to File", "Markdown Preview"]
        let types = ["clipboard", "share", "reminder", "event", "file", "htmlpreview"]
        var library: LibraryStore? = try LibraryStore(directory: folder)
        let actions = library!.orderedActions(on: .list)
        #expect(actions.map(\.name) == expected)
        #expect(actions.map { $0.steps.map(\.type) } == types.map { [$0] })
        #expect(Set(actions.map(\.id)).count == 6)
        #expect(actions.allSatisfy { $0.group == "General" && !$0.symbol.isEmpty })
        var copy = try #require(actions.first)
        copy.steps = [ActionStep("clipboard", ["template": "User template 🐼"])]
        try library!.saveAction(copy)
        library = nil
        let reopened = try LibraryStore(directory: folder)
        #expect(reopened.actions.count == 6)
        #expect(reopened.actions.first { $0.id == copy.id }?.steps == copy.steps)
        #expect(Set(reopened.actions.map(\.id)) == Set(actions.map(\.id)))
    }

    @Test func existingCustomCatalogDoesNotReceiveUnrequestedDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var library: LibraryStore? = try LibraryStore(directory: folder, seed: false)
        let custom = DraftAction(name: "Personal", steps: [ActionStep("clipboard", ["template": "Neutral"])])
        try library!.saveAction(custom)
        library = nil
        let reopened = try LibraryStore(directory: folder)
        #expect(reopened.actions == [custom])
    }
}
