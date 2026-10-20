import Foundation
import IOKit.ps

public enum APIValues {
    public static func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
    public static func parseDate(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    public static func workspace(_ values: [String: Any]) throws -> Workspace {
        let sorts = values["_sorts"] as? [String: [String: Any]] ?? [:]
        for value in sorts.values {
            if let name = value["sort"] as? String, !["name", "modified", "created", "accessed"].contains(name) { throw DraftlyError.message("The workspace sort is invalid.") }
        }
        if let name = values["loadFolder"] as? String, NoteFolder(rawValue: name) == nil { throw DraftlyError.message("The workspace folder is invalid.") }
        if let status = values["flaggedStatus"] as? String, !["any", "flagged", "unflagged"].contains(status) { throw DraftlyError.message("The flagged status is invalid.") }
        for key in ["startDate", "endDate"] {
            guard let value = values[key] as? [String: Any] else { continue }
            if let field = value["field"] as? String, !["created", "modified", "accessed"].contains(field) { throw DraftlyError.message("The query date field is invalid.") }
            if let type = value["type"] as? String {
                guard ["none", "relative", "absolute"].contains(type) else { throw DraftlyError.message("The query date type is invalid.") }
                if type == "absolute" && APIValues.parseDate(value["date"]) == nil { throw DraftlyError.message("The absolute query date is invalid.") }
            }
        }
        var workspace = Workspace(name: values["name"] as? String ?? "Script")
        if let id = (values["uuid"] as? String).flatMap(UUID.init(uuidString:)) { workspace.id = id }
        workspace.query = values["queryString"] as? String ?? ""
        if let error = DraftQuery(workspace.query).error { throw DraftlyError.message(error) }
        let tags = (values["tagFilter"] as? String ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        workspace.tags = TagRules.normalize(tags.filter { !$0.hasPrefix("!") })
        workspace.excludedTags = TagRules.normalize(tags.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) })
        workspace.matchAnyTag = !(values["tagFilterRequireAll"] as? Bool ?? true)
        workspace.folder = NoteFolder(rawValue: values["loadFolder"] as? String ?? "inbox") ?? .inbox
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)]
        var options = DraftListOptions()
        options.showDate = values["showDate"] as? Bool ?? true
        options.showPreview = values["showPreview"] as? Bool ?? true
        options.showTags = values["showTags"] as? Bool ?? true
        options.showLastAction = values["showLastAction"] as? Bool ?? false
        options.previewSearchMatches = values["showSearchPreview"] as? Bool ?? true
        workspace.listOptions = options
        if let (sort, ascending, _) = workspace.scriptSort(for: workspace.folder) { workspace.sort = sort; workspace.ascending = ascending }
        return workspace
    }

}

