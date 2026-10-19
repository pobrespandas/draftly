import Foundation

public enum SyntaxTaskError: Error { case invalidSnapshot }

public struct SyntaxDefinition: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var type: String
    public var source: String
    public init(data: Data, type: String = "custom", id: UUID = UUID()) throws {
        guard ["custom", "file", "builtIn"].contains(type),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = value["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DraftlyError.message("The syntax needs a name and a valid type.")
        }
        for key in ["patterns", "navigationPatterns", "linkDefinitions", "taskMarkDefinitions", "indentationPatterns"] {
            guard let rules = value[key] as? [[String: Any]] else { throw DraftlyError.message("The syntax needs a \(key) array.") }
            for rule in rules {
                guard let pattern = rule["match"] as? String else { throw DraftlyError.message("A syntax pattern is missing.") }
                let expression = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
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
        self.id = id; self.name = name; self.type = type
        self.source = String(decoding: data, as: UTF8.self)
    }
    public var object: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(source.utf8))) as? [String: Any] ?? [:] }
    private func rules(_ key: String) -> [[String: Any]] { (object[key] as? [[String: Any]] ?? []).filter { $0["enabled"] as? Bool != false } }
    private func results(_ rule: [String: Any], _ text: String) -> [NSTextCheckingResult] {
        guard let pattern = rule["match"] as? String, let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
    }
    private func capture(_ match: NSTextCheckingResult, _ index: Any?) -> NSRange? {
        guard let value = index as? String, let index = Int(value), index >= 0, index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        return range.location == NSNotFound ? nil : range
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
