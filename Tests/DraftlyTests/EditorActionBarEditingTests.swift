import Foundation
import Testing
@testable import DraftlyCore
@testable import Draftly

@Suite("Editing bar text operations") @MainActor
struct EditorActionBarEditingTests {
    @Test(arguments: [
        EditingBarCase("left over emoji", "A🐼e\u{301}Z", range(3), expected: range(1), direction: -1),
        EditingBarCase("right over emoji", "A🐼e\u{301}Z", range(1), expected: range(3)),
        EditingBarCase("left over combining sequence", "A🐼e\u{301}Z", range(5), expected: range(3), direction: -1),
        EditingBarCase("right over combining sequence", "A🐼e\u{301}Z", range(3), expected: range(5)),
        EditingBarCase("right over joined family", "👨‍👩‍👧‍👦Z", range(0), expected: range(11)),
        EditingBarCase("right over flag", "🇦🇷Z", range(0), expected: range(4)),
        EditingBarCase("left before selected sequence", "A🐼e\u{301}Z", range(3, 2), expected: range(1), direction: -1),
        EditingBarCase("right after selected sequence", "A🐼e\u{301}Z", range(1, 2), expected: range(5)),
        EditingBarCase("left document boundary", "A🐼", range(0, 1), expected: range(0, 1), direction: -1),
        EditingBarCase("right document boundary", "A🐼", range(3), expected: range(3)),
        EditingBarCase("safe left from invalid location", "A🐼Z", range(100, 999), expected: range(3), direction: -1),
        EditingBarCase("right boundary retains raw invalid range", "A🐼Z", range(100, 999), expected: range(100, 999)),
        EditingBarCase("left boundary retains raw negative range", "A🐼Z", range(-5, 3), expected: range(-5, 3), direction: -1),
        EditingBarCase("empty document still focuses", "", range(0), expected: range(0))
    ])
    func characterMovementUsesComposedUTF16RangesWithoutSaving(_ scenario: EditingBarCase) throws {
        try withBar(scenario.text, selection: scenario.selection) { fixture in
            let focus = fixture.model.editor.focusToken
            fixture.bar.move(scenario.direction)
            verify(scenario, fixture: fixture, previousFocus: focus)
        }
    }

    @Test(arguments: [
        EditingBarCase("up keeps current text order", "one\ntwo\nthree", range(4, 3), expected: range(0, 3), direction: -1),
        EditingBarCase("up first line boundary", "one\ntwo\nthree", range(0, 3), expected: range(0, 3), direction: -1, focuses: false),
        EditingBarCase("down swaps adjacent lines", "one\ntwo\nthree", range(0, 3), expected: range(4, 3), content: "two\none\nthree", dirty: true),
        EditingBarCase("down final line boundary", "one\ntwo\nthree", range(8, 5), expected: range(8, 5), focuses: false),
        EditingBarCase("down selected line block", "a\nb\nc\nd\n", range(0, 3), expected: range(2, 3), content: "c\na\nb\nd\n", dirty: true),
        EditingBarCase("up selected block keeps text order", "a\nb\nc\nd\n", range(2, 3), expected: range(0, 3), direction: -1),
        EditingBarCase("down unterminated neighbor", "a\nb", range(0, 1), expected: range(1, 1), content: "ba\n", dirty: true),
        EditingBarCase("down CRLF lines", "a\r\nb\r\n", range(0, 1), expected: range(3, 1), content: "b\r\na\r\n", dirty: true),
        EditingBarCase("up empty final line", "a\n", range(2), expected: range(0), direction: -1),
        EditingBarCase("empty document does not focus", "", range(0), expected: range(0), focuses: false)
    ])
    func lineMovementRetainsCurrentOrderingSelectionAndSaveBehavior(_ scenario: EditingBarCase) throws {
        try withBar(scenario.text, selection: scenario.selection) { fixture in
            let focus = fixture.model.editor.focusToken
            fixture.bar.moveLine(scenario.direction)
            verify(scenario, fixture: fixture, previousFocus: focus)
        }
    }

