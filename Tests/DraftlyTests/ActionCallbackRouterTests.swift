import Foundation
import Testing
@testable import Draftly

@Suite("Asynchronous native callbacks") @MainActor
struct ActionCallbackRouterTests {
    private func callback(_ url: URL, key: String = "x-success") throws -> URL {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return try #require(items.first { $0.name == key }?.value.flatMap(URL.init(string:)))
    }

    @Test(arguments: [("x-success", "success"), ("x-cancel", "cancelled"), ("x-error", "error")])
    func synchronousDeliveryCompletesOnce(_ example: (String, String)) async throws {
        var callbackURL: URL?
        let result = try await ActionCallbackRouter.openAsync(["url": "neutral-test://run?x-success=old&keep=yes"], openURL: { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(items.contains { $0.name == "keep" && $0.value == "yes" })
            #expect(items.filter { $0.name == "x-success" }.count == 1)
            do {
                var response = URLComponents(url: try callback(url, key: example.0), resolvingAgainstBaseURL: false)!
                response.queryItems = (response.queryItems ?? []) + [URLQueryItem(name: "value", value: "café 🐼")]
                callbackURL = response.url
                #expect(ActionCallbackRouter.receive(try #require(callbackURL)))
            } catch { Issue.record(error) }
            return true
        })
        #expect(result["status"] as? String == example.1)
        #expect((result["parameters"] as? [String: String])?["value"] == "café 🐼")
        #expect(!ActionCallbackRouter.receive(try #require(callbackURL)))
    }

    @Test(arguments: ["during launch", "before timer resumes"])
    func absoluteDeadlineRejectsDeliveryBeforeTheTimeoutTaskRuns(_ phase: String) async throws {
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        var now = origin
        var delivered: URL?
        let task = Task { @MainActor in
            let result = try await ActionCallbackRouter.openAsync(["url": "neutral-test://deadline"], timeout: 10,
                now: { now }, openURL: { url in
                    delivered = try? callback(url)
                    if phase == "during launch", let delivered {
                        now = origin.addingTimeInterval(10)
                        #expect(!ActionCallbackRouter.receive(delivered))
                    }
                    return true
                })
            return (result["status"] as? String, result["parameters"] as? [String: String])
        }
        let setupDeadline = ContinuousClock.now + .seconds(5)
        while delivered == nil, ContinuousClock.now < setupDeadline { await Task.yield() }
        let expired = try #require(delivered)
        if phase == "before timer resumes" {
            now = origin.addingTimeInterval(10)
            #expect(!ActionCallbackRouter.receive(expired))
        }
        let response = try await task.value
        #expect(response.0 == "timeout")
        #expect(response.1?.isEmpty == true)
        #expect(!ActionCallbackRouter.receive(expired))
        let next = try await ActionCallbackRouter.openAsync(["url": "neutral-test://next"],
            now: { now }, openURL: { url in
                do { #expect(ActionCallbackRouter.receive(try callback(url))) }
                catch { Issue.record(error) }
                return true
            })
        #expect(next["status"] as? String == "success")
    }

    @Test func timeoutInvalidatesTheToken() async throws {
        var late: URL?
        let result = try await ActionCallbackRouter.openAsync(["url": "neutral-test://run"], timeout: 0.02, openURL: { url in
            late = try? callback(url); return true
        })
        #expect(result["status"] as? String == "timeout")
        #expect(!ActionCallbackRouter.receive(try #require(late)))
        #expect(!ActionCallbackRouter.receive(URL(string: "draftly://callback?token=unknown&status=success")!))
    }

    @Test func cancellationReleasesTheWaitAndRejectsLateDelivery() async throws {
        var late: URL?
        let task = Task { @MainActor in
            do {
                _ = try await ActionCallbackRouter.openAsync(["url": "neutral-test://run"], openURL: { url in
                    late = try? callback(url); return true
                })
                return false
            } catch { return error is CancellationError }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while late == nil, ContinuousClock.now < deadline { await Task.yield() }
        task.cancel()
        #expect(await task.value)
        var nextURL: URL?
        let next = Task { @MainActor in
            let result = try await ActionCallbackRouter.openAsync(["url": "neutral-test://next"], timeout: 5, openURL: { url in
                nextURL = try? callback(url); return true
            })
            return (result["status"] as? String, (result["parameters"] as? [String: String])?["value"])
        }
        let nextDeadline = ContinuousClock.now + .seconds(5)
        while nextURL == nil, ContinuousClock.now < nextDeadline { await Task.yield() }
        let valid = try #require(nextURL)
        #expect(valid != late)
        #expect(!ActionCallbackRouter.receive(try #require(late)))
        var response = try #require(URLComponents(url: valid, resolvingAgainstBaseURL: false))
        response.queryItems = (response.queryItems ?? []) + [URLQueryItem(name: "value", value: "Fresh café 🐼")]
        #expect(ActionCallbackRouter.receive(try #require(response.url)))
        let result = try await next.value
        #expect(result.0 == "success" && result.1 == "Fresh café 🐼")
    }

    @Test func concurrentCallbacksStayWithTheirOwnRequest() async throws {
        var urls: [String: URL] = [:]
        func start(_ name: String) -> Task<String?, Error> {
            Task { @MainActor in
                let response = try await ActionCallbackRouter.openAsync(["url": "neutral-test://" + name], openURL: { url in
                    urls[name] = try? callback(url); return true
                })
                return (response["parameters"] as? [String: String])?["request"]
            }
        }
        let first = start("first"), second = start("second")
        let deadline = ContinuousClock.now + .seconds(5)
        while urls.count < 2, ContinuousClock.now < deadline { await Task.yield() }
        for name in ["second", "first"] {
            var response = URLComponents(url: try #require(urls[name]), resolvingAgainstBaseURL: false)!
            response.queryItems = (response.queryItems ?? []) + [URLQueryItem(name: "request", value: name)]
            #expect(ActionCallbackRouter.receive(try #require(response.url)))
        }
        #expect(try await first.value == "first")
        #expect(try await second.value == "second")
    }

    @Test func wrongSchemeDoesNotConsumeAnActiveCallback() async throws {
        let response = try await ActionCallbackRouter.openAsync(["url": "neutral-test://run"], openURL: { url in
            do {
                let valid = try callback(url)
                var wrong = try #require(URLComponents(url: valid, resolvingAgainstBaseURL: false))
                wrong.scheme = "unrelated-callback"
                #expect(!ActionCallbackRouter.receive(try #require(wrong.url)))
                #expect(ActionCallbackRouter.receive(valid))
            } catch { Issue.record(error) }
            return true
        })
        #expect(response["status"] as? String == "success")
    }

    @Test func invalidTargetsAndOpenFailureNeverWait() async throws {
        for raw in ["javascript:alert(1)", "DATA:text/plain,test", "file:///tmp/test", "relative"] {
            let result = try await ActionCallbackRouter.openAsync(["url": raw], openURL: { _ in Issue.record("An invalid URL was opened."); return true })
            #expect(result["status"] as? String == "invalid")
        }
        let failed = try await ActionCallbackRouter.openAsync(["url": "neutral-test://run"], openURL: { _ in false })
        #expect(failed["status"] as? String == "invalid")
        let immediate = try await ActionCallbackRouter.openAsync(["url": "neutral-test://run", "waitForResponse": false], openURL: { url in
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == nil)
            return true
        })
        #expect(immediate["status"] as? String == "success")
    }
}
