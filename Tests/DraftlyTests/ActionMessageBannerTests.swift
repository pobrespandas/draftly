import Foundation
import Testing
import DraftlyCore
@testable import Draftly

@Suite("Action message banner routing") @MainActor
struct ActionMessageBannerTests {
    @Test(arguments: ["info", "success", "warning", "error"])
    func nativeHostRoutesMessagesToItsWindowModel(severity: String) throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        #expect(model.window == nil && model.messageBanner == nil)
        let result = try model.host.perform("displayMessage", values: ["message": "Neutral café 🐼", "severity": severity])
        #expect(result == nil)
        let banner = try #require(model.messageBanner)
        #expect(banner.message == "Neutral café 🐼" && banner.severity.rawValue == severity)
        #expect(model.window == nil && library.notes.isEmpty)
    }

    @Test func newMessagesReplaceIdentityAndInvalidSeverityPreservesTheCurrentBanner() throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let model = WindowModel(library: library)
        _ = try model.host.perform("displayMessage", values: ["message": "First", "severity": "info"])
        let first = try #require(model.messageBanner)
        _ = try model.host.perform("displayMessage", values: ["message": "Second", "severity": "warning"])
        let second = try #require(model.messageBanner)
        #expect(second.id != first.id && second.message == "Second" && second.severity == .warning)
        #expect(throws: (any Error).self) {
            try model.host.perform("displayMessage", values: ["message": "Rejected", "severity": "invalid"])
        }
        #expect(model.messageBanner?.id == second.id && model.messageBanner?.message == second.message)
        #expect(model.messageBanner?.severity == .warning)
    }

    @Test func successfulMessageUsesOnlyTheBannerWhileOtherResultsKeepTheirStatus() async throws {
        let library = try LibraryStore(inMemory: true, seed: false)
        let note = try library.createNote(content: "Keep café 🐼")
        let model = WindowModel(library: library)
        model.select(note.id)
        let displayed = DraftAction(name: "Neutral info", steps: [
            ActionStep("script", ["script": "app.displayInfoMessage('Neutral café 🐼');"])
        ])
        let success = await model.runAsync(displayed)
        #expect(success?.reason == .success)
        #expect(model.status.isEmpty)
        #expect(model.messageBanner?.message == "Neutral café 🐼" && model.messageBanner?.severity == .info)
        #expect(library.runs.first { $0.actionID == displayed.id }?.message == "Neutral café 🐼")
        let unrelated = DraftAction(name: "Other status", steps: [
            ActionStep("script", ["script": "console.log('Unrelated status');"])
        ])
        #expect(await model.runAsync(unrelated)?.reason == .success)
        #expect(model.status == "Unrelated status")
        let failed = DraftAction(name: "Neutral failure", steps: [
            ActionStep("script", ["script": "context.fail('Distinct failure');"])
        ])
        #expect(await model.runAsync(failed)?.reason == .error)
        #expect(model.status == "Distinct failure")
        #expect(library.runs.first { $0.actionID == failed.id }?.message == "Distinct failure")
        #expect(model.messageBanner?.message == "Neutral café 🐼")
        #expect(model.window == nil && model.editor.content == note.content)
    }

    @Test func nativeHostWithoutAPresenterFailsExplicitly() throws {
        let host = NativeActionHost()
        #expect(host.onMessage == nil)
        do {
            _ = try host.perform("displayMessage", values: ["message": "Neutral", "severity": "info"])
            Issue.record("A host without a presenter accepted a message.")
        } catch {
            #expect(error.localizedDescription == "Message banners require an open Draftly window.")
        }
    }
}
