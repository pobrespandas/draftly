import Foundation
import CoreData
import CloudKit

@MainActor
final class LibrarySyncCoordinator {
    private let container: NSPersistentContainer
    private let cloudIdentifier: String?
    private let onRemoteChange: () -> Void
    private let onStatusChange: (String) -> Void
    private var observers: [NSObjectProtocol] = []
    private var cloudState = CloudSyncState()
    private var accountCheck = 0

    init(container: NSPersistentContainer, cloudIdentifier: String?,
         onRemoteChange: @escaping () -> Void, onStatusChange: @escaping (String) -> Void) {
        self.container = container
        self.cloudIdentifier = cloudIdentifier
        self.onRemoteChange = onRemoteChange
        self.onStatusChange = onStatusChange
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.onRemoteChange()
            }
        })
        if let cloud = container as? NSPersistentCloudKitContainer {
            observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: cloud, queue: .main) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
                let phase: CloudSyncState.Phase
                switch event.type {
                case .setup: phase = .setup
                case .import: phase = .download
                case .export: phase = .upload
                @unknown default: return
                }
                let id = event.identifier, storeID = event.storeIdentifier
                let ended = event.endDate != nil, succeeded = event.succeeded
                let message = event.error.map(CloudSyncError.message)
                Task { @MainActor in
                    guard let self, self.container.persistentStoreCoordinator.persistentStores.contains(where: { $0.identifier == storeID }) else { return }
                    self.cloudState.receive(id: id, phase: phase, ended: ended, succeeded: succeeded, error: message)
                    self.onStatusChange(self.cloudState.message)
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshCloudAccount() }
            })
            Task { @MainActor [weak self] in await self?.refreshCloudAccount() }
        }
    }

    func refreshCloudAccount() async {
        guard let cloudIdentifier else { return }
        accountCheck += 1
        let check = accountCheck
        let account: CloudSyncState.Account
        do {
            switch try await CKContainer(identifier: cloudIdentifier).accountStatus() {
            case .available: account = .available
            case .noAccount: account = .signedOut
            case .restricted: account = .restricted
            case .temporarilyUnavailable: account = .temporarilyUnavailable
            case .couldNotDetermine: account = .failed("The account status could not be determined.")
            @unknown default: account = .failed("The account status is not supported.")
            }
        } catch { account = .failed(CloudSyncError.message(error)) }
        guard accountCheck == check else { return }
        cloudState.account = account
        onStatusChange(cloudState.message)
    }
}
