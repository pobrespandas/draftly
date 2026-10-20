import AppKit
import UserNotifications
import EventKit
import DraftlyCore

@MainActor
struct NativeSystemAdapter {
    let events: EKEventStore
    var reportError: (String) -> Void
    static let operations: Set<String> = ["actionNotification", "clipboard", "getClipboard", "getCredential", "setCredential", "forgetCredential", "openURL", "reminder", "event"]

    func perform(_ operation: String, values: [String: Any]) throws -> Any? {
        let text = values["text"] as? String ?? ""
        switch operation {
        case "actionNotification":
            let title = values["title"] as? String ?? "Draftly", message = values["message"] as? String ?? ""
            Task {
                let center = UNUserNotificationCenter.current()
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                    reportError("Notifications are unavailable or permission was denied. The action result was kept.")
                    return
                }
                let content = UNMutableNotificationContent(); content.title = title; content.body = message
                do { try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
                catch { reportError("The notification failed: " + error.localizedDescription) }
            }
            return true
        case "clipboard": NSPasteboard.general.clearContents(); return NSPasteboard.general.setString(text, forType: .string)
        case "getClipboard": return NSPasteboard.general.string(forType: .string) ?? ""
        case "getCredential": return try CredentialStore.read(values["name"] as? String ?? "")
        case "setCredential": try CredentialStore.write(values["name"] as? String ?? "", values: values["values"] as? [String: String] ?? [:]); return true
        case "forgetCredential": try CredentialStore.forget(values["name"] as? String ?? ""); return true
        case "openURL":
            guard let string = values["url"] as? String, let url = URL(string: string), let scheme = url.scheme,
                  !["javascript", "data", "file"].contains(scheme.lowercased()) else { throw DraftlyError.message("The action URL is invalid.") }
            guard NSWorkspace.shared.open(url) else { throw DraftlyError.message("No app could open this URL.") }
            return true
        case "reminder":
            try requestAccess(reminders: true)
            return try createReminder(text)
        case "event":
            try requestAccess(reminders: false)
            guard let calendar = events.defaultCalendarForNewEvents else { throw DraftlyError.message("No Calendar is available.") }
            let alert = NSAlert(); alert.messageText = "Create calendar event"
            let picker = NSDatePicker(); picker.datePickerElements = [.yearMonthDay, .hourMinute]; picker.dateValue = Date()
            picker.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
            alert.informativeText = text.components(separatedBy: .newlines).first ?? text; alert.accessoryView = picker
            alert.addButton(withTitle: "Create Event"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { throw DraftlyError.message("Event creation cancelled.") }
            let event = EKEvent(eventStore: events); event.title = alert.informativeText; event.notes = text
            event.calendar = calendar; event.startDate = picker.dateValue; event.endDate = picker.dateValue.addingTimeInterval(3600)
            try events.save(event, span: .thisEvent); return true
        default: throw DraftlyError.message("The native operation is unavailable.")
        }
    }

    func performAsync(_ operation: String, values: [String: Any],
                      presentEvent: NativeEventDialog.Presenter = NativeEventDialog.presentCreation) async throws -> Any? {
        guard operation == "reminder" || operation == "event" else {
            throw DraftlyError.message("The asynchronous system operation is unavailable.")
        }
        try await requestAccessAsync(reminders: operation == "reminder")
        try Task.checkCancellation()
        let text = values["text"] as? String ?? ""
        if operation == "reminder" { return try createReminder(text) }
        guard let calendar = events.defaultCalendarForNewEvents else {
            throw DraftlyError.message("No Calendar is available.")
        }
        let start = Date()
        let initial = EventDialogValues(title: text.components(separatedBy: .newlines).first ?? text,
                                        notes: text, start: start, end: start.addingTimeInterval(3600))
        guard try await EventDialogCommit.run(initial, present: presentEvent, save: { edited in
            let event = EKEvent(eventStore: events)
            event.title = edited.title; event.notes = edited.notes; event.calendar = calendar
            event.startDate = edited.start; event.endDate = edited.end
            try events.save(event, span: .thisEvent)
        }) != nil else { throw ActionExecutionInterruption.cancelled }
        return true
    }

    private func createReminder(_ text: String) throws -> Bool {
        guard let calendar = events.defaultCalendarForNewReminders() else {
            throw DraftlyError.message("No Reminders list is available.")
        }
        let reminder = EKReminder(eventStore: events)
        reminder.title = text.components(separatedBy: .newlines).first ?? text
        reminder.notes = text; reminder.calendar = calendar
        try events.save(reminder, commit: true)
        return true
    }

    func requestAccessAsync(reminders: Bool, timeout: TimeInterval = 60) async throws {
        let authorization = EventKitAuthorizationRequest(
            status: { EKEventStore.authorizationStatus(for: $0) },
            request: { reminders, completion in
                if reminders { events.requestFullAccessToReminders(completion: completion) }
                else { events.requestFullAccessToEvents(completion: completion) }
            })
        try await authorization.requireFullAccess(reminders: reminders, timeout: timeout)
    }

    func requestAccess(reminders: Bool) throws {
        let entity: EKEntityType = reminders ? .reminder : .event
        if EKEventStore.authorizationStatus(for: entity) == .fullAccess { return }
        let result = AccessResult()
        if reminders { events.requestFullAccessToReminders { allowed, error in result.complete(allowed, error) } }
        else { events.requestFullAccessToEvents { allowed, error in result.complete(allowed, error) } }
        while !result.finished { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        guard result.allowed else { throw DraftlyError.message(result.error?.localizedDescription ?? "Access was denied. Enable access in System Settings.") }
    }
}

private final class AccessResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: (Bool, Error?)?
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }
    var allowed: Bool { lock.lock(); defer { lock.unlock() }; return result?.0 == true }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return result?.1 }
    func complete(_ allowed: Bool, _ error: Error?) { lock.lock(); result = (allowed, error); lock.unlock() }
}


