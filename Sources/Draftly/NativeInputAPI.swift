import AppKit
import AVFoundation
@preconcurrency import Speech
import Vision
import PDFKit
import DraftlyCore

@MainActor extension NativeActionHost {
    func arrangeText(_ text: String) -> String {
        let controller = ArrangeTextController(text: text)
        let alert = NSAlert(); alert.messageText = "Arrange lines"; alert.accessoryView = controller.view
        alert.addButton(withTitle: "Done"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? controller.lines.joined(separator: "\n") : text
    }
    func transcribe(_ values: [String: Any], dictate: Bool) throws -> String {
        let authorization = SpeechResult()
        SFSpeechRecognizer.requestAuthorization { status in authorization.setAuthorized(status == .authorized) }
        let authorizationDeadline = Date().addingTimeInterval(60)
        while authorization.authorized == nil && Date() < authorizationDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard authorization.authorized == true else { throw DraftlyError.message("Speech recognition access is denied.") }
        let locale = values["locale"] as? String ?? ""
        guard let recognizer = SFSpeechRecognizer(locale: locale.isEmpty ? .current : Locale(identifier: locale)), recognizer.isAvailable else { throw DraftlyError.message("Speech recognition is unavailable for this language.") }
        let result = SpeechResult()
        if !dictate {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio, .movie]
            guard panel.runModal() == .OK, let url = panel.url else { return "" }
            let request = SFSpeechURLRecognitionRequest(url: url)
            let task = recognizer.recognitionTask(with: request) { response, error in result.update(response?.bestTranscription.formattedString, final: response?.isFinal == true, error: error) }
            defer { task.cancel() }
            let deadline = Date().addingTimeInterval(120)
            while !result.finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            if let error = result.error { throw error }
            guard result.finished else { throw DraftlyError.message("Audio transcription timed out.") }
            return result.text
        }
        let microphone = SpeechResult()
        AVCaptureDevice.requestAccess(for: .audio) { microphone.setAuthorized($0) }
        while microphone.authorized == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard microphone.authorized == true else { throw DraftlyError.message("Microphone access is denied.") }
        let engine = AVAudioEngine(), request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw DraftlyError.message("No microphone is available.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        let task = recognizer.recognitionTask(with: request) { response, error in result.update(response?.bestTranscription.formattedString, final: response?.isFinal == true, error: error) }
        defer { engine.stop(); input.removeTap(onBus: 0); request.endAudio(); task.cancel() }
        engine.prepare(); try engine.start()
        let alert = NSAlert(); alert.messageText = "Dictation"; alert.informativeText = "Speak, then choose Done."
        let field = NSTextField(wrappingLabelWithString: "Listening…"); field.frame = NSRect(x: 0, y: 0, width: 420, height: 140)
        alert.accessoryView = field; alert.addButton(withTitle: "Done"); alert.addButton(withTitle: "Cancel")
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in Task { @MainActor in field.stringValue = result.text } }
        RunLoop.main.add(timer, forMode: .modalPanel); defer { timer.invalidate() }
        guard alert.runModal() == .alertFirstButtonReturn else { return "" }
        if let error = result.error { throw error }; return result.text
    }
    func scanDocument() throws -> String {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image, .pdf]
        panel.message = "Choose an image or PDF to recognize text."
        guard panel.runModal() == .OK, let url = panel.url else { return "" }
        let images: [NSImage]
        if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) {
            images = (0..<document.pageCount).compactMap { document.page(at: $0)?.thumbnail(of: NSSize(width: 2400, height: 3200), for: .mediaBox) }
        } else { images = NSImage(contentsOf: url).map { [$0] } ?? [] }
        var pages: [String] = []
        for image in images {
            guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: bitmap).perform([request])
            pages.append((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
        }
        return pages.joined(separator: "\n\n")
    }
}

private final class SpeechResult: @unchecked Sendable {
    private let lock = NSLock(); private var value = "", done = false, failure: Error?, permission: Bool?
    var text: String { lock.lock(); defer { lock.unlock() }; return value }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return done }
    var error: Error? { lock.lock(); defer { lock.unlock() }; return failure }
    var authorized: Bool? { lock.lock(); defer { lock.unlock() }; return permission }
    func setAuthorized(_ allowed: Bool) { lock.lock(); permission = allowed; lock.unlock() }
    func update(_ text: String?, final: Bool, error: Error?) { lock.lock(); if let text { value = text }; done = final || error != nil; failure = error; lock.unlock() }
}

@MainActor private final class ArrangeTextController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var lines: [String]
    let table = NSTableView(), view = NSStackView()
    init(text: String) {
        lines = text.components(separatedBy: "\n"); super.init()
        view.orientation = .vertical; view.frame = NSRect(x: 0, y: 0, width: 480, height: 340)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("line")); column.width = 460; table.addTableColumn(column)
        table.headerView = nil; table.dataSource = self; table.delegate = self; table.allowsMultipleSelection = false
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.widthAnchor.constraint(equalToConstant: 480).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 290).isActive = true
        view.addArrangedSubview(scroll)
        let buttons = NSStackView()
        buttons.addArrangedSubview(NSButton(title: "Move Up", target: self, action: #selector(up)))
        buttons.addArrangedSubview(NSButton(title: "Move Down", target: self, action: #selector(down)))
        view.addArrangedSubview(buttons)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { lines.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { NSTextField(labelWithString: lines[row].isEmpty ? " " : lines[row]) }
    @objc private func up() { move(-1) }
    @objc private func down() { move(1) }
    private func move(_ offset: Int) { let row = table.selectedRow; guard lines.indices.contains(row), lines.indices.contains(row + offset) else { return }; lines.swapAt(row, row + offset); table.reloadData(); table.selectRowIndexes(IndexSet(integer: row + offset), byExtendingSelection: false) }
}
