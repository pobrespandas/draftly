import Foundation

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
}

@MainActor extension ActionRunner {
    func actionValue(_ action: DraftAction) -> [String: Any] {
        ["uuid": action.id.uuidString, "name": action.name, "configuredValues": action.configuredValues,
         "isSeparator": action.scriptMetadata?["isSeparator"] == "true"]
    }
    func workspaceValue(_ workspace: Workspace) -> [String: Any] {
        var result: [String: Any] = [:]
        if let text = workspace.scriptMetadata?["api"], let data = text.data(using: .utf8) {
            result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        result["uuid"] = workspace.id.uuidString; result["name"] = workspace.name; result["queryString"] = workspace.query
        result["tagFilter"] = (workspace.tags + (workspace.excludedTags ?? []).map { "!" + $0 }).joined(separator: ",")
        result["tagFilterRequireAll"] = !(workspace.matchAnyTag ?? false)
        return result
    }
    func decodeWorkspace(_ values: [String: Any]) throws -> Workspace {
        var workspace = Workspace(name: values["name"] as? String ?? "Script")
        if let id = (values["uuid"] as? String).flatMap(UUID.init(uuidString:)) { workspace.id = id }
        workspace.query = values["queryString"] as? String ?? ""
        let tags = (values["tagFilter"] as? String ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        workspace.tags = TagRules.normalize(tags.filter { !$0.hasPrefix("!") })
        workspace.excludedTags = TagRules.normalize(tags.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) })
        workspace.matchAnyTag = !(values["tagFilterRequireAll"] as? Bool ?? true)
        workspace.folder = NoteFolder(rawValue: values["loadFolder"] as? String ?? "inbox") ?? .inbox
        workspace.scriptMetadata = ["api": String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)]
        return workspace
    }
    func queryWorkspace(_ values: [String: Any]) throws -> [Note] {
        let details = values["workspace"] as? [String: Any] ?? [:]
        var workspace = try decodeWorkspace(details)
        workspace.folder = NoteFolder(rawValue: values["folder"] as? String ?? "all") ?? .all
        let sorts = details["_sorts"] as? [String: [String: Any]] ?? [:]
        let sort = sorts[workspace.folder.rawValue] ?? sorts["all"] ?? [:]
        let sortName = sort["sort"] as? String ?? "modified"
        workspace.sort = sortName == "name" ? .title : NoteSort(rawValue: sortName) ?? .modified
        workspace.ascending = !(sort["descending"] as? Bool ?? true)
        var notes = workspace.filter(library.notes)
        let flaggedStatus = details["flaggedStatus"] as? String ?? "any"
        if flaggedStatus == "flagged" { notes = notes.filter { $0.flag > 0 } }
        if flaggedStatus == "unflagged" { notes = notes.filter { $0.flag == 0 } }
        if workspace.folder == .inbox && details["inboxIncludesFlagged"] as? Bool == false || workspace.folder == .archive && details["archiveIncludesFlagged"] as? Bool == false {
            notes = notes.filter { $0.flag == 0 }
        }
        for key in ["startDate", "endDate"] {
            guard let query = details[key] as? [String: Any], let type = query["type"] as? String, type != "none" else { continue }
            let date = type == "relative" ? Calendar.current.date(byAdding: .day, value: query["days"] as? Int ?? 0, to: Date()) : APIValues.parseDate(query["date"])
            guard let date else { continue }
            let start = Calendar.current.startOfDay(for: date)
            let boundary = key == "endDate" ? Calendar.current.date(byAdding: .day, value: 1, to: start)! : start
            notes = notes.filter { note in
                let value = query["field"] as? String == "created" ? note.createdAt : note.modifiedAt
                return key == "endDate" ? value < boundary : value >= boundary
            }
        }
        if sort["flagged"] as? Bool == true { notes = notes.filter { $0.flag > 0 } + notes.filter { $0.flag == 0 } }
        return notes
    }
    func dispatchAPI(_ operation: String, values: [String: Any]) throws -> Any? {
        switch operation {
        case "newUUID": return UUID().uuidString
        case "editorNoteID": return editor.noteID?.uuidString
        case "saveEditor": try flushEditor(); return true
        case "newEditor": try flushEditor(); editor.load(try library.createNote()); return true
        case "recentDrafts": return editor.recentNoteIDs.compactMap { id in library.notes.first { $0.id == id && $0.trashedAt == nil } }.map(noteValue)
        case "selectedDrafts": return (selectedDrafts?() ?? library.notes.filter { $0.id == editor.noteID }).map(noteValue)
        case "ui": if let uiOperation { return try uiOperation(values) }; return try platform("ui", values)
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
            let old = TagRules.normalize(values["oldTag"] as? String ?? ""), new = TagRules.normalize(values["newTag"] as? String ?? "")
            var count = 0
            for var note in library.notes where note.tags.contains(old) {
                note.tags = note.tags.map { $0 == old ? new : $0 }; try library.saveNote(note); count += 1
            }
            return count
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
                 "log": $0.message, "status": $0.status.lowercased()] as [String: Any]
            }
        case "deleteLog":
            guard let id = (values["uuid"] as? String).flatMap(UUID.init(uuidString:)) else { return false }
            try library.deleteRun(id); return true
        case "recentActions":
            var seen: Set<UUID> = []
            return library.runs.compactMap { run -> DraftAction? in
                guard let action = library.actions.first(where: { $0.id == run.actionID || $0.name == run.actionName }), seen.insert(action.id).inserted else { return nil }
                return action
            }.map(actionValue)
        case "actionGroups":
            return Array(Set(library.actions.map(\.group))).sorted().map { ["name": $0, "uuid": stableGroupID($0)] }
        case "groupActions": return library.actions.filter { $0.group == values["name"] as? String }.map(actionValue)
        case "actionInstallURL":
            guard let action = library.actions.first(where: { $0.id.uuidString == values["uuid"] as? String }) else { return nil }
            return try installURL(action)
        case "groupInstallURL": return try installURL(library.actions.filter { $0.group == values["name"] as? String })
        case "syntaxes": return ["Plain Text", "Markdown", "TaskPaper", "JavaScript", "Simple List", "MultiMarkdown", "GitHub Markdown"].map { ["name": $0, "type": "builtIn"] }
        case "themes": return ["Default", "Dark", "Light"].map { ["name": $0, "type": "builtIn"] }
        case "device": return ["systemName": "macOS", "model": "Mac", "systemVersion": ProcessInfo.processInfo.operatingSystemVersionString, "batteryLevel": -1] as [String: Any]
        case "detectURLs":
            let text = values["text"] as? String ?? ""
            return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue).matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { $0.url?.absoluteString }
        case "parseURL", "buildURL": return try ScriptUtilities.url(operation, values)
        case "formatDate":
            let date = APIValues.parseDate(values["date"]) ?? Date(), format = values["format"] as? String ?? "%Y-%m-%d"
            return Templates.render("[[date|\(format)]]", note: Note(), now: date)
        case "adjustDate": return APIValues.date(try ScriptUtilities.adjustDate(values))
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
        let bytes = Array(name.utf8); var result = [UInt8](repeating: 0, count: 16)
        for (i, byte) in bytes.enumerated() { result[i % 16] = result[i % 16] &* 31 &+ byte }
        return UUID(uuid: (result[0],result[1],result[2],result[3],result[4],result[5],result[6],result[7],result[8],result[9],result[10],result[11],result[12],result[13],result[14],result[15])).uuidString
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

