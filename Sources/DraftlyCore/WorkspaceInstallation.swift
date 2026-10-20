import Foundation

public enum WorkspaceInstallation {
    public static func decode(_ url: URL) throws -> Workspace {
        guard url.scheme == "draftly", url.host == "workspace",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              items.filter({ $0.name == "data" }).count == 1,
              let text = items.first(where: { $0.name == "data" })?.value,
              let values = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              values["name"] is String else {
            throw DraftlyError.message("The workspace link is invalid.")
        }
        if let identity = values["uuid"],
           (identity as? String).flatMap(UUID.init(uuidString:)) == nil {
            throw DraftlyError.message("The workspace ID is invalid.")
        }
        return try APIValues.workspace(values)
    }
}
