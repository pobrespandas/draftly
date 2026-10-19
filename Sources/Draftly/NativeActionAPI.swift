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
        case "forgetBookmark": UserDefaults.standard.removeObject(forKey: "bookmark.\(values["name"] as? String ?? "")"); return true
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

    func bookmarkRoot(_ name: String) throws -> URL {
        guard !name.isEmpty else { throw DraftlyError.message("The bookmark name is empty.") }
        let key = "bookmark.\(name)"
        var stale = false
        if let data = UserDefaults.standard.data(forKey: key), let root = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale), !stale { return root }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.message = "Choose the folder for \(name)."
        guard panel.runModal() == .OK, let root = panel.url else { throw DraftlyError.message("Folder selection cancelled.") }
        UserDefaults.standard.set(try root.bookmarkData(options: .withSecurityScope), forKey: key)
        return root
    }
    func fileAPI(_ values: [String: Any]) throws -> Any {
        let storage = values["storage"] as? String ?? "local", manager = FileManager.default
        let root: URL
        switch storage {
        case "bookmark": root = try bookmarkRoot(values["bookmark"] as? String ?? "")
        case "cloud":
            guard let cloud = manager.url(forUbiquityContainerIdentifier: nil) else { throw DraftlyError.message("iCloud Drive is unavailable. Sign in and enable iCloud for Draftly.") }
            root = cloud.appendingPathComponent("Documents")
        default: root = try libraryFolder()
        }
        let scoped = root.startAccessingSecurityScopedResource(); defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        func resolve(_ path: String) throws -> URL {
            let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            var ancestor = canonical.appendingPathComponent(relative).standardizedFileURL
            var suffix: [String] = []
            while !manager.fileExists(atPath: ancestor.path) && ancestor.path != "/" {
                suffix.insert(ancestor.lastPathComponent, at: 0)
                ancestor.deleteLastPathComponent()
            }
            let url = suffix.reduce(ancestor.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }.standardizedFileURL
            guard url == canonical || url.path.hasPrefix(canonical.path + "/") else { throw DraftlyError.message("The path must stay inside the selected file root.") }
            return url
        }
        let target = try resolve(values["path"] as? String ?? "")
        switch values["operation"] as? String ?? "" {
        case "basePath": return root.path
        case "baseURL": return root.absoluteString
        case "readString": return try String(contentsOf: target, encoding: .utf8)
        case "writeString":
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (values["text"] as? String ?? "").write(to: target, atomically: true, encoding: .utf8); return true
        case "exists": return manager.fileExists(atPath: target.path)
        case "isDirectory": var isDirectory: ObjCBool = false; return manager.fileExists(atPath: target.path, isDirectory: &isDirectory) && isDirectory.boolValue
        case "createDirectory": try manager.createDirectory(at: target, withIntermediateDirectories: true); return true
        case "listContents": return try manager.contentsOfDirectory(at: target, includingPropertiesForKeys: nil).map { $0.path.replacingOccurrences(of: canonical.path, with: "", options: .anchored) }.sorted()
        case "copyItem": try manager.copyItem(at: target, to: resolve(values["destination"] as? String ?? "")); return true
        case "moveItem": try manager.moveItem(at: target, to: resolve(values["destination"] as? String ?? "")); return true
        case "getCreationDate", "getModificationDate":
            let key: FileAttributeKey = values["operation"] as? String == "getCreationDate" ? .creationDate : .modificationDate
            guard let date = try manager.attributesOfItem(atPath: target.path)[key] as? Date else { throw DraftlyError.message("The file date is unavailable.") }
            return APIValues.date(date)
        case "setCreationDate", "setModificationDate":
            guard let date = APIValues.parseDate(values["date"]) else { throw DraftlyError.message("The file date is invalid.") }
            try manager.setAttributes([values["operation"] as? String == "setCreationDate" ? .creationDate : .modificationDate: date], ofItemAtPath: target.path); return true
        case "getTags": return try target.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        case "setTags": var url = target; var resource = URLResourceValues(); resource.tagNames = values["tags"] as? [String] ?? []; try url.setResourceValues(resource); return true
        default: throw DraftlyError.message("The file operation is invalid.")
        }
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
    private func compose(_ operation: String, _ values: [String: Any]) throws -> [String: String] {
        guard values["isBodyHTML"] as? Bool != true else { throw DraftlyError.message("HTML mail composition is unavailable on macOS.") }
        guard let service = NSSharingService(named: operation == "composeMail" ? .composeEmail : .composeMessage) else { throw DraftlyError.message("The system composition service is unavailable.") }
        service.recipients = values["toRecipients"] as? [String] ?? []; service.subject = values["subject"] as? String ?? ""
        if !(values["ccRecipients"] as? [String] ?? []).isEmpty || !(values["bccRecipients"] as? [String] ?? []).isEmpty { throw DraftlyError.message("The macOS composition service does not accept CC or BCC recipients. Use a mailto URL.") }
        let result = ScriptSharingResult(); service.delegate = result
        service.perform(withItems: [values["body"] as? String ?? ""])
        let deadline = Date().addingTimeInterval(120)
        while result.status == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        return ["status": result.status ?? "timeout"]
    }
    func decodeHTML(_ text: String) throws -> String {
        let safe = text.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        return try NSAttributedString(data: Data(safe.utf8), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil).string
    }
    private func htmlToMarkdown(_ text: String, options: [String: Any]) throws -> String {
        var result = text
        func replace(_ pattern: String, _ replacement: String) { result = result.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive]) }
        replace("(?s)<(?:script|style)[^>]*>.*?</(?:script|style)>", "")
        replace("(?s)<pre[^>]*>\\s*<code[^>]*>(.*?)</code>\\s*</pre>", "\n```\n$1\n```\n")
        for level in 1...6 { replace("(?s)<h\(level)[^>]*>(.*?)</h\(level)>", "\n" + String(repeating: "#", count: level) + " $1\n") }
        if options["ignoreLinks"] as? Bool == true { replace("(?s)<a[^>]*>(.*?)</a>", "$1") }
        else { replace("(?s)<a[^>]*href=[\"']([^\"']*)[\"'][^>]*>(.*?)</a>", "[$2]($1)") }
        if options["ignoreImages"] as? Bool == true { replace("<img[^>]*>", "") }
        else { replace("<img[^>]*src=[\"']([^\"']*)[\"'][^>]*>", "![]($1)") }
        let emphasis = options["emphasisMark"] as? String ?? "_", strong = options["strongMark"] as? String ?? "**"
        replace("(?s)<(?:strong|b)[^>]*>(.*?)</(?:strong|b)>", options["ignoreEmphasis"] as? Bool == true ? "$1" : strong + "$1" + strong)
        replace("(?s)<(?:em|i)[^>]*>(.*?)</(?:em|i)>", options["ignoreEmphasis"] as? Bool == true ? "$1" : emphasis + "$1" + emphasis)
        replace("(?s)<code[^>]*>(.*?)</code>", "`$1`")
        replace("<li[^>]*>", "\n" + (options["ulItemMark"] as? String ?? "*") + " ")
        replace("<(?:br|hr)\\s*/?>", "\n"); replace("</(?:p|div|ul|ol|blockquote)>", "\n\n")
        replace("<[^>]+>", ""); replace("\n{3,}", "\n\n")
        return try decodeHTML(result).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor private final class ScriptSharingResult: NSObject, NSSharingServiceDelegate {
    var status: String?
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { status = "sent" }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) { status = "error" }
}

