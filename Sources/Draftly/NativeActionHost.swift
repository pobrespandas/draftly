import AppKit
import UserNotifications
import WebKit
import EventKit
import Security
import DraftlyCore

@MainActor
final class NativeActionHost: ActionHost {
    let events = EKEventStore()
    let models = NativeModelAPI()
    var onMessage: ((String) -> Void)?
    var onActionPreview: ((ActionPreviewRequest) -> Void)?
    var dictationHandler: (([String: Any]) throws -> String)?
    var testFileRoot: URL?
    var onPreview: ((String) -> Void)?
    var onError: (String) -> Void = { _ in }
    private let previewAdapter = NativePreviewAdapter()

    func finishAction() { models.clear() }

    func supportsAsync(_ operation: String) -> Bool {
        if NativePromptAdapter.operations.contains(operation) { return true }
        return ["callbackURL", "shellScript", "shortcut", "eventAPI", "reminder", "event", "location", "speak", "transcribe", "modelModes", "modelRespond", "appleScript", "dictate", "htmlPreview", "saveFile", "bookmark", "fileAPI", "composeMail", "composeMessage", "print", "arrangeText", "share", "shareFile", "shareURL"].contains(operation)
    }

    func performAsync(_ operation: String, payload: String) async throws -> String {
        guard let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw DraftlyError.message("The native operation payload must be an object.")
        }
        if operation == "modelModes" || operation == "modelRespond" {
            return try await models.performAsync(operation, payload: payload)
        }
        let result: Any?
        if NativePromptAdapter.operations.contains(operation) {
            result = try await NativePromptAdapter().performAsync(operation, values: values)
            return String(decoding: try JSONSerialization.data(withJSONObject: ["value": result ?? NSNull()]), as: UTF8.self)
        }
        switch operation {
        case "share", "shareFile", "shareURL": result = try await NativeSharingRequest.run(operation, values, reportCleanupError: { [weak self] message in self?.onError(message) })
        case "print": result = try await NativePrintRequest.run(values)
        case "arrangeText": result = try await arrangeTextAsync(values["text"] as? String ?? "")
        case "htmlPreview": result = try await interactivePreviewAsync(values)
        case "saveFile", "bookmark", "fileAPI": result = try await NativeFileAdapter(testFileRoot: testFileRoot).performAsync(operation, values: values)
        case "composeMail", "composeMessage": result = try await NativeMessageAdapter().composeAsync(operation, values)
        case "callbackURL": result = try await ActionCallbackRouter.openAsync(values)
        case "shellScript": result = try await NativeAutomationAdapter().executeShellAsync(values)
        case "shortcut": result = try await NativeAutomationAdapter().runShortcutAsync(name: values["name"] as? String ?? "", input: values["text"] as? String ?? "", waitForResponse: values["waitForResponse"] as? Bool ?? true)
        case "eventAPI": result = try await eventAPIAsync(values)
        case "reminder", "event": result = try await NativeSystemAdapter(events: events, reportError: onError).performAsync(operation, values: values)
        case "location": result = try await NativeLocationRequest.current()
        case "speak": result = try await NativeSpeechRequest.run(values)
        case "transcribe": result = try await NativeTranscriptionRequest.run(values)
        case "appleScript": result = try await NativeAppleScriptProcess.run(values)
        case "dictate":
            if let dictationHandler { result = try dictationHandler(values) }
            else { result = try await NativeDictationRequest.run(values) }
        default: result = try perform(operation, values: values)
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: ["value": result ?? NSNull()]), as: UTF8.self)
    }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if NativePromptAdapter.operations.contains(operation) { return try NativePromptAdapter().perform(operation, values: values) }
        if NativeFileAdapter.operations.contains(operation) { return try NativeFileAdapter(testFileRoot: testFileRoot).perform(operation, values: values) }
        if NativePreviewAdapter.operations.contains(operation) { return try previewAdapter.perform(operation, values: values, host: self) }
        if NativeAutomationAdapter.operations.contains(operation) { return try NativeAutomationAdapter().perform(operation, values: values, host: self) }
        if NativeSystemAdapter.operations.contains(operation) { return try NativeSystemAdapter(events: events, reportError: onError).perform(operation, values: values) }
        return try performAPI(operation, values: values)
    }
    func libraryFolder() throws -> URL { try NativeFileAdapter(testFileRoot: testFileRoot).libraryFolder() }
    func showHTML(_ html: String) { previewAdapter.showHTML(html, onPreview: onPreview) }
    func requestAccess(reminders: Bool) throws { try NativeSystemAdapter(events: events, reportError: onError).requestAccess(reminders: reminders) }
}
