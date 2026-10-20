import AppKit
import DraftlyCore

struct NativePrintConfiguration: Equatable {
    enum Format: String { case text, html }
    let text: String
    let format: Format
    let topMargin: CGFloat
    let bottomMargin: CGFloat
    let leftMargin: CGFloat
    let rightMargin: CGFloat

    init(_ values: [String: Any]) throws {
        text = values["text"] as? String ?? ""
        let raw = (values["format"] as? String ?? values["printFormat"] as? String ?? "Text").lowercased()
        guard let format = Format(rawValue: raw == "plain" ? "text" : raw) else { throw DraftlyError.message("The print format is invalid.") }
        self.format = format
        func margin(_ key: String) throws -> CGFloat {
            guard let value = values[key] else { return 72 }
            let number: Double?
            if let text = value as? String { number = Double(text) }
            else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { number = value.doubleValue }
            else { number = nil }
            guard let number, number.isFinite, number >= 0 else { throw DraftlyError.message("The print margin \(key) must be a finite nonnegative number.") }
            return CGFloat(number)
        }
        topMargin = try margin("topMargin"); bottomMargin = try margin("bottomMargin")
        leftMargin = try margin("leftMargin"); rightMargin = try margin("rightMargin")
    }
}

@MainActor protocol NativePrintDriver: AnyObject {
    var onFinish: ((Result<Bool, Error>) -> Void)? { get set }
    func start()
    func cancelOwnedPresentation()
    func detach()
}

@MainActor enum NativePrintRequest {
    static func run(_ values: [String: Any], timeout: TimeInterval = 120,
                    now: @escaping @MainActor () -> Date = { Date() },
                    makeDriver: @MainActor (NativePrintConfiguration) throws -> any NativePrintDriver = { try SheetPrintDriver($0) }) async throws -> Bool {
        try Task.checkCancellation()
        guard timeout.isFinite, timeout > 0 else { throw DraftlyError.message("The print timeout must be positive and finite.") }
        let deadline = now().addingTimeInterval(timeout)
        let configuration = try NativePrintConfiguration(values)
        return try await PrintRequestWait(driver: makeDriver(configuration), deadline: deadline, now: now).run()
    }
}

@MainActor private final class SheetPrintDriver: NSObject, NativePrintDriver {
    let window: NSWindow
    let operation: NSPrintOperation
    let printedView: NSTextView
    var onFinish: ((Result<Bool, Error>) -> Void)?
    private weak var ownedSheet: NSWindow?
    private var retention: SheetPrintDriver?
    init(_ configuration: NativePrintConfiguration) throws {
        guard let window = NSApp?.keyWindow else { throw DraftlyError.message("Open a Draftly window before printing.") }
        guard window.attachedSheet == nil else { throw DraftlyError.message("Close the current window sheet before printing.") }
        self.window = window
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        if configuration.format == .html {
            view.textStorage?.setAttributedString(try NSAttributedString(data: Data(configuration.text.utf8), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil))
        } else { view.string = configuration.text }
        printedView = view
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = configuration.topMargin; info.bottomMargin = configuration.bottomMargin
        info.leftMargin = configuration.leftMargin; info.rightMargin = configuration.rightMargin
        operation = NSPrintOperation(view: view, printInfo: info)
        operation.canSpawnSeparateThread = true
        super.init()
    }
    func start() {
        retention = self
        operation.runModal(for: window, delegate: self, didRun: #selector(Self.didRun(_:success:contextInfo:)), contextInfo: nil)
        ownedSheet = window.attachedSheet
    }
    func cancelOwnedPresentation() {
        guard let sheet = ownedSheet, window.attachedSheet === sheet else { return }
        ownedSheet = nil
        window.endSheet(sheet, returnCode: .cancel)
        sheet.orderOut(nil)
    }
    func detach() { onFinish = nil }
    @objc private func didRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        ownedSheet = nil
        // AppKit does not distinguish user cancellation from printing failure here.
        onFinish?(.success(success))
        retention = nil
    }
}

@MainActor private final class PrintRequestWait {
    let driver: any NativePrintDriver
    var continuation: CheckedContinuation<Bool, Error>?
    var timer: Task<Void, Never>?
    let deadline: Date
    let now: @MainActor () -> Date
    init(driver: any NativePrintDriver, deadline: Date, now: @escaping @MainActor () -> Date) {
        self.driver = driver; self.deadline = deadline; self.now = now
    }
    func run() async throws -> Bool {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else { finish(.failure(CancellationError()), cancel: true); return }
                guard now() < deadline else { finish(.failure(ActionExecutionInterruption.timeout), cancel: true); return }
                driver.onFinish = { [weak self] result in self?.finish(result) }
                timer = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSince(now())))) } catch { return }
                    finish(.failure(ActionExecutionInterruption.timeout), cancel: true)
                }
                driver.start()
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError()), cancel: true) } }
    }
    private func finish(_ result: Result<Bool, Error>, cancel: Bool = false) {
        guard let continuation else { return }
        self.continuation = nil
        let expired = !cancel && now() >= deadline
        timer?.cancel(); timer = nil
        driver.detach()
        if cancel || expired { driver.cancelOwnedPresentation() }
        continuation.resume(with: expired ? .failure(ActionExecutionInterruption.timeout) : result)
    }
}
