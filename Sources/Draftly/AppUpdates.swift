import AppKit
import Foundation
import Sparkle

struct AppUpdateConfiguration {
    static func isAvailable(enabled: String?, bundleID: String?, publicKey: String?, feed: String?) -> Bool {
        guard enabled == "YES", bundleID == "com.pobrespandas.draftly",
              let publicKey, let key = Data(base64Encoded: publicKey), key.count == 32,
              let feed, let url = URL(string: feed), url.scheme == "https",
              url.host == "draftly.pobrespandas.com", url.path == "/appcast.xml" else { return false }
        return true
    }
}

@MainActor
final class AppUpdates {
    static let shared = AppUpdates()
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil,
              AppUpdateConfiguration.isAvailable(enabled: Bundle.main.object(forInfoDictionaryKey: "DraftlyUpdatesEnabled") as? String,
                  bundleID: Bundle.main.bundleIdentifier,
                  publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                  feed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var isAvailable: Bool { controller != nil }
    func check() { controller?.checkForUpdates(nil) }
}
