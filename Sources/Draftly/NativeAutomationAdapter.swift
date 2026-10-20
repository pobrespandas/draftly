import AppKit
import Carbon
import DraftlyCore

@MainActor
struct NativeAutomationAdapter {
    static let operations: Set<String> = ["shortcut", "appleScript"]

    func perform(_ operation: String, values: [String: Any], host: NativeActionHost) throws -> Any? {
        let text = values["text"] as? String ?? ""
        switch operation {
        case "shortcut": return try runShortcut(name: values["name"] as? String ?? "", input: text, waitForResponse: values["waitForResponse"] as? Bool ?? true)
        case "appleScript": return try host.executeAppleScript(values)
        default: throw DraftlyError.message("The native operation is unavailable.")
        }
    }

    func runShortcut(name: String, input: String, waitForResponse: Bool = true,
                     executable: URL = URL(fileURLWithPath: "/usr/bin/shortcuts"), timeout: TimeInterval = 60) throws -> String? {
        guard timeout.isFinite, timeout > 0 else { throw DraftlyError.message("The process timeout must be positive and finite.") }
        guard !name.isEmpty else { throw DraftlyError.message("Enter a Shortcut name in the action step.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var detached = false
        defer { if !detached { try? FileManager.default.removeItem(at: root) } }
        let source = root.appendingPathComponent("input.txt"); let output = root.appendingPathComponent("output.txt")
        let errors = root.appendingPathComponent("errors.txt")
        try input.write(to: source, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { if !detached { try? errorHandle.close() } }
        let process = Process(); process.executableURL = executable
        process.arguments = ["run", name, "--input-path", source.path, "--output-path", output.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = errorHandle
        if !waitForResponse {
            detached = true
            try NativeProcessExecutor.launchDetached(process, timeout: timeout) {
                try? errorHandle.close()
                try? FileManager.default.removeItem(at: root)
            }
            return nil
        }
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        if process.isRunning { process.terminate(); throw DraftlyError.message(timeout == 60 ? "The Shortcut exceeded 60 seconds." : "The Shortcut exceeded its timeout.") }
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

    func runShortcutAsync(name: String, input: String, waitForResponse: Bool = true,
                          executable: URL = URL(fileURLWithPath: "/usr/bin/shortcuts"),
                          timeout: TimeInterval = 60) async throws -> String? {
        guard !name.isEmpty else { throw DraftlyError.message("Enter a Shortcut name in the action step.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var detached = false
        defer { if !detached { try? FileManager.default.removeItem(at: root) } }
        let source = root.appendingPathComponent("input.txt"), output = root.appendingPathComponent("output.txt")
        let errors = root.appendingPathComponent("errors.txt")
        try input.write(to: source, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { if !detached { try? errorHandle.close() } }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["run", name, "--input-path", source.path, "--output-path", output.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = errorHandle
        if !waitForResponse {
            detached = true
            try NativeProcessExecutor.launchDetached(process, timeout: timeout) {
                try? errorHandle.close()
                try? FileManager.default.removeItem(at: root)
            }
            return nil
        }
        let status = try await NativeProcessExecutor.run(process, timeout: timeout)
        guard status == 0 else {
            throw DraftlyError.message((try? String(contentsOf: errors, encoding: .utf8)) ?? "The Shortcut failed.")
        }
        return (try? String(contentsOf: output, encoding: .utf8)) ?? ""
    }

    func executeAppleScript(_ values: [String: Any]) throws -> Any {
        try NativeAppleScriptDescriptor.execute(values)
    }

}
