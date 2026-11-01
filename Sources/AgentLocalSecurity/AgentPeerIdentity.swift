import Foundation
import Darwin
import Security
import AgentContracts

package enum AgentPeerIdentity {
    // Use a kernel-provided audit token. A PID or a claimed name is not identity.
    package static func validate(_ token: Data, role: AgentCredentialRole) throws {
        guard token.count == MemoryLayout<audit_token_t>.size else { throw AgentErrorCode.permissionDenied }
        var code: SecCode?, requirement: SecRequirement?
        let attributes = [kSecGuestAttributeAudit as String: token] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(rawValue: 0), &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(AgentCredentialIdentity.requirement(for: role) as CFString,
                SecCSFlags(rawValue: 0), &requirement) == errSecSuccess, let requirement,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: 0), requirement) == errSecSuccess else {
            throw AgentErrorCode.permissionDenied
        }
    }
}