@MainActor final class ActionCallbackRouter {
    private static var responses: [String: [String: Any]] = [:]
    static func receive(_ url: URL) -> Bool {
        guard url.host == "callback", let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let token = query.first(where: { $0.name == "token" })?.value else { return false }
        var parameters: [String: String] = [:]
        for item in query where item.name != "token" && item.name != "status" { parameters[item.name] = item.value ?? "" }
        responses[token] = ["status": query.first(where: { $0.name == "status" })?.value ?? "error", "parameters": parameters]; return true
    }
    static func open(_ values: [String: Any]) throws -> [String: Any] {
        guard var components = URLComponents(string: values["url"] as? String ?? ""), let scheme = components.scheme, !["javascript", "data", "file"].contains(scheme) else { return ["status": "invalid"] }
        let token = UUID().uuidString, wait = values["waitForResponse"] as? Bool ?? true
        defer { responses.removeValue(forKey: token) }
        if wait {
            var query = (components.queryItems ?? []).filter { !["x-success", "x-cancel", "x-error"].contains($0.name) }
            for (key, status) in [("x-success", "success"), ("x-cancel", "cancelled"), ("x-error", "error")] {
                query.append(URLQueryItem(name: key, value: "draftly://callback?token=\(token)&status=\(status)"))
            }
            components.queryItems = query
        }
        guard let url = components.url, NSWorkspace.shared.open(url) else { return ["status": "invalid"] }
        if !wait { return ["status": "success", "parameters": [:]] }
        let deadline = Date().addingTimeInterval(120)
        while responses[token] == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return responses[token] ?? ["status": "timeout", "parameters": [:]]
    }
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
