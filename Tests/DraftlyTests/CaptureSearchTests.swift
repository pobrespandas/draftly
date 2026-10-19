import Foundation
import SwiftUI
import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Capture and quick search") @MainActor
struct CaptureSearchTests {
    @Test func searchInputRoutesArrowsReturnAndEscape() {
        var moves: [Int] = []; var opened = false; var cancelled = false
        let input = QuickSearchInput(query: .constant(""), move: { moves.append($0) }, open: { opened = true }, cancel: { cancelled = true })
        let delegate = input.makeCoordinator(), field = NSTextField(), editor = NSTextView()
        for selector in ["moveDown:", "moveUp:", "insertNewline:", "cancelOperation:"] {
            #expect(delegate.control(field, textView: editor, doCommandBy: NSSelectorFromString(selector)))
        }
        #expect(moves == [1, -1]); #expect(opened && cancelled)
        #expect(!delegate.control(field, textView: editor, doCommandBy: NSSelectorFromString("moveLeft:")))
    }
    @Test func captureSurvivesRecreationAndFailureThenClearsOnSave() throws {
        let suite = "DraftlyCaptureTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = CaptureBuffer(defaults: defaults)
        first.text = "Idea ñ 🐼\nSecond line"
        first.receive("Clipboard\nText")
        let reopened = CaptureBuffer(defaults: defaults)
        let expected = "Idea ñ 🐼\nSecond line\n\nClipboard\nText"
        #expect(reopened.text == expected)
        #expect(!reopened.save { _ in throw DraftlyError.message("Disk full") })
        #expect(reopened.text == expected)
        #expect(reopened.error == "Disk full")
        #expect(CaptureBuffer(defaults: defaults).text == expected)
        var saved = ""
        #expect(reopened.save { saved = $0 })
        #expect(saved == expected)
        #expect(CaptureBuffer(defaults: defaults).text.isEmpty)
    }
    @Test func emptyCaptureDoesNotCreateADraftAndDiscardPersists() throws {
        let suite = "DraftlyCaptureTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let buffer = CaptureBuffer(defaults: defaults)
        var wrote = false
        #expect(!buffer.save { _ in wrote = true })
        #expect(!wrote)
        buffer.text = "Temporary"; buffer.discard()
        #expect(CaptureBuffer(defaults: defaults).text.isEmpty)
    }
    @Test func quickSearchIncludesArchiveAndTagsButExcludesTrash() {
        let inbox = Note(content: "Hello Unicode 🐼", tags: ["projects/swift"])
        var archive = Note(content: "Archived Unicode"); archive.isArchived = true
        var trash = Note(content: "Trashed Unicode"); trash.trashedAt = Date()
        let notes = [inbox, archive, trash]
        #expect(Set(QuickSearch.results(in: notes, query: "Unicode").map(\.id)) == [inbox.id, archive.id])
        #expect(QuickSearch.results(in: notes, query: "projects").map(\.id) == [inbox.id])
        #expect(QuickSearch.results(in: notes, query: "🐼").map(\.id) == [inbox.id])
        #expect(QuickSearch.results(in: notes, query: "absent").isEmpty)
    }
}
