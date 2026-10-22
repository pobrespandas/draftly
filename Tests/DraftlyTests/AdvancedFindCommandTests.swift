import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Advanced Find commands") @MainActor
struct AdvancedFindCommandTests {
    private let content = "🐼 café café\nTail"

    private func model(defaults: UserDefaults) throws -> WindowModel {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: content)
        let dependencies = WindowDependencies(preferences: WindowPreferences(defaults: defaults))
        let model = WindowModel(library: library, dependencies: dependencies)
        model.select(note.id)
        return model
    }

    @Test(arguments: [false, true])
    func navigationUsesUTF16SelectionBoundariesAndWraps(backward: Bool) throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindNavigation.")
        defer { preferences.close() }
        let model = try model(defaults: preferences.defaults)
        let commands = AdvancedFindCommands(model: model)
        let ranges = try EditorFindQuery("café").matches(in: content)
        #expect(ranges == [NSRange(location: 3, length: 4), NSRange(location: 8, length: 4)])
        let cases: [(selection: NSRange, next: NSRange, previous: NSRange)] = [
            (NSRange(location: 0, length: 0), ranges[0], ranges[1]),
            (ranges[0], ranges[1], ranges[1]),
            (ranges[1], ranges[0], ranges[0]),
            (NSRange(location: 5, length: 0), ranges[1], ranges[0]),
            (NSRange(location: 2, length: 7), ranges[0], ranges[1]),
            (NSRange(location: 999, length: 999), ranges[0], ranges[1])
        ]
        var synchronized: [NSRange] = []
        model.editor.synchronizeScriptEdit = { synchronized.append(model.editor.selection) }
        defer { model.editor.synchronizeScriptEdit = nil }
        let focus = model.editor.focusToken
        for row in cases {
            model.editor.selection = row.selection
            commands.navigate(in: ranges, backward: backward)
            let expected = backward ? row.previous : row.next
            #expect(model.editor.selection == expected)
            #expect(synchronized.last == expected)
        }
        #expect(synchronized.count == cases.count)
        #expect(model.editor.content == content && model.library.notes.first?.content == content)
        #expect(model.editor.focusToken == focus && !model.hasUnsavedChanges)
    }

    @Test func zeroLengthMatchesAdvanceWithoutSplittingUnicodeAndWrapToThemselvesWhenAlone() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindZeroLength.")
        defer { preferences.close() }
        let model = try model(defaults: preferences.defaults)
        let commands = AdvancedFindCommands(model: model)
        let ranges = try EditorFindQuery("(?=café)|$", regularExpression: true).matches(in: content)
        #expect(ranges == [NSRange(location: 3, length: 0), NSRange(location: 8, length: 0), NSRange(location: 17, length: 0)])
        var synchronizations = 0
        model.editor.synchronizeScriptEdit = { synchronizations += 1 }
        defer { model.editor.synchronizeScriptEdit = nil }
        model.editor.selection = ranges[0]
        commands.navigate(in: ranges, backward: false)
        #expect(model.editor.selection == ranges[1])
        model.editor.selection = ranges[0]
        commands.navigate(in: ranges, backward: true)
        #expect(model.editor.selection == ranges[2])
        commands.navigate(in: [ranges[2]], backward: false)
        #expect(model.editor.selection == ranges[2])
        commands.navigate(in: [ranges[2]], backward: true)
        #expect(model.editor.selection == ranges[2])
        #expect(synchronizations == 4 && model.editor.content == content)
    }

    @Test func noMatchesLeaveEvenAnOutOfBoundsSelectionAndFocusUnchanged() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindNoMatches.")
        defer { preferences.close() }
        let model = try model(defaults: preferences.defaults)
        let commands = AdvancedFindCommands(model: model)
        let selection = NSRange(location: 999, length: 999)
        model.editor.selection = selection
        let focus = model.editor.focusToken
        var synchronizations = 0
        model.editor.synchronizeScriptEdit = { synchronizations += 1 }
        defer { model.editor.synchronizeScriptEdit = nil }
        let noMatches = try EditorFindQuery("missing").matches(in: content)
        let invalidQuery = Result { try EditorFindQuery("[", regularExpression: true) }
        let invalidMatches = (try? invalidQuery.get().matches(in: content)) ?? []
        for ranges in [noMatches, invalidMatches] {
            commands.navigate(in: ranges, backward: false)
            commands.navigate(in: ranges, backward: true)
        }
        #expect(model.editor.selection == selection && model.editor.focusToken == focus)
        #expect(synchronizations == 0 && !model.hasUnsavedChanges)
        #expect(model.editor.content == content && model.library.notes.first?.content == content)
    }

    @Test func choosingAResultSynchronizesOnlyThatEditorsSelection() throws {
        let preferences = try TestPreferences(prefix: "Draftly.FindSelection.")
        defer { preferences.close() }
        let model = try model(defaults: preferences.defaults)
        let other = WindowModel(library: model.library,
            dependencies: WindowDependencies(preferences: WindowPreferences(defaults: preferences.defaults)))
        other.select(model.editor.noteID)
        other.editor.selection = NSRange(location: 0, length: 2)
        var synchronizations = 0
        model.editor.synchronizeScriptEdit = { synchronizations += 1 }
        other.editor.synchronizeScriptEdit = { Issue.record("Another editor must not synchronize.") }
        defer { model.editor.synchronizeScriptEdit = nil; other.editor.synchronizeScriptEdit = nil }
        let focus = model.editor.focusToken
        AdvancedFindCommands(model: model).select(NSRange(location: 3, length: 4))
        #expect(model.editor.selectedText == "café" && synchronizations == 1)
        #expect(other.editor.selection == NSRange(location: 0, length: 2))
        #expect(model.editor.content == content && model.library.notes.first?.content == content)
        #expect(model.editor.focusToken == focus && !model.hasUnsavedChanges)
    }
}
