import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Theme URL installation") @MainActor
struct URLThemeInstallationTests {
    @Test func roundTripPreservesUnknownFieldsAndDoesNotSelectTheTheme() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = EditorThemeDefinition(name: "Install café 🐼 &?%", unknownFields: ["future": .array([.bool(false), .string("🦊\n&?%")])])
        let beforeNotes = library.notes
        #expect(try ApplicationURLRouter.installTheme(ThemeInstallation.custom(original).url, library: library) { _ in
            Issue.record("A new theme requested replacement."); return false
        })
        #expect(library.themes == [original] && library.notes == beforeNotes)
        try library.reload(); #expect(library.themes == [original])
        let restored = try LibraryStore(inMemory: true, seed: false)
        try restored.restore(library.backupData()); #expect(restored.themes == [original])
        #expect(try ApplicationURLRouter.installTheme(ThemeInstallation.custom(original).url, library: library) { _ in
            Issue.record("An identical theme requested replacement."); return false
        })
        for name in ThemeCatalog.builtInNames {
            #expect(try ApplicationURLRouter.installTheme(ThemeInstallation.builtIn(name).url, library: library) { _ in
                Issue.record("A built-in theme requested replacement."); return false
            })
        }
        #expect(library.themes == [original])
    }

    @Test func cancellationAndConfirmedNameReplacementKeepExistingIdentity() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = EditorThemeDefinition(name: "Same name")
        try library.saveTheme(original)
        var incoming = EditorThemeDefinition(name: original.name, background: "123456")
        incoming.unknownFields = ["future": .string("keep")]
        let before = try library.backupData()
        var calls: [UUID] = []
        let url = try ThemeInstallation.custom(incoming).url
        #expect(try !ApplicationURLRouter.installTheme(url, library: library) { calls.append($0.id); return false })
        #expect(calls == [original.id] && library.themes == [original])
        #expect(try library.backupData() == before)
        #expect(try ApplicationURLRouter.installTheme(url, library: library) { calls.append($0.id); return true })
        incoming.id = original.id
        #expect(library.themes == [incoming])
        try library.reload(); #expect(library.themes == [incoming])
    }

    @Test func conflictingIdentityOrCommitFailureCannotPartiallyReplaceThemes() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let first = EditorThemeDefinition(name: "First"), second = EditorThemeDefinition(name: "Second")
        try library.saveThemes([first, second])
        let before = try library.backupData()
        var collision = first; collision.name = second.name
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installTheme(ThemeInstallation.custom(collision).url, library: library) { _ in
                Issue.record("An invalid identity collision requested replacement."); return true
            }
        }
        #expect(try library.backupData() == before)
        var replacement = first; replacement.background = "102030"
        library.beforeBatchCommit = { throw DraftlyError.message("Injected theme commit failure") }
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installTheme(ThemeInstallation.custom(replacement).url, library: library) { _ in true }
        }
        library.beforeBatchCommit = nil
        #expect(try library.backupData() == before)
        try library.reload(); #expect(try library.backupData() == before)
    }

    @Test func aChangeDuringConfirmationCannotBeOverwritten() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let original = EditorThemeDefinition(name: "Pending confirmation")
        try library.saveTheme(original)
        var incoming = original; incoming.background = "123456"
        var newer = original; newer.background = "ABCDEF"
        let url = try ThemeInstallation.custom(incoming).url
        #expect(throws: (any Error).self) {
            try ApplicationURLRouter.installTheme(url, library: library) { _ in
                do { try library.saveTheme(newer) } catch { Issue.record(error) }
                return true
            }
        }
        #expect(library.themes == [newer])
        try library.reload(); #expect(library.themes == [newer])
    }

    @Test func malformedLinksAndMissingLibraryFailBeforeConfirmation() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        for text in ["draftly://theme?data=invalid", "draftly://theme?name=Missing", "draftly://theme?type=file&name=Dark"] {
            #expect(throws: (any Error).self) {
                try ApplicationURLRouter.installTheme(URL(string: text)!, library: library) { _ in
                    Issue.record("Invalid links must fail before confirmation."); return false
                }
            }
        }
        let url = try ThemeInstallation.builtIn("Dark").url
        #expect(throws: (any Error).self) { try ApplicationURLRouter.installTheme(url, library: nil) { _ in false } }
        #expect(library.themes.isEmpty)
    }
}
