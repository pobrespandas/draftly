enum NativeAsyncRoute: Equatable {
    case http
    case xmlrpc
    case model
    case prompt
    case sharing
    case printing
    case arrangement
    case htmlPreview
    case file
    case message
    case messageHandoff
    case callback
    case shell
    case shortcut
    case eventAPI
    case event
    case reviewedEvent
    case location
    case speech
    case transcription
    case appleScript
    case dictation

    @MainActor
    static func resolve(_ operation: String) -> Self? {
        if operation == "modelModes" || operation == "modelRespond" { return .model }
        if NativePromptAdapter.operations.contains(operation) { return .prompt }
        switch operation {
        case "http": return .http
        case "xmlrpc": return .xmlrpc
        case "share", "shareFile", "shareURL": return .sharing
        case "print": return .printing
        case "arrangeText": return .arrangement
        case "htmlPreview": return .htmlPreview
        case "saveFile", "bookmark", "fileAPI": return .file
        case "composeMail", "composeMessage": return .message
        case "openMailComposer", "openMessagesComposer": return .messageHandoff
        case "callbackURL": return .callback
        case "shellScript": return .shell
        case "shortcut": return .shortcut
        case "eventAPI": return .eventAPI
        case "reminder", "event": return .event
        case "prepareCalendarCreate", "prepareReminderCreate", "calendarCreate", "reminderCreate": return .reviewedEvent
        case "location": return .location
        case "speak": return .speech
        case "transcribe": return .transcription
        case "appleScript": return .appleScript
        case "dictate": return .dictation
        default: return nil
        }
    }
}
