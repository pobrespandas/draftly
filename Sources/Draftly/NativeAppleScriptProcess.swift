import AppKit
import Carbon
import DraftlyCore

@MainActor enum NativeAppleScriptProcess {
    static let helperFlag = "--draftly-applescript-helper"

    // The app entry point must call this before it creates the SwiftUI app.
    static func runHelperIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Int32? {
        guard arguments.contains(helperFlag) else { return nil }
        guard arguments.count == 4, arguments[1] == helperFlag else { return 64 }
        let output = URL(fileURLWithPath: arguments[3])
        do {
            let envelope: [String: Any]
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
                guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw DraftlyError.message("The AppleScript helper request must be an object.")
                }
                envelope = ["value": try NativeAppleScriptDescriptor.execute(values)]
            } catch { envelope = ["error": error.localizedDescription] }
            try JSONSerialization.data(withJSONObject: envelope).write(to: output, options: .atomic)
            return 0
        } catch { return 74 }
    }

    static func run(_ values: [String: Any], executable: URL? = Bundle.main.executableURL,
                    timeout: TimeInterval = 120) async throws -> Any {
        try Task.checkCancellation()
        guard let executable else { throw DraftlyError.message("The AppleScript helper executable is unavailable.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Draftly-AppleScript-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("request.json"), output = directory.appendingPathComponent("result.json")
        let errors = directory.appendingPathComponent("stderr.txt")
        try JSONSerialization.data(withJSONObject: values).write(to: input, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let stderr = try FileHandle(forWritingTo: errors); defer { try? stderr.close() }
        let process = Process(); process.executableURL = executable
        process.arguments = [helperFlag, input.path, output.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = stderr
        let status = try await NativeProcessExecutor.run(process, timeout: timeout)
        guard status == 0 else {
            let detail = (try? String(contentsOf: errors, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw DraftlyError.message(detail.isEmpty ? "The AppleScript helper exited with status \(status)." : detail)
        }
        guard let data = try? Data(contentsOf: output),
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DraftlyError.message("The AppleScript helper returned an invalid response.")
        }
        if let message = envelope["error"] as? String { throw DraftlyError.message(message) }
        guard let value = envelope["value"] else { throw DraftlyError.message("The AppleScript helper returned an invalid response.") }
        return value
    }
}

@MainActor enum NativeAppleScriptDescriptor {
    private static let missingValueCode: OSType = 0x6D736E67
    private static let propertyNames: [AEKeyword: String] = [
        0x63747874: "text", 0x706E616D: "name", 0x70636E74: "contents", 0x49442020: "id"
    ]
    static func execute(_ values: [String: Any]) throws -> Any {
        guard let script = NSAppleScript(source: values["source"] as? String ?? "") else { throw DraftlyError.message("The AppleScript could not be compiled.") }
        var error: NSDictionary?
        let result: NSAppleEventDescriptor
        if let subroutine = values["subroutine"] as? String, !subroutine.isEmpty {
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(NSAppleEventDescriptor(string: subroutine), forKeyword: AEKeyword(keyASSubroutineName))
            let arguments = NSAppleEventDescriptor.list()
            for (index, argument) in (values["arguments"] as? [Any] ?? []).enumerated() { arguments.insert(try appleDescriptor(argument), at: index + 1) }
            event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
            result = script.executeAppleEvent(event, error: &error)
        } else { result = script.executeAndReturnError(&error) }
        if let error { throw DraftlyError.message(error[NSAppleScript.errorMessage] as? String ?? error.description) }
        return try appleValue(result)
    }
    private static func appleDescriptor(_ value: Any) throws -> NSAppleEventDescriptor {
        if value is NSNull { return NSAppleEventDescriptor(typeCode: missingValueCode) }
        if let value = value as? String { return NSAppleEventDescriptor(string: value) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return NSAppleEventDescriptor(boolean: number.boolValue) }
            return NSAppleEventDescriptor(double: number.doubleValue)
        }
        if let values = value as? [Any] { let list = NSAppleEventDescriptor.list(); for (i, v) in values.enumerated() { list.insert(try appleDescriptor(v), at: i + 1) }; return list }
        if let values = value as? [String: Any] {
            let record = NSAppleEventDescriptor.record(), fields = NSAppleEventDescriptor.list()
            for (key, value) in values.sorted(by: { $0.key < $1.key }) { fields.insert(NSAppleEventDescriptor(string: key), at: fields.numberOfItems + 1); fields.insert(try appleDescriptor(value), at: fields.numberOfItems + 1) }
            record.setDescriptor(fields, forKeyword: AEKeyword(keyASUserRecordFields)); return record
        }
        throw DraftlyError.message("The AppleScript argument type is unsupported.")
    }
    private static func appleValue(_ value: NSAppleEventDescriptor) throws -> Any {
        switch value.descriptorType {
        case typeAEList: return try (1...max(1, value.numberOfItems)).compactMap { try value.atIndex($0).map(appleValue) }
        case typeAERecord:
            var record: [String: Any] = [:]
            if let fields = value.forKeyword(AEKeyword(keyASUserRecordFields)), fields.numberOfItems > 1 {
                for i in stride(from: 1, to: fields.numberOfItems, by: 2) {
                    if let key = fields.atIndex(i)?.stringValue, let item = fields.atIndex(i + 1) {
                        guard record[key] == nil else { throw DraftlyError.message("The AppleScript record has a duplicate field: \(key)") }
                        record[key] = try appleValue(item)
                    }
                }
            }
            if value.numberOfItems > 0 {
                for index in 1...value.numberOfItems {
                    let keyword = value.keywordForDescriptor(at: index)
                    guard keyword != AEKeyword(keyASUserRecordFields), let item = value.atIndex(index) else { continue }
                    // Unknown terminology keeps its four-character Apple event key.
                    let bytes: [UInt8] = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: keyword >> $0) }
                    let key = propertyNames[keyword] ?? String(bytes: bytes, encoding: .isoLatin1)!
                    guard record[key] == nil else { throw DraftlyError.message("The AppleScript record has a duplicate field: \(key)") }
                    record[key] = try appleValue(item)
                }
            }
            return record
        case typeBoolean, typeTrue, typeFalse: return value.booleanValue
        case typeSInt16, typeSInt32, typeSInt64, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint: return value.doubleValue
        case typeNull: return NSNull()
        case typeType where value.typeCodeValue == missingValueCode: return NSNull()
        default: return value.stringValue ?? ""
        }
    }

}