private final class ScriptHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let follow: Bool
    init(follow: Bool) { self.follow = follow }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(follow ? request : nil) }
    private final class Result: @unchecked Sendable {
        let lock = NSLock(); var value: [String: Any]?
        func set(_ value: [String: Any]) { lock.lock(); self.value = value; lock.unlock() }
        func get() -> [String: Any]? { lock.lock(); defer { lock.unlock() }; return value }
    }
    static func request(_ values: [String: Any]) -> [String: Any] {
        do {
            guard let string = values["url"] as? String, var components = URLComponents(string: string), ["http", "https"].contains(components.scheme?.lowercased() ?? "") else { throw DraftlyError.message("HTTP requests require an HTTP or HTTPS URL.") }
            if let parameters = values["parameters"] as? [String: Any] { components.queryItems = (components.queryItems ?? []) + parameters.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) } }
            guard let url = components.url else { throw DraftlyError.message("The request URL is invalid.") }
            var request = URLRequest(url: url); request.httpMethod = values["method"] as? String ?? "GET"
            request.timeoutInterval = min(600, max(0.01, values["timeout"] as? Double ?? 60))
            for (key, value) in values["headers"] as? [String: String] ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
            if let username = values["username"] as? String { request.setValue("Basic " + Data((username + ":" + (values["password"] as? String ?? "")).utf8).base64EncodedString(), forHTTPHeaderField: "Authorization") }
            if let data = values["data"] {
                if values["encoding"] as? String == "form", let fields = data as? [String: Any] {
                    var form = URLComponents(); form.queryItems = fields.map { URLQueryItem(name: $0.key, value: String(describing: $0.value)) }
                    request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
                    if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
                } else {
                    request.httpBody = try JSONSerialization.data(withJSONObject: data, options: [.fragmentsAllowed])
                    if request.value(forHTTPHeaderField: "Content-Type") == nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
                }
            }
            let transport = ScriptHTTP(follow: values["followRedirects"] as? Bool ?? true)
            let session = URLSession(configuration: .ephemeral, delegate: transport, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let result = Result()
            let task = session.dataTask(with: request) { data, response, error in
                let response = response as? HTTPURLResponse, data = data ?? Data()
                var value: [String: Any] = ["success": error == nil && (200..<300).contains(response?.statusCode ?? 0), "statusCode": response?.statusCode ?? 0,
                                          "responseText": String(data: data, encoding: .utf8) ?? "", "headers": response?.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) } ?? [:]]
                value["responseData"] = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) ?? NSNull()
                if let error { value["error"] = error.localizedDescription }
                result.set(value)
            }
            task.resume()
            let deadline = Date().addingTimeInterval(request.timeoutInterval + 1)
            while result.get() == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            return result.get() ?? ["success": false, "statusCode": 0, "responseText": "", "headers": [:], "error": "The HTTP request timed out."]
        } catch { return ["success": false, "statusCode": 0, "responseText": "", "headers": [:], "error": error.localizedDescription] }
    }
}

