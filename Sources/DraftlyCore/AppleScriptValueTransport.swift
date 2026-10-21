import Foundation

/// Carries AppleScript dates through JSON without changing ordinary record values.
public enum AppleScriptValueTransport {
    public enum TransportError: LocalizedError {
        case invalidValue(String)
        case invalidMetadata(String)

        public var errorDescription: String? {
            switch self {
            case .invalidValue(let detail), .invalidMetadata(let detail):
                return "Invalid AppleScript value transport: " + detail
            }
        }
    }

    public static func encode(_ value: Any) throws -> [String: Any] {
        var paths: [String] = []
        let encoded = try encodeValue(value, path: "", dates: &paths)
        var envelope: [String: Any] = ["value": encoded]
        if !paths.isEmpty { envelope["appleScriptDatePaths"] = paths }
        return envelope
    }

    public static func decode(_ envelope: [String: Any]) throws -> Any {
        guard var value = envelope["value"] else {
            throw TransportError.invalidMetadata("The value is missing.")
        }
        guard let metadata = envelope["appleScriptDatePaths"] else { return value }
        guard let paths = metadata as? [String] else {
            throw TransportError.invalidMetadata("Date paths must be an array of strings.")
        }
        var seen: Set<String> = []
        for path in paths {
            guard seen.insert(path).inserted else {
                throw TransportError.invalidMetadata("A date path occurs more than once.")
            }
            value = try replaceDate(in: value, components: pointerComponents(path)[...])
        }
        return value
    }

    private static func encodeValue(_ value: Any, path: String, dates: inout [String]) throws -> Any {
        if let date = value as? Date {
            let milliseconds = date.timeIntervalSince1970 * 1_000
            guard milliseconds.isFinite else { throw TransportError.invalidValue("The date is not finite.") }
            dates.append(path)
            return milliseconds
        }
        if let record = value as? [String: Any] {
            var result: [String: Any] = [:]
            for key in record.keys.sorted() {
                result[key] = try encodeValue(record[key]!, path: path + "/" + escape(key), dates: &dates)
            }
            return result
        }
        if let array = value as? [Any] {
            return try array.enumerated().map { index, item in
                try encodeValue(item, path: path + "/" + String(index), dates: &dates)
            }
        }
        if value is NSNull || value is String { return value }
        if let number = value as? NSNumber, number.doubleValue.isFinite { return number }
        throw TransportError.invalidValue("The value is not a supported JSON value.")
    }

    private static func escape(_ component: String) -> String {
        component.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    private static func pointerComponents(_ path: String) throws -> [String] {
        if path.isEmpty { return [] }
        guard path.first == "/" else { throw TransportError.invalidMetadata("A date path must be a JSON Pointer.") }
        return try path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map { component in
            var result = ""
            var iterator = component.makeIterator()
            while let character = iterator.next() {
                guard character == "~" else { result.append(character); continue }
                switch iterator.next() {
                case "0": result.append("~")
                case "1": result.append("/")
                default: throw TransportError.invalidMetadata("A date path has an invalid escape.")
                }
            }
            return result
        }
    }

    private static func replaceDate(in value: Any, components: ArraySlice<String>) throws -> Any {
        guard let component = components.first else {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite else {
                throw TransportError.invalidMetadata("A date path must identify a finite number.")
            }
            return Date(timeIntervalSince1970: number.doubleValue / 1_000)
        }
        if var record = value as? [String: Any], let child = record[component] {
            record[component] = try replaceDate(in: child, components: components.dropFirst())
            return record
        }
        if var array = value as? [Any], let index = Int(component), index >= 0,
           String(index) == component, array.indices.contains(index) {
            array[index] = try replaceDate(in: array[index], components: components.dropFirst())
            return array
        }
        throw TransportError.invalidMetadata("A date path does not identify a value.")
    }
}
