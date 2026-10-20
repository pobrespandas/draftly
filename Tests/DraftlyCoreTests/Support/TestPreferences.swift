import Foundation

struct TestPreferences {
    private enum SetupError: Error { case unavailableSuite(String) }
    let name: String
    let defaults: UserDefaults

    init(prefix: String = "Draftly-CoreTests") throws {
        name = prefix + "-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else { throw SetupError.unavailableSuite(name) }
        self.defaults = defaults
    }

    func close() { defaults.removePersistentDomain(forName: name) }
}
