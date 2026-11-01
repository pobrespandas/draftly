import Foundation
import AgentContracts

extension AgentCapability {
    var userTitle: String {
        switch self {
        case .draftsRead: "Read drafts"
        case .draftsWrite: "Create and change drafts"
        case .editorRead: "Read editor context"
        case .editorWrite: "Change editor text and selection"
        case .presentUI: "Show windows and change focus"
        case .actionsRead: "Read Actions"
        case .actionsManage: "Manage Actions and their scripts"
        case .actionsRun: "Run Actions"
        case .workspacesRead: "Read Workspaces"
        case .workspacesManage: "Manage Workspaces"
        case .workspacesApply: "Apply Workspaces to windows"
        case .appearanceRead: "Read themes and syntax"
        case .appearanceManage: "Manage themes and syntax"
        case .preferencesRead: "Read app preferences"
        case .preferencesWrite: "Change app preferences"
        case .filesRead: "Read files in approved folders"
        case .filesWrite: "Write files in approved folders"
        case .backupsExport: "Export a library backup"
        case .backupsRestore: "Request backup restoration"
        case .nativeUse: "Use native integrations"
        case .scriptsUnrestricted: "Run unrestricted scripts"
        case .destructiveRequest: "Request permanent deletion"
        }
    }
}

extension AgentResourceKind {
    var userTitle: String {
        switch self {
        case .draft: "Draft"
        case .revision: "Version"
        case .action: "Action"
        case .actionGroup: "Action group"
        case .workspace: "Workspace"
        case .theme: "Theme"
        case .syntax: "Syntax"
        case .window: "Window"
        case .bookmark: "Folder bookmark"
        case .operation: "Operation"
        }
    }
}

extension AgentConnectionRegistry.DisplayStatus {
    var userTitle: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .inactive: "Inactive"
        case .revoked: "Revoked"
        case .needsReview: "Needs review"
        }
    }
}

extension AgentErrorCode {
    var connectionMessage: String {
        switch self {
        case .permissionDenied: "Access is not permitted. Review the connection and this build's setup."
        case .notFound: "A selected resource or connection is no longer available."
        case .versionConflict: "These permissions changed. Close and reopen the editor to review their current values."
        case .storageError: "Draftly could not read or save connection settings. Your edits are not discarded."
        case .outcomeUnknown: "Draftly could not confirm the result. Review the connection before you try again."
        case .interactionRequired: "Compare the codes before you approve this connection."
        case .invalidInput: "Check the name and expiration date."
        case .unavailable: "Local agent access is not available in this build."
        case .busy: "Draftly is busy. Wait for the current change to finish."
        case .cancelled: "The change was cancelled."
        case .timeout, .retryWindowExpired: "The request expired. Start a new request."
        case .editorConflict: "The editor changed. Review its current state."
        case .executionError: "Draftly could not complete the change."
        }
    }
}