    @Test(arguments: [
        EditingBarCase("Unicode line from interior UTF16 position", "🐼\nlast", range(1), expected: range(3, 3), content: "🐼\n🐼\nlast", dirty: true),
        EditingBarCase("unterminated final line concatenates", "a\nlast", range(3), expected: range(6, 4), content: "a\nlastlast", dirty: true),
        EditingBarCase("terminated final line", "a\nlast\n", range(3), expected: range(7, 5), content: "a\nlast\nlast\n", dirty: true),
        EditingBarCase("selected line block", "a\nb\nc", range(0, 3), expected: range(4, 4), content: "a\nb\na\nb\nc", dirty: true),
        EditingBarCase("CRLF final line", "a\r\nb\r\n", range(3), expected: range(6, 3), content: "a\r\nb\r\nb\r\n", dirty: true),
        EditingBarCase("empty final line still focuses", "a\n", range(2), expected: range(2)),
        EditingBarCase("safe final line from invalid location", "a\nb", range(999), expected: range(3, 1), content: "a\nbb", dirty: true),
        EditingBarCase("empty document does not focus", "", range(0), expected: range(0), focuses: false)
    ])
    func duplicationRetainsCurrentLineBoundariesAndSaveBehavior(_ scenario: EditingBarCase) throws {
        try withBar(scenario.text, selection: scenario.selection) { fixture in
            let focus = fixture.model.editor.focusToken
            fixture.bar.duplicateLine()
            verify(scenario, fixture: fixture, previousFocus: focus)
        }
    }

    @Test(arguments: [
        EditingBarCase("next Unicode heading", "# 🐼\nbody\n## café\n", range(0), expected: range(10, 7)),
        EditingBarCase("previous wraps to final heading", "# 🐼\nbody\n## café\n", range(0), expected: range(10, 7), direction: -1),
        EditingBarCase("previous heading", "# 🐼\nbody\n## café\n", range(10), expected: range(0, 4), direction: -1),
        EditingBarCase("next wraps to first heading", "# 🐼\nbody\n## café\n", range(10), expected: range(0, 4)),
        EditingBarCase("inside heading selects current previous", "# 🐼\nbody\n## café\n", range(2, 1), expected: range(0, 4), direction: -1),
        EditingBarCase("single heading refocuses", "# café", range(0, 6), expected: range(0, 6)),
        EditingBarCase("plain text has no markers", "Plain 🐼", range(0), expected: range(0), focuses: false),
        EditingBarCase("non-Markdown marker remains unmatched", "Project:\n\t- task\n", range(0), expected: range(0), focuses: false)
    ])
    func markerNavigationRetainsMarkdownSelectionAndWrapping(_ scenario: EditingBarCase) throws {
        try withBar(scenario.text, selection: scenario.selection) { fixture in
            let focus = fixture.model.editor.focusToken
            fixture.bar.moveToMarker(scenario.direction)
            verify(scenario, fixture: fixture, previousFocus: focus)
        }
    }

    @Test func markerNavigationUsesAssignedSyntaxAndSynchronizesWithoutSaving() throws {
        let text = "🐼\r\n! Café\r\n# ignored\r\n! Last"
        try withBar(text, selection: range(0)) { fixture in
            let syntax = try SyntaxDefinition(data: JSONSerialization.data(withJSONObject: [
                "name": "Neutral markers", "patterns": [], "taskMarkDefinitions": [], "linkDefinitions": [], "indentationPatterns": [],
                "navigationPatterns": [["match": "^! ([^\r\n]*)", "rangeCapture": "1", "labelCapture": "1", "level": 0]]]))
            try fixture.library.saveSyntax(syntax)
            var note = try #require(fixture.model.currentNote); note.syntax = syntax.name
            try fixture.library.saveNote(note)
            let expected = (text as NSString).range(of: "Café")
            var synchronized: [NSRange] = []
            fixture.model.editor.synchronizeScriptEdit = { synchronized.append(fixture.model.editor.selection) }
            defer { fixture.model.editor.synchronizeScriptEdit = nil }
            fixture.bar.moveToMarker(1)
            #expect(fixture.model.editor.selection == expected)
            fixture.bar.moveToMarker(-1)
            #expect(fixture.model.editor.selectedText == "Last")
            #expect(synchronized.count == 2)
            #expect(fixture.model.editor.content == text && !fixture.model.hasUnsavedChanges)
        }
    }