@MainActor extension ActionRunner {
    func actionValue(_ action: DraftAction) -> [String: Any] {
        ["uuid": action.id.uuidString, "name": action.name, "configuredValues": action.configuredValues,
         "isSeparator": action.isSeparator]
    }
    func workspaceValue(_ workspace: Workspace) -> [String: Any] {
        var result: [String: Any] = [:]
        if let text = workspace.scriptMetadata?["api"], let data = text.data(using: .utf8) {
            result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        result["uuid"] = workspace.id.uuidString; result["name"] = workspace.name; result["queryString"] = workspace.query
        result["tagFilter"] = (workspace.tags + (workspace.excludedTags ?? []).map { "!" + $0 }).joined(separator: ",")
        result["tagFilterRequireAll"] = !(workspace.matchAnyTag ?? false)
        result["loadFolder"] = workspace.folder.rawValue
        let options = workspace.listOptions ?? DraftListOptions()
        result["showDate"] = options.showDate; result["showPreview"] = options.showPreview
        result["showTags"] = options.showTags; result["showLastAction"] = options.showLastAction
        result["showSearchPreview"] = options.previewSearchMatches
        var sorts = result["_sorts"] as? [String: [String: Any]] ?? [:]
        var sort = sorts[workspace.folder.rawValue] ?? [:]
        sort["sort"] = workspace.sort == .title ? "name" : workspace.sort.rawValue
        sort["descending"] = !workspace.ascending
        sorts[workspace.folder.rawValue] = sort; result["_sorts"] = sorts
        return result
    }
    func decodeWorkspace(_ values: [String: Any]) throws -> Workspace {
        try APIValues.workspace(values)
    }
    func queryWorkspace(_ values: [String: Any]) throws -> [Note] {
        let details = values["workspace"] as? [String: Any] ?? [:]
        var workspace = try decodeWorkspace(details)
        guard let folder = NoteFolder(rawValue: values["folder"] as? String ?? "all") else { throw DraftlyError.message("The workspace query folder is invalid.") }
        workspace.folder = folder
        if let (sort, ascending, _) = workspace.scriptSort(for: workspace.folder) {
            workspace.sort = sort; workspace.ascending = ascending
        }
        let notes = workspace.filter(library.notes)
        return notes
    }
    func dispatchAPI(_ operation: String, values: [String: Any]) throws -> Any? {
        switch operation {
        case "successParameter":
            guard let name = values["name"] as? String, let value = values["value"] as? String else {
                throw DraftlyError.message("Success parameters must be strings.")
            }
            successParameters[name] = value
            return nil
        case "newUUID": return UUID().uuidString
        case "editorNoteID": return editor.noteID?.uuidString
        case "saveEditor": try flushEditor(); return true
        case "newEditor":
            try flushEditor(); let note = Note(accessedAt: Date())
            try library.saveNote(note, preserveRevision: false, preserveDates: true)
            editor.load(note); editor.synchronizeScriptEdit?(); return true
        case "recentDrafts": return editor.recentNoteIDs.compactMap { id in library.notes.first { $0.id == id && $0.trashedAt == nil } }.map(noteValue)
        case "selectedDrafts": return (selectedDrafts?() ?? library.notes.filter { $0.id == editor.noteID }).map(noteValue)
        case "ui": if let uiOperation { return try uiOperation(values) }; return try platform("ui", values)
        case "defaultWorkspace": return workspaceValue(defaultWorkspace?() ?? Workspace(name: ""))
        case "currentWorkspace": return workspaceValue(currentWorkspace?() ?? Workspace(name: "Current"))
        case "queryWorkspace": return try queryWorkspace(values).map(noteValue)
        case "workspaces": return library.workspaces.map(workspaceValue)
        case "updateWorkspace": let workspace = try decodeWorkspace(values); try library.saveWorkspace(workspace); return workspaceValue(workspace)
        case "tags":
            let query = TagRules.normalize(values["query"] as? String ?? "")
            return Array(Set(library.notes.flatMap(\.tags))).sorted().filter { query.isEmpty || $0.localizedStandardContains(query) }
        case "recentTags":
            var tags: [String] = []
            for note in library.notes.sorted(by: { $0.modifiedAt > $1.modifiedAt }) {
                for tag in note.tags where !tags.contains(tag) { tags.append(tag) }
            }
            return tags
        case "renameTag":
            return try library.changeTag(values["oldTag"] as? String ?? "", to: values["newTag"] as? String ?? "")
        case "versions":
            return library.revisions.filter { $0.noteID.uuidString == values["uuid"] as? String }.map { ["uuid": $0.id.uuidString, "draftUUID": $0.noteID.uuidString, "content": $0.content, "createdAt": APIValues.date($0.date)] }
        case "saveVersion":
            guard let id = (values["uuid"] as? String).flatMap(UUID.init(uuidString:)) else { throw DraftlyError.message("The draft ID is invalid.") }
            try library.saveRevision(Revision(noteID: id, content: values["content"] as? String ?? "")); return true
        case "deleteVersion":
            guard let id = (values["uuid"] as? String).flatMap(UUID.init(uuidString:)) else { return false }
            try library.deleteRevision(id); return true
        case "actionLogs":
            return library.runs.filter { $0.noteID?.uuidString == values["uuid"] as? String }.map {
                ["uuid": $0.id.uuidString, "draftUUID": $0.noteID?.uuidString ?? "", "actionName": $0.actionName,
                 "executedAt": APIValues.date($0.date), "executedDevice": "Mac", "executedLatitude": 0, "executedLongitude": 0,
                 "log": $0.message, "status": ["success": "completed", "error": "failed"][$0.status.lowercased()] ?? $0.status.lowercased()] as [String: Any]
            }
        case "actionForLog":
            guard let run = library.runs.first(where: { $0.id.uuidString == values["uuid"] as? String }) else { return nil }
            return library.actions.first(where: { run.actionID == $0.id || run.actionID == nil && run.actionName == $0.name }).map(actionValue)
        case "deleteLog":
            guard let id = (values["uuid"] as? String).flatMap(UUID.init(uuidString:)) else { return false }
            try library.deleteRun(id); return true
        case "recentActions":
            var seen: Set<UUID> = []
            return library.runs.compactMap { run -> DraftAction? in
                guard let action = library.actions.first(where: { $0.id == run.actionID || run.actionID == nil && $0.name == run.actionName }), seen.insert(action.id).inserted else { return nil }
                return action
            }.map(actionValue)
        case "actionGroups":
            return library.groupNames.map { ["name": $0, "uuid": stableGroupID($0)] }
        case "groupActions": return library.orderedActions().filter { $0.group == values["name"] as? String }.map(actionValue)
        case "actionInstallURL":
            guard let action = library.actions.first(where: { $0.id.uuidString == values["uuid"] as? String }) else { return nil }
            return try installURL(action)
        case "groupInstallURL": return try installURL(library.orderedActions().filter { $0.group == values["name"] as? String })
        case "syntaxes": return ScriptSyntax.names.map { ["name": $0, "type": "builtIn"] } + library.syntaxes.map { ["name": $0.name, "type": $0.type] }
        case "syntaxInstallURL":
            let name = values["name"] as? String ?? ""
            var components = URLComponents(); components.scheme = "draftly"; components.host = "syntax"
            if let definition = library.syntaxes.first(where: { $0.name == name && $0.type == values["type"] as? String }) {
                components.queryItems = [URLQueryItem(name: "data", value: try library.syntaxDefinition(named: definition.name).source)]
            } else if ScriptSyntax.names.contains(name) { components.queryItems = [URLQueryItem(name: "name", value: name)] }
            else { throw DraftlyError.message("The syntax is not installed.") }
            return components.string
        case "syntaxAnalysis":
            let syntax = try library.syntaxDefinition(named: values["syntax"] as? String ?? "Markdown")
            let text = values["text"] as? String ?? ""
            return ["tasks": syntax.tasks(in: text), "markers": syntax.markers(in: text), "links": syntax.links(in: text)]
        case "syntaxTaskChange":
            let syntax = try library.syntaxDefinition(named: values["syntax"] as? String ?? "Markdown")
            do {
                let change = try syntax.taskChange(in: values["text"] as? String ?? "", task: values["task"] as? [String: Any] ?? [:], operation: values["operation"] as? String ?? "")
                return ["range": [change.0.location, change.0.length], "text": change.1]
            } catch SyntaxTaskError.invalidSnapshot { return ["changed": false] }
        case "themes":
            if let uiOperation { return try uiOperation(["operation": "themes"]) }
            return ["Default", "Dark", "Light"].map { ["name": $0, "type": "builtIn"] }
        case "device": return ["systemName": "macOS", "model": "Mac", "systemVersion": ProcessInfo.processInfo.operatingSystemVersionString] as [String: Any]
        case "batteryLevel": return try ScriptDevice.batteryLevel()
        case "detectURLs":
            let text = values["text"] as? String ?? ""
            return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue).matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { $0.url?.absoluteString }
        case "parseURL", "buildURL": return try ScriptUtilities.url(operation, values)
        case "formatDate":
            let date = APIValues.parseDate(values["date"]) ?? Date(), format = values["format"] as? String ?? "%Y-%m-%d"
            return Templates.render("[[date|\(format)]]", note: Note(), now: date)
        case "adjustDate": return APIValues.date(try ScriptUtilities.adjustDate(values))
        case "xmlrpc":
            let body = try ScriptXMLRPC.requestBody(method: values["methodName"] as? String ?? "", params: values["params"] as? [Any] ?? [])
            let response = ScriptHTTP.request(["url": values["url"] ?? "", "method": "POST", "headers": ["Content-Type": "text/xml; charset=utf-8"], "encoding": "raw", "data": body])
            if response["success"] as? Bool != true { return ["success": false, "statusCode": response["statusCode"] ?? 0, "params": [], "error": response["error"] ?? "The XML-RPC HTTP request failed."] }
            return ScriptXMLRPC.response(Data((response["responseText"] as? String ?? "").utf8), statusCode: response["statusCode"] as? Int ?? 0)
        case "http": return ScriptHTTP.request(values)
        case "mustache": return try MustacheRenderer.render(values["template"] as? String ?? "", data: values["data"] ?? [:], escape: values["contentType"] as? String != "text", partials: values["partials"] as? [String: String] ?? [:])
        case "renderMarkdown":
            return try ScriptMarkdown.render(values["text"] as? String ?? "", engine: values["engine"] as? String ?? "multi", options: values["options"] as? [String: Any] ?? [:])
        case "autocomplete":
            let key = "script.autocomplete", operation = values["operation"] as? String ?? "get"
            var entries = UserDefaults.standard.stringArray(forKey: key) ?? []
            if let value = values["value"] as? String {
                if operation == "add", !entries.contains(value) { entries.append(value) }
                if operation == "remove" { entries.removeAll { $0 == value } }
                UserDefaults.standard.set(entries, forKey: key)
            }
            return operation == "get" ? entries as Any : true
        default: return try platform(operation, values)
        }
    }
    private func installURL<T: Encodable>(_ value: T) throws -> String {
        let text = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        var components = URLComponents(); components.scheme = "draftly"; components.host = "action"; components.queryItems = [URLQueryItem(name: "data", value: text)]
        return components.string!
    }
    private func stableGroupID(_ name: String) -> String {
        (library.actionGroups.first(where: { $0.name == name })?.id ?? ActionGroupRecord.identifier(for: name)).uuidString
    }
}

