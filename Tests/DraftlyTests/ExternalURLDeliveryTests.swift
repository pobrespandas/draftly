import AppKit
import Testing
import DraftlyCore
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

    @Test func configuredApplicationSchemePreservesPayloadAndCallbackDestinations() throws {
        let canonical = try #require(URL(string: "draftly://x-callback-url/runAction?action=caf%C3%A9%20%F0%9F%90%BC&x-success=draftly-engine-qa%3A%2F%2Fcallback%3Ftoken%3Dneutral&text=%2f%2B%25%0A"))
        #expect(ApplicationURLRouter.applicationURL(canonical, registeredScheme: "draftly") == canonical)
        var isolated = try #require(URLComponents(url: canonical, resolvingAgainstBaseURL: false))
        isolated.scheme = "draftly-engine-qa"
        let isolatedURL = try #require(isolated.url)
        let normalized = try #require(ApplicationURLRouter.applicationURL(isolatedURL, registeredScheme: "draftly-engine-qa"))
        let parts = try #require(URLComponents(url: normalized, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "draftly" && parts.host == isolated.host && parts.path == isolated.path)
        #expect(parts.percentEncodedQuery == isolated.percentEncodedQuery)
        #expect(parts.queryItems?.first { $0.name == "x-success" }?.value == "draftly-engine-qa://callback?token=neutral")
        for text in ["draftly-other-qa://theme?name=Dark", "drafts://theme?name=Dark", "https://theme?name=Dark", "file:///theme"] {
            let url = try #require(URL(string: text))
            #expect(ApplicationURLRouter.applicationURL(url, registeredScheme: "draftly-engine-qa") == nil)
        }
        #expect(ApplicationURLRouter.applicationURL(isolatedURL, registeredScheme: "draftly") == nil)
        #expect(ApplicationURLRouter.applicationURL(isolatedURL, registeredScheme: "") == nil)
    }

    @Test func isolatedThemeURLUsesTheSameDecoderAndReceiverAsTheCanonicalScheme() throws {
        let theme = EditorThemeDefinition(name: "Isolated café 🐼", unknownFields: ["future": .string("&?%")])
        var components = try #require(URLComponents(url: ThemeInstallation.custom(theme).url, resolvingAgainstBaseURL: false))
        components.scheme = "draftly-engine-qa"
        let isolatedURL = try #require(components.url)
        let canonical = try #require(ApplicationURLRouter.applicationURL(isolatedURL, registeredScheme: "draftly-engine-qa"))
        #expect(try ThemeInstallation(url: canonical) == .custom(theme))
        let library = try LibraryStore(inMemory: true, seed: false)
        #expect(try ApplicationURLRouter.installTheme(canonical, library: library) { _ in
            Issue.record("An isolated new theme requested replacement."); return false
        })
        #expect(library.themes == [theme])
    }

}
