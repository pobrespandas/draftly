import AppKit
import Carbon
import CoreLocation
import DraftlyCore

@MainActor extension NativeActionHost {
    func performAPI(_ operation: String, values: [String: Any]) throws -> Any? {
        switch operation {
        case "arrangeText": return arrangeText(values["text"] as? String ?? "")
        case "dictate": return try dictationHandler?(values) ?? transcribe(values, dictate: true)
        case "transcribe": return try transcribe(values, dictate: false)
        case "scanDocument": return scanDocument()
        case "recognizeDocument": return try recognizeDocument()
        case "fileAPI": return try fileAPI(values)
        case "bookmark": return try bookmarkRoot(values["name"] as? String ?? "").path
        case "forgetBookmark": BookmarkPreferences.forget(values["name"] as? String ?? "", defaults: fileDefaults); return true
        case "requireScript":
            var path = values["path"] as? String ?? ""
            if !path.hasSuffix(".js") { path += ".js" }
            return try fileAPI(["storage": "local", "operation": "readString", "path": "Scripts/" + path])
        case "shellScript": return try executeShell(values)
        case "callbackURL": return try ActionCallbackRouter.open(values)
        case "eventAPI": return try eventAPI(values)
        case "htmlUnescape": return try decodeHTML(values["text"] as? String ?? "")
        case "htmlToMarkdown": return try htmlToMarkdown(values["text"] as? String ?? "", options: values["options"] as? [String: Any] ?? [:])
        case "composeMail", "composeMessage": return try compose(operation, values)
        case "shareURL":
            guard let url = URL(string: values["url"] as? String ?? ""), let view = NSApp.keyWindow?.contentView else { return false }
            NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY); return true
        case "print":
            let text = values["text"] as? String ?? "", view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
            if values["format"] as? String == "html" {
                view.textStorage?.setAttributedString(try NSAttributedString(data: Data(text.utf8), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil))
            } else { view.string = text }
            let info = NSPrintInfo.shared.copy() as! NSPrintInfo
            for (key, setter) in [("topMargin", { info.topMargin = $0 }), ("bottomMargin", { info.bottomMargin = $0 }), ("leftMargin", { info.leftMargin = $0 }), ("rightMargin", { info.rightMargin = $0 })] as [(String, (CGFloat) -> Void)] {
                setter(values[key] as? CGFloat ?? 72)
            }
            return NSPrintOperation(view: view, printInfo: info).run()
        case "speechVoices": return NSSpeechSynthesizer.availableVoices.compactMap { voice -> [String: String]? in
            let attributes = NSSpeechSynthesizer.attributes(forVoice: voice)
            return ["id": voice.rawValue, "name": attributes[.name] as? String ?? voice.rawValue, "language": attributes[.localeIdentifier] as? String ?? ""]
        }
        case "speak":
            let settings = values["settings"] as? [String: Any] ?? [:], text = values["text"] as? String ?? ""
            if settings["autoStart"] as? Bool == false {
                let alert = NSAlert(); alert.messageText = "Read text aloud"; alert.informativeText = text
                alert.addButton(withTitle: "Read"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return false }
            }
            let voice = ((settings["voice"] as? [String: Any])?["id"] as? String).map(NSSpeechSynthesizer.VoiceName.init(rawValue:))
            guard let synthesizer = NSSpeechSynthesizer(voice: voice) else { throw DraftlyError.message("The selected voice is unavailable.") }
            synthesizer.rate = settings["rate"] as? String == "slow" ? 130 : settings["rate"] as? String == "fast" ? 240 : 180
            guard synthesizer.startSpeaking(text) else { return false }
            while synthesizer.isSpeaking { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            if settings["autoClose"] as? Bool == false { let alert = NSAlert(); alert.messageText = "Reading complete"; alert.runModal() }
            return true
        case "location": return try ScriptLocation.current()
        case "lookup":
            guard let encoded = (values["text"] as? String ?? "").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "dict:///" + encoded) else { return false }
            return NSWorkspace.shared.open(url)
        case "modelModes", "modelRespond": return try models.perform(operation, values)
        case "ui": throw DraftlyError.message("This action needs an active Draftly editor window.")
        default: throw DraftlyError.message("Unsupported native operation: \(operation)")
        }
    }

    func bookmarkRoot(_ name: String) throws -> URL { try fileAdapter.bookmarkRoot(name) }
    func fileAPI(_ values: [String: Any]) throws -> Any { try fileAdapter.fileAPI(values) }
    func executeShell(_ values: [String: Any]) throws -> [String: Any] { try NativeAutomationAdapter().executeShell(values) }
    func executeAppleScript(_ values: [String: Any]) throws -> Any { try NativeAutomationAdapter().executeAppleScript(values) }
    private func compose(_ operation: String, _ values: [String: Any]) throws -> [String: String] { try NativeMessageAdapter().compose(operation, values) }
    func decodeHTML(_ text: String) throws -> String { try NativeHTMLConversion().decodeHTML(text) }
    private func htmlToMarkdown(_ text: String, options: [String: Any]) throws -> String { try NativeHTMLConversion().htmlToMarkdown(text, options: options) }
}

@MainActor private final class ScriptLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    let manager = CLLocationManager(); var location: CLLocation?; var failure: Error?
    static func current() throws -> [String: Double] {
        let request = ScriptLocation(); request.manager.delegate = request
        if request.manager.authorizationStatus == .notDetermined { request.manager.requestWhenInUseAuthorization() }
        if request.manager.authorizationStatus == .denied || request.manager.authorizationStatus == .restricted { throw DraftlyError.message("Location access is denied.") }
        request.manager.startUpdatingLocation(); defer { request.manager.stopUpdatingLocation() }
        let deadline = Date().addingTimeInterval(30)
        while request.location == nil && request.failure == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        if let error = request.failure { throw error }
        guard let value = request.location else { throw DraftlyError.message("The location request timed out.") }
        return ["latitude": value.coordinate.latitude, "longitude": value.coordinate.longitude]
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { location = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) { failure = error }
}