enum ScriptUtilities {
    static func url(_ operation: String, _ values: [String: Any]) throws -> Any {
        let base = (values["base"] as? String).flatMap(URL.init(string:))
        guard let url = URL(string: values["url"] as? String ?? "", relativeTo: base)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true), components.scheme != nil else { throw DraftlyError.message("The URL is invalid.") }
        if operation == "buildURL" {
            let parameters = values["parameters"] as? [String: Any] ?? [:]
            components.queryItems = (components.queryItems ?? []) + parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
            return components.string!
        }
        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] { parameters[item.name] = item.value ?? "" }
        return ["href": url.absoluteString, "protocol": (components.scheme ?? "") + ":", "host": (components.host ?? "") + (components.port.map { ":\($0)" } ?? ""),
                "hostname": components.host ?? "", "port": components.port.map(String.init) ?? "", "pathname": components.path, "search": components.percentEncodedQuery.map { "?" + $0 } ?? "",
                "hash": components.fragment.map { "#" + $0 } ?? "", "searchParams": parameters, "username": components.user ?? "", "password": components.password ?? ""] as [String: Any]
    }
    static func adjustDate(_ values: [String: Any]) throws -> Date {
        var date = APIValues.parseDate(values["date"]) ?? Date()
        let input = values["adjustment"] as? String ?? ""
        let regex = try NSRegularExpression(pattern: "([+-]?\\d+)\\s*(years?|months?|weeks?|days?|hours?|minutes?|seconds?)", options: .caseInsensitive)
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        guard !matches.isEmpty else { throw DraftlyError.message("The date adjustment is invalid.") }
        for match in matches {
            let source = input as NSString, count = Int(source.substring(with: match.range(at: 1))) ?? 0, unit = source.substring(with: match.range(at: 2)).lowercased()
            let component: Calendar.Component = unit.hasPrefix("year") ? .year : unit.hasPrefix("month") ? .month : unit.hasPrefix("week") ? .weekOfYear : unit.hasPrefix("day") ? .day : unit.hasPrefix("hour") ? .hour : unit.hasPrefix("minute") ? .minute : .second
            date = Calendar.current.date(byAdding: component, value: count, to: date) ?? date
        }
        return date
    }
}


