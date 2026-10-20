import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Action URL targets") @MainActor
struct ApplicationURLActionTests {
    @Test func validTargetResolvesWithoutChangingTheLibrary() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Neutral target")
        let action = DraftAction(name: "Neutral action", steps: [])
        try library.saveAction(action)
        let target = try ApplicationURLRouter.runTarget(parameters: ["action": action.name, "uuid": note.id.uuidString], library: library)
        #expect(target.action.id == action.id)
        #expect(target.note.id == note.id)
        #expect(library.runs.isEmpty)
    }

    @Test func invalidTargetsFailBeforeExecutionAndSupplyAnErrorCallback() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let action = DraftAction(name: "Neutral action", steps: [])
        try library.saveAction(action)
        let invalid: [[String: String]] = [[:], ["action": "Missing"], ["action": action.name, "uuid": "invalid"], ["action": action.name, "uuid": UUID().uuidString]]
        for parameters in invalid {
            do {
                _ = try ApplicationURLRouter.runTarget(parameters: parameters, library: library)
                Issue.record("An invalid action URL resolved.")
            } catch {
                let callback = ActionExecutionResult.failure(error.localizedDescription).callbackURL(parameters: ["x-error": "test-callback://error?existing=1"])
                let items = URLComponents(url: try #require(callback), resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(items.contains { $0.name == "errorMessage" && $0.value == error.localizedDescription })
                #expect(items.contains { $0.name == "existing" && $0.value == "1" })
            }
        }
        #expect(library.runs.isEmpty)
        #expect(throws: (any Error).self) { try ApplicationURLRouter.runTarget(parameters: [:], library: nil) }
    }
}
