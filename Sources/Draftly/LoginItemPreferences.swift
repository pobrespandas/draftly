import Combine
import ServiceManagement

@MainActor
final class LoginItemPreferences: ObservableObject {
    enum Status: Equatable {
        case disabled, enabled, requiresApproval, unavailable
    }

    @Published private(set) var status: Status
    @Published private(set) var error: String?
    @Published private(set) var isChanging = false
    private let readStatus: () -> Status
    private let register: () throws -> Void
    private let unregister: () async throws -> Void

    convenience init() {
        self.init(readStatus: {
            switch SMAppService.mainApp.status {
            case .notRegistered: .disabled
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notFound: .unavailable
            @unknown default: .unavailable
            }
        }, register: {
            try SMAppService.mainApp.register()
        }, unregister: {
            try await SMAppService.mainApp.unregister()
        })
    }

    init(readStatus: @escaping () -> Status,
         register: @escaping () throws -> Void,
         unregister: @escaping () async throws -> Void) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        status = readStatus()
    }

    var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    func refresh() { status = readStatus() }

    func setEnabled(_ enabled: Bool) async {
        guard !isChanging else { return }
        refresh()
        guard enabled != isRegistered else { return }
        isChanging = true
        error = nil
        defer {
            refresh()
            isChanging = false
        }
        do {
            if enabled { try register() }
            else { try await unregister() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