@MainActor
struct EventKitAuthorizationRequest {
    var status: (EKEntityType) -> EKAuthorizationStatus
    var request: (Bool, @escaping @Sendable (Bool, Error?) -> Void) -> Void

    func requireFullAccess(reminders: Bool, timeout: TimeInterval = 60) async throws {
        try Task.checkCancellation()
        let entity: EKEntityType = reminders ? .reminder : .event
        let current = status(entity)
        if current == .fullAccess { return }
        if current == .denied || current == .restricted { throw denied() }
        let allowed: Bool = try await EventKitCallbackWait.wait(timeout: timeout) { completion in
            request(reminders) { allowed, error in
                if let error { completion(.failure(error)) }
                else { completion(.success(allowed)) }
            }
            return nil
        }
        try Task.checkCancellation()
        guard allowed, status(entity) == .fullAccess else { throw denied() }
    }

    private func denied() -> Error {
        DraftlyError.message("Access was denied. Enable access in System Settings.")
    }
}

@MainActor
final class EventKitCallbackWait<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var cancelRequest: (() -> Void)?

    static func wait(timeout: TimeInterval,
                     start: (@escaping @Sendable (Result<Value, Error>) -> Void) throws -> (() -> Void)?) async throws -> Value {
        guard timeout.isFinite, timeout > 0 else {
            throw DraftlyError.message("The EventKit timeout must be positive and finite.")
        }
        let pending = EventKitCallbackWait()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.continuation = continuation
                guard !Task.isCancelled else {
                    pending.finish(.failure(CancellationError()), cancel: true)
                    return
                }
                do {
                    pending.cancelRequest = try start { result in
                        Task { @MainActor in pending.finish(result) }
                    }
                    pending.timeoutTask = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                        pending.finish(.failure(ActionExecutionInterruption.timeout), cancel: true)
                    }
                } catch { pending.finish(.failure(error), cancel: true) }
            }
        } onCancel: {
            Task { @MainActor in pending.finish(.failure(CancellationError()), cancel: true) }
        }
    }

    private func finish(_ result: Result<Value, Error>, cancel: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        let cancelRequest = cancelRequest
        self.cancelRequest = nil
        if cancel { cancelRequest?() }
        continuation.resume(with: result)
    }
}
