import SwiftUI
import Darwin
import AgentContracts

// Manual UI host only. No broker, Keychain adapter or library file is used.
@MainActor final class AgentSettingsPreviewSession: ObservableObject {
    final class Memory {
        var bytes: Data?
        var credentials: [UUID: Data] = [:]
    }
    let model: AgentConnectionsSettingsModel
    let pairing: AgentPairingCoordinator
    private let registry: AgentConnectionRegistry

    init() throws {
        let memory = Memory(), libraryID = UUID()
        let alpha = AgentResourceReference(kind: .draft, id: UUID())
        let beta = AgentResourceReference(kind: .draft, id: UUID())
        let targets: Set<AgentResourceReference> = [alpha, beta]
        let registry = AgentConnectionRegistry(metadata: .init(read: { memory.bytes }, replace: { data, expected in
            guard memory.bytes == expected else { throw AgentErrorCode.versionConflict }
            memory.bytes = data
        }), credentials: .init(read: { memory.credentials[$0] }, create: { memory.credentials[$0] = $1 },
                               remove: { memory.credentials.removeValue(forKey: $0) }), authorityChanged: { _ in })
        let pairing = AgentPairingCoordinator(registry: registry, libraryID: libraryID, validateHost: {}, isLocked: { false },
            resolveTargets: { $0.intersection(targets) })
        self.registry = registry; self.pairing = pairing
        model = try AgentConnectionsSettingsModel(libraryID: libraryID, registry: registry, pairing: pairing,
            choices: { [.init(reference: alpha, title: "Neutral draft Alpha"), .init(reference: beta, title: "Neutral draft Beta 🐼")] },
            initialTargets: { [alpha] }, resolveTargets: { $0.intersection(targets) }, setAccessEnabled: { enabled in
                try registry.setEnabledFromUserInterface(enabled)
                if !enabled { pairing.invalidatePending() }
            })
        try model.setEnabled(true)
        _ = try registry.connectFromUserInterface(name: "QA reader", libraryID: libraryID, scope: .resources([alpha]))
        model.refresh()
        try addRequest()
    }

    func addRequest() throws {
        _ = try pairing.request(clientName: "QA client — untrusted label")
        model.refresh()
    }
}

@main struct AgentSettingsPreviewApp: App {
    @StateObject private var session: AgentSettingsPreviewSession
    @State private var appearance: ColorScheme = .dark
    init() {
        do {
            let session = try AgentSettingsPreviewSession()
            _session = StateObject(wrappedValue: session)
        }
        catch { fputs("Cannot prepare the neutral UI preview.\n", stderr); exit(1) }
    }
    var body: some Scene {
        WindowGroup("Draftly — Agents UI Preview") {
            VStack(spacing: 0) {
                HStack {
                    Text("Manual QA · Memory only · No agent endpoint").font(.caption)
                    Spacer()
                    Picker("Preview appearance", selection: $appearance) {
                        Text("Light").tag(ColorScheme.light)
                        Text("Dark").tag(ColorScheme.dark)
                    }.pickerStyle(.segmented).frame(width: 150)
                    Button("Create neutral request") { try? session.addRequest() }
                }.padding(12)
                Divider()
                AgentConnectionsSettingsView(model: session.model)
            }.frame(width: 770, height: 720).preferredColorScheme(appearance)
        }
    }
}