@MainActor public extension ActionRunner {
    func performModelTool(_ operation: String, json: String) throws -> String {
        let values = (try JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
        let result: Any
        switch operation {
        case "draft.query":
            var workspace = Workspace(name: "Model"); workspace.folder = NoteFolder(rawValue: values["folder"] as? String ?? "all") ?? .all
            workspace.query = values["query"] as? String ?? ""; workspace.tags = values["tags"] as? [String] ?? []; result = workspace.filter(library.notes).map(noteValue)
        case "draft.find": result = library.notes.first { $0.id.uuidString == values["uuid"] as? String }.map(noteValue) ?? [:]
        case "draft.create": result = noteValue(try library.createNote(content: values["text"] as? String ?? "", tags: values["tags"] as? [String] ?? []))
        case "draft.append", "draft.prepend":
            guard var note = library.notes.first(where: { $0.id.uuidString == values["uuid"] as? String }) else { throw DraftlyError.message("The model target draft was not found.") }
            let text = values["text"] as? String ?? ""
            note.content = operation == "draft.append" ? note.content + "\n" + text : text + "\n" + note.content
            try library.saveNote(note); if editor.noteID == note.id { editor.content = note.content }; result = noteValue(note)
        case "editor.open":
            guard let note = library.notes.first(where: { $0.id.uuidString == values["uuid"] as? String }) else { throw DraftlyError.message("The model target draft was not found.") }
            try flushEditor(); editor.load(note); result = true
        case "action.run":
            guard let action = library.actions.first(where: { $0.name == values["name"] as? String }), let note = library.notes.first(where: { $0.id.uuidString == values["uuid"] as? String || $0.id == editor.noteID }) else { throw DraftlyError.message("The model target action or draft was not found.") }
            queued.append((action, note)); result = true
        case "workspace.find": result = library.workspaces.first { $0.name == values["name"] as? String }.map(workspaceValue) ?? [:]
        default: throw DraftlyError.message("The model tool \(operation) is unavailable.")
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]), as: UTF8.self)
    }
}
