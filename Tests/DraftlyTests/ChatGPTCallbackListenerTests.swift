import Foundation
import Testing
@testable import Draftly

@Suite("ChatGPT loopback callback", .serialized) @MainActor
struct ChatGPTCallbackListenerTests {
    private func callback(_ authorization: ChatGPTAuthorization, state: String? = nil) -> URL {
        var url = URLComponents(url: authorization.redirectURI, resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "state", value: state ?? authorization.state),
                          .init(name: "code", value: "neutral-code"), .init(name: "client_id", value: "oaiapp_test")]
        return url.url!
    }

    @Test func forgedCallbackDoesNotConsumeAttemptAndValidCallbackIsSingleUse() async throws {
        let listener = ChatGPTCallbackListener(lifetime: .seconds(10))
        defer { listener.cancel() }
        let port = try await listener.start()
        let authorization = try ChatGPTAuthorization(port: port, hostID: "neutral-host")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var browserTask: Task<Void, any Error>?
        let code = try await listener.waitForCode(using: authorization) { _ in
            browserTask = Task {
                let (_, rejected) = try await session.data(from: callback(authorization, state: "wrong"))
                #expect((rejected as? HTTPURLResponse)?.statusCode == 400)
                let (data, accepted) = try await session.data(from: callback(authorization))
                #expect((accepted as? HTTPURLResponse)?.statusCode == 200)
                #expect(!String(decoding: data, as: UTF8.self).contains("neutral-code"))
            }
            return true
        }
        try await browserTask?.value
        #expect(code.value == "neutral-code" && code.clientID == "oaiapp_test")
        await #expect(throws: ChatGPTCallbackListener.Failure.self) {
            try await listener.waitForCode(using: authorization, openBrowser: { _ in true })
        }
    }

    @Test func cancelEndsPendingCallback() async throws {
        let listener = ChatGPTCallbackListener()
        let port = try await listener.start()
        let authorization = try ChatGPTAuthorization(port: port, hostID: "host")
        await #expect(throws: CancellationError.self) {
            try await listener.waitForCode(using: authorization) { _ in
                listener.cancel()
                return true
            }
        }
        listener.cancel()
    }

    @Test func failedBrowserLaunchClosesListener() async throws {
        let listener = ChatGPTCallbackListener()
        let port = try await listener.start()
        let authorization = try ChatGPTAuthorization(port: port, hostID: "host")
        await #expect(throws: ChatGPTCallbackListener.Failure.self) {
            try await listener.waitForCode(using: authorization, openBrowser: { _ in false })
        }
        await #expect(throws: ChatGPTCallbackListener.Failure.self) { try await listener.start() }
    }

    @Test func httpBoundaryRejectsOtherHostsMethodsBodiesAndAmbiguousFraming() {
        let valid = "GET /auth/callback?state=neutral HTTP/1.1\r\nHost: 127.0.0.1:1455\r\n\r\n"
        #expect(ChatGPTCallbackListener.callbackURL(request: Data(valid.utf8), port: 1455) != nil)
        let invalid = [valid.replacingOccurrences(of: "GET ", with: "POST "),
                       valid.replacingOccurrences(of: "127.0.0.1", with: "localhost"),
                       valid.replacingOccurrences(of: "Host:", with: "Host: evil\r\nHost:"),
                       valid.replacingOccurrences(of: "Host:", with: "Content-Length: 0\r\nHost:"),
                       valid.replacingOccurrences(of: "Host:", with: "Transfer-Encoding: chunked\r\nHost:"),
                       valid + "extra", String(repeating: "x", count: 16385)]
        for request in invalid {
            #expect(ChatGPTCallbackListener.callbackURL(request: Data(request.utf8), port: 1455) == nil)
        }
    }
}
