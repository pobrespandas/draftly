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
        ["callbackURL", "shellScript", "shortcut"].contains(operation)
    }

    func performAsync(_ operation: String, payload: String) async throws -> String {
        guard let values = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw DraftlyError.message("The native operation payload must be an object.")
        }
        let result: Any?
        switch operation {
        case "callbackURL": result = try await ActionCallbackRouter.openAsync(values)
        case "shellScript": result = try await NativeAutomationAdapter().executeShellAsync(values)
        case "shortcut": result = try await NativeAutomationAdapter().runShortcutAsync(name: values["name"] as? String ?? "", input: values["text"] as? String ?? "")
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
