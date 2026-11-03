import Foundation

@MainActor final class ChatGPTCredentialStore {
    typealias Backend = DeviceCredentialStore.Backend
    typealias Failure = DeviceCredentialStore.Failure
    private let store: DeviceCredentialStore

    init(bundleID: String = Bundle.main.bundleIdentifier ?? "com.pobrespandas.draftly", backend: Backend = .system) {
        store = DeviceCredentialStore(service: bundleID + ".chatgpt.credentials.v1", backend: backend)
    }

    func read(_ accountID: UUID) throws -> Data? { try store.read(accountID) }
    func write(_ data: Data, accountID: UUID) throws { try store.write(data, accountID: accountID) }
    func remove(_ accountID: UUID) throws { try store.remove(accountID) }
}
