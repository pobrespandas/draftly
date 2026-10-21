import Foundation
import DraftlyCore

enum ActionGroupReferenceResolver {
    static func resolve(_ reference: [String: Any], names: [String], groups: [ActionGroupRecord],
                        errorMessage: String = "The action group was not found.") throws -> [String: Any] {
        let name: String?
        if let rawID = reference["uuid"] {
            guard let text = rawID as? String, let id = UUID(uuidString: text) else {
                throw DraftlyError.message(errorMessage)
            }
            let identifiers = ActionGroupIdentity.identifiers(names: names, records: groups)
            name = names.first { identifiers[$0] == id }
        } else {
            name = (reference["name"] as? String).flatMap { names.contains($0) ? $0 : nil }
        }
        guard let name else { throw DraftlyError.message(errorMessage) }
        var reference = reference
        reference["name"] = name
        return reference
    }
}
