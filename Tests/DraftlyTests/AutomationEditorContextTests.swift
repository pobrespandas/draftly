import AppKit
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Automation editor context") @MainActor
struct AutomationEditorContextTests {
    @Test func visibleContextPrefersMatchingKeyThenMainThenVisibleWindows() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Target"), other = try library.createNote(content: "Other")
        func model(_ note: Note) -> WindowModel { let model = WindowModel(library: library); model.select(note.id); return model }
        let visible = model(target), main = model(target), key = model(target), hidden = model(target), wrong = model(other)
        let models = [wrong, hidden, visible, main, key]
        var states = [
            ObjectIdentifier(visible): AutomationActionExecution.WindowState(isVisible: true, isKey: false, isMain: false, order: 10),
            ObjectIdentifier(main): .init(isVisible: true, isKey: false, isMain: true, order: 20),
            ObjectIdentifier(key): .init(isVisible: true, isKey: true, isMain: false, order: 30),
            ObjectIdentifier(hidden): .init(isVisible: false, isKey: true, isMain: true, order: 1),
            ObjectIdentifier(wrong): .init(isVisible: true, isKey: true, isMain: true, order: 0)
        ]
        #expect(AutomationActionExecution.visibleModel(models, noteID: target.id, describe: { states[ObjectIdentifier($0)] }) === key)
        states[ObjectIdentifier(key)]?.isKey = false
        #expect(AutomationActionExecution.visibleModel(models, noteID: target.id, describe: { states[ObjectIdentifier($0)] }) === main)
        states[ObjectIdentifier(main)]?.isVisible = false
        #expect(AutomationActionExecution.visibleModel(models, noteID: target.id, describe: { states[ObjectIdentifier($0)] }) === visible)
        states[ObjectIdentifier(visible)]?.isVisible = false
        states[ObjectIdentifier(key)]?.isVisible = false
        #expect(AutomationActionExecution.visibleModel(models, noteID: target.id, describe: { states[ObjectIdentifier($0)] }) == nil)
    }

    @Test func matchingContextUsesItsActualEditorUndoAndUIWithoutChangingAnotherDraft() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "🐼 café\nTail"), other = try library.createNote(content: "Other")
        let model = WindowModel(library: library), otherModel = WindowModel(library: library)
        model.select(target.id); otherModel.select(other.id)
        otherModel.editor.content = "Pending other draft"; otherModel.contentChanged()
        let native = NativeEditor(session: model.editor, fontName: "System", fontSize: 17, lineSpacing: 2, markdown: false, onChange: { [weak model] in
            model?.contentChanged(); _ = model?.flush()
        })
        let coordinator = NativeEditor.Coordinator(native), text = TestUndoTextView(frame: .zero)
        text.string = target.content; coordinator.textView = text; text.manager.groupsByEvent = false
        model.editor.synchronizeScriptEdit = {
            text.manager.beginUndoGrouping(); coordinator.synchronizeScriptEdit(); text.manager.endUndoGrouping()
        }
        model.editor.performUndo = { redo in if redo { text.manager.redo() } else { text.manager.undo() } }
        defer {
            model.editor.synchronizeScriptEdit = nil; model.editor.performUndo = nil
            coordinator.textView = nil; text.manager.removeAllActions()
        }
        let fallback = UnusedAutomationContextHost()
        let action = DraftAction(name: "Actual editor context", steps: [ActionStep("script", ["script": """
        function check(value,label){if(!value)throw new Error(label);}
        editor.setSelectedRange(3,4);editor.setSelectedText('té');
        editor.undo();check(editor.getText()==='🐼 café\\nTail','undo source');
        editor.redo();check(editor.getText()==='🐼 té\\nTail','redo content');
        editor.showFind(true,'neutral');
        """])])
        let output = try await AutomationActionExecution.run(action, noteID: target.id, library: library,
            models: [otherModel, model], host: fallback, resolveModel: { models, id in models.first { $0.editor.noteID == id } })
        #expect(output.report.reason == .success && model.runner.lastReport == output.report)
        #expect(model.editor.content == "🐼 té\nTail" && text.string == model.editor.content)
        #expect(model.editor.selection == text.selectedRange())
        #expect(model.showAdvancedFind && model.advancedFindQuery == "neutral")
        #expect(!otherModel.showAdvancedFind && otherModel.editor.noteID == other.id)
        #expect(otherModel.editor.content == "Pending other draft" && !otherModel.hasUnsavedChanges)
        #expect(library.notes.first { $0.id == other.id }?.content == "Pending other draft")
        #expect(fallback.calls == 0)
    }

    @Test(arguments: [false, true])
    func cleanDuplicateEditorCannotOverwritePendingOwnerText(ownerFirst: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Stored café 🐼")
        var savedContents: [String] = []
        let save: (Note) throws -> Void = { note in
            savedContents.append(note.content); try library.saveNote(note)
        }
        let owner = WindowModel(library: library, saveDraft: save)
        let duplicate = WindowModel(library: library, saveDraft: save)
        owner.select(note.id); duplicate.select(note.id)
        owner.editor.content = "Pending café 🐼"; owner.contentChanged()
        let action = DraftAction(name: "Append to pending text", steps: [
            ActionStep("script", ["script": "editor.setText(editor.getText()+' done');draft.update();"])
        ])
        let output = try await AutomationActionExecution.run(action, noteID: note.id, library: library,
            models: ownerFirst ? [owner, duplicate] : [duplicate, owner], host: UnusedAutomationContextHost(),
            resolveModel: { _, _ in owner })
        #expect(output.report.reason == .success)
        #expect(owner.editor.content == "Pending café 🐼 done")
        #expect(library.notes.first { $0.id == note.id }?.content == "Pending café 🐼 done")
        #expect(owner.runner.lastReport == output.report && duplicate.runner.lastReport == nil)
        #expect(!savedContents.contains("Stored café 🐼"), "A clean stale editor must not write an older version.")
        #expect(!owner.hasUnsavedChanges && !duplicate.hasUnsavedChanges)
    }

    @Test(arguments: [false, true])
    func busyReservationIsRejectedBeforeAnyPendingDraftIsSaved(ownerIsTarget: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Stored target"), other = try library.createNote(content: "Stored other")
        var saves = 0
        let targetModel = WindowModel(library: library, saveDraft: { note in saves += 1; try library.saveNote(note) })
        let otherModel = WindowModel(library: library, saveDraft: { note in saves += 1; try library.saveNote(note) })
        targetModel.select(target.id); otherModel.select(other.id)
        targetModel.editor.content = "Pending target"; targetModel.contentChanged()
        otherModel.editor.content = "Pending other"; otherModel.contentChanged()
        let owner = ownerIsTarget ? targetModel : otherModel
        owner.actionPending = true
        defer { owner.actionPending = false }
        let output = try await AutomationActionExecution.run(DraftAction(name: "Rejected", steps: []), noteID: target.id,
            library: library, models: [otherModel, targetModel], host: UnusedAutomationContextHost(),
            resolveModel: { models, id in models.first { $0.editor.noteID == id } })
        #expect(output.report.reason == .busy && output.report.successParameters.isEmpty)
        #expect(saves == 0 && library.runs.isEmpty)
        #expect(owner.actionPending && owner.runner.lastReport == nil)
        #expect(targetModel.hasUnsavedChanges && otherModel.hasUnsavedChanges)
        #expect(targetModel.editor.content == "Pending target" && otherModel.editor.content == "Pending other")
        #expect(library.notes.first { $0.id == target.id }?.content == target.content)
        #expect(library.notes.first { $0.id == other.id }?.content == other.content)
    }

    @Test(arguments: ["close", "stored edit"])
    func ownedContextCancelsWithoutRetargetingOrOverwritingConcurrentText(interruption: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Source")
        let owner = WindowModel(library: library), alternate = WindowModel(library: library)
        owner.select(target.id); alternate.select(target.id)
        let host = WaitingAutomationContextHost()
        owner.runner.host = host
        var resolutions = 0
        let action = DraftAction(name: "Owned context", steps: [ActionStep("script", ["script": "editor.arrange('Neutral');editor.setText('Late write');"])])
        let task = Task { try await AutomationActionExecution.run(action, noteID: target.id, library: library,
            models: [alternate, owner], host: UnusedAutomationContextHost(), resolveModel: { _, _ in resolutions += 1; return owner }) }
        await host.waitForStart()
        if interruption == "close" { owner.cancelActions() }
        else {
            var changed = target; changed.content = "Concurrent external text"
            try library.saveNote(changed)
        }
        let output = try await task.value
        #expect(output.report.reason == .cancelled && resolutions == 1)
        #expect(owner.runner.lastReport == output.report && alternate.runner.lastReport == nil)
        #expect(!host.finish("Late response"))
        let expected = interruption == "close" ? target.content : "Concurrent external text"
        #expect(owner.editor.content == expected)
        #expect(library.notes.first?.content == expected)
    }

    @Test func ownerCloseBeforeChildStartsDoesNotFlushOrExecute() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Stored")
        var saves = 0, removals = 0
        let model = WindowModel(library: library, saveDraft: { note in saves += 1; try library.saveNote(note) })
        model.select(target.id)
        model.editor.content = "Pending"; model.contentChanged()
        let action = DraftAction(name: "Never start", steps: [ActionStep("script", ["script": "editor.setText('Late');"])])
        let output = try await AutomationActionExecution.run(action, noteID: target.id, library: library,
            models: [model], host: UnusedAutomationContextHost(), resolveModel: { _, _ in model },
            registerClose: { _, close in close(); return { removals += 1 } })
        #expect(output.report.reason == .cancelled)
        #expect(saves == 0 && removals == 1 && library.runs.isEmpty)
        #expect(model.runner.lastReport == nil && !model.actionPending)
        #expect(model.editor.content == "Pending" && model.hasUnsavedChanges)
        #expect(library.notes.first?.content == "Stored")
    }

    @Test(arguments: ["owner close", "parent cancellation"])
    func ownerLifetimeCancelsItsChildAndRemovesObserverOnce(interruption: String) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Source")
        let model = WindowModel(library: library), alternate = WindowModel(library: library)
        model.select(target.id); alternate.select(target.id)
        let host = WaitingAutomationContextHost(); model.runner.host = host
        var closeOwner: (@MainActor () -> Void)?, removals = 0, resolutions = 0
        let action = DraftAction(name: "Owner lifetime", steps: [ActionStep("script", ["script": "editor.arrange('Neutral');editor.setText('Late');"])])
        let task = Task { try await AutomationActionExecution.run(action, noteID: target.id, library: library,
            models: [alternate, model], host: UnusedAutomationContextHost(), resolveModel: { _, _ in resolutions += 1; return model },
            registerClose: { _, close in closeOwner = close; return { removals += 1; closeOwner = nil } }) }
        await host.waitForStart()
        if interruption == "owner close" { closeOwner?() } else { task.cancel() }
        let output = try await task.value
        #expect(output.report.reason == .cancelled && resolutions == 1 && removals == 1)
        #expect(closeOwner == nil && !model.actionPending && !model.runner.isRunning)
        #expect(alternate.runner.lastReport == nil && !host.finish("Late response"))
        #expect(model.editor.content == target.content && library.notes.first?.content == target.content)
    }

    @Test func successfulOwnedRunRemovesCloseObserverOnce() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Source")
        let model = WindowModel(library: library); model.select(target.id)
        var removals = 0
        let output = try await AutomationActionExecution.run(DraftAction(name: "Success", steps: []), noteID: target.id,
            library: library, models: [model], host: UnusedAutomationContextHost(), resolveModel: { _, _ in model },
            registerClose: { _, _ in { removals += 1 } })
        #expect(output.report.reason == .success && removals == 1)
        #expect(!model.actionPending && !model.runner.isRunning)
    }

    @Test func aResolverCannotBorrowAModelForAnotherNote() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let target = try library.createNote(content: "Target"), other = try library.createNote(content: "Other")
        let unrelated = WindowModel(library: library); unrelated.select(other.id)
        let action = DraftAction(name: "Headless target", steps: [ActionStep("script", ["script": "editor.setText('Changed target');"])])
        let output = try await AutomationActionExecution.run(action, noteID: target.id, library: library,
            models: [unrelated], host: UnusedAutomationContextHost(), resolveModel: { _, _ in unrelated })
        #expect(output.report.reason == .success)
        #expect(unrelated.editor.noteID == other.id && unrelated.editor.content == other.content)
        #expect(unrelated.runner.lastReport == nil)
        #expect(library.notes.first { $0.id == target.id }?.content == "Changed target")
    }
}

@MainActor private final class UnusedAutomationContextHost: ActionHost {
    private(set) var calls = 0
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        calls += 1
        throw DraftlyError.message("The fallback native host must not be used: \(operation)")
    }
}

@MainActor private final class WaitingAutomationContextHost: ActionHost {
    private let started = AsyncStream.makeStream(of: Bool.self)
    private var continuation: CheckedContinuation<String, Error>?
    func supportsAsync(_ operation: String) -> Bool { operation == "arrangeText" }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? { throw DraftlyError.message("Unexpected synchronous host operation.") }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if Task.isCancelled { failCancellation(); return }
                started.continuation.yield(true)
            }
        } onCancel: { Task { @MainActor in self.failCancellation() } }
    }
    func waitForStart() async { var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next() }
    @discardableResult func finish(_ value: String) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        do { continuation.resume(returning: String(decoding: try JSONSerialization.data(withJSONObject: ["value": value]), as: UTF8.self)) }
        catch { continuation.resume(throwing: error) }
        return true
    }
    private func failCancellation() {
        let continuation = continuation; self.continuation = nil
        continuation?.resume(throwing: CancellationError())
    }
}
