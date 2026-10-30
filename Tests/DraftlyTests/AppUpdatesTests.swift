import Foundation
import AppKit
import Combine
import Testing
@testable import Draftly

@Suite("Update configuration")
struct AppUpdatesTests {
    private let key = Data(repeating: 42, count: 32).base64EncodedString()
    private let feed = "https://draftly.pobrespandas.com/appcast.xml"

    private func available(enabled: String?, bundleID: String?, publicKey: String?, feed: String?,
                           signedFeed: Bool = true, verifyBeforeExtraction: Bool = true,
                           allowsAutomaticUpdates: Bool = false) -> Bool {
        AppUpdateConfiguration.isAvailable(enabled: enabled, bundleID: bundleID, publicKey: publicKey, feed: feed,
            signedFeed: signedFeed, verifyBeforeExtraction: verifyBeforeExtraction, allowsAutomaticUpdates: allowsAutomaticUpdates)
    }

    @Test func enablesOnlyTheConfiguredMainApp() {
        #expect(available(enabled: "YES", bundleID: "com.pobrespandas.draftly", publicKey: key, feed: feed))
        #expect(!available(enabled: nil, bundleID: "com.pobrespandas.draftly", publicKey: key, feed: feed))
        #expect(!available(enabled: "YES", bundleID: "com.example.qa", publicKey: key, feed: feed))
        #expect(!available(enabled: "YES", bundleID: nil, publicKey: key, feed: feed))
    }

    @Test func rejectsMissingOrInvalidConfiguration() {
        let id = "com.pobrespandas.draftly"
        #expect(!available(enabled: "YES", bundleID: id, publicKey: "", feed: feed))
        #expect(!available(enabled: "YES", bundleID: id, publicKey: "not a key", feed: feed))
        #expect(!available(enabled: "YES", bundleID: id, publicKey: key, feed: "http://draftly.pobrespandas.com/appcast.xml"))
        #expect(!available(enabled: "YES", bundleID: id, publicKey: key, feed: "https://example.com/appcast.xml"))
        #expect(!available(enabled: "YES", bundleID: id, publicKey: key, feed: nil))
        #expect(!available(enabled: "YES", bundleID: id, publicKey: key, feed: feed, signedFeed: false))
        #expect(!available(enabled: "YES", bundleID: id, publicKey: key, feed: feed, verifyBeforeExtraction: false))
        #expect(!available(enabled: "YES", bundleID: id, publicKey: key, feed: feed, allowsAutomaticUpdates: true))
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

    @Test func terminationRepliesOutsideTheDefaultRunLoopMode() async {
        let replies: Int = await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    #if compiler(>=6.4)
                    let mode = CFRunLoopMode(rawValue: "DraftlyTerminationTestMode" as CFString)
                    #else
                    let mode = "DraftlyTerminationTestMode" as CFString
                    #endif
                    let loop = CFRunLoopGetMain()!
                    CFRunLoopAddCommonMode(loop, mode)
                    let port = Port()
                    RunLoop.main.add(port, forMode: RunLoop.Mode("DraftlyTerminationTestMode"))
                    defer { port.invalidate() }

                    let changes = PassthroughSubject<Bool, Never>()
                    let coordinator = ActionTerminationCoordinator()
                    var busy = true
                    var count = 0
                    let reply = coordinator.request(busy: { busy }, changes: changes.eraseToAnyPublisher(),
                        flush: { true }, reply: { _ in count += 1; CFRunLoopStop(loop) })
                    #expect(reply == .terminateLater)
                    busy = false
                    changes.send(false)
                    CFRunLoopRunInMode(mode, 1, false)
                    withExtendedLifetime(coordinator) { continuation.resume(returning: count) }
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        #expect(replies == 1)
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