@MainActor public extension ActionRunner {
    func performModelTool(_ operation: String, json: String) throws -> String {
        guard isRunning else { throw DraftlyError.message("The action is no longer running.") }
        try checkCancellation()
        return try withScriptMutation { try performActiveModelTool(operation, json: json) }
    }

    private func performActiveModelTool(_ operation: String, json: String) throws -> String {
        let values = (try JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        let result: Any
        switch operation {
        case "draft.query":
            var workspace = Workspace(name: "Model"); workspace.folder = NoteFolder(rawValue: values["folder"] as? String ?? "all") ?? .all
            workspace.query = values["query"] as? String ?? ""; workspace.tags = values["tags"] as? [String] ?? []; result = workspace.filter(library.notes).map(noteValue)
        case "draft.find": result = library.notes.first { $0.id.uuidString == values["uuid"] as? String }.map(noteValue) ?? [:]
        case "draft.create":
            let note = try library.createNote(content: values["text"] as? String ?? "", tags: values["tags"] as? [String] ?? [])
            recordScriptSave(note); result = noteValue(note)
        case "draft.append", "draft.prepend":
            guard var note = library.notes.first(where: { $0.id.uuidString == values["uuid"] as? String }) else { throw DraftlyError.message("The model target draft was not found.") }
            let text = values["text"] as? String ?? ""
            note.content = operation == "draft.append" ? note.content + "\n" + text : text + "\n" + note.content
            try validateScriptNote(note.id)
            try library.saveNote(note); recordScriptSave(note)
            if editor.noteID == note.id {
                editor.content = note.content; editor.acknowledgeSaved(note)
                editor.synchronizeScriptEdit?()
            }
            result = noteValue(note)
        case "editor.open":
            guard let note = library.notes.first(where: { $0.id.uuidString == values["uuid"] as? String }) else { throw DraftlyError.message("The model target draft was not found.") }
            try flushEditor(); try library.recordAccess(note.id); editor.load(note); result = true
        case "action.run":
            guard let action = library.actions.first(where: { $0.name == values["name"] as? String }), let note = library.notes.first(where: { $0.id.uuidString == values["uuid"] as? String || $0.id == editor.noteID }) else { throw DraftlyError.message("The model target action or draft was not found.") }
            queued.append((action, note)); result = true
        case "workspace.find": result = library.workspaces.first { $0.name == values["name"] as? String }.map(workspaceValue) ?? [:]
        default: throw DraftlyError.message("The model tool \(operation) is unavailable.")
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]), as: UTF8.self)
    }
}


enum ScriptDevice {
    static func batteryLevel() throws -> Double {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            throw DraftlyError.message("The battery level is unavailable on this Mac.")
        }
        let values = sources.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
        return try batteryLevel(sources: values)
    }
    static func batteryLevel(sources: [[String: Any]]) throws -> Double {
        for source in sources where source[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
            guard let current = source[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = source[kIOPSMaxCapacityKey] as? Double,
                  current.isFinite, maximum.isFinite, maximum > 0, current >= 0, current <= maximum else { continue }
            return current / maximum
        }
        throw DraftlyError.message("The battery level is unavailable on this Mac.")
    }
}
