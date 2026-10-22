import AppKit
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Library window close protection") @MainActor
struct LibraryWindowCloseTests {
    private enum Failure: LocalizedError {
        case disk
        var errorDescription: String? { "Close test storage failure" }
    }

    private final class ExistingDelegate: NSObject, NSWindowDelegate {
        var allowsClose = true
        var closeChecks = 0
        var zoomChecks = 0
        var didClose = 0
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            closeChecks += 1
            return allowsClose
        }
        func windowWillClose(_ notification: Notification) { didClose += 1 }
        func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
            zoomChecks += 1
            return false
        }
    }

    @Test(arguments: [false, true])
    func rejectedSaveVetoesCloseAndRetryKeepsIdentityTextAndSelection(temporary: Bool) throws {
        let preferences = try TestPreferences(prefix: "Draftly.CloseTests.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        if temporary { #expect(model.create()) }
        else { model.select(try library.createNote(content: "Original neutral text").id) }
        let id = model.editor.noteID
        model.editor.content = "Pending café 🐼"
        model.editor.selection = NSRange(location: 8, length: 4)
        model.contentChanged()
        let app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: preferences.defaults))
        let window = OffscreenTestWindow(contentRect: .init(x: 0, y: 0, width: 850, height: 600),
                                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let existing = ExistingDelegate()
        window.delegate = existing
        app.registerWindow(model, window: window)
        library.beforeBatchCommit = { throw Failure.disk }
        defer { library.beforeBatchCommit = nil; window.delegate = nil }

        #expect(window.delegate?.windowShouldClose?(window) == false)
        #expect(model.hasUnsavedChanges && model.editor.noteID == id)
        #expect(model.editor.content == "Pending café 🐼")
        #expect(model.editor.selection == NSRange(location: 8, length: 4))
        #expect(app.windows.allObjects.contains { $0 === model })
        #expect(library.notes.first(where: { $0.id == id })?.content == (temporary ? nil : "Original neutral text"))
        #expect(library.error == "Close test storage failure")
        #expect(existing.closeChecks == 0)

        library.beforeBatchCommit = nil
        #expect(window.delegate?.windowShouldClose?(window) == true)
        #expect(library.notes.first(where: { $0.id == id })?.content == "Pending café 🐼")
        #expect(model.editor.noteID == id && !model.hasUnsavedChanges)
        #expect(model.editor.selection == NSRange(location: 8, length: 4))
        #expect(existing.closeChecks == 1)
        #expect(!window.isVisible)
    }

    @Test func sceneDelegateVetoAndOtherOptionalMethodsSurviveRepeatedRegistration() throws {
        let preferences = try TestPreferences(prefix: "Draftly.CloseDelegateTests.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        model.select(try library.createNote(content: "Keep neutral text").id)
        let app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: preferences.defaults))
        let window = OffscreenTestWindow(contentRect: .init(x: 0, y: 0, width: 850, height: 600),
                                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let existing = ExistingDelegate()
        existing.allowsClose = false
        window.delegate = existing
        defer { window.delegate = nil }
        app.registerWindow(model, window: window)
        let guardDelegate = try #require(window.delegate as? LibraryWindowCloseGuard)
        app.registerWindow(model, window: window)
        #expect(window.delegate === guardDelegate)
        #expect(window.delegate?.windowShouldClose?(window) == false)
        #expect(existing.closeChecks == 1 && model.editor.content == "Keep neutral text")
        #expect(window.delegate?.windowShouldZoom?(window, toFrame: window.frame) == false)
        #expect(existing.zoomChecks == 1)
        window.delegate?.windowWillClose?(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(existing.didClose == 1)
        #expect(!window.isVisible)
    }

    @Test func closingACleanDuplicateDoesNotOverwriteTheLatestStoredText() throws {
        let preferences = try TestPreferences(prefix: "Draftly.CloseDuplicateTests.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        var note = try library.createNote(content: "Saved café 🐼")
        let model = WindowModel(library: library)
        model.select(note.id)
        model.editor.selection = NSRange(location: 6, length: 4)
        note = try #require(library.notes.first { $0.id == note.id })
        note.content = "Latest café 🐼"
        try library.saveNote(note)
        let stored = try #require(library.notes.first { $0.id == note.id })
        let revisions = library.revisions
        #expect(!model.hasUnsavedChanges && model.editor.content == "Saved café 🐼")
        let app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: preferences.defaults))
        let window = OffscreenTestWindow(contentRect: .init(x: 0, y: 0, width: 850, height: 600),
                                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        app.registerWindow(model, window: window)
        defer { window.delegate = nil }
        #expect(window.delegate?.windowShouldClose?(window) == true)
        #expect(library.notes.first { $0.id == note.id } == stored)
        #expect(library.revisions == revisions)
        #expect(model.editor.content == "Latest café 🐼")
        #expect(model.editor.selection == NSRange(location: 6, length: 4))
    }


    @Test func reregistrationPreservesAReplacementSceneDelegateWithoutRecursion() throws {
        let preferences = try TestPreferences(prefix: "Draftly.CloseReplacementTests.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        let app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: preferences.defaults))
        let window = OffscreenTestWindow(contentRect: .init(x: 0, y: 0, width: 850, height: 600),
                                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let initial = ExistingDelegate(), replacement = ExistingDelegate()
        window.delegate = initial
        defer { window.delegate = nil }
        app.registerWindow(model, window: window)
        let guardDelegate = try #require(window.delegate as? LibraryWindowCloseGuard)
        window.delegate = replacement
        app.registerWindow(model, window: window)
        #expect(window.delegate === guardDelegate)
        #expect(window.delegate?.windowShouldClose?(window) == true)
        #expect(initial.closeChecks == 0 && replacement.closeChecks == 1)
        #expect(window.delegate?.windowShouldZoom?(window, toFrame: window.frame) == false)
        #expect(replacement.zoomChecks == 1)
    }

    @Test func movingTheModelRestoresTheOldDelegateAndProtectsTheNewWindow() throws {
        let preferences = try TestPreferences(prefix: "Draftly.CloseMoveTests.")
        defer { preferences.close() }
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        let app = AppController(library: library, recentDrafts: RecentDraftStore(defaults: preferences.defaults))
        let first = OffscreenTestWindow(contentRect: .init(x: 0, y: 0, width: 850, height: 600),
                                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let second = OffscreenTestWindow(contentRect: first.frame, styleMask: [.titled, .closable],
                                        backing: .buffered, defer: false)
        let firstScene = ExistingDelegate(), secondScene = ExistingDelegate()
        first.delegate = firstScene; second.delegate = secondScene
        defer { first.delegate = nil; second.delegate = nil }
        app.registerWindow(model, window: first)
        let guardDelegate = try #require(first.delegate as? LibraryWindowCloseGuard)
        app.registerWindow(model, window: second)
        #expect(first.delegate === firstScene && second.delegate === guardDelegate)
        #expect(model.window === second)
        #expect(second.delegate?.windowShouldClose?(second) == true)
        #expect(firstScene.closeChecks == 0 && secondScene.closeChecks == 1)
    }

}
