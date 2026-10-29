import Foundation
import AppKit
import Combine
import Testing
@testable import Draftly

@Suite("Update configuration")
struct AppUpdatesTests {
    private let key = Data(repeating: 42, count: 32).base64EncodedString()
    private let feed = "https://draftly.pobrespandas.com/appcast.xml"

    @Test func enablesOnlyTheConfiguredMainApp() {
        #expect(AppUpdateConfiguration.isAvailable(enabled: "YES", bundleID: "com.pobrespandas.draftly", publicKey: key, feed: feed))
        #expect(!AppUpdateConfiguration.isAvailable(enabled: nil, bundleID: "com.pobrespandas.draftly", publicKey: key, feed: feed))
        #expect(!AppUpdateConfiguration.isAvailable(enabled: "YES", bundleID: "com.example.qa", publicKey: key, feed: feed))
        #expect(!AppUpdateConfiguration.isAvailable(enabled: "YES", bundleID: nil, publicKey: key, feed: feed))
    }

    @Test func rejectsMissingOrInvalidConfiguration() {
        let id = "com.pobrespandas.draftly"
        #expect(!AppUpdateConfiguration.isAvailable(enabled: "YES", bundleID: id, publicKey: "", feed: feed))
        #expect(!AppUpdateConfiguration.isAvailable(enabled: "YES", bundleID: id, publicKey: "not a key", feed: feed))
        #expect(!AppUpdateConfiguration.isAvailable(enabled: "YES", bundleID: id, publicKey: key, feed: "http://draftly.pobrespandas.com/appcast.xml"))
        #expect(!AppUpdateConfiguration.isAvailable(enabled: "YES", bundleID: id, publicKey: key, feed: "https://example.com/appcast.xml"))
        #expect(!AppUpdateConfiguration.isAvailable(enabled: "YES", bundleID: id, publicKey: key, feed: nil))
    }
}

@Suite("Termination during Actions")
@MainActor
struct ActionTerminationCoordinatorTests {
    @Test func idleTerminationFlushesAndReportsSaveFailure() {
        let changes = PassthroughSubject<Bool, Never>()
        let coordinator = ActionTerminationCoordinator()
        var replies = 0
        let allowed = coordinator.request(busy: { false }, changes: changes.eraseToAnyPublisher(),
                                          flush: { true }, reply: { _ in replies += 1 })
        let rejected = coordinator.request(busy: { false }, changes: changes.eraseToAnyPublisher(),
                                           flush: { false }, reply: { _ in replies += 1 })
        #expect(allowed == .terminateNow)
        #expect(rejected == .terminateCancel)
        #expect(replies == 0)
    }

    @Test(arguments: [true, false]) func terminationWaitsForActionAndRepliesOnceAfterSave(saveSucceeds: Bool) async {
        let changes = PassthroughSubject<Bool, Never>()
        let coordinator = ActionTerminationCoordinator()
        var busy = true
        var flushCount = 0
        var replyCount = 0
        let result: Bool = await withCheckedContinuation { continuation in
            let reply = coordinator.request(busy: { busy }, changes: changes.eraseToAnyPublisher(),
                flush: { flushCount += 1; return saveSucceeds },
                reply: { value in replyCount += 1; continuation.resume(returning: value) })
            #expect(reply == .terminateLater)
            #expect(flushCount == 0)
            let duplicate = coordinator.request(busy: { busy }, changes: changes.eraseToAnyPublisher(),
                flush: { Issue.record("A second termination must not replace the first"); return true },
                reply: { _ in Issue.record("Unexpected second reply") })
            #expect(duplicate == .terminateLater)
            busy = false
            changes.send(false)
        }
        #expect(result == saveSucceeds)
        #expect(flushCount == 1)
        #expect(replyCount == 1)
    }
}