    @Test func taskPaperMarkersAndMissingSyntaxDoNotFallBackToMarkdown() throws {
        let text = "🐼\n# not a project\nProject:\n- task\nLast:"
        try withBar(text, selection: range(0)) { fixture in
            var note = try #require(fixture.model.currentNote); note.syntax = "TaskPaper"
            try fixture.library.saveNote(note)
            fixture.bar.moveToMarker(1)
            #expect(fixture.model.editor.selectedText == "Project:")
            let selection = fixture.model.editor.selection
            note.syntax = "Plain Text"; try fixture.library.saveNote(note)
            let focus = fixture.model.editor.focusToken
            fixture.bar.moveToMarker(1)
            #expect(fixture.model.editor.selection == selection && fixture.model.editor.focusToken == focus)
            note.syntax = "Missing syntax"; try fixture.library.saveNote(note)
            fixture.bar.moveToMarker(1)
            #expect(fixture.library.error?.contains("Missing syntax") == true)
            #expect(fixture.model.editor.selection == selection && fixture.model.editor.content == text)
        }
    }

    private func verify(_ scenario: EditingBarCase, fixture: Fixture, previousFocus: UUID) {
        let expected = scenario.content ?? scenario.text
        #expect(fixture.model.editor.content == expected)
        #expect(fixture.model.editor.selection == scenario.expected)
        #expect((fixture.model.editor.focusToken != previousFocus) == scenario.focuses)
        #expect(fixture.model.hasUnsavedChanges == scenario.dirty)
        #expect(fixture.library.notes.first { $0.id == fixture.noteID }?.content == scenario.text)
        #expect(fixture.model.flush())
        #expect(!fixture.model.hasUnsavedChanges)
        #expect(fixture.library.notes.first { $0.id == fixture.noteID }?.content == expected)
        #expect(fixture.model.editor.selection == scenario.expected)
    }

    private func withBar(_ text: String, selection: NSRange, _ body: (Fixture) throws -> Void) throws {
        let domain = "Draftly-EditorActionBarEditing-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: text)
        var dependencies = WindowDependencies()
        dependencies.preferences = WindowPreferences(defaults: defaults)
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(note.id)
        model.editor.selection = selection
        let bar = EditorActionBar(model: model, session: model.editor, library: library)
        try body(Fixture(library: library, model: model, bar: bar, noteID: note.id))
    }

    private struct Fixture {
        let library: LibraryStore
        let model: WindowModel
        let bar: EditorActionBar
        let noteID: UUID
    }
}

struct EditingBarCase: Sendable, CustomTestStringConvertible {
    let name: String
    let text: String
    let selection: NSRange
    let expected: NSRange
    let direction: Int
    let content: String?
    let focuses: Bool
    let dirty: Bool
    var testDescription: String { name }

    init(_ name: String, _ text: String, _ selection: NSRange, expected: NSRange,
         direction: Int = 1, content: String? = nil, focuses: Bool = true, dirty: Bool = false) {
        self.name = name; self.text = text; self.selection = selection; self.expected = expected
        self.direction = direction; self.content = content; self.focuses = focuses; self.dirty = dirty
    }
}

private func range(_ location: Int, _ length: Int = 0) -> NSRange {
    NSRange(location: location, length: length)
}
