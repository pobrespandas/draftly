import Foundation

struct ActionMessageStep {
    let operation: String
    let values: [String: Any]
    init(_ step: ActionStep, text: String, render: (String) throws -> String) throws {
        operation = step.type == "mail" ? "composeMail" : "composeMessage"
        var values: [String: Any] = ["subject": try render(step.values["subject"] ?? ""), "body": text]
        for key in ["toRecipients", "ccRecipients", "bccRecipients", "replyToRecipients"] {
            values[key] = try render(step.values[key] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        values["isBodyHTML"] = step.values["isBodyHTML"] == "true"
        values["sendInBackground"] = step.values["sendInBackground"] == "true"
        self.values = values
    }

    func accepted(_ result: Any?) throws -> Bool {
        let response = result as? [String: String] ?? [:]
        if response["status"] == "userCancelled" { return false }
        guard response["status"] == "sent" else { throw DraftlyError.message("Message composition failed: \(response["status"] ?? "unknownError")") }
        return true
    }
}
