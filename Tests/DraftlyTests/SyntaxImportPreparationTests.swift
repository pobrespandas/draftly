import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Syntax import choices") @MainActor
struct SyntaxImportPreparationTests {
    private func definition(_ name: String = "Neutral café 🐼", type: String = "custom") throws -> SyntaxDefinition {
        try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: ["name": name,
            "patterns": [], "navigationPatterns": [], "indentationPatterns": [], "linkDefinitions": [], "taskMarkDefinitions": [],
            "future": ["keep": true]]), type: type)
    }

    @Test func replacingKeepsIdentityAndDoesNotSaveBeforeTheCallerCommits() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = try definition()
        try library.saveSyntax(original)
        let incoming = try definition()
        let result = try #require(try SyntaxImportPreparation.prepare(incoming, installed: library.syntaxes, choice: .replace))
        #expect(result.id == original.id && result.source == incoming.source)
        #expect(library.syntaxes == [original])
        #expect(try SyntaxImportPreparation.prepare(incoming, installed: library.syntaxes, choice: .cancel) == nil)
        #expect(library.syntaxes == [original])
    }

    @Test func importingAsNewChangesOnlyNameAndIdentityAndRetainsBackupData() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = try definition()
        try library.saveSyntax(original)
        let copy = try #require(try SyntaxImportPreparation.prepare(original, installed: library.syntaxes, choice: .copy("Copy café 🐼")))
        #expect(copy.id != original.id && copy.name == "Copy café 🐼" && copy.type == "custom")
        var expected = original.object; expected["name"] = copy.name
        #expect((copy.object as NSDictionary).isEqual(to: expected))
        #expect(library.syntaxes == [original])
        try library.saveSyntax(copy)
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData())
        #expect(Set(restored.syntaxes.map(\.id)) == [original.id, copy.id])
        #expect(restored.syntaxes.first { $0.id == copy.id }?.source == copy.source)
    }

    @Test func conflictingNamesBuiltInsAndFileCopiesFailWithoutChanges() throws {
        let original = try definition(), incoming = try definition()
        for name in ["", "   ", original.name, "Markdown"] {
            #expect(throws: (any Error).self) { try SyntaxImportPreparation.prepare(incoming, installed: [original], choice: .copy(name)) }
        }
        #expect(throws: (any Error).self) { try SyntaxImportPreparation.prepare(definition("Markdown"), installed: [], choice: .replace) }
        #expect(try SyntaxImportPreparation.prepare(definition("Markdown"), installed: [], choice: .copy("Imported Markdown"))?.name == "Imported Markdown")
        #expect(throws: (any Error).self) { try SyntaxImportPreparation.prepare(definition(type: "file"), installed: [original], choice: .copy("File copy")) }
    }

    @Test func failedCopySaveKeepsOriginalAndRetryUsesThePreparedIdentity() throws {
        enum Failure: Error { case storage }
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = try definition(); try library.saveSyntax(original)
        let copy = try #require(try SyntaxImportPreparation.prepare(original, installed: library.syntaxes, choice: .copy("Neutral copy")))
        library.beforeBatchCommit = { throw Failure.storage }
        #expect(throws: Failure.storage) { try library.saveSyntax(copy) }
        #expect(library.syntaxes == [original])
        library.beforeBatchCommit = nil
        try library.saveSyntax(copy)
        #expect(Set(library.syntaxes.map(\.id)) == [original.id, copy.id])
    }

    @Test func linkInstallationHandlesIdenticalCancelledAndFailedWrites() throws {
        enum Failure: Error { case storage }
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = try definition(); try library.saveSyntax(original)
        let data = Data(original.source.utf8)
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installSyntax(data, library: nil) { incoming, _ in incoming }
        }
        #expect(try ApplicationURLRouter.installSyntax(data, library: library) { _, _ in
            Issue.record("An identical syntax must not require review"); return nil
        })
        var object = original.object; object["future"] = ["keep": false]
        let replacement = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(try !ApplicationURLRouter.installSyntax(replacement, library: library) { _, _ in nil })
        try library.reload(); #expect(library.syntaxes == [original])
        library.beforeBatchCommit = { throw Failure.storage }
        #expect(throws: Failure.storage) {
            try ApplicationURLRouter.installSyntax(replacement, library: library) { incoming, store in
                try SyntaxImportPreparation.prepare(incoming, installed: store.syntaxes, choice: .replace)
            }
        }
        library.beforeBatchCommit = nil
        try library.reload(); #expect(library.syntaxes == [original])
        #expect(try ApplicationURLRouter.installSyntax(replacement, library: library) { incoming, store in
            try SyntaxImportPreparation.prepare(incoming, installed: store.syntaxes, choice: .replace)
        })
        try library.reload()
        #expect(library.syntaxes.first?.id == original.id)
        #expect(library.syntaxes.first?.source == String(decoding: replacement, as: UTF8.self))
    }
}
