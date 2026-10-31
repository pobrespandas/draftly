import Foundation

/// Copies local preferences before the main app creates its controllers.
@MainActor enum ApplicationIdentityMigration {
    static let identifier = "com.pobrespandas.draftly"
    static let legacyIdentifier = "com.andrestobelem.draftly"
    static let completionKey = "application.identityMigration.com.andrestobelem.draftly.v1"

    struct Domains {
        var read: (String) throws -> [String: Any]?
        var write: (String, [String: Any]) throws -> Void

        static func persistent(defaults: UserDefaults = .standard) -> Self {
            Self(read: { domain in
                guard CFPreferencesAppSynchronize(domain as CFString) else {
                    throw MigrationError.persistence
                }
                let values = defaults.persistentDomain(forName: domain)
                let file = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences/\(domain).plist")
                guard values != nil || !FileManager.default.fileExists(atPath: file.path) else {
                    throw MigrationError.persistence
                }
                return values
            }, write: { domain, values in
                defaults.setPersistentDomain(values, forName: domain)
                guard CFPreferencesAppSynchronize(domain as CFString) else {
                    throw MigrationError.persistence
                }
            })
        }
    }

    enum MigrationError: LocalizedError {
        case persistence
        var errorDescription: String? {
            "Draftly could not preserve the local preferences. The previous preferences and library are unchanged. Try again before opening the library."
        }
    }

    static func isRequired(bundleIdentifier: String?, isolated: Bool) -> Bool {
        bundleIdentifier == identifier && !isolated
    }

    static func prepare(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) throws {
        let isolated = arguments.contains("--ui-testing")
            || bundle.object(forInfoDictionaryKey: "DraftlyUITesting") as? Bool == true
            || bundle.object(forInfoDictionaryKey: "DraftlyCloudTesting") as? Bool == true
        guard isRequired(bundleIdentifier: bundle.bundleIdentifier, isolated: isolated) else { return }
        try migrate(domains: .persistent())
    }

    @discardableResult
    static func migrate(domains: Domains, source: String = legacyIdentifier,
                        destination: String = identifier) throws -> Bool {
        let current = try domains.read(destination) ?? [:]
        if current[completionKey] as? Bool == true { return false }
        var merged = try domains.read(source) ?? [:]
        merged.removeValue(forKey: completionKey)
        merged.merge(current) { _, existing in existing }
        try writeAndVerify(merged, to: destination, domains: domains)
        merged[completionKey] = true
        try writeAndVerify(merged, to: destination, domains: domains)
        return true
    }

    private static func writeAndVerify(_ values: [String: Any], to domain: String, domains: Domains) throws {
        try domains.write(domain, values)
        let actual = try domains.read(domain) ?? [:]
        guard NSDictionary(dictionary: values).isEqual(to: actual) else {
            throw MigrationError.persistence
        }
    }
}
