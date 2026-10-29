import Foundation

public enum ActionImporter {
    public static func decode(_ data: Data, source: String? = nil) throws -> [DraftAction] {
        if let native = try? JSONDecoder().decode([DraftAction].self, from: data) { return native }
        if let native = try? JSONDecoder().decode(DraftAction.self, from: data) { return [native] }
        let object = try JSONDecoder().decode(JSONValue.self, from: data)
        let entries: [JSONValue]
        if case .array(let array) = object { entries = array }
        else if case .object(let dictionary) = object {
            if case .array(let array) = dictionary["actions"] { entries = array }
            else { entries = [object] }
        } else { throw DraftlyError.message("This file does not contain an action.") }
        return try entries.map { value in
            let entryData = try JSONEncoder().encode(value)
            if let native = try? JSONDecoder().decode(DraftAction.self, from: entryData) { return native }
            guard let entry = try JSONSerialization.jsonObject(with: entryData) as? [String: Any] else {
                throw DraftlyError.message("The action must contain a name and steps.")
            }
            guard let name = entry["name"] as? String, let rawSteps = entry["steps"] as? [[String: Any]] else {
                throw DraftlyError.message("The action must contain a name and steps.")
            }
            let steps = try rawSteps.map { raw -> ActionStep in
                guard let type = raw["type"] as? String else { throw DraftlyError.message("An action step has no type.") }
                var values: [String: String] = [:]
                let nested = raw["data"] as? [String: Any] ?? raw["parameters"] as? [String: Any] ?? raw["values"] as? [String: Any] ?? [:]
                for (key, value) in raw.merging(nested, uniquingKeysWith: { _, new in new }) where key != "type" {
                    if let text = value as? String { values[key] = text }
                    else if JSONSerialization.isValidJSONObject(value), let json = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) { values[key] = String(data: json, encoding: .utf8) }
                    else { values[key] = String(describing: value) }
                }
                if type == "includeAction", nested["uuid"] == nil {
                    values.removeValue(forKey: "uuid")
                }
                var step = ActionStep(type, values)
                step.isEnabled = raw["isEnabled"] as? Bool
                if let value = raw["uuid"] as? String, let id = UUID(uuidString: value) { step.id = id }
                return step
            }
            var action = DraftAction(name: name, steps: steps)
            action.group = entry["group"] as? String ?? "Imported"
            if entry["backingIsSeparator"] as? Bool == true { action.scriptMetadata = ["isSeparator": "true"] }
            if let command = entry["keyCommand"] as? [String: Any] {
                action.shortcut = command["input"] as? String ?? ""
                action.shortcutModifiers = ["command", "option", "shift", "control"].filter { command[$0 + "Key"] as? Bool == true }
            }
            if let icon = entry["icon"] as? String, icon.hasPrefix("symbol||") { action.symbol = String(icon.dropFirst(8)) }
            if let uuid = entry["uuid"] as? String, let id = UUID(uuidString: uuid) { action.id = id }
            let disposition = entry["disposition"] as? Int ?? 3
            let success = entry["afterSuccess"] as? String ?? (disposition == 1 ? "archive" : disposition == 2 ? "trash" : "none")
            action.afterSuccess = success.lowercased()
            var presentation = ActionPresentation()
            presentation.description = entry["actionDescription"] as? String ?? ""
            presentation.tintColor = entry["tintColor"] as? String
            presentation.barLabel = entry["shortName"] as? String
            presentation.barUsesIcon = entry["keyUseIcon"] as? Bool
            presentation.confirmBeforeRun = entry["shouldConfirm"] as? Bool ?? false
            if let notification = entry["notificationType"] as? Int {
                presentation.notifyOnSuccess = notification == 2
                presentation.notifyOnError = notification == 1 || notification == 2
            }
            presentation.logLevel = entry["logLevel"] as? Int
            presentation.addTags = TagRules.normalize(entry["assignTags"] as? [String] ?? [])
            action.options = presentation
            action.sourceURL = source
            action.rawPayload = String(data: try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]), encoding: .utf8)
            for step in steps where step.type == "configurationKey" {
                let field = ActionConfigurationField(step)
                action.configuredValues[field.key] = field.textValue(configuredValues: [:])
            }
            return action
        }
    }

    public static func download(_ url: URL) async throws -> [DraftAction] {
        try await download(url, depth: 0)
    }

    public static func installationActions(_ url: URL) throws -> [DraftAction] {
        try decode(installationData(url))
    }

    public static func installationData(_ url: URL) throws -> Data {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let encoded = query?.first(where: { $0.name == "data" })?.value else {
            throw DraftlyError.message("This installation link has no action data.")
        }
        // URL can add one encoding layer when a directory link contains raw brackets.
        for candidate in [encoded, encoded.removingPercentEncoding ?? encoded] {
            for data in [candidate.data(using: .utf8), Data(base64Encoded: candidate)].compactMap({ $0 }) {
                guard let actions = try? decode(data) else { continue }
                return try normalizedInstallationData(data, actions: actions)
            }
        }
        throw DraftlyError.message("The installation link contains invalid action data.")
    }

    private static func normalizedInstallationData(_ data: Data, actions: [DraftAction]) throws -> Data {
        if let backup = try? JSONDecoder().decode(Backup.self, from: data) {
            guard backup.version == 1 else { throw DraftlyError.message("This installation version is not supported.") }
            return try JSONEncoder().encode(Backup(notes: [], revisions: [], workspaces: [],
                actions: actions, actionGroups: backup.actionGroups))
        }
        if case .object(let object) = try? JSONDecoder().decode(JSONValue.self, from: data),
           case .array = object["actions"], object["uuid"] != nil, object["steps"] == nil {
            let (group, groupActions) = try DraftsActionGroupImport.decodeJSON(data)
            return try JSONEncoder().encode(Backup(notes: [], revisions: [], workspaces: [],
                actions: groupActions, actionGroups: [group]))
        }
        return data
    }

    @_spi(DraftlyInternal) public static func directoryInstallationData(_ url: URL) async throws -> Data {
        try await directoryInstallationData(url) { try await URLSession.shared.data(from: $0) }
    }

    static func directoryInstallationData(_ url: URL,
        transport: @escaping @Sendable (URL) async throws -> (Data, URLResponse)) async throws -> Data {
        func load(_ url: URL, depth: Int) async throws -> Data {
            guard depth < 5 else { throw DraftlyError.message("The directory link redirects too many times.") }
            if ["draftly", "drafts", "drafts5"].contains(url.scheme?.lowercased() ?? ""),
               ["action", "actiongroup"].contains(url.host?.lowercased() ?? "") {
                return try installationData(url)
            }
            guard url.scheme == "https", ["actions.getdrafts.com", "directory.getdrafts.com", "config.getdrafts.com"].contains(url.host ?? "") else {
                throw DraftlyError.message("Use an HTTPS Drafts Directory link or import an action file.")
            }
            let (data, response) = try await transport(url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DraftlyError.message("The action could not be downloaded.") }
            let installation: Data
            if let actions = try? decode(data) {
                installation = try normalizedInstallationData(data, actions: actions)
            } else {
                guard let html = String(data: data, encoding: .utf8) else { throw DraftlyError.message("The directory returned an invalid page.") }
                let expression = try NSRegularExpression(pattern: "(?:href|data-install-url)=[\"']([^\"']*(?:drafts5?://|config.getdrafts.com)[^\"']+)[\"']")
                guard let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                      let range = Range(match.range(at: 1), in: html),
                      let target = URL(string: String(html[range]).replacingOccurrences(of: "&amp;", with: "&")), target != url else {
                    throw DraftlyError.message("No installation data was found. Export the action from Drafts and import the file.")
                }
                installation = try await load(target, depth: depth + 1)
            }
            if var backup = try? JSONDecoder().decode(Backup.self, from: installation) {
                var actions = backup.actions
                for index in actions.indices { actions[index].sourceURL = url.absoluteString }
                backup.actions = actions
                return try JSONEncoder().encode(backup)
            }
            return try JSONEncoder().encode(decode(installation, source: url.absoluteString))
        }
        return try await load(url, depth: 0)
    }

    private static func download(_ url: URL, depth: Int) async throws -> [DraftAction] {
        guard depth < 5 else { throw DraftlyError.message("The directory link redirects too many times.") }
        if ["drafts", "drafts5"].contains(url.scheme?.lowercased() ?? ""),
           ["action", "actiongroup"].contains(url.host?.lowercased() ?? "") {
            return try installationActions(url)
        }
        guard url.scheme == "https", ["actions.getdrafts.com", "directory.getdrafts.com", "config.getdrafts.com"].contains(url.host ?? "") else {
            throw DraftlyError.message("Use an HTTPS Drafts Directory link or import an action file.")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DraftlyError.message("The action could not be downloaded.") }
        if let decoded = try? decode(data, source: url.absoluteString) { return decoded }
        guard let html = String(data: data, encoding: .utf8) else { throw DraftlyError.message("The directory returned an invalid page.") }
        let pattern = "(?:href|data-install-url)=[\"']([^\"']*(?:drafts5?://|config.getdrafts.com)[^\"']+)[\"']"
        let regex = try NSRegularExpression(pattern: pattern)
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let link = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            if let target = URL(string: link), target != url, ["drafts", "drafts5"].contains(target.scheme ?? "") || target.host == "config.getdrafts.com" {
                var actions = try await download(target, depth: depth + 1)
                for index in actions.indices { actions[index].sourceURL = url.absoluteString }
                return actions
            }
        }
        throw DraftlyError.message("No installation data was found. Export the action from Drafts and import the file.")
    }

    public static func importNotes(_ data: Data) throws -> [Note] {
        let object = try JSONSerialization.jsonObject(with: data)
        let entries = (object as? [[String: Any]]) ?? (object as? [String: Any])?["drafts"] as? [[String: Any]] ?? []
        guard !entries.isEmpty else { throw DraftlyError.message("No drafts were found in this JSON file.") }
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: Any?) -> Date? { guard let text = value as? String else { return nil }; return fractional.date(from: text) ?? formatter.date(from: text) }
        return try entries.map { entry in
            guard let content = entry["content"] as? String else { throw DraftlyError.message("A draft has no content.") }
            var note = Note(content: content, tags: entry["tags"] as? [String] ?? [])
            note.id = (entry["uuid"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            note.isArchived = entry["isArchived"] as? Bool ?? false
            note.flag = entry["flag"] as? Int ?? (entry["isFlagged"] as? Bool == true ? 1 : 0)
            note.syntax = entry["syntax"] as? String ?? "Markdown"
            note.trashedAt = date(entry["trashedAt"])
            if let parsed = date(entry["createdAt"]) { note.createdAt = parsed }
            if let parsed = date(entry["modifiedAt"]) { note.modifiedAt = parsed }
            return note
        }
    }
}
