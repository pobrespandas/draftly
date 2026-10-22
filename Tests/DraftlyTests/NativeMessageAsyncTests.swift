import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous message composition") @MainActor
struct NativeMessageAsyncTests {
    @MainActor private final class Driver: NativeMessageDriver {
        var recipients: [String] = []
        var subject = ""
        var onFinish: ((Result<Void, Error>) -> Void)?
        var late: ((Result<Void, Error>) -> Void)?
        var permitted = true
        var result: Result<Void, Error>? = .success(())
        var body: String?
        var detachCount = 0
        var onStart: (() -> Void)?
        func canPerform(_ body: String) -> Bool { permitted }
        func perform(_ body: String) { self.body = body; late = onFinish; onStart?(); if let result { onFinish?(result) } }
        func detach() { detachCount += 1; onFinish = nil }
    }

    @Test(arguments: ["composeMail", "composeMessage"])
    func recipientsSubjectAndUnicodeReachTheCorrectService(_ operation: String) async throws {
        let driver = Driver(); var requested: String?
        let result = try await NativeMessageAdapter().composeAsync(operation, ["toRecipients": ["neutral@example.invalid"], "subject": "Neutral", "body": "café 🐼"], makeDriver: { name in requested = name; return driver })
        #expect(result["status"] == "sent" && requested == operation)
        #expect(driver.recipients == ["neutral@example.invalid"] && driver.subject == "Neutral" && driver.body == "café 🐼")
        #expect(driver.detachCount == 1 && driver.onFinish == nil)
        driver.late?(.failure(NSError(domain: "Late", code: 1)))
        #expect(driver.detachCount == 1)
    }

    @Test(arguments: [false, true])
    func actualMailAdapterRejectsUnverifiableDeliveryBeforeOpeningAComposer(asynchronous: Bool) async {
        do {
            let values: [String: Any] = ["subject": "Neutral QA", "body": "Neutral café 🐼", "toRecipients": [String]()]
            if asynchronous {
                _ = try await NativeMessageAdapter().composeAsync("composeMail", values, makeDriver: { operation in
                    try SharingMessageDriver(operation: operation, makeService: { _ in
                        Issue.record("Unverifiable Mail delivery must fail before creating a sharing service."); return nil
                    })
                })
            } else {
                _ = try NativeMessageAdapter().compose("composeMail", values, makeService: { _ in
                    Issue.record("Unverifiable Mail delivery must fail before creating a sharing service."); return nil
                })
            }
            Issue.record("Opening a Mail composer must not be reported as a sent message.")
        } catch {
            #expect(error.localizedDescription.contains("cannot confirm that a message was sent"))
            #expect(error.localizedDescription.contains("Mail.send() is unavailable through this service"))
        }
    }

