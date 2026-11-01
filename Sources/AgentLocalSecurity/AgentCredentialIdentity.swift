import Foundation
import Security
import AgentContracts

package enum AgentCredentialRole: Sendable {
    case application, helper

    package var identifier: String {
        switch self {
        case .application: "com.pobrespandas.draftly"
        case .helper: "com.pobrespandas.draftly.agent"
        }
    }
}

package enum AgentCredentialIdentity {
    package static let team = "NM92LU2KKV"
    package static let accessGroup = "NM92LU2KKV.com.pobrespandas.draftly.agent-access"
    package static let prohibitedEntitlements = ["com.apple.security.get-task-allow", "get-task-allow",
        "com.apple.security.cs.disable-library-validation",
        "com.apple.security.cs.allow-dyld-environment-variables",
        "com.apple.security.cs.allow-unsigned-executable-memory"]

    package static func requirement(for role: AgentCredentialRole) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(role.identifier)\""
    }

    // This policy supplements, and does not replace, the OS entitlement check.
    package static func validateEntitlements(_ values: [String: Any]) throws {
        guard let groups = values["keychain-access-groups"] as? [String], groups.contains(accessGroup) else {
            throw AgentErrorCode.permissionDenied
        }
        for key in prohibitedEntitlements {
            guard let value = values[key] else { continue }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), !number.boolValue else {
                throw AgentErrorCode.permissionDenied
            }
        }
    }

    package static func validateCurrentProcess(_ role: AgentCredentialRole) throws {
        var code: SecCode?, requirement: SecRequirement?
        guard SecCodeCopySelf(SecCSFlags(rawValue: 0), &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(self.requirement(for: role) as CFString,
                SecCSFlags(rawValue: 0), &requirement) == errSecSuccess, let requirement,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: 0), requirement) == errSecSuccess,
              let task = SecTaskCreateFromSelf(nil) else { throw AgentErrorCode.permissionDenied }
        var values: [String: Any] = [:]
        for key in ["keychain-access-groups"] + prohibitedEntitlements {
            var error: Unmanaged<CFError>?
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, &error)
            if let error { _ = error.takeRetainedValue(); throw AgentErrorCode.permissionDenied }
            if let value { values[key] = value }
        }
        try validateEntitlements(values)
    }
}
