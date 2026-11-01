import Foundation

package enum AgentEffect: String, Hashable, Sendable {
    case scriptRuntime, templateRead, editorMutation, draftCreation
    case clipboardRead, clipboardWrite, fileRead, fileWrite, externalURL
    case nativePresentation, unrestrictedAutomation, htmlInteraction
    case initialConfiguration, executionLocalState, windowPresentation
    case communication, reminders, calendar, speech, includedAction
    case finalDisposition, queuedAction
}

package enum AgentStepReview: Equatable, Sendable {
    case skipped
    case unsupported
    // Potential effects identify runtime checks, not capabilities to grant in advance.
    case requiresRuntimeChecks(Set<AgentEffect>)
}

package enum AgentStepEffectCatalog {
    package static var stepTypes: Set<String> { Set(effects.keys) }

    package static let executionChecks: Set<AgentEffect> = [
        .initialConfiguration, .finalDisposition, .queuedAction
    ]

    package static func review(type: String, isEnabled: Bool?) -> AgentStepReview {
        guard isEnabled != false else { return .skipped }
        guard var checks = effects[type] else { return .unsupported }
        if type != "script" { checks.insert(.templateRead) }
        return .requiresRuntimeChecks(checks)
    }

    private static let effects: [String: Set<AgentEffect>] = [
        "script": [.scriptRuntime],
        "clipboard": [.clipboardRead, .clipboardWrite],
        "url": [.externalURL],
        "insertText": [.editorMutation],
        "createDraft": [.draftCreation, .windowPresentation],
        "file": [.fileRead, .fileWrite],
        "share": [.nativePresentation, .communication],
        "runShortcut": [.unrestrictedAutomation],
        "runAppleScript": [.unrestrictedAutomation],
        "htmlpreview": [.htmlInteraction, .nativePresentation],
        "configurationKey": [.initialConfiguration],
        "includeAction": [.includedAction],
        "reminder": [.reminders],
        "event": [.calendar],
        "callbackUrl": [.externalURL],
        "prompt": [.nativePresentation, .executionLocalState],
        "defineTemplateTag": [.executionLocalState],
        "configureWindow": [.windowPresentation],
        "mail": [.communication, .nativePresentation],
        "message": [.communication, .nativePresentation],
        "listInReminders": [.reminders],
        "export": [.fileWrite, .nativePresentation],
        "openIn": [.fileWrite, .nativePresentation, .externalURL],
        "print": [.nativePresentation, .fileWrite],
        "speak": [.speech, .nativePresentation]
    ]
}
