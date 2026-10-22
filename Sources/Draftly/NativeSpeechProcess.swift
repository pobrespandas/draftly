import AppKit
import DraftlyCore

@MainActor enum NativeSpeechProcess {
    static let helperFlag = "--draftly-speech-helper"

    static func runHelperIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments,
                                    synthesize: @MainActor ([String: Any]) throws -> Bool = synthesize) -> Int32? {
        guard arguments.contains(helperFlag) else { return nil }
        guard arguments.count == 4, arguments[1] == helperFlag else { return 64 }
        let output = URL(fileURLWithPath: arguments[3])
        do {
            let envelope: [String: Any]
            do {
                guard let values = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[2]))) as? [String: Any] else {
                    throw DraftlyError.message("The speech helper request must be an object.")
                }
                envelope = ["success": try synthesize(values)]
            } catch { envelope = ["error": error.localizedDescription] }
            try JSONSerialization.data(withJSONObject: envelope).write(to: output, options: .atomic)
            return 0
        } catch { return 74 }
    }

    static func run(text: String, voice: String?, rate: Float,
                    executable: URL? = Bundle.main.executableURL, timeout: TimeInterval = 120,
                    temporaryDirectory: URL = FileManager.default.temporaryDirectory) async throws -> Bool {
        try Task.checkCancellation()
        guard let executable else { throw DraftlyError.message("The speech helper executable is unavailable.") }
        let directory = temporaryDirectory.appendingPathComponent("Draftly-Speech-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("request.json"), output = directory.appendingPathComponent("result.json")
        var values: [String: Any] = ["text": text, "rate": rate]
        if let voice { values["voice"] = voice }
        try JSONSerialization.data(withJSONObject: values).write(to: input, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        let process = Process(); process.executableURL = executable
        process.arguments = [helperFlag, input.path, output.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        let status = try await NativeProcessExecutor.run(process, timeout: timeout)
        try Task.checkCancellation()
        guard status == 0 else { throw DraftlyError.message("The speech helper exited with status \(status).") }
        guard let data = try? Data(contentsOf: output),
              let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DraftlyError.message("The speech helper returned an invalid response.")
        }
        if let message = envelope["error"] as? String { throw DraftlyError.message(message) }
        guard let success = envelope["success"] as? NSNumber, CFGetTypeID(success) == CFBooleanGetTypeID() else {
            throw DraftlyError.message("The speech helper returned an invalid response.")
        }
        return success.boolValue
    }

    private static func synthesize(_ values: [String: Any]) throws -> Bool {
        guard let text = values["text"] as? String, let rate = values["rate"] as? NSNumber,
              rate.floatValue.isFinite, rate.floatValue > 0 else {
            throw DraftlyError.message("The speech helper request is invalid.")
        }
        let voice = (values["voice"] as? String).map(NSSpeechSynthesizer.VoiceName.init(rawValue:))
        guard let synthesizer = NSSpeechSynthesizer(voice: voice) else {
            throw DraftlyError.message("The selected voice is unavailable.")
        }
        let observer = SpeechHelperCompletion()
        synthesizer.delegate = observer
        synthesizer.rate = rate.floatValue
        guard synthesizer.startSpeaking(text) else { return false }
        if observer.result == nil { CFRunLoopRun() }
        guard let result = observer.result else { throw DraftlyError.message("Speech ended without a completion result.") }
        withExtendedLifetime(synthesizer) {}
        return result
    }
}

@MainActor private final class SpeechHelperCompletion: NSObject, NSSpeechSynthesizerDelegate {
    var result: Bool?
    nonisolated func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        DispatchQueue.main.async { [self] in
            result = finishedSpeaking
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }
}
