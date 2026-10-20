import Foundation

@MainActor extension ActionRunner {
    func platformAsync(_ operation: String, payload: String) async throws -> String {
        try checkCancellation()
        guard host != nil else { throw DraftlyError.message("The operation \(operation) is unavailable.") }
        let timeout = hostOperationTimeout
        guard timeout.isFinite, timeout > 0 else { throw DraftlyError.message("The host operation timeout must be positive and finite.") }
        let wait = NativeOperationWait(timeout: timeout, now: hostOperationNow)
        cancelNativeOperation = { wait.finish(.failure(ActionExecutionInterruption.cancelled)) }
        defer { cancelNativeOperation = nil }
        do {
            let response: String = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    wait.continuation = continuation
                    guard !Task.isCancelled else { wait.finish(.failure(CancellationError())); return }
                    wait.operation = Task { @MainActor [weak self] in
                        do {
                            guard let host = self?.host else { throw DraftlyError.message("The operation \(operation) is unavailable.") }
                            guard wait.now() < wait.deadline else { throw ActionExecutionInterruption.timeout }
                            let value = try await host.performAsync(operation, payload: payload)
                            wait.finish(.success(value))
                        } catch { wait.finish(.failure(error)) }
                    }
                    wait.timeout = Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(max(0, wait.deadline.timeIntervalSince(wait.now())))) } catch { return }
                        wait.finish(.failure(ActionExecutionInterruption.timeout))
                    }
                }
            } onCancel: {
                Task { @MainActor in wait.finish(.failure(CancellationError())) }
            }
            await wait.cleanup()
            try checkCancellation()
            try Task.checkCancellation()
            return response
        } catch {
            await wait.cleanup()
            throw error
        }
    }

    func nativeValue(_ operation: String, _ values: [String: Any]) async throws -> Any? {
        let response = try await platformAsync(operation, payload: json(values))
        guard let envelope = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any] else {
            throw DraftlyError.message("The native operation returned an invalid response.")
        }
        if let error = envelope["error"] as? String { throw DraftlyError.message(error) }
        return envelope["value"] is NSNull ? nil : envelope["value"]
    }

    func performSuspendingStep(_ step: ActionStep, text: String, rendered: String, current: Note,
                               evaluate: (String) -> Void) async throws -> Bool? {
        switch step.type {
        case "share":
            return try await nativeValue("share", ["text": rendered]) as? Bool != false
        case "openIn":
            let name = try renderTemplate(step.values["name"] ?? "[[safe_title]].txt", note: current)
            return try await nativeValue("shareFile", ["text": rendered, "name": name]) as? Bool != false
        case "print":
            return try await nativeValue("print", step.values.merging(["text": rendered]) { _, new in new }) as? Bool != false
        case "prompt":
            let prompt = try ActionPromptStep(step) { try renderTemplate($0, note: current) }
            guard let tags = try prompt.tags(from: await nativeValue("prompt", prompt.values)) else { return false }
            customTags.merge(tags) { _, new in new }
            return true
        case "file", "export":
            let file = try ActionFileStep(step, text: rendered) { try renderTemplate($0, note: current) }
            _ = try await nativeValue("saveFile", file.values)
            return true
        case "mail", "message":
            let message = try ActionMessageStep(step, text: rendered) { try renderTemplate($0, note: current) }
            return try message.accepted(await nativeValue(message.operation, message.values))
        case "htmlpreview":
            let html = rendered.range(of: "<[^>]+>", options: .regularExpression) == nil ? MarkdownRenderer.page(try MarkdownPreferences.render(rendered, defaults: markdownDefaults)) : rendered
            let result = try await nativeValue("htmlPreview", ["html": html, "hideInterface": step.values["hideInterface"] == "true"])
            if result as? Bool == false || (result as? [String: Any])?["success"] as? Bool == false { return false }
            if let fields = (result as? [String: Any])?["values"] as? [String: Any] { evaluate("context.previewValues = \(try json(fields));") }
            return true
        case "runAppleScript":
            let result = try await nativeValue("appleScript", ["source": step.values["script"] ?? step.values["source"] ?? "", "subroutine": "execute", "arguments": [noteValue(current)]])
            evaluate("context.appleScriptResponses.push(\(try json(result ?? NSNull())));")
            return true
        case "speak":
            let value = try await nativeValue("speak", ["text": rendered, "settings": ["autoStart": step.values["autoStart"] != "false", "autoClose": step.values["autoClose"] != "false"]])
            return value as? Bool != false
        case "reminder", "event":
            _ = try await nativeValue(step.type, ["text": rendered])
            return true
        case "listInReminders":
            let name = try renderTemplate(step.values["list"] ?? step.values["listTemplate"] ?? "Reminders", note: current)
            guard let list = try await nativeValue("eventAPI", ["entity": "list", "operation": "findOrCreate", "title": name]) as? [String: Any] else {
                throw DraftlyError.message("The Reminders list was not found.")
            }
            for line in rendered.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                try checkCancellation()
                _ = try await nativeValue("eventAPI", ["entity": "reminder", "operation": "update", "value": ["title": line, "list": list]])
            }
            return true
        case "callbackUrl":
            let url = try renderURL(step.values["url"] ?? text, note: current, encodeTags: step.values["encodeTags"] != "false")
            let response = try await nativeValue("callbackURL", ["url": url, "waitForResponse": step.values["waitForResponse"] != "false"]) as? [String: Any] ?? [:]
            let status = response["status"] as? String ?? "error"
            if status == "cancelled" { return false }
            if status == "timeout" { throw ActionExecutionInterruption.timeout }
            guard status == "success" else { throw DraftlyError.message("The callback URL returned \(status).") }
            let parameters = response["parameters"] as? [String: String] ?? [:]
            for (key, value) in parameters { customTags["callback_" + key] = value }
            evaluate("context.callbackResponses.push(\(try json(parameters)));")
            return true
        case "runShortcut":
            let result = try await nativeValue("shortcut", ["name": step.values["name"] ?? "", "text": rendered])
            if let result {
                customTags["shortcut_result"] = String(describing: result)
                if step.values["waitForResponse"] != "false" {
                    evaluate("context.callbackResponses.push(\(try json(["result": result])));")
                }
            }
            return true
        default: return nil
        }
    }
}

@MainActor private final class NativeOperationWait {
    var continuation: CheckedContinuation<String, Error>?
    var operation: Task<Void, Never>?
    var timeout: Task<Void, Never>?
    let deadline: Date
    let now: () -> Date
    init(timeout: TimeInterval, now: @escaping () -> Date) {
        self.now = now
        deadline = now().addingTimeInterval(timeout)
    }

    // Keep the library reserved until the host finishes cancellation cleanup.
    func cleanup() async {
        let task = operation
        operation = nil
        await task?.value
    }

    func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        operation?.cancel()
        timeout?.cancel(); timeout = nil
        continuation.resume(with: now() >= deadline ? .failure(ActionExecutionInterruption.timeout) : result)
    }
}
