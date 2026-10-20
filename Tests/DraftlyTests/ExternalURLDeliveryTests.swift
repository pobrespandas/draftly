import AppKit
import Testing
@testable import Draftly

@Suite("Application-wide external URLs") @MainActor
struct ExternalURLDeliveryTests {
    @Test func callbackDeliveryDoesNotReachTheWindowRoutingHandler() throws {
        let callback = try #require(URL(string: "draftly-qa://callback?token=neutral&status=success&value=caf%C3%A9"))
        var received: [URL] = []
        var routed: [URL] = []
        AppDelegate.routeExternalURLs([callback], receiveCallback: {
            received.append($0)
            return true
        }, handle: { routed.append($0) })
        #expect(received == [callback])
        #expect(routed.isEmpty)
    }

    @Test func normalURLsRetainInputOrderWithoutRewritingTheirSchemeOrPayload() throws {
        let input = try [
            "draftly://open?uuid=neutral",
            "draftly://capture?text=caf%C3%A9%20%F0%9F%90%BC",
            "draftly://create?text=line%0Abreak",
            "draftly://run?action=Neutral&uuid=neutral",
            "draftly://x-callback-url/runAction?action=Neutral&uuid=neutral"
        ].map { try #require(URL(string: $0)) }
        var received: [URL] = []
        var routed: [URL] = []
        AppDelegate.routeExternalURLs(input, receiveCallback: {
            received.append($0)
            return false
        }, handle: { routed.append($0) })
        #expect(received == input)
        #expect(routed == input)
    }

    @Test func mixedDeliveryConsumesOnlyRecognizedCallbacks() throws {
        let input = try ["draftly://open?uuid=neutral", "draftly-qa://callback?token=known", "draftly://capture?text=Neutral"].map {
            try #require(URL(string: $0))
        }
        var routed: [URL] = []
        AppDelegate.routeExternalURLs(input, receiveCallback: { $0 == input[1] }, handle: { routed.append($0) })
        #expect(routed == [input[0], input[2]])
    }
}
