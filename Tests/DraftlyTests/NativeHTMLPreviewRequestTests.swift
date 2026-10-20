import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Asynchronous HTML preview lifecycle") @MainActor
struct NativeHTMLPreviewRequestTests {
    @Test func htmlValuesAndHiddenInterfaceSurviveSuccessfulCompletion() async throws {
        var cleanup = 0, finished = 0
        let output = try await NativeHTMLPreviewRequest.run(["html": "<p>Neutral café 🐼</p>", "hideInterface": true]) { request in
            #expect(request.html == "<p>Neutral café 🐼</p>" && request.hideInterface)
            request.onFinish = { finished += 1 }; request.addCleanup { cleanup += 1 }
            request.receive(["operation": "send", "key": "answer", "value": ["text": "café 🐼", "empty": NSNull()]])
            request.receive(["operation": "continue"])
            request.receive(["operation": "send", "key": "late", "value": "Ignored"])
            request.receive(["operation": "cancel"])
        }
        #expect(output["success"] as? Bool == true)
        let values = try #require(output["values"] as? [String: Any])
        let answer = try #require(values["answer"] as? [String: Any])
        #expect(answer["text"] as? String == "café 🐼" && answer["empty"] is NSNull)
        #expect(values["late"] == nil && cleanup == 1 && finished == 1)
    }

    @Test func userCancellationAndWindowClosureReturnFalse() async throws {
        for close in [false, true] {
            var cleanup = 0
            let output = try await NativeHTMLPreviewRequest.run([:]) { request in
                #expect(request.html.isEmpty && !request.hideInterface)
                request.addCleanup { cleanup += 1 }
                if close { request.finish(false) } else { request.receive(["operation": "cancel"]) }
            }
            #expect(output["success"] as? Bool == false && cleanup == 1)
        }
    }

    @Test func timeoutCleansThePresentationAndRejectsLateJavaScript() async throws {
        var shown: ActionPreviewRequest?, cleanup = 0
        do {
            _ = try await NativeHTMLPreviewRequest.run([:], timeout: 0.02) { request in
                shown = request; request.addCleanup { cleanup += 1 }
            }
            Issue.record("Timed out preview succeeded.")
        } catch { #expect(error as? ActionExecutionInterruption == .timeout) }
        let request = try #require(shown)
        request.receive(["operation": "send", "key": "late", "value": true])
        request.receive(["operation": "continue"])
        #expect(request.result == false && request.values.isEmpty && cleanup == 1)
    }

    @Test func callerCancellationCleansPresentationAndCompletesOnce() async throws {
        var shown: ActionPreviewRequest?, cleanup = 0, finished = 0
        let started = AsyncStream.makeStream(of: Bool.self)
        let task = Task { @MainActor in
            do {
                _ = try await NativeHTMLPreviewRequest.run([:]) { request in
                    shown = request; request.addCleanup { cleanup += 1 }; request.onFinish = { finished += 1 }
                    started.continuation.yield(true)
                }
                return false
            } catch { return error is CancellationError }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        #expect(await task.value)
        let request = try #require(shown)
        request.finish(true); request.fail(NSError(domain: "Late", code: 1))
        #expect(request.result == false && cleanup == 1 && finished == 1)
    }

    @Test func presentationAndNavigationFailuresRemainErrors() async throws {
        for presentationFails in [false, true] {
            var cleanup = 0
            do {
                _ = try await NativeHTMLPreviewRequest.run([:]) { request in
                    request.addCleanup { cleanup += 1 }
                    let failure = NSError(domain: "NeutralPreviewFailure", code: 7)
                    if presentationFails { throw failure }
                    request.fail(failure)
                }
                Issue.record("Failed preview succeeded.")
            } catch { #expect((error as NSError).domain == "NeutralPreviewFailure") }
            #expect(cleanup == 1)
        }
    }

    @Test func subframesAndUnknownMessagesCannotFinishOrChangeValues() {
        let request = ActionPreviewRequest(html: "", hideInterface: false)
        request.receive(["operation": "continue"], mainFrame: false)
        request.receive(["operation": "send", "key": "secret", "value": true], mainFrame: false)
        request.receive(["operation": "unknown"])
        #expect(request.result == nil && request.values.isEmpty)
        request.receive(["operation": "send", "key": "empty"])
        #expect(request.values["empty"] is NSNull)
        request.finish(true)
    }
}
