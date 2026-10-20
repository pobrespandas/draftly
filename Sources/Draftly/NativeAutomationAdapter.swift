import AppKit
import Carbon
import DraftlyCore

@MainActor
struct NativeAutomationAdapter {
    static let operations: Set<String> = ["shortcut", "appleScript"]

    func perform(_ operation: String, values: [String: Any], host: NativeActionHost) throws -> Any? {
        let text = values["text"] as? String ?? ""
        switch operation {
        case "shortcut": return try runShortcut(name: values["name"] as? String ?? "", input: text)
        case "appleScript": return try host.executeAppleScript(values)
        default: throw DraftlyError.message("The native operation is unavailable.")
        }
    }

    func runShortcut(name: String, input: String) throws -> String {
        guard !name.isEmpty else { throw DraftlyError.message("Enter a Shortcut name in the action step.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("input.txt"); let output = root.appendingPathComponent("output.txt")
        let errors = root.appendingPathComponent("errors.txt")
        try input.write(to: source, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { try? errorHandle.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name, "--input-path", source.path, "--output-path", output.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = errorHandle
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        if process.isRunning { process.terminate(); throw DraftlyError.message("The Shortcut exceeded 60 seconds.") }
        guard process.terminationStatus == 0 else { throw DraftlyError.message((try? String(contentsOf: errors, encoding: .utf8)) ?? "The Shortcut failed.") }
        return (try? String(contentsOf: output, encoding: .utf8)) ?? ""
    }
    func executeShell(_ values: [String: Any]) throws -> [String: Any] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("action"), out = folder.appendingPathComponent("stdout"), err = folder.appendingPathComponent("stderr")
        let source = values["source"] as? String ?? ""
        try (source.hasPrefix("#!") ? source : "#!/bin/sh\n" + source).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        FileManager.default.createFile(atPath: out.path, contents: nil); FileManager.default.createFile(atPath: err.path, contents: nil)
        let output = try FileHandle(forWritingTo: out), errors = try FileHandle(forWritingTo: err)
        defer { try? output.close(); try? errors.close() }
        let process = Process(); process.executableURL = file; process.arguments = values["arguments"] as? [String] ?? []
        process.standardOutput = output; process.standardError = errors; try process.run()
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        if process.isRunning { process.terminate(); throw DraftlyError.message("The shell script exceeded 120 seconds.") }
        return ["status": Int(process.terminationStatus), "stdout": (try? String(contentsOf: out, encoding: .utf8)) ?? "", "stderr": (try? String(contentsOf: err, encoding: .utf8)) ?? ""]
    }
    func executeShellAsync(_ values: [String: Any], timeout: TimeInterval = 120) async throws -> [String: Any] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("action")
        let out = folder.appendingPathComponent("stdout"), err = folder.appendingPathComponent("stderr")
        let source = values["source"] as? String ?? ""
        try (source.hasPrefix("#!") ? source : "#!/bin/sh\n" + source).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        let output = try FileHandle(forWritingTo: out), errors = try FileHandle(forWritingTo: err)
        defer { try? output.close(); try? errors.close() }
        let process = Process()
        process.executableURL = file
        process.arguments = values["arguments"] as? [String] ?? []
        process.standardOutput = output; process.standardError = errors
        let status = try await NativeProcessExecutor.run(process, timeout: timeout)
        return ["status": Int(status), "stdout": (try? String(contentsOf: out, encoding: .utf8)) ?? "",
                "stderr": (try? String(contentsOf: err, encoding: .utf8)) ?? ""]
    }

    func runShortcutAsync(name: String, input: String,
                          executable: URL = URL(fileURLWithPath: "/usr/bin/shortcuts"),
                          timeout: TimeInterval = 60) async throws -> String {
        guard !name.isEmpty else { throw DraftlyError.message("Enter a Shortcut name in the action step.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("input.txt"), output = root.appendingPathComponent("output.txt")
        let errors = root.appendingPathComponent("errors.txt")
        try input.write(to: source, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { try? errorHandle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["run", name, "--input-path", source.path, "--output-path", output.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = errorHandle
        let status = try await NativeProcessExecutor.run(process, timeout: timeout)
        guard status == 0 else {
            throw DraftlyError.message((try? String(contentsOf: errors, encoding: .utf8)) ?? "The Shortcut failed.")
        }
        return (try? String(contentsOf: output, encoding: .utf8)) ?? ""
    }

    func executeAppleScript(_ values: [String: Any]) throws -> Any {
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
        return appleValue(result)
    }
    private func appleDescriptor(_ value: Any) throws -> NSAppleEventDescriptor {
        if value is NSNull { return .null() }
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
    private func appleValue(_ value: NSAppleEventDescriptor) -> Any {
        switch value.descriptorType {
        case typeAEList: return (1...max(1, value.numberOfItems)).compactMap { value.atIndex($0).map(appleValue) }
        case typeAERecord:
            var record: [String: Any] = [:]
            if let fields = value.forKeyword(AEKeyword(keyASUserRecordFields)), fields.numberOfItems > 1 {
                for i in stride(from: 1, to: fields.numberOfItems, by: 2) { if let key = fields.atIndex(i)?.stringValue, let item = fields.atIndex(i + 1) { record[key] = appleValue(item) } }
            }
            return record
        case typeBoolean, typeTrue, typeFalse: return value.booleanValue
        case typeSInt16, typeSInt32, typeSInt64, typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint: return value.doubleValue
        case typeNull: return NSNull()
        default: return value.stringValue ?? ""
        }
    }

}
