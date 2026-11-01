import Foundation
import AgentContracts

struct AgentGrantEditingCopy: Equatable {
    var name: String
    var capabilities: Set<AgentCapability>
    var wholeLibrary: Bool
    var targets: Set<AgentResourceReference>
    var expiresAt: Date
    var renewable: Bool
    let originalGrantID: UUID?

    init(name: String, selectedTargets: Set<AgentResourceReference> = [], now: Date) {
        self.name = name; capabilities = [.draftsRead]; wholeLibrary = false
        targets = selectedTargets; expiresAt = now.addingTimeInterval(3600); renewable = false; originalGrantID = nil
    }

    init(record: AgentConnectionRecord) {
        name = record.name; capabilities = Set(record.capabilities); wholeLibrary = record.scopeKind == .library
        targets = Set(record.resources); expiresAt = record.expiresAt; renewable = record.renewable
        originalGrantID = record.grantID
    }

    var scope: AgentResourceScope { wholeLibrary ? .library : .resources(targets) }
}
