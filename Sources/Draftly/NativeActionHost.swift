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
    var onMessage: ((String, String) throws -> Void)?
    var onActionPreview: ((ActionPreviewRequest) -> Void)?
    var dictationHandler: (([String: Any]) throws -> String)?
    var testFileRoot: URL?
    var fileDefaults: UserDefaults = .standard
    var fileAdapter: NativeFileAdapter { NativeFileAdapter(defaults: fileDefaults, testFileRoot: testFileRoot) }
    var onPreview: ((String) -> Void)?
    var onError: (String) -> Void = { _ in }
    var ownerWindow: @MainActor () -> NSWindow? = { nil }
    private let previewAdapter = NativePreviewAdapter()

    func finishAction() { models.clear() }

    func supportsAsync(_ operation: String) -> Bool {
        NativeAsyncRoute.resolve(operation) != nil
    }

    func performAsync(_ operation: String, payload: String) async throws -> String {
        guard let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw DraftlyError.message("The native operation payload must be an object.")
        }
        let result: Any?
        switch NativeAsyncRoute.resolve(operation) {
        case .model: return try await models.performAsync(operation, payload: payload)
        case .prompt:
            result = try await NativePromptAdapter().performAsync(operation, values: values)
            return String(decoding: try JSONSerialization.data(withJSONObject: ["value": result ?? NSNull()]), as: UTF8.self)
        case .sharing: result = try await NativeSharingRequest.run(operation, values, ownerWindow: ownerWindow,
                                                                  reportCleanupError: { [weak self] message in self?.onError(message) })
        case .printing: result = try await NativePrintRequest.run(values, ownerWindow: ownerWindow)
        case .arrangement: result = try await arrangeTextAsync(values["text"] as? String ?? "")
        case .htmlPreview: result = try await interactivePreviewAsync(values)
        case .file: result = try await fileAdapter.performAsync(operation, values: values)
        case .message: result = try await NativeMessageAdapter().composeAsync(operation, values)
        case .callback: result = try await ActionCallbackRouter.openAsync(values)
        case .shell: result = try await NativeAutomationAdapter().executeShellAsync(values)
        case .shortcut: result = try await NativeAutomationAdapter().runShortcutAsync(name: values["name"] as? String ?? "", input: values["text"] as? String ?? "", waitForResponse: values["waitForResponse"] as? Bool ?? true)
        case .eventAPI: result = try await eventAPIAsync(values)
        case .event: result = try await NativeSystemAdapter(events: events, reportError: onError).performAsync(operation, values: values)
        case .location: result = try await NativeLocationRequest.current()
        case .speech: result = try await NativeSpeechRequest.run(values)
        case .transcription: result = try await NativeTranscriptionRequest.run(values)
        case .appleScript: result = try await NativeAppleScriptProcess.run(values)
        case .dictation:
            if let dictationHandler { result = try dictationHandler(values) }
            else { result = try await NativeDictationRequest.run(values) }
        case nil: result = try perform(operation, values: values)
        }
        let envelope = operation == "appleScript" ? try AppleScriptValueTransport.encode(result ?? NSNull()) : ["value": result ?? NSNull()]
        return String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
    }

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        if NativePromptAdapter.operations.contains(operation) { return try NativePromptAdapter().perform(operation, values: values) }
        if NativeFileAdapter.operations.contains(operation) { return try fileAdapter.perform(operation, values: values) }
        if NativePreviewAdapter.operations.contains(operation) { return try previewAdapter.perform(operation, values: values, host: self) }
        if NativeAutomationAdapter.operations.contains(operation) { return try NativeAutomationAdapter().perform(operation, values: values, host: self) }
        if NativeSystemAdapter.operations.contains(operation) { return try NativeSystemAdapter(events: events, reportError: onError).perform(operation, values: values) }
        return try performAPI(operation, values: values)
    }
    func libraryFolder() throws -> URL { try fileAdapter.libraryFolder() }
    func showHTML(_ html: String) { previewAdapter.showHTML(html, onPreview: onPreview) }
    func requestAccess(reminders: Bool) throws { try NativeSystemAdapter(events: events, reportError: onError).requestAccess(reminders: reminders) }
}
