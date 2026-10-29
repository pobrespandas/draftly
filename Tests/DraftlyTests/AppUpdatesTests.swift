import Foundation
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
