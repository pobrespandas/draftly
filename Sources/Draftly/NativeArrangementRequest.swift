import AppKit
import DraftlyCore

@MainActor enum NativeArrangementRequest {
    typealias Presenter = @MainActor (String) async throws -> String?
    struct Content {
        let alert: NSAlert
        let read: () -> String
    }

    static func prepare(_ text: String) -> Content {
        let controller = ArrangeTextController(text: text)
        let alert = NSAlert()
        alert.messageText = "Arrange lines"
        alert.accessoryView = controller.view
        alert.addButton(withTitle: "Done")
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        return Content(alert: alert, read: { controller.lines.joined(separator: "\n") })
    }

    static func present(_ text: String) async throws -> String? {
        let content = prepare(text)
        let response = try await NativeAlertWait.present(content.alert)
        try Task.checkCancellation()
        return response == .alertFirstButtonReturn ? content.read() : nil
    }

    static func arrange(_ text: String, present: Presenter = NativeArrangementRequest.present) async throws -> String {
        try Task.checkCancellation()
        let result = try await present(text)
        try Task.checkCancellation()
        return result ?? text
    }
}

@MainActor extension NativeActionHost {
    func arrangeTextAsync(_ text: String,
                          present: NativeArrangementRequest.Presenter = NativeArrangementRequest.present) async throws -> String {
        try await NativeArrangementRequest.arrange(text, present: present)
    }
}