    @Test(arguments: [false, true])
    func actualMessagesAdapterRejectsUnverifiableDeliveryBeforeOpeningAComposer(asynchronous: Bool) async {
        do {
            if asynchronous {
                _ = try await NativeMessageAdapter().composeAsync("composeMessage", [:], makeDriver: { operation in
                    try SharingMessageDriver(operation: operation, makeService: { _ in
                        Issue.record("Unconfirmed Messages must not open a service."); return nil
                    })
                })
            } else {
                _ = try NativeMessageAdapter().compose("composeMessage", [:], makeService: { _ in
                    Issue.record("Unconfirmed Messages must not open a service."); return nil
                })
            }
            Issue.record("Unconfirmed Messages reported success.")
        } catch { #expect(error.localizedDescription.contains("Messages sharing service cannot confirm")) }
    }

    @Test func unsupportedOptionsFailBeforeCreatingOrOpeningAComposer() async {
        let unsupported: [[String: Any]] = [["isBodyHTML": true], ["sendInBackground": true], ["replyToRecipients": ["neutral@example.invalid"]], ["ccRecipients": ["neutral@example.invalid"]], ["bccRecipients": ["neutral@example.invalid"]]]
        for values in unsupported {
            do {
                _ = try await NativeMessageAdapter().composeAsync("composeMail", values, makeDriver: { _ in Issue.record("Unsupported composition created a service."); return Driver() })
                Issue.record("Unsupported composition succeeded.")
            } catch { }
        }
    }

    @Test func unavailableAndIncapableServicesDoNotPerform() async {
        enum Failure: Error { case unavailable }
        do {
            _ = try await NativeMessageAdapter().composeAsync("composeMail", [:], makeDriver: { _ in throw Failure.unavailable })
            Issue.record("Unavailable service succeeded.")
        } catch { #expect(error is Failure) }
        let driver = Driver(); driver.permitted = false
        do { _ = try await NativeMessageAdapter().composeAsync("composeMail", [:], makeDriver: { _ in driver }); Issue.record("Incapable service succeeded.") }
        catch { #expect(driver.body == nil && driver.detachCount == 1) }
    }

    @Test func systemUserCancellationHasItsOwnStatus() async throws {
        let driver = Driver(); driver.result = .failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        let result = try await NativeMessageAdapter().composeAsync("composeMail", [:], makeDriver: { _ in driver })
        #expect(result["status"] == "userCancelled" && driver.detachCount == 1)
    }

    @Test func serviceErrorsPropagateWithoutAFalseSuccessStatus() async {
        let driver = Driver(); driver.result = .failure(NSError(domain: "NeutralServiceFailure", code: 7))
        do { _ = try await NativeMessageAdapter().composeAsync("composeMessage", [:], makeDriver: { _ in driver }); Issue.record("Failed service succeeded.") }
        catch { #expect((error as NSError).domain == "NeutralServiceFailure") }
        #expect(driver.detachCount == 1)
    }

    @Test func timeoutDetachesAndIgnoresLateCompletion() async throws {
        let driver = Driver(); driver.result = nil
        do { _ = try await NativeMessageAdapter().composeAsync("composeMail", [:], timeout: 0.02, makeDriver: { _ in driver }); Issue.record("Timed out service succeeded.") }
        catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        driver.late?(.success(()))
        #expect(driver.detachCount == 1 && driver.onFinish == nil)
    }

    @Test(arguments: [false, true])
    func completionAtOrAfterDeadlineCannotBeatQueuedTimeout(exactDeadline: Bool) async {
        let driver = Driver()
        var now = Date(timeIntervalSinceReferenceDate: 100)
        driver.onStart = { now = now.addingTimeInterval(exactDeadline ? 10 : 11) }
        do {
            _ = try await NativeMessageAdapter().composeAsync("composeMessage", [:], timeout: 10,
                now: { now }, makeDriver: { _ in driver })
            Issue.record("Expired composition reported success.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        #expect(driver.detachCount == 1 && driver.onFinish == nil)
        driver.late?(.success(()))
        #expect(driver.detachCount == 1)
    }

    @Test func taskCancellationDetachesWithoutClaimingToRecallExternalComposition() async throws {
        let driver = Driver(); driver.result = nil
        let started = AsyncStream.makeStream(of: Bool.self)
        driver.onStart = { started.continuation.yield(true) }
        let task = Task { @MainActor in
            do { _ = try await NativeMessageAdapter().composeAsync("composeMail", [:], makeDriver: { _ in driver }); return false }
            catch { return error is CancellationError }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        #expect(await task.value)
        driver.late?(.success(()))
        #expect(driver.detachCount == 1 && driver.onFinish == nil)
    }

    @Test(arguments: [false, true], [false, true])
    func unconfirmedMailStopsBothRunnersAndPreservesPriorEffects(worker: Bool, script: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let editor = EditorSession(); editor.load(note)
        let host = UnconfirmedMailHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = unconfirmedMailAction(script: script)
        let report = worker ? await runner.runAsync(action) : runner.runReport(action)
        #expect(report.reason == .error && !report.result.succeeded)
        #expect(report.successParameters.isEmpty)
        #expect(runner.message?.contains("cannot confirm that a message was sent") == true)
        #expect(editor.content == "Retained café 🐼")
        let saved = try #require(library.notes.first { $0.id == note.id })
        #expect(saved.content == editor.content && !saved.isArchived)
        #expect(library.runs.count == 1 && library.runs.first?.status == "Error")
        let recovery = DraftAction(name: "Following mail failure", steps: [ActionStep("script", ["script": "editor.setText('Recovery');"])])
        let next = worker ? await runner.runAsync(recovery) : runner.runReport(recovery)
        #expect(next.reason == .success && next.executionID != report.executionID)
        #expect(library.notes.first { $0.id == note.id }?.content == "Recovery")
    }
    @Test func actualIntentPropagatesUnconfirmedMailAsFailure() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let host = UnconfirmedMailHost()
        let action = unconfirmedMailAction(script: false)
        try library.saveAction(action)
        var request = RunDraftActionIntent()
        request.name = action.name; request.uuid = note.id.uuidString
        request.executionEnvironment = RunActionIntentEnvironment(library: library, models: [], host: host)
        do { _ = try await request.perform(); Issue.record("The Intent reported success without confirmed mail delivery.") }
        catch {
            let error = try #require(error as? AutomationActionError)
            #expect(error.reason == .error)
            #expect(error.localizedDescription.contains("cannot confirm that a message was sent"))
        }
        let saved = try #require(library.notes.first { $0.id == note.id })
        #expect(saved.content == "Retained café 🐼" && !saved.isArchived)
        #expect(library.runs.count == 1 && library.runs.first?.status == "Error")
        #expect(!ActionRunner.isExecuting(in: library))
    }

    @Test(arguments: [false, true])
    func unconfirmedMessagesStopBothRunnersWithoutSuccessEffects(worker: Bool) async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let editor = EditorSession(); editor.load(note)
        let host = UnconfirmedMailHost()
        let runner = ActionRunner(library: library, editor: editor, host: host)
        let action = unconfirmedMessagesAction()
        let report = worker ? await runner.runAsync(action) : runner.runReport(action)
        #expect(report.reason == .error && report.successParameters.isEmpty)
        #expect(runner.message?.contains("Messages sharing service cannot confirm") == true, "Final message: \(runner.message ?? "nil")")
        #expect(library.notes.first?.content == "Retained café 🐼" && library.notes.first?.isArchived == false)
        #expect(library.runs.first?.status == "Error")
        let next = DraftAction(name: "Messages recovery", steps: [ActionStep("script", ["script": "editor.setText('Recovered');draft.update();"])])
        let recovered = worker ? await runner.runAsync(next) : runner.runReport(next)
        #expect(recovered.reason == .success && recovered.executionID != report.executionID)
        #expect(library.notes.first?.content == "Recovered")
    }

    @Test func actualIntentPropagatesUnconfirmedMessagesAsFailure() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral")
        let action = unconfirmedMessagesAction()
        try library.saveAction(action)
        var request = RunDraftActionIntent()
        request.name = action.name; request.uuid = note.id.uuidString
        request.executionEnvironment = RunActionIntentEnvironment(library: library, models: [], host: UnconfirmedMailHost())
        do { _ = try await request.perform(); Issue.record("Unconfirmed Messages Intent succeeded.") }
        catch {
            #expect(try #require(error as? AutomationActionError).reason == .error)
            #expect(error.localizedDescription.contains("Messages sharing service cannot confirm"))
        }
        #expect(library.notes.first?.content == "Retained café 🐼" && library.notes.first?.isArchived == false)
        #expect(library.runs.first?.status == "Error" && !ActionRunner.isExecuting(in: library))
    }

    private func unconfirmedMessagesAction() -> DraftAction {
        var action = unconfirmedMailAction(script: true)
        action.name = "Unconfirmed Messages result"
        action.steps[1] = ActionStep("script", ["script": "var m=Message.create();m.body='Neutral';m.send();"])
        return action
    }

    private func unconfirmedMailAction(script: Bool) -> DraftAction {
        let mail = script
            ? ActionStep("script", ["script": "var m=Mail.create();m.subject='Neutral';m.body='Neutral body';m.send();"])
            : ActionStep("mail", ["subject": "Neutral", "template": "Neutral body"])
        var action = DraftAction(name: "Unconfirmed mail result", steps: [
            ActionStep("script", ["script": "editor.setText('Retained café 🐼');draft.update();context.addSuccessParameter('discard','yes');"]),
            mail,
            ActionStep("insertText", ["template": "ERROR: tail"])
        ])
        action.afterSuccess = "archive"
        return action
    }

}

@MainActor private final class UnconfirmedMailHost: ActionHost {
    func supportsAsync(_ operation: String) -> Bool { ["composeMail", "composeMessage"].contains(operation) }
    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if operation == "device" { return [String: Any]() }
        guard ["composeMail", "composeMessage"].contains(operation) else { throw DraftlyError.message("Unexpected neutral host operation: " + operation) }
        return try NativeMessageAdapter().compose(operation, values, makeService: { _ in
            Issue.record("A Mail result test must not create a sharing service."); return nil
        })
    }
    func performAsync(_ operation: String, payload: String) async throws -> String {
        let values = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        let result = try await NativeMessageAdapter().composeAsync(operation, values, makeDriver: { operation in
            try SharingMessageDriver(operation: operation, makeService: { _ in
                Issue.record("A Mail result test must not create a sharing service."); return nil
            })
        })
        return String(decoding: try JSONSerialization.data(withJSONObject: ["value": result]), as: UTF8.self)
    }
}
