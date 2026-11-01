package enum AgentCLIStatus {
    package static func exitCode(_ error: AgentErrorCode) -> Int32 {
        switch error {
        case .invalidInput: 2
        case .permissionDenied, .interactionRequired: 3
        case .versionConflict, .editorConflict, .busy: 4
        case .unavailable: 5
        default: 1
        }
    }
}
