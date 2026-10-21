import Foundation
import Testing

struct TestPreferences {
    let name: String
    let defaults: UserDefaults

    init(prefix: String) throws {
        name = prefix + UUID().uuidString
        defaults = try #require(UserDefaults(suiteName: name))
    }

    func close() { defaults.removePersistentDomain(forName: name) }
}
