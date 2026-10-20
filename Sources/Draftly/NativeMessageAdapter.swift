import AppKit
import DraftlyCore

@MainActor
struct NativeMessageAdapter {
    func compose(_ operation: String, _ values: [String: Any]) throws -> [String: String] {
        guard values["isBodyHTML"] as? Bool != true else { throw DraftlyError.message("HTML mail composition is unavailable on macOS.") }
        guard let service = NSSharingService(named: operation == "composeMail" ? .composeEmail : .composeMessage) else { throw DraftlyError.message("The system composition service is unavailable.") }
        service.recipients = values["toRecipients"] as? [String] ?? []; service.subject = values["subject"] as? String ?? ""
        if !(values["ccRecipients"] as? [String] ?? []).isEmpty || !(values["bccRecipients"] as? [String] ?? []).isEmpty { throw DraftlyError.message("The macOS composition service does not accept CC or BCC recipients. Use a mailto URL.") }
        let result = ScriptSharingResult(); service.delegate = result
        service.perform(withItems: [values["body"] as? String ?? ""])
        let deadline = Date().addingTimeInterval(120)
        while result.status == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        return ["status": result.status ?? "timeout"]
    }
}

@MainActor private final class ScriptSharingResult: NSObject, NSSharingServiceDelegate {
    var status: String?
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { status = "sent" }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) { status = "error" }
}
