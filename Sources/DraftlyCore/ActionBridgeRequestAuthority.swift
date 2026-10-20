import Foundation

final class ActionBridgeRequestAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [UUID: ActionBridgeRequest] = [:]
    private var seenTokens: Set<UUID> = []
    private var invalidated = false

    func register(_ request: ActionBridgeRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !invalidated, request.deadline > Date(), seenTokens.insert(request.token).inserted else { return false }
        requests[request.token] = request
        return true
    }

    func consume(_ request: ActionBridgeRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !invalidated, let registered = requests[request.token] else { return false }
        guard registered.deadline > Date() else {
            requests.removeValue(forKey: request.token)
            return false
        }
        guard registered.executionID == request.executionID,
              registered.stepID == request.stepID,
              registered.deadline == request.deadline,
              registered.operation == request.operation,
              registered.payload == request.payload else { return false }
        requests.removeValue(forKey: request.token)
        return true
    }

    func revoke(_ token: UUID) {
        lock.lock(); defer { lock.unlock() }
        requests.removeValue(forKey: token)
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        invalidated = true
        requests.removeAll()
        seenTokens.removeAll()
    }
}
