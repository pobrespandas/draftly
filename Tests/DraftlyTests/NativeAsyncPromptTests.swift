import AppKit
import Testing
@testable import Draftly

@Suite("Asynchronous native prompts") @MainActor
struct NativeAsyncPromptTests {
    @Test func acceptedPromptRetainsFieldTypesAndButtonIndex() async throws {
        let result = try await NativePromptAdapter().performAsync("prompt", values: [
            "fields": [["key": "text", "kind": "text", "value": "café 🐼"],
                       ["key": "enabled", "kind": "switch", "value": true],
                       ["key": "number", "kind": "number", "value": 3]],
            "buttons": [["title": "Keep"], ["title": "Save", "isDefault": true]]
        ], present: { alert in
            #expect(alert.buttons.map(\.title) == ["Keep", "Save", "Cancel"])
            #expect(alert.buttons[1].keyEquivalent == "\r")
            return .alertSecondButtonReturn
        }) as? [String: Any]
        let fields = result?["fields"] as? [String: Any]
        #expect(result?["index"] as? Int == 1)
        #expect(fields?["text"] as? String == "café 🐼")
        #expect(fields?["enabled"] as? Bool == true && fields?["number"] as? Double == 3)
    }

    @Test func cancellingPromptDoesNotReturnEditedFields() async throws {
        let result = try await NativePromptAdapter().performAsync("prompt", values: ["isCancellable": true], present: { _ in .alertSecondButtonReturn })
        #expect(result == nil)
    }

    @Test func invalidNumberShowsErrorThenAllowsCancellation() async throws {
        var titles: [String] = []
        let result = try await NativePromptAdapter().performAsync("prompt", values: [
            "title": "Number", "fields": [["key": "number", "kind": "number", "value": "invalid"]]
        ], present: { alert in
            titles.append(alert.messageText)
            return titles.count < 3 ? .alertFirstButtonReturn : .alertSecondButtonReturn
        })
        #expect(result == nil)
        #expect(titles == ["Number", "Enter a valid number.", "Number"])
    }

    @Test func selectionReturnsTheOriginalIndexAfterFiltering() async throws {
        let result = try await NativePromptAdapter().performAsync("selectPrompt", values: [
            "items": [["title": "First", "subtitle": "One"], ["title": "Second", "subtitle": "café 🐼"]]
        ], present: { alert in
            let stack = try #require(alert.accessoryView as? NSStackView)
            let scroll = try #require(stack.arrangedSubviews.last as? NSScrollView)
            let table = try #require(scroll.documentView as? NSTableView)
            let choices = try #require(table.delegate as? SearchablePromptChoices)
            choices.filter("café")
            return .alertFirstButtonReturn
        }) as? [String: Any]
        #expect(result?["index"] as? Int == 1)
    }

    @Test func emptySelectionDoesNotPresentAnyWindow() async throws {
        let result = try await NativePromptAdapter().performAsync("selectPrompt", values: [:], present: { _ in
            Issue.record("An empty selection was presented."); return .alertFirstButtonReturn
        })
        #expect(result == nil)
    }

    @Test func cancelledTaskCannotAcceptLateFields() async throws {
        let started = AsyncStream.makeStream(of: Bool.self)
        let task = Task { try await NativePromptAdapter().performAsync("prompt", values: [:], present: { _ in
            started.continuation.yield(true)
            try? await Task.sleep(for: .seconds(10))
            return .alertFirstButtonReturn
        }) != nil }
        var iterator = started.stream.makeAsyncIterator(); _ = await iterator.next()
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation returned fields.") }
        catch { #expect(error is CancellationError) }
    }
}
