import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Workspace URL installation") @MainActor
struct URLWorkspaceInstallationTests {
    private func link(_ values: [String: Any]) throws -> URL {
        var components = URLComponents()
        components.scheme = "draftly"; components.host = "workspace"
        let data = try JSONSerialization.data(withJSONObject: values)
        components.queryItems = [URLQueryItem(name: "data", value: String(decoding: data, as: UTF8.self))]
        return try #require(components.url)
    }

    @Test func replacementRequiresConfirmationAndPreservesIdentity() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = Workspace(name: "Original 🐼")
        try library.saveWorkspace(original)
        let url = try link(["uuid": original.id.uuidString, "name": "Updated café", "future": ["keep": true]])
        let before = try library.backupData()
        #expect(try !ApplicationURLRouter.installWorkspace(url, library: library) { $0.id != original.id })
        #expect(try library.backupData() == before)
        #expect(try ApplicationURLRouter.installWorkspace(url, library: library) { $0.id == original.id })
        let installed = try #require(library.workspaces.first)
        #expect(installed.id == original.id && installed.name == "Updated café")
        #expect(installed.scriptMetadata?["api"]?.contains("future") == true)
        try library.reload()
        #expect(library.workspaces == [installed])
        let recovered = try LibraryStore(inMemory: true, seed: false)
        try recovered.restore(library.backupData())
        #expect(recovered.workspaces == [installed])
    }

    @Test func concurrentChangesAndMissingLibraryFailExplicitly() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = Workspace(name: "Original")
        try library.saveWorkspace(original)
        let url = try link(["uuid": original.id.uuidString, "name": "Incoming"])
        var newer = original; newer.name = "Local edit"
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installWorkspace(url, library: library) { _ in
                do { try library.saveWorkspace(newer) } catch { Issue.record(error) }
                return true
            }
        }
        #expect(library.workspaces == [newer])
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installWorkspace(url, library: nil) { _ in true } }
    }

    @Test func newAndIdenticalLinksNeedNoConfirmationAndSaveFailuresRollBack() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let id = UUID()
        let url = try link(["uuid": id.uuidString, "name": "Neutral", "future": ["text": "café 🐼"]])
        #expect(try ApplicationURLRouter.installWorkspace(url, library: library) { _ in
            Issue.record("A new workspace requested replacement."); return false
        })
        let original = try #require(library.workspaces.first)
        #expect(try ApplicationURLRouter.installWorkspace(url, library: library) { _ in
            Issue.record("An identical workspace requested replacement."); return false
        })
        let before = try library.backupData()
        let replacement = try link(["uuid": id.uuidString, "name": "Updated"])
        library.beforeBatchCommit = { throw DraftlyError.message("Injected save failure") }
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installWorkspace(replacement, library: library) { _ in true }
        }
        library.beforeBatchCommit = nil
        #expect(library.workspaces == [original])
        #expect(try library.backupData() == before)
        try library.reload()
        #expect(library.workspaces == [original])
    }
}
