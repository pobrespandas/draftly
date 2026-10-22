import Foundation
import CoreFoundation

public enum SyntaxTaskError: Error { case invalidSnapshot }

public struct SyntaxFeature: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let defaultValue: Bool
}

public struct SyntaxCompletion: Equatable {
    public let label: String
    public let value: String
    public let draftID: UUID?
}

public struct SyntaxCompletionRequest: Equatable {
    public let range: NSRange
    public let items: [SyntaxCompletion]
}

public struct SyntaxDefinition: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var type: String
    public var source: String
    public private(set) var featureValues: [String: Bool] = [:]
    private enum CodingKeys: String, CodingKey { case id, name, type, source }
    public var features: [SyntaxFeature] {
        (object["featureKeys"] as? [[String: Any]] ?? []).compactMap { feature in
            guard let id = feature["id"] as? String, let name = feature["name"] as? String,
                  let description = feature["description"] as? String, let value = feature["defaultValue"] as? Bool else { return nil }
            return SyntaxFeature(id: id, name: name, description: description, defaultValue: value)
        }
    }
    public var featureState: String {
        features.map { "\($0.id):\(featureValues[$0.id] ?? $0.defaultValue)" }.joined(separator: ",")
    }
    public func resolvingFeatures(_ values: [String: Bool]) -> SyntaxDefinition {
        var definition = self; definition.featureValues = values
        return definition
    }
    public init(data: Data, type: String = "custom", id: UUID = UUID()) throws {
        guard ["custom", "file", "builtIn"].contains(type),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = value["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DraftlyError.message("The syntax needs a name and a valid type.")
        }
        func isBoolean(_ value: Any?) -> Bool {
            guard let number = value as? NSNumber else { return false }
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        }
        func validateOptions(_ rule: [String: Any]) throws {
            for key in ["enabled", "exclusive"] where rule[key] != nil {
                guard isBoolean(rule[key]) else { throw DraftlyError.message("The syntax \(key) option must be a boolean.") }
            }
            if let keys = rule["featureKeys"], !(keys is String) {
                throw DraftlyError.message("The syntax feature requirement must be a string.")
            }
        }
        for key in ["patterns", "navigationPatterns", "linkDefinitions", "taskMarkDefinitions", "indentationPatterns"] {
            guard let rules = value[key] as? [[String: Any]] else { throw DraftlyError.message("The syntax needs a \(key) array.") }
            for rule in rules {
                try validateOptions(rule)
                if let captures = rule["captures"] {
                    if key == "patterns" {
                        guard let captures = captures as? [String: [String: Any]] else { throw DraftlyError.message("The syntax style captures must be objects.") }
                        for capture in captures.values {
                            try validateOptions(capture)
                            if let scope = capture["scope"], !(scope is String) { throw DraftlyError.message("The syntax scope must be a string.") }
                        }
                    } else if !(captures is [String: String]) {
                        throw DraftlyError.message("The syntax captures must contain string indices.")
                    }
                }
                for option in ["scopes", "templates"] where rule[option] != nil {
                    guard rule[option] is [String: String] else { throw DraftlyError.message("The syntax \(option) must contain strings.") }
                }
                if let scope = rule["indentScope"], !(scope is String) { throw DraftlyError.message("The indentation scope must be a string.") }
                if key == "linkDefinitions" {
                    let captures = rule["captures"] as? [String: String] ?? [:]
                    guard ["key", "value", "link"].allSatisfy({ !(captures[$0] ?? "").isEmpty }) else {
                        throw DraftlyError.message("The link pattern needs key, value and link captures.")
                    }
                }
                guard let pattern = rule["match"] as? String else { throw DraftlyError.message("A syntax pattern is missing.") }
                let expression = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
                if key == "indentationPatterns", rule["indentCapture"] as? String == nil {
                    throw DraftlyError.message("The indentation pattern needs an indent capture.")
                }
                if key == "navigationPatterns" {
                    guard rule["rangeCapture"] is String, rule["labelCapture"] is String, (0...9).contains(rule["level"] as? Int ?? 0) else { throw DraftlyError.message("The navigation pattern is invalid.") }
                }
                if key == "taskMarkDefinitions" {
                    let captures = rule["captures"] as? [String: String] ?? [:]
                    guard captures["state"] != nil, captures["interactive"] != nil else { throw DraftlyError.message("The task pattern needs state and interactive captures.") }
                }
                var captures: [String] = []
                if let values = rule["captures"] as? [String: Any] {
                    captures = key == "patterns" ? Array(values.keys) : values.values.compactMap { $0 as? String }
                }
                for key in ["rangeCapture", "labelCapture", "indentCapture"] { if let capture = rule[key] as? String { captures.append(capture) } }
                for capture in captures where !capture.isEmpty {
                    guard let index = Int(capture), index >= 0, index <= expression.numberOfCaptureGroups else {
                        throw DraftlyError.message("A syntax capture is outside its pattern.")
                    }
                }
                if key == "taskMarkDefinitions" {
                    guard let states = rule["states"] as? [String], !states.isEmpty, Set(states).count == states.count,
                          let initial = (rule["initialState"] as? String) ?? states.first, states.contains(initial),
                          let completed = (rule["completedState"] as? [String]) ?? states.last.map({ [$0] }), !completed.isEmpty,
                          completed.allSatisfy(states.contains), ["line", "task"].contains(rule["rangeType"] as? String ?? "") else {
                        throw DraftlyError.message("The syntax task states are invalid.")
                    }
                }
            }
        }
        if let definitions = value["autocompleteDefinitions"] {
            guard let definitions = definitions as? [[String: Any]] else { throw DraftlyError.message("The autocomplete definitions are invalid.") }
            for definition in definitions {
                try validateOptions(definition)
                guard let trigger = definition["trigger"] as? String, !trigger.isEmpty,
                      let type = definition["type"] as? String, ["draft", "static"].contains(type) else {
                    throw DraftlyError.message("The autocomplete trigger or type is invalid.")
                }
                if type == "draft" {
                    guard definition["label"] is String, definition["value"] is String,
                          ["title", "fullText"].contains(definition["queryType"] as? String ?? "title") else {
                        throw DraftlyError.message("The draft autocomplete definition is invalid.")
                    }
                } else {
                    guard let items = definition["items"] as? [[String: Any]],
                          items.allSatisfy({ $0["label"] is String && $0["value"] is String }) else {
                        throw DraftlyError.message("The static autocomplete items are invalid.")
                    }
                }
            }
        }
        if let definitions = value["featureKeys"] {
            guard let definitions = definitions as? [[String: Any]] else { throw DraftlyError.message("The syntax feature keys are invalid.") }
            var ids = Set<String>()
            for feature in definitions {
                guard let id = feature["id"] as? String, !id.isEmpty, ids.insert(id).inserted,
                      feature["name"] is String, feature["description"] is String, isBoolean(feature["defaultValue"]) else {
                    throw DraftlyError.message("A syntax feature key is invalid.")
                }
            }
        }
        if let definitions = value["listCompletionDefinitions"] {
            guard let definitions = definitions as? [[String: Any]] else { throw DraftlyError.message("The list completion definitions are invalid.") }
            for rule in definitions {
                try validateOptions(rule)
                guard let pattern = rule["match"] as? String,
                      let captures = rule["captures"] as? [String: String],
                      ["indent", "prefix", "line"].allSatisfy({ captures[$0] != nil }) else {
                    throw DraftlyError.message("The list completion pattern needs indent, prefix and line captures.")
                }
                let expression = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
                for capture in captures.values where !capture.isEmpty {
                    guard let index = Int(capture), (0...expression.numberOfCaptureGroups).contains(index) else {
                        throw DraftlyError.message("A list completion capture is outside its pattern.")
                    }
                }
                if let padding = rule["sequencePadding"] {
                    guard let padding = padding as? String, let count = Int(padding), count >= 0, count < Int.max else {
                        throw DraftlyError.message("The list sequence padding is invalid.")
                    }
                }
                if let replacements = rule["replacements"], !(replacements is [String: String]) {
                    throw DraftlyError.message("The list replacements are invalid.")
                }
            }
        }
        self.id = id; self.name = name; self.type = type
        self.source = String(decoding: data, as: UTF8.self)
    }
    public var object: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(source.utf8))) as? [String: Any] ?? [:] }
    private func rules(_ key: String) -> [[String: Any]] {
        let defaults = features.reduce(into: [String: Bool]()) { $0[$1.id] = $1.defaultValue }
        return (object[key] as? [[String: Any]] ?? []).filter { rule in
            guard rule["enabled"] as? Bool != false else { return false }
            let keys = (rule["featureKeys"] as? String ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return keys.allSatisfy { featureValues[$0] ?? defaults[$0] ?? false }
        }
    }
    private func results(_ rule: [String: Any], _ text: String) -> [NSTextCheckingResult] {
        guard let pattern = rule["match"] as? String, let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
    }
    private func capture(_ match: NSTextCheckingResult, _ index: Any?) -> NSRange? {
        guard let value = index as? String, let index = Int(value), index >= 0, index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        return range.location == NSNotFound ? nil : range
    }
    public func indentations(in text: String) -> [(range: NSRange, prefix: NSRange, scope: String)] {
        let source = text as NSString
        var lines: Set<Int> = []
        return rules("indentationPatterns").flatMap { rule in
            results(rule, text).compactMap { match in
                guard let prefix = capture(match, rule["indentCapture"]), prefix.length > 0 else { return nil }
                let line = source.lineRange(for: match.range)
                guard match.range.location == line.location,
                      NSMaxRange(prefix) <= NSMaxRange(line),
                      source.substring(with: prefix).rangeOfCharacter(from: .newlines) == nil,
                      lines.insert(line.location).inserted else { return nil }
                return (line, prefix, rule["indentScope"] as? String ?? "text.normal")
            }
        }
    }
    public func tasks(in text: String) -> [[String: Any]] {
        let source = text as NSString
        return rules("taskMarkDefinitions").enumerated().flatMap { ruleIndex, rule -> [[String: Any]] in
            let captures = rule["captures"] as? [String: String] ?? [:]
            return results(rule, text).compactMap { match in
                guard let state = capture(match, captures["state"]), let interactive = capture(match, captures["interactive"]) else { return nil }
                let line = source.lineRange(for: match.range)
                let lineText = source.substring(with: line).trimmingCharacters(in: .newlines)
                let labelEnd = line.location + lineText.utf16.count
                var labelStart = min(NSMaxRange(match.range), labelEnd)
                while labelStart < labelEnd, [UInt16(32), UInt16(9)].contains(source.character(at: labelStart)) { labelStart += 1 }
                let label = capture(match, captures["label"]) ?? NSRange(location: labelStart, length: labelEnd - labelStart)
                let stateText = source.substring(with: state)
                let completed = (rule["completedState"] as? [String]) ?? (rule["states"] as? [String])?.last.map { [$0] } ?? []
                let isCompleted = completed.contains { rule["caseInsensitiveStates"] as? Bool == true ? $0.lowercased() == stateText.lowercased() : $0 == stateText }
                return ["line": lineText, "lineRange": [line.location, lineText.utf16.count],
                        "label": source.substring(with: label), "labelRange": [label.location, label.length],
                        "state": stateText, "stateRange": [state.location, state.length],
                        "interactive": source.substring(with: interactive), "interactiveRange": [interactive.location, interactive.length],
                        "isCompleted": isCompleted || (name == "TaskPaper" && stateText.hasPrefix(" @done(")), "_rule": ruleIndex]
            }
        }.sorted { ($0["stateRange"] as? [Int] ?? [0])[0] < ($1["stateRange"] as? [Int] ?? [0])[0] }
    }
    public func taskChange(in text: String, task: [String: Any], operation: String) throws -> (NSRange, String) {
        guard let range = task["stateRange"] as? [Int], range.count == 2,
              let actual = tasks(in: text).first(where: { ($0["stateRange"] as? [Int]) == range }),
              actual["state"] as? String == task["state"] as? String,
              let index = actual["_rule"] as? Int else { throw SyntaxTaskError.invalidSnapshot }
        let rule = rules("taskMarkDefinitions")[index], states = rule["states"] as? [String] ?? []
        let replacement: String
        switch operation {
        case "complete": replacement = (rule["completedState"] as? [String])?.first ?? states.last ?? ""
        case "reset": replacement = rule["initialState"] as? String ?? states.first ?? ""
        case "advance":
            guard let index = states.firstIndex(where: { rule["caseInsensitiveStates"] as? Bool == true ? $0.lowercased() == (actual["state"] as? String ?? "").lowercased() : $0 == actual["state"] as? String }) ?? (name == "TaskPaper" && actual["isCompleted"] as? Bool == true ? states.count - 1 : nil) else { throw DraftlyError.message("The task state is invalid.") }
            replacement = states[(index + 1) % states.count]
        default: throw DraftlyError.message("The task operation is invalid.")
        }
        return (NSRange(location: range[0], length: range[1]), replacement)
    }
    public func markers(in text: String) -> [[String: Any]] {
        let source = text as NSString
        return rules("navigationPatterns").flatMap { rule in
            results(rule, text).compactMap { match -> [String: Any]? in
                guard let range = capture(match, rule["rangeCapture"]), let label = capture(match, rule["labelCapture"]) else { return nil }
                return ["label": source.substring(with: label), "location": range.location, "length": range.length,
                        "prefix": rule["prefix"] as? String ?? "", "level": rule["level"] as? Int ?? 0, "range": [range.location, range.length]]
            }
        }.sorted { ($0["location"] as? Int ?? 0) < ($1["location"] as? Int ?? 0) }
    }
    public func completion(in text: String, selection: NSRange, drafts: [Note], current: Note,
                           now: Date = Date()) -> SyntaxCompletionRequest? {
        let source = text as NSString
        guard selection.length == 0, selection.location >= 0, selection.location <= source.length else { return nil }
        let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let before = source.substring(with: NSRange(location: lineRange.location, length: selection.location - lineRange.location)) as NSString
        var candidates: [(Int, Int, [String: Any])] = []
        for (index, definition) in rules("autocompleteDefinitions").enumerated() {
            guard let trigger = definition["trigger"] as? String, !trigger.isEmpty else { continue }
            let found = before.range(of: trigger, options: .backwards)
            if found.location != NSNotFound { candidates.append((found.location, index, definition)) }
        }
        guard let candidate = candidates.sorted(by: { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }).first,
              let trigger = candidate.2["trigger"] as? String else { return nil }
        let rule = candidate.2
        let query = before.substring(from: candidate.0 + trigger.utf16.count)
        let suffix = rule["suffix"] as? String ?? ""
        guard suffix.isEmpty || !query.contains(suffix) else { return nil }
        var context = current; context.content = text
        func contains(_ value: String) -> Bool {
            query.isEmpty || value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        func rendered(_ item: [String: Any], note: Note, template: Bool) -> SyntaxCompletion {
            let prefix = item["prefix"] as? String ?? "", suffix = item["suffix"] as? String ?? ""
            let label = item["label"] as? String ?? "", value = item["value"] as? String ?? ""
            return SyntaxCompletion(label: prefix + (template ? Templates.render(label, note: note, now: now) : label) + suffix,
                value: prefix + (template ? Templates.render(value, note: note, now: now) : value) + suffix,
                draftID: rule["type"] as? String == "draft" ? note.id : nil)
        }
        let items: [SyntaxCompletion]
        if rule["type"] as? String == "draft" {
            let filters = (rule["queryTagFilter"] as? String ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            items = drafts.filter { note in
                note.id != current.id && note.trashedAt == nil &&
                contains(rule["queryType"] as? String == "fullText" ? note.content : note.title) &&
                filters.allSatisfy { TagRules.matches($0, in: note.tags) }
            }.sorted { $0.modifiedAt == $1.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.modifiedAt > $1.modifiedAt }
                .map { rendered(rule, note: $0, template: true) }
        } else {
            items = (rule["items"] as? [[String: Any]] ?? []).map { item in
                rendered(item, note: context, template: item["processTemplateTags"] as? Bool ?? rule["processTemplateTags"] as? Bool ?? false)
            }.filter { contains($0.label) }
        }
        return SyntaxCompletionRequest(range: NSRange(location: lineRange.location + candidate.0,
            length: before.length - candidate.0), items: items)
    }

    public func listContinuation(in text: String, selection: NSRange) -> (range: NSRange, text: String)? {
        let source = text as NSString
        guard selection.location >= 0, selection.length >= 0, selection.location <= source.length,
              selection.length <= source.length - selection.location else { return nil }
        let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let lineSource = line as NSString
        for rule in rules("listCompletionDefinitions") {
            let captures = rule["captures"] as? [String: String] ?? [:]
            guard let match = results(rule, line).first, match.range.location == 0,
                  let indentRange = capture(match, captures["indent"]),
                  let prefixRange = capture(match, captures["prefix"]),
                  let contentRange = capture(match, captures["line"]),
                  selection.location >= lineRange.location + NSMaxRange(prefixRange) else { continue }
            if lineSource.substring(with: contentRange).trimmingCharacters(in: .whitespaces).isEmpty {
                return (NSRange(location: lineRange.location, length: NSMaxRange(selection) - lineRange.location), "\n")
            }
            var prefix = lineSource.substring(with: prefixRange)
            if let sequence = capture(match, captures["sequence"]),
               NSIntersectionRange(sequence, prefixRange) == sequence,
               let number = Int(lineSource.substring(with: sequence)), number < Int.max {
                let next = String(number + 1)
                let padding = Int(rule["sequencePadding"] as? String ?? "0") ?? 0
                let digits = String(repeating: "0", count: max(0, padding + 1 - next.count)) + next
                prefix = (prefix as NSString).replacingCharacters(in: NSRange(location: sequence.location - prefixRange.location, length: sequence.length), with: digits)
            }
            for (key, value) in (rule["replacements"] as? [String: String] ?? [:]).sorted(by: { $0.key < $1.key }) where !key.isEmpty {
                prefix = prefix.replacingOccurrences(of: key, with: value)
            }
            return (selection, "\n" + lineSource.substring(with: indentRange) + prefix)
        }
        return nil
    }

    public func taskStyledRanges(in text: String) -> [(NSRange, String)] {
        let definitions = rules("taskMarkDefinitions")
        return tasks(in: text).compactMap { task in
            guard let index = task["_rule"] as? Int,
                  let scope = (definitions[index]["scopes"] as? [String: String])?["interactive"],
                  let range = task["interactiveRange"] as? [Int], range.count == 2 else { return nil }
            return (NSRange(location: range[0], length: range[1]), scope)
        }
    }

    public func linkStyledRanges(in text: String) -> [(NSRange, String)] {
        return rules("linkDefinitions").flatMap { rule in
            let captures = rule["captures"] as? [String: String] ?? [:]
            let scopes = rule["scopes"] as? [String: String] ?? [:]
            return results(rule, text).flatMap { match in
                ["key", "value", "prefix", "suffix"].compactMap { key -> (NSRange, String)? in
                    guard let scope = scopes[key], let range = capture(match, captures[key]) else { return nil }
                    return (range, scope)
                }
            }
        }
    }

    public func resolvedLinks(in text: String) -> [(range: NSRange, url: URL)] {
        let source = text as NSString
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return rules("linkDefinitions").flatMap { rule in
            let captures = rule["captures"] as? [String: String] ?? [:]
            let templates = rule["templates"] as? [String: String] ?? [:]
            return results(rule, text).compactMap { match -> (range: NSRange, url: URL)? in
                let key = capture(match, captures["key"]).map(source.substring(with:)) ?? ""
                guard let template = templates[key],
                      let valueRange = capture(match, captures["value"]),
                      let range = capture(match, captures["link"]), range.length > 0 else { return nil }
                let value = source.substring(with: valueRange)
                guard let encoded = value.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
                // Preserve URL delimiters and existing escapes in the raw value.
                let urlCharacters = unreserved.union(CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;=%"))
                guard let raw = value.addingPercentEncoding(withAllowedCharacters: urlCharacters) else { return nil }
                let expanded = template.replacingOccurrences(of: "[[value]]", with: encoded)
                    .replacingOccurrences(of: "[[value_unencoded]]", with: raw)
                guard let url = URL(string: expanded), url.scheme != nil else { return nil }
                return (range, url)
            }
        }.sorted { $0.range.location < $1.range.location }
    }

    public func links(in text: String) -> [[String: Any]] {
        let source = text as NSString
        return rules("linkDefinitions").flatMap { rule in
            let captures = rule["captures"] as? [String: String] ?? [:]
            return results(rule, text).map { match in
                var value: [String: Any] = ["location": match.range.location, "length": match.range.length, "range": [match.range.location, match.range.length]]
                for key in ["key", "value", "link", "prefix", "suffix"] { value[key] = capture(match, captures[key]).map(source.substring(with:)) ?? "" }
                return value
            }
        }.sorted { ($0["location"] as? Int ?? 0) < ($1["location"] as? Int ?? 0) }
    }
}

@MainActor public enum SyntaxFileAccess {
    public static func install(_ definition: SyntaxDefinition, from url: URL, in library: LibraryStore,
                               defaults: UserDefaults = .standard) throws {
        guard definition.type == "file" else { throw DraftlyError.message("A file syntax definition is required.") }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        try library.saveSyntax(definition)
        defaults.set(bookmark, forKey: "syntax.file." + definition.id.uuidString)
    }

    public static func register(_ url: URL, id: UUID, defaults: UserDefaults = .standard) throws {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: "syntax.file." + id.uuidString)
    }
    public static func read(_ definition: SyntaxDefinition, defaults: UserDefaults = .standard) throws -> SyntaxDefinition {
        guard let bookmark = defaults.data(forKey: "syntax.file." + definition.id.uuidString) else { throw DraftlyError.message("Reselect the file for syntax \(definition.name).") }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        let active = url.startAccessingSecurityScopedResource(); defer { if active { url.stopAccessingSecurityScopedResource() } }
        let current = try SyntaxDefinition(data: Data(contentsOf: url), type: "file", id: definition.id)
        guard current.name == definition.name else { throw DraftlyError.message("The file syntax name changed. Import it again.") }
        if stale { try register(url, id: definition.id, defaults: defaults) }
        return current
    }
}

public extension SyntaxDefinition {
    func styledRanges(in text: String) -> [(NSRange, String)] {
        var output: [(NSRange, String)] = [], excluded: [NSRange] = []
        for rule in rules("patterns") {
            for match in results(rule, text) where !excluded.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                for (index, value) in rule["captures"] as? [String: [String: Any]] ?? [:] {
                    guard let range = capture(match, index) else { continue }
                    output.append((range, value["scope"] as? String ?? ""))
                    if value["exclusive"] as? Bool == true { excluded.append(range) }
                }
                if rule["exclusive"] as? Bool == true { excluded.append(match.range) }
            }
        }
        return output
    }
}

public enum SyntaxFeaturePreferences {
    public static let key = "editor.syntaxFeatures"
    public static func values(for syntax: String, encoded: String) -> [String: Bool] {
        let object = (try? JSONSerialization.jsonObject(with: Data(encoded.utf8))) as? [String: Any] ?? [:]
        return (object[syntax] as? [String: Any] ?? [:]).reduce(into: [String: Bool]()) { values, entry in
            if let value = entry.value as? Bool { values[entry.key] = value }
        }
    }
    public static func setting(_ enabled: Bool, feature: String, syntax: String, encoded: String) -> String {
        var object = (try? JSONSerialization.jsonObject(with: Data(encoded.utf8))) as? [String: Any] ?? [:]
        var values = object[syntax] as? [String: Any] ?? [:]
        values[feature] = enabled; object[syntax] = values
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return encoded }
        return String(decoding: data, as: UTF8.self)
    }
}
