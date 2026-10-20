import AppKit
import DraftlyCore

@MainActor extension NativePromptAdapter {
    func performAsync(_ operation: String, values: [String: Any],
                      present: @MainActor (NSAlert) async throws -> NSApplication.ModalResponse = { try await NativeAlertWait.present($0) }) async throws -> Any? {
        try Task.checkCancellation()
        switch operation {
        case "confirmAction":
            let alert = NSAlert(); alert.messageText = "Run " + (values["name"] as? String ?? "Action") + "?"
            alert.addButton(withTitle: "Run"); alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            let response = try await present(alert)
            try Task.checkCancellation()
            return response == .alertFirstButtonReturn
        case "alert":
            let alert = NSAlert(); alert.messageText = values["message"] as? String ?? "Draftly"
            alert.addButton(withTitle: "OK")
            _ = try await present(alert)
            try Task.checkCancellation()
            return true
        case "prompt":
            let content = try preparePrompt(values)
            defer { withExtendedLifetime(content.retained) {} }
            while true {
                let response = try await present(content.alert)
                try Task.checkCancellation()
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                guard (0..<content.buttonCount).contains(index) else { return nil }
                content.alert.window.makeFirstResponder(nil)
                if let fields = content.read() { return ["index": index, "fields": fields] }
                let error = NSAlert(); error.messageText = "Enter a valid number."; error.addButton(withTitle: "OK")
                _ = try await present(error)
                try Task.checkCancellation()
            }
        case "selectPrompt":
            guard let content = prepareSelection(values) else { return nil }
            let response = try await present(content.alert)
            try Task.checkCancellation()
            guard response == .alertFirstButtonReturn else { return nil }
            guard let index = content.choices.selectedIndex else { return nil }
            return ["index": index]
        default: throw DraftlyError.message("The native operation is unavailable.")
        }
    }
}

@MainActor final class NativeAlertWait: NSObject, NSWindowDelegate {
    private let alert: NSAlert
    private var continuation: CheckedContinuation<NSApplication.ModalResponse, Error>?
    private init(_ alert: NSAlert) { self.alert = alert }

    static func present(_ alert: NSAlert) async throws -> NSApplication.ModalResponse {
        try await NativeAlertWait(alert).show()
    }

    private func show() async throws -> NSApplication.ModalResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError())); return }
                alert.layout()
                for (index, button) in alert.buttons.enumerated() {
                    button.tag = index
                    button.target = self
                    button.action = #selector(choose(_:))
                }
                alert.window.isReleasedWhenClosed = false
                alert.window.delegate = self
                alert.window.center()
                alert.window.makeKeyAndOrderFront(nil)
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    @objc private func choose(_ sender: NSButton) {
        finish(.success(NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + sender.tag)))
    }
    func windowWillClose(_ notification: Notification) { finish(.success(.cancel)) }
    private func finish(_ result: Result<NSApplication.ModalResponse, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        alert.window.delegate = nil
        alert.window.close()
        continuation.resume(with: result)
    }
}
