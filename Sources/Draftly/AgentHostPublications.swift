import AgentContracts
import AgentLocalSecurity

// Own publication attempts and their cleanup. The host still owns transport,
// authority checks and the order of lifecycle effects.
@MainActor final class AgentHostPublications {
    private let locator: AgentHostLocator
    private var retained: [AgentHostLocator.Endpoint] = []
    private(set) var cleanupError: AgentErrorCode?

    init(locator: AgentHostLocator) { self.locator = locator }

    func publish(_ entry: AgentHostLocator.Endpoint) throws {
        retained.append(entry)
        try locator.publish(entry)
    }

    // Called after the host rechecks ownership. This records the completed
    // publication; it does not approve or authorize an agent operation.
    func finishPublication(_ entry: AgentHostLocator.Endpoint) {
        retained = [entry]; cleanupError = nil
    }

    func withdraw() {
        var failure: AgentErrorCode?
        for entry in retained {
            do {
                try locator.withdraw(entry)
                retained.removeAll { $0 == entry }
            } catch {
                // Keep exact failed epochs for another explicit cleanup attempt.
                failure = (error as? AgentErrorCode) ?? .storageError
            }
        }
        cleanupError = failure
    }
}
